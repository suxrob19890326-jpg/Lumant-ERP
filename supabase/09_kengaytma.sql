-- =====================================================================
-- LUMANT ERP — 9-qadam: SOZLAMALAR, DOLLAR, MAXSUS NARXLAR, BUYURTMALAR
-- Supabase → SQL Editor → New query → shu faylni to'liq qo'yib → Run
-- (08 dan keyin, BIR MARTA ishga tushiriladi)
--
--   1. Korxona sozlamalari (nakladnoyda chiqadigan nom, manzil, telefon)
--   2. Dollar: mijoz hisobi so'mda yoki dollarda; "Dollar" kassa
--   3. Maxsus narxlar: mijozga alohida narx (chegirma)
--   4. Buyurtmalar: oldindan yozib qo'yiladigan yetkazishlar
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. KORXONA SOZLAMALARI (bitta qator)
-- ---------------------------------------------------------------------
create table sozlamalar (
  id            int primary key default 1 check (id = 1),
  korxona_nomi  text not null default 'Lumant Beton',
  manzil        text default 'Kogon tumani',
  telefon       text,
  inn           text,
  rekvizit      text,          -- bank, h/r, MFO
  nakladnoy_izoh text,         -- nakladnoy pastida chiqadigan matn
  updated_at    timestamptz not null default now()
);
insert into sozlamalar (id) values (1) on conflict do nothing;

alter table sozlamalar enable row level security;
create policy "rol: ko'radi" on sozlamalar for select to authenticated using (rolim() is not null);
create policy "rol: tahrir"  on sozlamalar for update to authenticated using (rol_bor('admin')) with check (rol_bor('admin'));
grant select, update on sozlamalar to authenticated;


