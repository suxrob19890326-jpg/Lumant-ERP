-- =====================================================================
-- LUMANT ERP — 2-qadam: Excel ("DT KT Mamurjon") bilan bir xil bo'lishi
-- uchun qo'shimcha ustunlar va jadvallar.
-- 01_jadvallar.sql dan KEYIN, 03_malumotlar.sql dan OLDIN ishga tushiring.
-- Supabase → SQL Editor → New query → shu faylni to'liq qo'yib → Run
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. MIJOZLAR: Sheets'dagi qolgan ustunlar
-- ---------------------------------------------------------------------
alter table mijozlar add column if not exists bifoza_nomi  text;   -- Бифозадаги номи
alter table mijozlar add column if not exists takror_guruh text;   -- Такрор гурух №
alter table mijozlar add column if not exists kochirildi   date;   -- Кўчирилди (✅ sana)
alter table mijozlar add column if not exists tartib       int;    -- Sheets'dagi qator tartibi


-- ---------------------------------------------------------------------
-- 2. MAHSULOTLAR: "Тури" ustuni (Тулов = pul turi: накд, переч, клик...)
-- ---------------------------------------------------------------------
alter table mahsulotlar add column if not exists turi   text;
alter table mahsulotlar add column if not exists tartib int;


-- ---------------------------------------------------------------------
-- 3. YOZUVLAR: kiritgan xodim ismi va Arxiv raqami
--    (kiritgan uuid — ERP'da yangi yozuvlar uchun; eski yozuvlarda
--     Sheets'dagi ism kiritgan_ismi ga yoziladi)
-- ---------------------------------------------------------------------
alter table yozuvlar add column if not exists kiritgan_ismi text;  -- Киритган
alter table yozuvlar add column if not exists arxiv_no      int;   -- Архив №
alter table yozuvlar add column if not exists tartib        int;   -- Sheets'dagi qator raqami


-- ---------------------------------------------------------------------
-- 4. ARXIV (Sheets'dagi "Arxiv" varag'i) — eski yozuvlar, faqat o'qish.
--    Qoldiqqa qo'shilmaydi (Sheets'da ham shunday).
--    Raqam bo'lmagan qiymatlar (m: "5000$") asl_matn ga yoziladi.
-- ---------------------------------------------------------------------
create table if not exists arxiv (
  qator            int primary key,          -- Sheets'dagi qator raqami (Архив №)
  sana             date,
  sana_matn        text,                     -- sana o'rnida matn bo'lsa (m: "25- yildan")
  nomi             text,                     -- Номи (mijoz nomi, matn holida)
  mahsulot         text,                     -- Махсулот номи
  olchov           text,                     -- Ул бир.
  miqdor           numeric,
  narx             numeric,
  summa            numeric,
  avto_raqami      text,
  izoh             text,
  qulf             boolean not null default true,
  kiritgan_ismi    text,
  kiritilgan_vaqt  timestamptz,
  asl_matn         jsonb                     -- raqam o'rnida yozilgan matnlar
);
create index if not exists arxiv_nomi_idx on arxiv (nomi, sana);


