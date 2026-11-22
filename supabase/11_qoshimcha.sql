-- =====================================================================
-- LUMANT ERP — 11-qadam: KASSA YOPISH, MIJOZ KABINETI, KAM QOLDIQ,
-- SIFAT PASPORTI, MASHINA XARAJATLARI, ISH HAQI, INTERNETSIZ ISHLASH
-- Supabase → SQL Editor → New query → shu faylni to'liq qo'yib → Run
-- (09 dan keyin, BIR MARTA. 10 — Telegram — bo'lmasa ham ishlaydi)
-- =====================================================================


-- ---------------------------------------------------------------------
-- 0. Telegram'ga xabar (10-SQL va bot sozlangan bo'lsa; bo'lmasa — jim)
-- ---------------------------------------------------------------------
create or replace function telegram_xabar(p_matn text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if to_regprocedure('public.telegram_yubor(text)') is null then return; end if;
  if not exists (select 1 from telegram_sozlama
                 where id = 1 and yoqilgan and coalesce(token, '') <> '' and coalesce(chat_id, '') <> '') then
    return;
  end if;
  execute 'select public.telegram_yubor($1)' using p_matn;
exception when others then
  null;   -- xabar ketmasa ham asosiy ish to'xtamasin
end $$;
revoke execute on function telegram_xabar(text) from public, anon, authenticated;

create or replace function pul_matn(n numeric) returns text
language sql immutable as $$
  select case when n < 0 then '−' else '' end ||
         ltrim(replace(to_char(abs(round(coalesce(n, 0))), 'FM999G999G999G999G990'), ',', ' '))
$$;


-- ---------------------------------------------------------------------
-- 1. KUNLIK KASSA YOPISH: kassir sanab kiritadi, farq bo'lsa — Telegram
-- ---------------------------------------------------------------------
create table kassa_yopish (
  id        bigint generated always as identity primary key,
  sana      date not null,
  kassa     text not null check (kassa in ('naqd','karta','bank','dollar')),
  hisobda   numeric not null,          -- tizim bo'yicha qoldiq
  sanaldi   numeric not null,          -- haqiqatda sanalgan
  farq      numeric generated always as (sanaldi - hisobda) stored,
  izoh      text,
  kim       uuid default auth.uid(),
  vaqt      timestamptz not null default now(),
  unique (sana, kassa)
);
alter table kassa_yopish enable row level security;
create policy "rol: ko'radi"  on kassa_yopish for select to authenticated using (rol_bor('admin','rahbar','kassir'));
create policy "rol: qo'shadi" on kassa_yopish for insert to authenticated with check (rol_bor('admin','rahbar','kassir'));
create policy "rol: tahrir"   on kassa_yopish for update to authenticated using (rol_bor('admin','rahbar','kassir'));
grant select, insert, update on kassa_yopish to authenticated;

create or replace function kassa_yopish_xabar() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if abs(new.farq) >= 1 then
    perform telegram_xabar('⚠️ Kassa farqi — ' || to_char(new.sana, 'DD.MM.YYYY') || E'\n' ||
      initcap(new.kassa) || ': hisobda ' || pul_matn(new.hisobda) || ', sanaldi ' || pul_matn(new.sanaldi) ||
      E'\nFarq: ' || pul_matn(new.farq) || coalesce(E'\nIzoh: ' || new.izoh, '') ||
      E'\nKim: ' || coalesce((select coalesce(ism, email) from xodimlar where user_id = new.kim), '—'));
  end if;
  return null;
end $$;
create trigger kassa_yopish_xabar after insert or update on kassa_yopish
  for each row execute function kassa_yopish_xabar();


-- ---------------------------------------------------------------------
-- 2. MIJOZ KABINETI: mijoz maxsus havola orqali (login'siz) o'z hisobini
--    ko'radi va buyurtma beradi. Havola = tasodifiy kalit (uuid).
-- ---------------------------------------------------------------------
alter table mijozlar add column if not exists kabinet_kalit uuid unique;

-- Havola yaratish / almashtirish / o'chirish (eski havola ishlamay qoladi)
create or replace function kabinet_kalit(p_mijoz bigint, p_ochir boolean default false) returns uuid
language plpgsql security definer set search_path = public as $$
declare k uuid := case when p_ochir then null else gen_random_uuid() end;
begin
  if not rol_bor('admin','rahbar','sotuvchi') then raise exception 'Ruxsat yo''q'; end if;
  update mijozlar set kabinet_kalit = k where id = p_mijoz;
  if not found then raise exception 'Mijoz topilmadi'; end if;
  return k;
end $$;
revoke execute on function kabinet_kalit(bigint, boolean) from public, anon;
grant execute on function kabinet_kalit(bigint, boolean) to authenticated;

-- Mijoz ko'radigan hamma narsa (faqat o'ziniki)
create or replace function kabinet(p_kalit uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m mijozlar%rowtype;
begin
  select * into m from mijozlar where kabinet_kalit = p_kalit and p_kalit is not null;
  if m.id is null then return null; end if;
  return jsonb_build_object(
    'nomi', m.nomi,
    'valyuta', m.valyuta,
    'qoldiq', (select coalesce(sum(summa), 0) from yozuvlar where mijoz_id = m.id),
    'korxona', (select jsonb_build_object('nomi', korxona_nomi, 'telefon', telefon, 'manzil', manzil) from sozlamalar where id = 1),
    'yozuvlar', coalesce((select jsonb_agg(x order by x.sana desc, x.id desc) from (
        select y.id, y.sana, y.turi, p.nomi mahsulot, y.miqdor, coalesce(y.olchov, p.olchov) olchov, y.narx, y.summa, y.avto_raqami
        from yozuvlar y left join mahsulotlar p on p.id = y.mahsulot_id
        where y.mijoz_id = m.id order by y.sana desc, y.id desc limit 300) x), '[]'::jsonb),
    'buyurtmalar', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'sana', b.sana, 'vaqt', b.vaqt, 'mahsulot', p.nomi,
        'miqdor', b.miqdor, 'olchov', p.olchov, 'holat', b.holat) order by b.sana desc, b.id desc)
        from buyurtmalar b join mahsulotlar p on p.id = b.mahsulot_id
        where b.mijoz_id = m.id and b.sana >= current_date - 30), '[]'::jsonb),
    'mahsulotlar', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'nomi', p.nomi, 'olchov', p.olchov) order by p.nomi)
        from mahsulotlar p where p.turkum = 'tayyor'), '[]'::jsonb)
  );