-- ---------------------------------------------------------------------
-- 2. DOLLAR
--    Har bir mijozning hisobi bitta valyutada: UZS (so'm) yoki USD.
--    Dollar mijozning to'lovi faqat "Dollar" kassaga tushadi.
-- ---------------------------------------------------------------------
alter table mijozlar add column if not exists valyuta text not null default 'UZS'
  check (valyuta in ('UZS','USD'));

-- Kassalar: naqd, karta, bank (so'm) + dollar
alter table yozuvlar drop constraint if exists yozuvlar_kassa_check;
alter table yozuvlar add constraint yozuvlar_kassa_check check (kassa in ('naqd','karta','bank','dollar'));
alter table kassa_yozuvlar drop constraint if exists kassa_yozuvlar_kassa_check;
alter table kassa_yozuvlar add constraint kassa_yozuvlar_kassa_check check (kassa in ('naqd','karta','bank','dollar'));

-- (o'chirib qayta yaratiladi: bazadagi eski ko'rinishda boshqa ustunlar bo'lishi mumkin)
drop view if exists kassa_qoldiq;
create view kassa_qoldiq with (security_invoker = on) as
select k.kassa,
       coalesce(sum(case when y.yonalish = 'kirim' then y.summa else -y.summa end), 0) as qoldiq
from (values ('naqd'), ('karta'), ('bank'), ('dollar')) as k(kassa)
left join kassa_yozuvlar y on y.kassa = k.kassa
group by k.kassa;
grant select on kassa_qoldiq to authenticated;

-- (o'chirib qayta yaratiladi: bazadagi eski ko'rinishda boshqa ustunlar bo'lishi mumkin)
drop view if exists mijoz_qoldiq;
create view mijoz_qoldiq with (security_invoker = on) as
select m.id, m.nomi, m.telefon,
       coalesce(sum(y.summa), 0) as qoldiq,
       max(y.sana)               as oxirgi_yozuv,
       m.valyuta
from mijozlar m
left join yozuvlar y on y.mijoz_id = m.id
group by m.id;
grant select on mijoz_qoldiq to authenticated;

-- To'lov kassasi mijoz valyutasiga mos bo'lsin
create or replace function d_valyuta_kassa() returns trigger
language plpgsql as $$
declare v text;
begin
  if new.kassa is null or current_setting('lumant.birlashtirish', true) = 'ha' then return new; end if;
  select valyuta into v from mijozlar where id = new.mijoz_id;
  if v = 'USD' and new.kassa <> 'dollar' then
    raise exception 'Dollar hisobidagi mijozning to''lovi faqat Dollar kassaga tushadi';
  end if;
  if coalesce(v, 'UZS') = 'UZS' and new.kassa = 'dollar' then
    raise exception 'So''m hisobidagi mijozning to''lovi Dollar kassaga tushmaydi';
  end if;
  return new;
end $$;
create trigger d_valyuta_kassa before insert or update on yozuvlar
  for each row execute function d_valyuta_kassa();

-- Yozuvi bor mijozning valyutasini almashtirib bo'lmaydi (eski summalar buziladi)
create or replace function mijoz_valyuta_tekshir() returns trigger
language plpgsql as $$
begin
  if new.valyuta is distinct from old.valyuta
     and exists (select 1 from yozuvlar where mijoz_id = old.id) then
    raise exception 'Bu mijozda yozuvlar bor — valyutasini o''zgartirib bo''lmaydi';
  end if;
  return new;
end $$;
create trigger mijoz_valyuta_tekshir before update on mijozlar
  for each row execute function mijoz_valyuta_tekshir();

-- ---------------------------------------------------------------------
-- 3. MAXSUS NARXLAR: shu mijozga shu mahsulot shu narxda
-- ---------------------------------------------------------------------
create table mijoz_narx (
  mijoz_id     bigint not null references mijozlar(id) on delete cascade,
  mahsulot_id  bigint not null references mahsulotlar(id) on delete cascade,
  narx         numeric not null check (narx >= 0),
  primary key (mijoz_id, mahsulot_id)
);
alter table mijoz_narx enable row level security;
create policy "rol: ko'radi"   on mijoz_narx for select to authenticated using (rolim() is not null);
create policy "rol: qo'shadi"  on mijoz_narx for insert to authenticated with check (rol_bor('admin','rahbar','sotuvchi'));
create policy "rol: tahrir"    on mijoz_narx for update to authenticated using (rol_bor('admin','rahbar','sotuvchi'));
create policy "rol: o'chiradi" on mijoz_narx for delete to authenticated using (rol_bor('admin','rahbar','sotuvchi'));
grant select, insert, update, delete on mijoz_narx to authenticated;

-- ---------------------------------------------------------------------
-- 4. BUYURTMALAR
--    holat: yangi → bajarildi (yozuv kiritildi) yoki bekor
-- ---------------------------------------------------------------------
create table buyurtmalar (
  id               bigint generated always as identity primary key,
  sana             date not null,                 -- yetkazish kuni
  vaqt             text,                          -- "09:00", "tushdan keyin"
  mijoz_id         bigint not null references mijozlar(id),
  mahsulot_id      bigint not null references mahsulotlar(id),
  miqdor           numeric not null check (miqdor > 0),
  narx             numeric check (narx >= 0),
  manzil           text,
  telefon          text,
  avto_raqami      text,
  izoh             text,
  holat            text not null default 'yangi' check (holat in ('yangi','bajarildi','bekor')),
  yozuv_id         bigint references yozuvlar(id),
  kiritgan         uuid default auth.uid(),
  kiritilgan_vaqt  timestamptz not null default now()
);
create index buyurtmalar_sana_idx on buyurtmalar (sana, id);

alter table buyurtmalar enable row level security;
create policy "rol: ko'radi"  on buyurtmalar for select to authenticated
  using (rol_bor('admin','rahbar','sotuvchi','omborchi'));
create policy "rol: qo'shadi" on buyurtmalar for insert to authenticated
  with check (rol_bor('admin','rahbar','sotuvchi'));
create policy "rol: tahrir"   on buyurtmalar for update to authenticated
  using (rol_bor('admin','rahbar','sotuvchi'));
grant select, insert, update on buyurtmalar to authenticated;

-- ---------------------------------------------------------------------
-- 4b. MIJOZLARNI BIRLASHTIRISH (07 dagi funksiyaning yangi varianti):
--     valyuta tekshiruvi; maxsus narxlar va buyurtmalar ham ko'chadi
-- ---------------------------------------------------------------------
create or replace function mijoz_birlashtir(p_qoladi bigint, p_ochiriladi bigint) returns int
language plpgsql security definer set search_path = public as $$
declare
  n int;
  k mijozlar%rowtype;
  d mijozlar%rowtype;
begin
  if not rol_bor('admin','rahbar') then
    raise exception 'Mijozlarni faqat admin yoki rahbar birlashtira oladi';
  end if;
  if p_qoladi = p_ochiriladi then raise exception 'Bir xil mijozni tanladingiz'; end if;
  select * into k from mijozlar where id = p_qoladi;
  select * into d from mijozlar where id = p_ochiriladi;
  if k.id is null or d.id is null then raise exception 'Mijoz topilmadi'; end if;
  if k.valyuta is distinct from d.valyuta then
    raise exception 'Biri so''mda, biri dollarda — bu mijozlarni birlashtirib bo''lmaydi';
  end if;

  perform set_config('lumant.birlashtirish', 'ha', true);   -- faqat shu tranzaksiya uchun
  update yozuvlar set mijoz_id = k.id where mijoz_id = d.id;
  get diagnostics n = row_count;
  perform set_config('lumant.birlashtirish', '', true);

  update buyurtmalar set mijoz_id = k.id where mijoz_id = d.id;
  insert into mijoz_narx (mijoz_id, mahsulot_id, narx)
    select k.id, mahsulot_id, narx from mijoz_narx where mijoz_id = d.id
    on conflict do nothing;          -- "qoladi" mijozning o'z narxi ustun
  delete from mijoz_narx where mijoz_id = d.id;

  update mijozlar set
    telefon = coalesce(nullif(k.telefon, ''), d.telefon),
    izoh    = concat_ws(' · ', nullif(k.izoh, ''), nullif(d.izoh, ''), 'birlashtirildi: ' || d.nomi)
  where id = k.id;
  delete from mijozlar where id = d.id;
  return n;
end $$;

-- ---------------------------------------------------------------------
-- 5. TARIX: yangi jadvallar ham kuzatiladi
--    (mijoz_narx'da "id" yo'q — tarixda yozuv raqami bo'sh qoladi)
-- ---------------------------------------------------------------------
create trigger tarix after insert or update or delete on sozlamalar  for each row execute function tarixga();
create trigger tarix after insert or update or delete on mijoz_narx  for each row execute function tarixga();
create trigger tarix after insert or update or delete on buyurtmalar for each row execute function tarixga();
