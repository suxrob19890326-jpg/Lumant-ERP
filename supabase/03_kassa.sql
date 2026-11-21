-- =====================================================================
-- LUMANT ERP — 3-qadam: KASSA
-- Supabase → SQL Editor → New query → shu faylni to'liq qo'yib → Run
-- (01 va 02 fayllardan keyin, BIR MARTA ishga tushiriladi)
--
-- 3 ta kassa: naqd, karta, bank.
-- Mijozdan "To'lov keldi" yoki yetkazib beruvchiga "Pul berildi" yozuvi
-- kassa tanlanib kiritilsa — kassaga O'ZI tushadi (kirim / chiqim).
-- Eski (ko'chirilgan) yozuvlarda kassa yo'q, ular kassaga tushmaydi.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Yozuvlarga "qaysi kassa" ustuni (faqat to'lov turlari uchun)
-- ---------------------------------------------------------------------
alter table yozuvlar add column if not exists kassa text
  check (kassa in ('naqd','karta','bank'));


-- ---------------------------------------------------------------------
-- 2. KASSA YOZUVLARI
--    yonalish: kirim (+) yoki chiqim (−). summa har doim musbat.
--    yozuv_id: yozuvlar jadvalidan o'zi kelgan bo'lsa, o'sha yozuv.
-- ---------------------------------------------------------------------
create table kassa_yozuvlar (
  id               bigint generated always as identity primary key,
  sana             date not null default current_date,
  kassa            text not null check (kassa in ('naqd','karta','bank')),
  yonalish         text not null check (yonalish in ('kirim','chiqim')),
  summa            numeric not null check (summa > 0),
  toifa            text,                     -- Oylik, Yoqilg'i, O'tkazma ...
  izoh             text,
  yozuv_id         bigint unique references yozuvlar(id),
  kiritgan         uuid default auth.uid(),
  kiritilgan_vaqt  timestamptz not null default now()
);

create index kassa_yozuvlar_sana_idx on kassa_yozuvlar (sana, id);


-- ---------------------------------------------------------------------
-- 3. To'lov yozuvi → kassaga avtomatik
--    security definer: kassa jadvalidagi cheklovlardan o'tib yozadi
--    (xodim bog'langan kassa yozuvini qo'lda o'zgartira olmaydi).
-- ---------------------------------------------------------------------
create or replace function yozuv_kassaga() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.turi in ('tolov_keldi','pul_berildi')
     and new.kassa is not null and coalesce(new.summa, 0) <> 0 then
    insert into kassa_yozuvlar (sana, kassa, yonalish, summa, toifa, izoh, yozuv_id, kiritgan)
    values (
      new.sana, new.kassa,
      case when new.turi = 'tolov_keldi' then 'kirim' else 'chiqim' end,
      abs(new.summa),
      case when new.turi = 'tolov_keldi' then 'Mijoz to''lovi' else 'Yetkazib beruvchiga' end,
      new.izoh, new.id, new.kiritgan
    )
    on conflict (yozuv_id) do update set
      sana = excluded.sana, kassa = excluded.kassa, yonalish = excluded.yonalish,
      summa = excluded.summa, toifa = excluded.toifa, izoh = excluded.izoh;
  else
    -- turi yoki kassasi o'zgartirilgan bo'lsa, eski kassa yozuvi olib tashlanadi
    delete from kassa_yozuvlar where yozuv_id = new.id;
  end if;
  return null;
end $$;

create trigger yozuv_kassaga
  after insert or update on yozuvlar
  for each row execute function yozuv_kassaga();


-- ---------------------------------------------------------------------
-- 4. KASSA QOLDIG'I — o'zi hisoblanadi
-- ---------------------------------------------------------------------
create view kassa_qoldiq with (security_invoker = on) as
select k.kassa,
       coalesce(sum(case when y.yonalish = 'kirim' then y.summa else -y.summa end), 0) as qoldiq
from (values ('naqd'), ('karta'), ('bank')) as k(kassa)
left join kassa_yozuvlar y on y.kassa = k.kassa
group by k.kassa;


-- ---------------------------------------------------------------------
-- 5. XAVFSIZLIK: faqat kirganlar. O'chirish yo'q.
--    Qo'lda faqat bog'lanmagan (yozuv_id bo'sh) yozuv qo'shiladi.
--    Kassa yozuvlarini o'zgartirish ham yo'q — xato bo'lsa teskari yozuv.
-- ---------------------------------------------------------------------
alter table kassa_yozuvlar enable row level security;

create policy "kirganlar ko'radi"  on kassa_yozuvlar for select to authenticated using (true);
create policy "kirganlar qo'shadi" on kassa_yozuvlar for insert to authenticated
  with check (yozuv_id is null);

grant select, insert on kassa_yozuvlar to authenticated;
grant select on kassa_qoldiq to authenticated;