end $$;

-- Mijozning o'zi buyurtma beradi
create or replace function kabinet_buyurtma(p_kalit uuid, p_sana date, p_mahsulot bigint, p_miqdor numeric,
                                            p_vaqt text, p_manzil text, p_telefon text, p_izoh text) returns bigint
language plpgsql security definer set search_path = public as $$
declare m mijozlar%rowtype; p mahsulotlar%rowtype; n bigint;
begin
  select * into m from mijozlar where kabinet_kalit = p_kalit and p_kalit is not null;
  if m.id is null then raise exception 'Havola eskirgan. Korxonadan yangisini so''rang.'; end if;
  select * into p from mahsulotlar where id = p_mahsulot and turkum = 'tayyor';
  if p.id is null then raise exception 'Mahsulotni tanlang'; end if;
  if p_sana is null or p_sana < (now() at time zone 'Asia/Tashkent')::date
     or p_sana > (now() at time zone 'Asia/Tashkent')::date + 60 then
    raise exception 'Sana noto''g''ri';
  end if;
  if p_miqdor is null or p_miqdor <= 0 or p_miqdor > 1000 then raise exception 'Miqdor noto''g''ri'; end if;
  if (select count(*) from buyurtmalar where mijoz_id = m.id and holat = 'yangi') >= 10 then
    raise exception 'Kutilayotgan buyurtmalar juda ko''p. Korxona bilan bog''laning.';
  end if;
  insert into buyurtmalar (sana, vaqt, mijoz_id, mahsulot_id, miqdor, narx, manzil, telefon, izoh, kiritgan)
  values (p_sana, left(nullif(trim(p_vaqt), ''), 40), m.id, p.id, p_miqdor,
          coalesce((select narx from mijoz_narx where mijoz_id = m.id and mahsulot_id = p.id),
                   case when m.valyuta = 'UZS' then p.oxirgi_narx end),
          left(nullif(trim(p_manzil), ''), 200), left(coalesce(nullif(trim(p_telefon), ''), m.telefon), 40),
          left('🌐 Mijozning o''zi: ' || coalesce(nullif(trim(p_izoh), ''), ''), 300), null)
  returning id into n;
  perform telegram_xabar('📋 Yangi buyurtma (mijoz kabinetidan)' || E'\n' || m.nomi || E'\n' ||
    p.nomi || ': ' || pul_matn(p_miqdor) || ' ' || coalesce(p.olchov, '') || E'\n' ||
    to_char(p_sana, 'DD.MM.YYYY') || coalesce(' ' || nullif(trim(p_vaqt), ''), '') ||
    coalesce(E'\n📍 ' || nullif(trim(p_manzil), ''), ''));
  return n;
end $$;

revoke execute on function kabinet(uuid) from public;
revoke execute on function kabinet_buyurtma(uuid, date, bigint, numeric, text, text, text, text) from public;
grant execute on function kabinet(uuid) to anon, authenticated;
grant execute on function kabinet_buyurtma(uuid, date, bigint, numeric, text, text, text, text) to anon, authenticated;


