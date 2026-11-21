-- =====================================================================
-- LUMANT ERP — 5-qadam: TAKROR MAHSULOTLARNI BIRLASHTIRISH
-- Supabase → SQL Editor → New query → shu faylni to'liq qo'yib → Run
--
-- Har juftlikda: "o'chiriladi" mahsulotning barcha yozuvlari va ombor
-- harakatlari "qoladi" mahsulotga o'tkaziladi, keyin u o'chiriladi.
-- Bo'sh narx / o'lchov / turkum o'chirilayotganidan olinadi.
--
-- Xavfsiz: hammasi bitta tranzaksiyada (xato bo'lsa hech narsa o'zgarmaydi).
-- Qayta ishga tushirilsa zarari yo'q — topilmagan juftlik o'tkazib yuboriladi.
-- 03 / 04 fayllar ishga tushirilgan yoki tushirilmaganidan qat'i nazar ishlaydi.
-- =====================================================================

do $$
declare
  j record;
  k mahsulotlar%rowtype;
  d mahsulotlar%rowtype;
  n_yozuv int;
  n_ombor int := 0;
  bor_turkum boolean := exists (select 1 from information_schema.columns
                                where table_schema = 'public' and table_name = 'mahsulotlar' and column_name = 'turkum');
  bor_ombor  boolean := to_regclass('public.ombor_harakat') is not null;
begin
  -- Qulflangan eski yozuvlarni ham ko'chirish uchun yozuvlar triggerlari
  -- vaqtincha o'chiriladi (summa va qulf o'zgarmaydi, faqat mahsulot_id).
  alter table yozuvlar disable trigger user;

  for j in
    select * from (values
      ('Цемент',          'семент'),
      ('лестиниса 59/12', 'лестиниса 59'),
      ('вр сим 3,5',      'сим 3,5'),
      ('кришка 1,2',      'кришка'),
      ('колодес 10/90',   'колодес 1/09')
    ) as t(qoladi, ochiriladi)
  loop
    select * into k from mahsulotlar where nomi = j.qoladi;
    select * into d from mahsulotlar where nomi = j.ochiriladi;
    if k.id is null or d.id is null then
      raise notice 'O''tkazib yuborildi (topilmadi): % ← %', j.qoladi, j.ochiriladi;
      continue;
    end if;

    update mahsulotlar set
      oxirgi_narx = coalesce(k.oxirgi_narx, d.oxirgi_narx),
      olchov      = coalesce(nullif(k.olchov, ''), d.olchov)
    where id = k.id;
    if bor_turkum then
      execute 'update mahsulotlar set turkum = coalesce(turkum, (select turkum from mahsulotlar where id = $2)) where id = $1'
        using k.id, d.id;
    end if;

    update yozuvlar set mahsulot_id = k.id where mahsulot_id = d.id;
    get diagnostics n_yozuv = row_count;

    if bor_ombor then
      execute 'update ombor_harakat set mahsulot_id = $1 where mahsulot_id = $2' using k.id, d.id;
      get diagnostics n_ombor = row_count;
    end if;

    delete from mahsulotlar where id = d.id;
    raise notice 'Birlashtirildi: "%" ← "%" (% ta yozuv, % ta ombor harakati)',
      j.qoladi, j.ochiriladi, n_yozuv, n_ombor;
  end loop;

  alter table yozuvlar enable trigger user;
end $$;

-- Tekshiruv: bu ro'yxatda faqat qolgan nomlar ko'rinishi kerak
select nomi, olchov, oxirgi_narx,
       (select count(*) from yozuvlar y where y.mahsulot_id = m.id) as yozuvlar
from mahsulotlar m
where nomi in ('Цемент','семент','лестиниса 59/12','лестиниса 59','вр сим 3,5','сим 3,5',
               'кришка 1,2','кришка','колодес 10/90','колодес 1/09')
order by nomi;
