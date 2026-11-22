-- =====================================================================
-- LUMANT ERP — 12-qadam: BUYURTMALAR — BO'LIB YETKAZISH, KREDIT LIMITI
-- Supabase → SQL Editor → New query → shu faylni to'liq qo'yib → Run
-- (09 va 11 dan keyin, BIR MARTA)
--
--   • Buyurtma bir necha reysda yetkaziladi: har reys = "Yuk berildi" yozuvi,
--     buyurtmaga bog'langan. Yetkazilgan miqdor o'zi hisoblanadi; to'liq
--     yetkazilganda buyurtma o'zi "bajarildi" bo'ladi.
--   • Mijozga kredit (qarz) limiti — oshsa ogohlantiriladi.
-- =====================================================================

alter table yozuvlar    add column if not exists buyurtma_id bigint references buyurtmalar(id);
alter table buyurtmalar add column if not exists yetkazildi numeric not null default 0;
alter table mijozlar    add column if not exists kredit_limit numeric check (kredit_limit >= 0);
create index if not exists yozuvlar_buyurtma_idx on yozuvlar (buyurtma_id) where buyurtma_id is not null;

-- Mijoz qoldig'ida kredit limiti ham ko'rinsin (yozuv kiritishda ogohlantirish uchun)
-- (o'chirib qayta yaratiladi: bazadagi eski ko'rinishda boshqa ustunlar bo'lishi mumkin)
drop view if exists mijoz_qoldiq;
create view mijoz_qoldiq with (security_invoker = on) as
select m.id, m.nomi, m.telefon,
       coalesce(sum(y.summa), 0) as qoldiq,
       max(y.sana)               as oxirgi_yozuv,
       m.valyuta,
       m.kredit_limit
from mijozlar m
left join yozuvlar y on y.mijoz_id = m.id
group by m.id;
grant select on mijoz_qoldiq to authenticated;

-- Buyurtmaning yetkazilgan miqdori va holatini qayta hisoblash
create or replace function buyurtma_hisobla(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare b buyurtmalar%rowtype; q numeric; oxirgi bigint; h text;
begin
  select * into b from buyurtmalar where id = p_id;
  if b.id is null then return; end if;
  select coalesce(sum(miqdor), 0), max(id) into q, oxirgi
  from yozuvlar where buyurtma_id = p_id and turi = 'yuk_berildi';
  h := case when b.holat = 'bekor' then 'bekor' when q >= b.miqdor - 0.001 then 'bajarildi' else 'yangi' end;
  if b.yetkazildi is distinct from q or b.holat <> h or b.yozuv_id is distinct from coalesce(oxirgi, b.yozuv_id) then
    update buyurtmalar set yetkazildi = q, holat = h, yozuv_id = coalesce(oxirgi, b.yozuv_id) where id = p_id;
  end if;
end $$;
revoke execute on function buyurtma_hisobla(bigint) from public, anon, authenticated;

create or replace function yozuv_buyurtmaga() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op <> 'INSERT' and old.buyurtma_id is not null then perform buyurtma_hisobla(old.buyurtma_id); end if;
  if tg_op <> 'DELETE' and new.buyurtma_id is not null
     and (tg_op = 'INSERT' or new.buyurtma_id is distinct from old.buyurtma_id
          or new.miqdor is distinct from old.miqdor or new.turi is distinct from old.turi) then
    perform buyurtma_hisobla(new.buyurtma_id);
  end if;
  return null;
end $$;
create trigger yozuv_buyurtmaga after insert or update or delete on yozuvlar
  for each row execute function yozuv_buyurtmaga();

-- Buyurtma miqdori o'zgartirilsa (tahrir) — holat qayta hisoblanadi
create or replace function buyurtma_miqdor_ozgardi() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.miqdor is distinct from old.miqdor then perform buyurtma_hisobla(new.id); end if;
  return null;
end $$;
create trigger buyurtma_miqdor_ozgardi after update of miqdor on buyurtmalar
  for each row execute function buyurtma_miqdor_ozgardi();

-- Eski (09 dagi) "bajarildi"lar: bog'langan bitta yozuvni buyurtmaga ulaymiz
update yozuvlar y set buyurtma_id = b.id
from buyurtmalar b
where b.yozuv_id = y.id and y.buyurtma_id is null and not y.qulf;   -- qulflanganlar o'zgarmaydi

-- Mijoz kabinetida ham necha m³ yetkazilgani ko'rinsin (11 dagi funksiyaning yangi varianti)
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
        'miqdor', b.miqdor, 'yetkazildi', b.yetkazildi, 'olchov', p.olchov, 'holat', b.holat) order by b.sana desc, b.id desc)
        from buyurtmalar b join mahsulotlar p on p.id = b.mahsulot_id
        where b.mijoz_id = m.id and b.sana >= current_date - 30), '[]'::jsonb),
    'mahsulotlar', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'nomi', p.nomi, 'olchov', p.olchov) order by p.nomi)
        from mahsulotlar p where p.turkum = 'tayyor'), '[]'::jsonb)
  );
end $$;

-- Kredit limitini faqat admin va rahbar o'zgartiradi
create or replace function kredit_limit_huquq() returns trigger
language plpgsql as $$
begin
  if new.kredit_limit is distinct from old.kredit_limit and auth.uid() is not null and not rol_bor('admin','rahbar') then
    raise exception 'Kredit limitini faqat admin yoki rahbar o''zgartira oladi';
  end if;
  return new;
end $$;
create trigger kredit_limit_huquq before update on mijozlar
  for each row execute function kredit_limit_huquq();
