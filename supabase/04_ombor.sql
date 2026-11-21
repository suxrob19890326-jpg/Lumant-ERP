-- =====================================================================
-- LUMANT ERP — 4-qadam: OMBOR
-- Supabase → SQL Editor → New query → shu faylni to'liq qo'yib → Run
-- (01, 02, 03 fayllardan keyin, BIR MARTA ishga tushiriladi)
--
-- Xomashyo va tayyor mahsulot (beton ham) qoldig'i.
-- Bundan keyin kiritilgan yozuvlar omborga O'ZI tushadi:
--   "Mahsulot olindi" → omborga kirim
--   "Yuk berildi"     → ombordan chiqim
-- Eski (ko'chirilgan) yozuvlar omborga tushmaydi — boshlang'ich qoldiq
-- ombor sahifasidagi "Sanoq" orqali kiritiladi.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Mahsulot turkumi: xomashyo yoki tayyor (bo'sh = belgilanmagan)
-- ---------------------------------------------------------------------
alter table mahsulotlar add column if not exists turkum text
  check (turkum in ('xomashyo','tayyor'));

-- Nomiga qarab taxminiy belgilash (keyin sahifada o'zgartirsa bo'ladi)
update mahsulotlar set turkum = case
  -- beton (М 200...), plitalar (Пк, Фс), blok, zinapoya, ustun, quduq halqalari
  when nomi ~ '^\s*([пП][кК]|[фФ][сС]|[мМ]\s*[0-9]|[кК][сС]\s)'
    or nomi ~ '([бБ]лок|[шШ]лака|[сС]толб|[лЛ]ести|[бБ]ордюр|[кК]олоде|[кК]р[иы]шка|[дД]ниш)' then 'tayyor'
  -- inert materiallar, sement, metall (armatura, sim, setka, profil...)
  when nomi ~ '([пП]есок|[гГ]равий|[гГ]алка|[сСцЦ]емент|[мМ]етал|[кК]омпот|[кК]айрок|[щЩ]ебен|[дД]обавк|[сС]иликат)'
    or nomi ~ '(^\s*[аА]рм|(^|\s)[сС]им(\s|$)|[сС]етка|[гГ]ладкий|[шШ]веллер|[уУ]голник|[пП]рофил|^\s*[лЛ]ист|^\s*[тТ]руба)' then 'xomashyo'
end
where turkum is null;


-- ---------------------------------------------------------------------
-- 2. OMBOR HARAKATLARI
--    sabab: olindi (yetkazib beruvchidan), sotildi (mijozga),
--           ishlab_chiqarildi, sarflandi (ishlab chiqarishga),
--           sanoq (inventarizatsiya farqi), boshqa
-- ---------------------------------------------------------------------
create table ombor_harakat (
  id               bigint generated always as identity primary key,
  sana             date not null default current_date,
  mahsulot_id      bigint not null references mahsulotlar(id),
  yonalish         text not null check (yonalish in ('kirim','chiqim')),
  miqdor           numeric not null check (miqdor > 0),
  sabab            text not null check (sabab in
                     ('olindi','sotildi','ishlab_chiqarildi','sarflandi','sanoq','boshqa')),
  izoh             text,
  yozuv_id         bigint unique references yozuvlar(id),
  kiritgan         uuid default auth.uid(),
  kiritilgan_vaqt  timestamptz not null default now()
);

create index ombor_harakat_mahsulot_idx on ombor_harakat (mahsulot_id, sana);


-- ---------------------------------------------------------------------
-- 3. Yozuv → omborga avtomatik
--    Yangi yozuv: olindi → kirim, yuk berildi → chiqim.
--    Tahrir: faqat omborga allaqachon tushgan yozuvlar yangilanadi
--    (eski ko'chirilgan yozuvlar tahrirlansa ham omborga tushmaydi).
-- ---------------------------------------------------------------------
create or replace function yozuv_omborga() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE'
     and not exists (select 1 from ombor_harakat where yozuv_id = new.id) then
    return null;
  end if;

  if new.turi in ('mahsulot_olindi','yuk_berildi')
     and new.mahsulot_id is not null and coalesce(new.miqdor, 0) <> 0 then
    insert into ombor_harakat (sana, mahsulot_id, yonalish, miqdor, sabab, izoh, yozuv_id, kiritgan)
    values (
      new.sana, new.mahsulot_id,
      case when new.turi = 'mahsulot_olindi' then 'kirim' else 'chiqim' end,
      abs(new.miqdor),
      case when new.turi = 'mahsulot_olindi' then 'olindi' else 'sotildi' end,
      new.izoh, new.id, new.kiritgan
    )
    on conflict (yozuv_id) do update set
      sana = excluded.sana, mahsulot_id = excluded.mahsulot_id, yonalish = excluded.yonalish,
      miqdor = excluded.miqdor, sabab = excluded.sabab, izoh = excluded.izoh;
  else
    delete from ombor_harakat where yozuv_id = new.id;
  end if;
  return null;
end $$;

create trigger yozuv_omborga
  after insert or update on yozuvlar
  for each row execute function yozuv_omborga();


-- ---------------------------------------------------------------------
-- 4. OMBOR QOLDIG'I — o'zi hisoblanadi
-- ---------------------------------------------------------------------
create view ombor_qoldiq with (security_invoker = on) as
select m.id, m.nomi, m.olchov, m.turkum,
       coalesce(sum(case when h.yonalish = 'kirim' then h.miqdor else -h.miqdor end), 0) as qoldiq,
       count(h.id) as harakatlar,
       max(h.sana) as oxirgi
from mahsulotlar m
left join ombor_harakat h on h.mahsulot_id = m.id
group by m.id;


-- ---------------------------------------------------------------------
-- 5. XAVFSIZLIK: faqat kirganlar. O'chirish va o'zgartirish yo'q.
--    Qo'lda faqat yozuvga bog'lanmagan harakat qo'shiladi.
-- ---------------------------------------------------------------------
alter table ombor_harakat enable row level security;

create policy "kirganlar ko'radi"  on ombor_harakat for select to authenticated using (true);
create policy "kirganlar qo'shadi" on ombor_harakat for insert to authenticated
  with check (yozuv_id is null);

grant select, insert on ombor_harakat to authenticated;
grant select on ombor_qoldiq to authenticated;
