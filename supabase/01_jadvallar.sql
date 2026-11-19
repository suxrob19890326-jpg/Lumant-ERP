-- =====================================================================
-- LUMANT ERP — 1-qadam: asosiy jadvallar
-- "DT KT Mamurjon" Google Sheets faylidan andoza olingan.
-- Supabase → SQL Editor → New query → shu faylni to'liq qo'yib → Run
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. MIJOZLAR (Sheets'dagi "Mijozlar" varag'i)
-- ---------------------------------------------------------------------
create table mijozlar (
  id          bigint generated always as identity primary key,
  nomi        text not null unique,          -- Mijoz nomi (takrorlanmaydi)
  telefon     text,
  izoh        text,
  created_at  timestamptz not null default now()
);


-- ---------------------------------------------------------------------
-- 2. MAHSULOTLAR (Sheets'dagi "Mahsulotlar" varag'i)
-- ---------------------------------------------------------------------
create table mahsulotlar (
  id           bigint generated always as identity primary key,
  nomi         text not null unique,         -- M 200, песок, Пк 62/12 ...
  olchov       text,                         -- куб, м3, дона ...
  oxirgi_narx  numeric,                      -- tanlaganda narx o'zi qo'yiladi
  created_at   timestamptz not null default now()
);


-- ---------------------------------------------------------------------
-- 3. YOZUVLAR (Sheets'dagi "Asosiy" varag'i)
--    turi: xodim tugmani tanlaydi, + / − belgini baza o'zi qo'yadi
--      yuk_berildi      → +  (mijozga mahsulot berdik, u bizdan qarz)
--      tolov_keldi      → −  (mijoz pul to'ladi)
--      mahsulot_olindi  → −  (biz yetkazib beruvchidan oldik, m: graviy)
--      pul_berildi      → +  (biz yetkazib beruvchiga pul berdik)
-- ---------------------------------------------------------------------
create table yozuvlar (
  id               bigint generated always as identity primary key,
  sana             date not null default current_date,
  mijoz_id         bigint not null references mijozlar(id),
  turi             text not null check (turi in
                     ('yuk_berildi','tolov_keldi','mahsulot_olindi','pul_berildi')),
  mahsulot_id      bigint references mahsulotlar(id),   -- to'lovda bo'sh qoladi
  olchov           text,                     -- Ул бир.
  miqdor           numeric,                  -- Микдори
  narx             numeric,                  -- Нархи
  summa            numeric,                  -- Сумма (belgisi avtomatik)
  avto_raqami      text,                     -- Авто раками
  izoh             text,                     -- Изох
  qulf             boolean not null default false,       -- Кулф
  kiritgan         uuid default auth.uid(),              -- Киритган (avtomatik)
  kiritilgan_vaqt  timestamptz not null default now()    -- Киритилган вакт
);

create index yozuvlar_mijoz_idx on yozuvlar (mijoz_id, sana);


-- ---------------------------------------------------------------------
-- 4. AVTOMATIK HISOB: summa = miqdor × narx, belgi turiga qarab
-- ---------------------------------------------------------------------
create or replace function b_yozuv_tayyorla() returns trigger
language plpgsql as $$
begin
  if new.miqdor is not null then
    new.miqdor := abs(new.miqdor);
  end if;

  if new.summa is null and new.miqdor is not null and new.narx is not null then
    new.summa := new.miqdor * new.narx;
  end if;

  if new.summa is not null then
    new.summa := abs(new.summa) *
      case when new.turi in ('yuk_berildi','pul_berildi') then 1 else -1 end;
  end if;

  return new;
end $$;

create trigger b_yozuv_tayyorla
  before insert or update on yozuvlar
  for each row execute function b_yozuv_tayyorla();


-- ---------------------------------------------------------------------
-- 5. QULF: qulflangan yozuvni HECH KIM o'zgartira yoki o'chira olmaydi
--    Kim kiritgani va qachon kiritilgani ham o'zgartirilmaydi.
-- ---------------------------------------------------------------------
create or replace function a_qulf_tekshir() returns trigger
language plpgsql as $$
begin
  if old.qulf then
    raise exception 'Bu yozuv qulflangan, uni o''zgartirib bo''lmaydi';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  new.kiritgan        := old.kiritgan;
  new.kiritilgan_vaqt := old.kiritilgan_vaqt;
  return new;
end $$;

create trigger a_qulf_tekshir
  before update or delete on yozuvlar
  for each row execute function a_qulf_tekshir();


-- ---------------------------------------------------------------------
-- 6. MIJOZ QOLDIG'I (Sheets'dagi "Колдик (карз)" ustuni) — o'zi hisoblanadi
-- ---------------------------------------------------------------------
create view mijoz_qoldiq with (security_invoker = on) as
select
  m.id,
  m.nomi,
  m.telefon,
  coalesce(sum(y.summa), 0) as qoldiq,
  max(y.sana)               as oxirgi_yozuv
from mijozlar m
left join yozuvlar y on y.mijoz_id = m.id
group by m.id;


-- ---------------------------------------------------------------------
-- 7. XAVFSIZLIK (RLS): faqat tizimga kirgan xodimlar ishlay oladi.
--    O'chirish (DELETE) ruxsati hech kimga berilmagan.
-- ---------------------------------------------------------------------
alter table mijozlar    enable row level security;
alter table mahsulotlar enable row level security;
alter table yozuvlar    enable row level security;

create policy "kirganlar ko'radi"   on mijozlar    for select to authenticated using (true);
create policy "kirganlar qo'shadi"  on mijozlar    for insert to authenticated with check (true);
create policy "kirganlar tahrirlaydi" on mijozlar  for update to authenticated using (true);

create policy "kirganlar ko'radi"   on mahsulotlar for select to authenticated using (true);
create policy "kirganlar qo'shadi"  on mahsulotlar for insert to authenticated with check (true);
create policy "kirganlar tahrirlaydi" on mahsulotlar for update to authenticated using (true);

create policy "kirganlar ko'radi"   on yozuvlar    for select to authenticated using (true);
create policy "kirganlar qo'shadi"  on yozuvlar    for insert to authenticated with check (true);
create policy "kirganlar tahrirlaydi" on yozuvlar  for update to authenticated using (true);

grant select, insert, update on mijozlar, mahsulotlar, yozuvlar to authenticated;
grant select on mijoz_qoldiq to authenticated;