-- ---------------------------------------------------------------------
-- 5. BIFOZA QOLDIQ ("Bifoza sverka" / "Bifozadagi ostatka" varag'lari)
-- ---------------------------------------------------------------------
create table if not exists bifoza_qoldiq (
  id           bigint generated always as identity primary key,
  holat_sana   date not null default date '2026-11-15',
  turi         text,                         -- Mijoz / Ta'minotchi
  nomi         text not null,                -- Nomi (Bifozada)
  telefon      text,
  oxirgi_savdo date,
  bizga_qarz   numeric not null default 0,   -- Bizga qarzdor (so'm)
  biz_qarz     numeric not null default 0,   -- Biz qarzdormiz / haqdor (so'm)
  izoh         text,
  tartib       int
);
create index if not exists bifoza_nomi_idx on bifoza_qoldiq (nomi);


-- ---------------------------------------------------------------------
-- 6. SEX: tayyor mahsulot ("Sex ostatka") va ishlab chiqarish ("Sex kirim")
-- ---------------------------------------------------------------------
create table if not exists sex_mahsulotlar (
  nomi                text primary key,
  boshlangich_qoldiq  numeric,               -- 15.11.2026 sanoq
  tartib              int
);

create table if not exists sex_kirim (
  id         bigint generated always as identity primary key,
  sana       date not null default current_date,
  mahsulot   text not null,
  olchov     text,
  soni       numeric not null,
  izoh       text,
  kiritilgan_vaqt timestamptz not null default now()
);


-- ---------------------------------------------------------------------
-- 7. O'LCHOV BIRLIKLARI ("Olchovlar") va O'ZGARISHLAR JURNALI ("Ozgarishlar")
-- ---------------------------------------------------------------------
create table if not exists olchovlar (
  nomi   text primary key,
  tartib int
);

create table if not exists ozgarishlar (
  id      bigint generated always as identity primary key,
  qator   text,                              -- Qator (raqam yoki vaqt)
  eski    text,                              -- Eski qiymat
  yangi   text,                              -- Yangi sana / qiymat
  sabab   text,
  tartib  int
);


-- ---------------------------------------------------------------------
-- 8. MIJOZ QOLDIG'I — Sheets'dagi "Mijozlar" varag'i formulalari bilan bir xil:
--    Колдик = Asosiy'dagi summalar yig'indisi, LEKIN faqat "Кўчирилди"
--    belgilangan mijozlarda; belgilanmaganlarda 0 (Sheets'da ham 0).
--    yozuvlar_jami — belgidan qat'i nazar haqiqiy yig'indi.
-- ---------------------------------------------------------------------
drop view if exists mijoz_qoldiq;
create view mijoz_qoldiq with (security_invoker = on) as
with y as (
  select mijoz_id, sum(summa) as jami, max(sana) as oxirgi
  from yozuvlar group by mijoz_id
),
b as (
  select distinct on (nomi) nomi, bizga_qarz - biz_qarz as qarz
  from bifoza_qoldiq
  order by nomi, (turi = 'Mijoz') desc, tartib
)
select
  m.id,
  m.nomi,
  m.telefon,
  case when m.kochirildi is null then 0 else coalesce(y.jami, 0) end as qoldiq,
  y.oxirgi                                                  as oxirgi_yozuv,
  case
    when m.kochirildi is not null and coalesce(y.jami,0) > 0 then 'Карздор'
    when m.kochirildi is not null and coalesce(y.jami,0) < 0 then 'Хакдор (олдиндан тулаган)'
    else 'Хисоб ёпик'
  end                                                       as holat,
  m.bifoza_nomi,
  case when coalesce(m.bifoza_nomi,'') = '' then null
       else coalesce(b.qarz, 0) end                         as bifoza_qarzi,
  case when coalesce(m.bifoza_nomi,'') = '' then null
       else (case when m.kochirildi is null then 0 else coalesce(y.jami,0) end)
            - coalesce(b.qarz, 0) end                       as farq,
  m.takror_guruh,
  m.kochirildi,
  coalesce(y.jami, 0)                                       as yozuvlar_jami,
  m.tartib
from mijozlar m
left join y on y.mijoz_id = m.id
left join b on b.nomi = m.bifoza_nomi;


-- ---------------------------------------------------------------------
-- 9. SEX QOLDIG'I ("Sex ostatka" formulasi): boshlang'ich + kirim − sotuv
--    (15.11.2026 dan boshlab)
-- ---------------------------------------------------------------------
create or replace view sex_qoldiq with (security_invoker = on) as
select
  s.nomi,
  s.boshlangich_qoldiq,
  coalesce((select sum(k.soni) from sex_kirim k
            where lower(k.mahsulot) = lower(s.nomi) and k.sana >= date '2026-11-15'), 0) as ishlab_chiqarildi,
  coalesce((select sum(y.miqdor) from yozuvlar y join mahsulotlar p on p.id = y.mahsulot_id
            where lower(p.nomi) = lower(s.nomi) and y.turi = 'yuk_berildi'
              and y.sana >= date '2026-11-15'), 0)                                    as sotildi,
  s.tartib
from sex_mahsulotlar s;


-- ---------------------------------------------------------------------
-- 10. XAVFSIZLIK (RLS)
-- ---------------------------------------------------------------------
alter table arxiv           enable row level security;
alter table bifoza_qoldiq   enable row level security;
alter table sex_mahsulotlar enable row level security;
alter table sex_kirim       enable row level security;
alter table olchovlar       enable row level security;
alter table ozgarishlar     enable row level security;

-- Arxiv — faqat o'qish
create policy "kirganlar ko'radi" on arxiv for select to authenticated using (true);

create policy "kirganlar ko'radi"     on bifoza_qoldiq for select to authenticated using (true);
create policy "kirganlar qo'shadi"    on bifoza_qoldiq for insert to authenticated with check (true);
create policy "kirganlar tahrirlaydi" on bifoza_qoldiq for update to authenticated using (true);

create policy "kirganlar ko'radi"     on sex_mahsulotlar for select to authenticated using (true);
create policy "kirganlar qo'shadi"    on sex_mahsulotlar for insert to authenticated with check (true);
create policy "kirganlar tahrirlaydi" on sex_mahsulotlar for update to authenticated using (true);

create policy "kirganlar ko'radi"     on sex_kirim for select to authenticated using (true);
create policy "kirganlar qo'shadi"    on sex_kirim for insert to authenticated with check (true);
create policy "kirganlar tahrirlaydi" on sex_kirim for update to authenticated using (true);

create policy "kirganlar ko'radi"     on olchovlar for select to authenticated using (true);
create policy "kirganlar qo'shadi"    on olchovlar for insert to authenticated with check (true);

create policy "kirganlar ko'radi"     on ozgarishlar for select to authenticated using (true);
create policy "kirganlar qo'shadi"    on ozgarishlar for insert to authenticated with check (true);

grant select on arxiv to authenticated;
grant select, insert, update on bifoza_qoldiq, sex_mahsulotlar, sex_kirim to authenticated;
grant select, insert on olchovlar, ozgarishlar to authenticated;
grant select on mijoz_qoldiq, sex_qoldiq to authenticated;
