-- =====================================================================
-- LUMANT ERP — bazadagi ESKI mijozlar / mahsulotlar / yozuvlarni tozalash
-- (03_malumotlar.sql "Bazada allaqachon yozuvlar bor" deb to'xtagan bo'lsa)
--
-- Eski ma'lumot O'CHIB KETMAYDI: avval "zaxira" sxemasiga nusxalanadi
-- (u sxema API orqali ko'rinmaydi). Keyin jadvallar bo'shatiladi.
-- Shundan keyin 03_malumotlar.sql ni qayta ishga tushiring.
-- Faqat BIR marta ishlaydi (zaxira ustidan yozib yubormaslik uchun).
-- Arxiv, 02 va 04 fayllariga tegilmaydi.
-- =====================================================================
begin;

create schema if not exists zaxira;
revoke all on schema zaxira from public, anon, authenticated;

create table zaxira.yozuvlar    as select * from public.yozuvlar;
create table zaxira.mijozlar    as select * from public.mijozlar;
create table zaxira.mahsulotlar as select * from public.mahsulotlar;

-- TRUNCATE qulf triggerini chetlab o'tadi (qulflangan yozuvlar ham tozalanadi)
truncate public.yozuvlar, public.mijozlar, public.mahsulotlar restart identity;

commit;

select (select count(*) from zaxira.yozuvlar)    as zaxiradagi_yozuvlar,
       (select count(*) from zaxira.mijozlar)    as zaxiradagi_mijozlar,
       (select count(*) from zaxira.mahsulotlar) as zaxiradagi_mahsulotlar;