-- ---------------------------------------------------------------------
-- 3. KAM QOLDIQ: mahsulotga minimal qoldiq; kunlik hisobotda ogohlantirish
-- ---------------------------------------------------------------------
alter table mahsulotlar add column if not exists min_qoldiq numeric check (min_qoldiq >= 0);

create or replace view ombor_qoldiq with (security_invoker = on) as
select m.id, m.nomi, m.olchov, m.turkum,
       coalesce(sum(case when h.yonalish = 'kirim' then h.miqdor else -h.miqdor end), 0) as qoldiq,
       count(h.id) as harakatlar,
       max(h.sana) as oxirgi,
       m.min_qoldiq
from mahsulotlar m
left join ombor_harakat h on h.mahsulot_id = m.id
group by m.id;


-- ---------------------------------------------------------------------
-- 4. BETON SIFAT PASPORTI (har bir mahsulot uchun; nakladnoy bilan chiqadi)
-- ---------------------------------------------------------------------
create table beton_pasport (
  mahsulot_id     bigint primary key references mahsulotlar(id) on delete cascade,
  sinf            text,     -- B15, B22.5 ...
  mustahkamlik    text,     -- MPa yoki kgs/sm²
  harakatchanlik  text,     -- P3, OK 10–15 sm
  sovuqqa         text,     -- F150
  suv_otkazmaslik text,     -- W6
  toldiruvchi     text,     -- shag'al fraksiyasi
  standart        text,     -- GOST 7473-2010 / O'zDSt
  izoh            text,
  updated_at      timestamptz not null default now()
);
alter table beton_pasport enable row level security;
create policy "rol: ko'radi"   on beton_pasport for select to authenticated using (rolim() is not null);
create policy "rol: qo'shadi"  on beton_pasport for insert to authenticated with check (rol_bor('admin','rahbar','omborchi'));
create policy "rol: tahrir"    on beton_pasport for update to authenticated using (rol_bor('admin','rahbar','omborchi'));
create policy "rol: o'chiradi" on beton_pasport for delete to authenticated using (rol_bor('admin','rahbar','omborchi'));
grant select, insert, update, delete on beton_pasport to authenticated;


-- ---------------------------------------------------------------------
-- 5. ISH HAQI: ishchilar, tabel; kassa chiqimi ishchiga / mashinaga bog'lanadi
-- ---------------------------------------------------------------------
create table ishchilar (
  id          bigint generated always as identity primary key,
  ism         text not null,
  lavozim     text,
  telefon     text,
  stavka_turi text not null default 'oylik' check (stavka_turi in ('oylik','kunlik')),
  stavka      numeric not null default 0 check (stavka >= 0),   -- oylik maosh yoki 1 kunlik haq
  faol        boolean not null default true,
  created_at  timestamptz not null default now()
);
create table tabel (
  ishchi_id  bigint not null references ishchilar(id) on delete cascade,
  sana       date not null,
  holat      text not null check (holat in ('ish','yarim','yoq')),   -- to'liq kun, yarim kun, kelmadi
  primary key (ishchi_id, sana)
);
alter table ishchilar enable row level security;
alter table tabel enable row level security;
create policy "rol: ko'radi"   on ishchilar for select to authenticated using (rol_bor('admin','rahbar','kassir'));
create policy "rol: qo'shadi"  on ishchilar for insert to authenticated with check (rol_bor('admin','rahbar'));
create policy "rol: tahrir"    on ishchilar for update to authenticated using (rol_bor('admin','rahbar'));
create policy "rol: ko'radi"   on tabel for select to authenticated using (rol_bor('admin','rahbar','kassir'));
create policy "rol: qo'shadi"  on tabel for insert to authenticated with check (rol_bor('admin','rahbar'));
create policy "rol: tahrir"    on tabel for update to authenticated using (rol_bor('admin','rahbar'));
create policy "rol: o'chiradi" on tabel for delete to authenticated using (rol_bor('admin','rahbar'));
grant select, insert, update on ishchilar to authenticated;
grant select, insert, update, delete on tabel to authenticated;

alter table kassa_yozuvlar add column if not exists ishchi_id bigint references ishchilar(id);
alter table kassa_yozuvlar add column if not exists avto_raqami text;


-- ---------------------------------------------------------------------
-- 6. INTERNETSIZ ISHLASH: telefonda navbatda turgan yozuv ikki marta tushmasin
-- ---------------------------------------------------------------------
alter table yozuvlar add column if not exists client_id uuid unique;


