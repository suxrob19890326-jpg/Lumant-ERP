-- =====================================================================
-- LUMANT ERP — 10-qadam: TELEGRAM — HAR KUNI KECHQURUN HISOBOT
-- Supabase → SQL Editor → New query → shu faylni to'liq qo'yib → Run
-- (09 dan keyin, BIR MARTA ishga tushiriladi)
--
-- Har kuni soat 20:00 da (Toshkent vaqti) sizning Telegram'ingizga:
-- bugungi sotuv, tushgan pul, kassa qoldig'i, jami qarzlar, ertangi buyurtmalar.
-- Bot tokeni va chat raqami saytdagi "⚙️ Sozlamalar" sahifasida kiritiladi.
-- =====================================================================

create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;

-- Maxfiy sozlamalar: faqat admin ko'radi va o'zgartiradi
create table telegram_sozlama (
  id        int primary key default 1 check (id = 1),
  token     text,              -- @BotFather bergan token
  chat_id   text,              -- hisobot boradigan chat (sizning Telegram'ingiz)
  yoqilgan  boolean not null default true,
  updated_at timestamptz not null default now()
);
insert into telegram_sozlama (id) values (1) on conflict do nothing;
alter table telegram_sozlama enable row level security;
create policy "rol: ko'radi" on telegram_sozlama for select to authenticated using (rol_bor('admin'));
create policy "rol: tahrir"  on telegram_sozlama for update to authenticated using (rol_bor('admin')) with check (rol_bor('admin'));
grant select, update on telegram_sozlama to authenticated;

-- "1250000" → "1 250 000"
create or replace function pul_matn(n numeric) returns text
language sql immutable as $$
  select case when n < 0 then '−' else '' end ||
         ltrim(replace(to_char(abs(round(coalesce(n, 0))), 'FM999G999G999G999G990'), ',', ' '))
$$;

-- Bugungi hisobot matni
create or replace function kunlik_hisobot_matni(p_kun date default (now() at time zone 'Asia/Tashkent')::date)
returns text
language plpgsql stable security definer set search_path = public as $$
declare
  m text;
  r record;
  v_qarz numeric; v_avans numeric; v_qarzdor int;
  v_buy int; v_buy_m numeric;
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

  select coalesce(sum(qoldiq) filter (where qoldiq > 0), 0), coalesce(-sum(qoldiq) filter (where qoldiq < 0), 0),
         count(*) filter (where qoldiq > 0)
    into v_qarz, v_avans, v_qarzdor
  from mijoz_qoldiq where coalesce(valyuta, 'UZS') = 'UZS';
  m := m || E'\n📒 Mijozlar qarzi: ' || pul_matn(v_qarz) || ' so''m (' || v_qarzdor || ' ta)'
         || E'\n📕 Biz qarz / avans: ' || pul_matn(v_avans) || ' so''m';
  select coalesce(sum(qoldiq) filter (where qoldiq > 0), 0) into v_qarz from mijoz_qoldiq where valyuta = 'USD';
  if v_qarz > 0 then m := m || E'\n📒 Dollar qarzlar: ' || pul_matn(v_qarz) || ' $'; end if;

  select count(*), coalesce(sum(miqdor), 0) into v_buy, v_buy_m
  from buyurtmalar where sana = p_kun + 1 and holat = 'yangi';
  if v_buy > 0 then
    m := m || E'\n\n📋 Ertaga ' || v_buy || ' ta buyurtma (' || pul_matn(v_buy_m) || ' birlik)';
  end if;
  return m;
end $$;

-- Telegram'ga yuborish (pg_net orqali, javobni kutmaydi)
create or replace function telegram_yubor(p_matn text) returns bigint
language plpgsql security definer set search_path = public, extensions as $$
declare t telegram_sozlama%rowtype;
begin
  select * into t from telegram_sozlama where id = 1;
  if t.token is null or t.chat_id is null or t.token = '' or t.chat_id = '' then
    raise exception 'Telegram sozlanmagan: bot tokeni va chat raqamini kiriting';
  end if;
  return net.http_post(
    url     := 'https://api.telegram.org/bot' || t.token || '/sendMessage',
    body    := jsonb_build_object('chat_id', t.chat_id, 'text', p_matn),
    headers := '{"Content-Type": "application/json"}'::jsonb
  );
end $$;

-- Har kuni ishga tushadigan
create or replace function kunlik_hisobot_yubor() returns void
language plpgsql security definer set search_path = public as $$
begin
  if (select yoqilgan and coalesce(token, '') <> '' and coalesce(chat_id, '') <> ''
      from telegram_sozlama where id = 1) then
    perform telegram_yubor(kunlik_hisobot_matni());
  end if;
end $$;

-- Saytdagi "Sinov xabari" tugmasi uchun (faqat admin)
create or replace function telegram_sinov() returns text
language plpgsql security definer set search_path = public as $$
declare m text;
begin
  if not rol_bor('admin') then raise exception 'Faqat admin'; end if;
  m := kunlik_hisobot_matni();
  perform telegram_yubor(m);
  return m;
end $$;

revoke execute on function telegram_yubor(text) from public, anon, authenticated;
revoke execute on function kunlik_hisobot_yubor() from public, anon, authenticated;
revoke execute on function kunlik_hisobot_matni(date) from public, anon;
revoke execute on function telegram_sinov() from public, anon;
grant execute on function telegram_sinov() to authenticated;

-- Har kuni 15:00 UTC = 20:00 Toshkent
select cron.unschedule(jobid) from cron.job where jobname = 'lumant-kunlik-hisobot';
select cron.schedule('lumant-kunlik-hisobot', '0 15 * * *', 'select public.kunlik_hisobot_yubor()');
