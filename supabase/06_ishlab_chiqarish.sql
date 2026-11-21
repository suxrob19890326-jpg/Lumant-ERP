-- =====================================================================
-- LUMANT ERP — 6-qadam: ISHLAB CHIQARISH
-- Supabase → SQL Editor → New query → shu faylni to'liq qo'yib → Run
-- (04_ombor.sql dan keyin, BIR MARTA ishga tushiriladi)
--
-- Ishlab chiqarilgan mahsulot → omborga kirim ("Ishlab chiqarildi")
-- Sarflangan xomashyo        → ombordan chiqim ("Sarflandi")
-- Retsept: 1 birlik mahsulotga qancha xomashyo ketadi (sarfni o'zi hisoblash uchun)
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. ISHLAB CHIQARISH YOZUVLARI
-- ---------------------------------------------------------------------
create table ishlab_chiqarish (
  id               bigint generated always as identity primary key,
  sana             date not null default current_date,
  mahsulot_id      bigint not null references mahsulotlar(id),
  miqdor           numeric not null check (miqdor > 0),
  izoh             text,
  kiritgan         uuid default auth.uid(),
  kiritilgan_vaqt  timestamptz not null default now()
);

create index ishlab_chiqarish_sana_idx on ishlab_chiqarish (sana, id);

-- Ombor harakati qaysi ishlab chiqarishga tegishli
alter table ombor_harakat add column if not exists ishlab_id bigint references ishlab_chiqarish(id);
create index if not exists ombor_harakat_ishlab_idx on ombor_harakat (ishlab_id);


-- ---------------------------------------------------------------------
-- 2. RETSEPTLAR: 1 birlik mahsulot uchun xomashyo miqdori
--    masalan: М 200 (1 м3) → Цемент 250 кг, песок 0,5 куб, гравий 0,8 куб
-- ---------------------------------------------------------------------
create table retseptlar (
  mahsulot_id  bigint not null references mahsulotlar(id),
  xomashyo_id  bigint not null references mahsulotlar(id),
  miqdor       numeric not null check (miqdor > 0),
  primary key (mahsulot_id, xomashyo_id),
  check (mahsulot_id <> xomashyo_id)
);


-- ---------------------------------------------------------------------
-- 3. KIRITISH: hammasi bitta tranzaksiyada (yo hammasi, yo hech biri)
--    p_sarflar: [{"xomashyo_id": 5, "miqdor": 250}, ...]
--    p_retsept: true bo'lsa, shu nisbat mahsulot retsepti sifatida saqlanadi
-- ---------------------------------------------------------------------
create or replace function ishlab_kirit(
  p_sana date, p_mahsulot_id bigint, p_miqdor numeric,
  p_izoh text, p_sarflar jsonb, p_retsept boolean
) returns bigint
language plpgsql security invoker set search_path = public as $$
declare
  v_id bigint;
begin
  if p_miqdor is null or p_miqdor <= 0 then
    raise exception 'Miqdor noto''g''ri';
  end if;

  insert into ishlab_chiqarish (sana, mahsulot_id, miqdor, izoh)
  values (coalesce(p_sana, current_date), p_mahsulot_id, p_miqdor, nullif(trim(p_izoh), ''))
  returning id into v_id;

  -- Tayyor mahsulot → omborga
  insert into ombor_harakat (sana, mahsulot_id, yonalish, miqdor, sabab, izoh, ishlab_id)
  values (coalesce(p_sana, current_date), p_mahsulot_id, 'kirim', p_miqdor, 'ishlab_chiqarildi',
          nullif(trim(p_izoh), ''), v_id);

  -- Xomashyo → ombordan (bir xil xomashyo ikki marta yozilsa, qo'shib yuboriladi)
  insert into ombor_harakat (sana, mahsulot_id, yonalish, miqdor, sabab, ishlab_id)
  select coalesce(p_sana, current_date), s.xomashyo_id, 'chiqim', sum(s.miqdor), 'sarflandi', v_id
  from jsonb_to_recordset(coalesce(p_sarflar, '[]'::jsonb)) as s(xomashyo_id bigint, miqdor numeric)
  where s.xomashyo_id is not null and s.miqdor > 0
  group by s.xomashyo_id;

  if p_retsept then
    delete from retseptlar where mahsulot_id = p_mahsulot_id;
    insert into retseptlar (mahsulot_id, xomashyo_id, miqdor)
    select p_mahsulot_id, s.xomashyo_id, sum(s.miqdor) / p_miqdor
    from jsonb_to_recordset(coalesce(p_sarflar, '[]'::jsonb)) as s(xomashyo_id bigint, miqdor numeric)
    where s.xomashyo_id is not null and s.miqdor > 0 and s.xomashyo_id <> p_mahsulot_id
    group by s.xomashyo_id;
  end if;

  return v_id;
end $$;

revoke execute on function ishlab_kirit(date, bigint, numeric, text, jsonb, boolean) from public, anon;
grant  execute on function ishlab_kirit(date, bigint, numeric, text, jsonb, boolean) to authenticated;


-- ---------------------------------------------------------------------
-- 4. RO'YXAT: har bir ishlab chiqarish va uning xomashyo sarfi
-- ---------------------------------------------------------------------
create view ishlab_royxat with (security_invoker = on) as
select i.id, i.sana, i.mahsulot_id, m.nomi, m.olchov, i.miqdor, i.izoh, i.kiritilgan_vaqt,
       coalesce((
         select jsonb_agg(jsonb_build_object('nomi', x.nomi, 'olchov', x.olchov, 'miqdor', h.miqdor)
                          order by x.nomi)
         from ombor_harakat h join mahsulotlar x on x.id = h.mahsulot_id
         where h.ishlab_id = i.id and h.sabab = 'sarflandi'
       ), '[]'::jsonb) as sarflar
from ishlab_chiqarish i
join mahsulotlar m on m.id = i.mahsulot_id;


-- ---------------------------------------------------------------------
-- 5. XAVFSIZLIK: faqat kirganlar. Ishlab chiqarish yozuvini o'chirish yo'q.
--    Retseptni xodimlar o'zgartira oladi.
-- ---------------------------------------------------------------------
alter table ishlab_chiqarish enable row level security;
alter table retseptlar       enable row level security;

create policy "kirganlar ko'radi"  on ishlab_chiqarish for select to authenticated using (true);
create policy "kirganlar qo'shadi" on ishlab_chiqarish for insert to authenticated with check (true);

create policy "kirganlar ko'radi"       on retseptlar for select to authenticated using (true);
create policy "kirganlar qo'shadi"      on retseptlar for insert to authenticated with check (true);
create policy "kirganlar tahrirlaydi"   on retseptlar for update to authenticated using (true);
create policy "kirganlar o'chiradi"     on retseptlar for delete to authenticated using (true);

grant select, insert on ishlab_chiqarish to authenticated;
grant select, insert, update, delete on retseptlar to authenticated;
grant select on ishlab_royxat to authenticated;