-- ---------------------------------------------------------------------
-- 7. KUNLIK TELEGRAM HISOBOTI: kam qoldiq va kassa farqi ham qo'shiladi
-- ---------------------------------------------------------------------
create or replace function kunlik_hisobot_matni(p_kun date default (now() at time zone 'Asia/Tashkent')::date)
returns text
language plpgsql stable security definer set search_path = public as $$
declare
  m text;
  r record;
  v_qarz numeric; v_avans numeric; v_qarzdor int;
  v_buy int; v_buy_m numeric;
  kam text;
begin
  m := '📊 ' || (select korxona_nomi from sozlamalar where id = 1) || ' — ' || to_char(p_kun, 'DD.MM.YYYY') || E'\n\n';

  for r in
    select y.turi, coalesce(mj.valyuta, 'UZS') v, count(*) n, sum(abs(y.summa)) s
    from yozuvlar y join mijozlar mj on mj.id = y.mijoz_id
    where y.sana = p_kun group by 1, 2
    order by array_position(array['yuk_berildi','tolov_keldi','mahsulot_olindi','pul_berildi','tuzatish'], y.turi), 2
  loop
    m := m || case r.turi when 'yuk_berildi' then '🚚 Sotuv' when 'tolov_keldi' then '💵 To''lov keldi'
                          when 'mahsulot_olindi' then '⬇️ Xarid' when 'pul_berildi' then '💸 Pul berildi'
                          else '✏️ Tuzatish' end
           || ': ' || pul_matn(r.s) || case when r.v = 'USD' then ' $' else ' so''m' end
           || ' (' || r.n || ' ta)' || E'\n';
  end loop;
  if not exists (select 1 from yozuvlar where sana = p_kun) then m := m || 'Bugun yozuv kiritilmadi' || E'\n'; end if;

  m := m || E'\n💰 Kassa:\n';
  for r in select kassa, qoldiq from kassa_qoldiq
           order by array_position(array['naqd','karta','bank','dollar'], kassa) loop
    m := m || '   ' || case r.kassa when 'naqd' then 'Naqd' when 'karta' then 'Karta' when 'bank' then 'Bank' else 'Dollar' end
           || ': ' || pul_matn(r.qoldiq) || case when r.kassa = 'dollar' then ' $' else '' end || E'\n';
  end loop;
  for r in select kassa, farq from kassa_yopish where sana = p_kun and abs(farq) >= 1 loop
    m := m || '   ⚠️ ' || initcap(r.kassa) || ' farqi: ' || pul_matn(r.farq) || E'\n';
  end loop;

  select coalesce(sum(qoldiq) filter (where qoldiq > 0), 0), coalesce(-sum(qoldiq) filter (where qoldiq < 0), 0),
         count(*) filter (where qoldiq > 0)
    into v_qarz, v_avans, v_qarzdor
  from mijoz_qoldiq where coalesce(valyuta, 'UZS') = 'UZS';
  m := m || E'\n📒 Mijozlar qarzi: ' || pul_matn(v_qarz) || ' so''m (' || v_qarzdor || ' ta)'
         || E'\n📕 Biz qarz / avans: ' || pul_matn(v_avans) || ' so''m';
  select coalesce(sum(qoldiq) filter (where qoldiq > 0), 0) into v_qarz from mijoz_qoldiq where valyuta = 'USD';
  if v_qarz > 0 then m := m || E'\n📒 Dollar qarzlar: ' || pul_matn(v_qarz) || ' $'; end if;

  select string_agg('   ' || nomi || ': ' || pul_matn(qoldiq) || ' ' || coalesce(olchov, '') ||
                    ' (min ' || pul_matn(min_qoldiq) || ')', E'\n' order by nomi)
    into kam
  from ombor_qoldiq where min_qoldiq is not null and qoldiq < min_qoldiq;
  if kam is not null then m := m || E'\n\n⚠️ Kam qolgan:\n' || kam; end if;

  select count(*), coalesce(sum(miqdor), 0) into v_buy, v_buy_m
  from buyurtmalar where sana = p_kun + 1 and holat = 'yangi';
  if v_buy > 0 then
    m := m || E'\n\n📋 Ertaga ' || v_buy || ' ta buyurtma (' || pul_matn(v_buy_m) || ' birlik)';
  end if;
  return m;
end $$;
revoke execute on function kunlik_hisobot_matni(date) from public, anon;


-- ---------------------------------------------------------------------
-- 8. TARIX: yangi jadvallar ham kuzatiladi
-- ---------------------------------------------------------------------
create trigger tarix after insert or update or delete on kassa_yopish  for each row execute function tarixga();
create trigger tarix after insert or update or delete on beton_pasport for each row execute function tarixga();
create trigger tarix after insert or update or delete on ishchilar     for each row execute function tarixga();
create trigger tarix after insert or update or delete on tabel         for each row execute function tarixga();
