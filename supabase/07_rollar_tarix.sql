-- =====================================================================
-- LUMANT ERP — 7-qadam: ROLLAR, TARIX (AUDIT), MIJOZLARNI BIRLASHTIRISH
-- Supabase → SQL Editor → New query → shu faylni to'liq qo'yib → Run
-- (01–06 fayllardan keyin, BIR MARTA ishga tushiriladi)
--
-- MUHIM: hozir mavjud BARCHA foydalanuvchilar "admin" bo'lib qoladi
-- (hech kim tizimdan chiqib qolmasligi uchun). Keyin "Xodimlar" sahifasida
-- har biriga kerakli rol beriladi. Yangi qo'shilgan foydalanuvchi rolsiz
-- bo'ladi — admin rol bermaguncha hech narsa ko'rmaydi.
--
-- Rollar:
--   admin    — hammasi + xodimlar va rollarni boshqarish
--   rahbar   — hammasi (xodimlarni faqat ko'radi), tarixni ko'radi
--   sotuvchi — mijozlar, yozuvlar, sverka; omborni ko'radi
--   kassir   — kassa, to'lov yozuvlari, sverka
--   omborchi — ombor, ishlab chiqarish, mahsulotlar
--
-- Favqulodda (admin rolini yo'qotib qo'ysangiz) — SQL Editor'da:
--   update xodimlar set rol = 'admin', faol = true where email = 'sizning@email';
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. XODIMLAR va ROLLAR
-- ---------------------------------------------------------------------
create table xodimlar (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  email       text,
  ism         text,
  rol         text check (rol in ('admin','rahbar','sotuvchi','kassir','omborchi')),
  faol        boolean not null default true,
  created_at  timestamptz not null default now()
);

-- Hozirgi foydalanuvchilar — admin
insert into xodimlar (user_id, email, rol)
select id, email, 'admin' from auth.users
on conflict (user_id) do nothing;

-- Yangi foydalanuvchi (Supabase → Authentication → Add user) — rolsiz qo'shiladi
create or replace function yangi_xodim() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.xodimlar (user_id, email) values (new.id, new.email)
  on conflict (user_id) do nothing;
  return new;
end $$;

create trigger yangi_xodim
  after insert on auth.users
  for each row execute function yangi_xodim();

-- Joriy foydalanuvchining roli (faol bo'lmasa — null)
create or replace function rolim() returns text
language sql stable security definer set search_path = public as $$
  select rol from xodimlar where user_id = auth.uid() and faol
$$;

create or replace function rol_bor(variadic rollar text[]) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(rolim() = any(rollar), false)
$$;

revoke execute on function rolim() from public, anon;
revoke execute on function rol_bor(text[]) from public, anon;
grant execute on function rolim() to authenticated;
grant execute on function rol_bor(text[]) to authenticated;


-- ---------------------------------------------------------------------
-- 2. RUXSATLAR (RLS) — eski "kirgan har kim hammasini" qoidalari o'rniga
-- ---------------------------------------------------------------------
drop policy if exists "kirganlar ko'radi"     on mijozlar;
drop policy if exists "kirganlar qo'shadi"    on mijozlar;
drop policy if exists "kirganlar tahrirlaydi" on mijozlar;
drop policy if exists "kirganlar ko'radi"     on mahsulotlar;
drop policy if exists "kirganlar qo'shadi"    on mahsulotlar;
drop policy if exists "kirganlar tahrirlaydi" on mahsulotlar;
drop policy if exists "kirganlar ko'radi"     on yozuvlar;
drop policy if exists "kirganlar qo'shadi"    on yozuvlar;
drop policy if exists "kirganlar tahrirlaydi" on yozuvlar;
drop policy if exists "kirganlar ko'radi"     on kassa_yozuvlar;
drop policy if exists "kirganlar qo'shadi"    on kassa_yozuvlar;
drop policy if exists "kirganlar ko'radi"     on ombor_harakat;
drop policy if exists "kirganlar qo'shadi"    on ombor_harakat;
drop policy if exists "kirganlar ko'radi"     on ishlab_chiqarish;
drop policy if exists "kirganlar qo'shadi"    on ishlab_chiqarish;
drop policy if exists "kirganlar ko'radi"     on retseptlar;
drop policy if exists "kirganlar qo'shadi"    on retseptlar;
drop policy if exists "kirganlar tahrirlaydi" on retseptlar;
drop policy if exists "kirganlar o'chiradi"   on retseptlar;

-- Mijozlar: hamma ko'radi (nomini tanlash uchun); sotuvchi va kassir qo'sha oladi
create policy "rol: ko'radi"  on mijozlar for select to authenticated using (rolim() is not null);
create policy "rol: qo'shadi" on mijozlar for insert to authenticated
  with check (rol_bor('admin','rahbar','sotuvchi','kassir'));
create policy "rol: tahrir"   on mijozlar for update to authenticated
  using (rol_bor('admin','rahbar','sotuvchi','kassir'));

-- Mahsulotlar: hamma ko'radi; omborchi boshqaradi
create policy "rol: ko'radi"  on mahsulotlar for select to authenticated using (rolim() is not null);
create policy "rol: qo'shadi" on mahsulotlar for insert to authenticated
  with check (rol_bor('admin','rahbar','omborchi'));
create policy "rol: tahrir"   on mahsulotlar for update to authenticated
  using (rol_bor('admin','rahbar','omborchi','sotuvchi'));   -- sotuvchi oxirgi narxni yangilaydi

-- Yozuvlar (qarzlar, sverka)
create policy "rol: ko'radi"  on yozuvlar for select to authenticated
  using (rol_bor('admin','rahbar','sotuvchi','kassir'));
create policy "rol: qo'shadi" on yozuvlar for insert to authenticated
  with check (rol_bor('admin','rahbar','sotuvchi')
              or (rol_bor('kassir') and turi in ('tolov_keldi','pul_berildi')));
create policy "rol: tahrir"   on yozuvlar for update to authenticated
  using (rol_bor('admin','rahbar','sotuvchi')
         or (rol_bor('kassir') and turi in ('tolov_keldi','pul_berildi')));

-- Kassa
create policy "rol: ko'radi"  on kassa_yozuvlar for select to authenticated
  using (rol_bor('admin','rahbar','kassir'));
create policy "rol: qo'shadi" on kassa_yozuvlar for insert to authenticated
  with check (yozuv_id is null and rol_bor('admin','rahbar','kassir'));

-- Ombor
create policy "rol: ko'radi"  on ombor_harakat for select to authenticated
  using (rol_bor('admin','rahbar','omborchi','sotuvchi'));
create policy "rol: qo'shadi" on ombor_harakat for insert to authenticated
  with check (yozuv_id is null and rol_bor('admin','rahbar','omborchi'));

-- Ishlab chiqarish va retseptlar
create policy "rol: ko'radi"  on ishlab_chiqarish for select to authenticated
  using (rol_bor('admin','rahbar','omborchi'));
create policy "rol: qo'shadi" on ishlab_chiqarish for insert to authenticated
  with check (rol_bor('admin','rahbar','omborchi'));
create policy "rol: ko'radi"  on retseptlar for select to authenticated
  using (rol_bor('admin','rahbar','omborchi'));
create policy "rol: qo'shadi" on retseptlar for insert to authenticated
  with check (rol_bor('admin','rahbar','omborchi'));
create policy "rol: tahrir"   on retseptlar for update to authenticated
  using (rol_bor('admin','rahbar','omborchi'));
create policy "rol: o'chiradi" on retseptlar for delete to authenticated
  using (rol_bor('admin','rahbar','omborchi'));

-- Xodimlar: o'zini va (admin/rahbar) hammani ko'radi; faqat admin o'zgartiradi
alter table xodimlar enable row level security;
create policy "rol: ko'radi" on xodimlar for select to authenticated
  using (user_id = auth.uid() or rol_bor('admin','rahbar'));
create policy "rol: tahrir"  on xodimlar for update to authenticated
  using (rol_bor('admin'))
  with check (rol_bor('admin'));
grant select, update (ism, rol, faol) on xodimlar to authenticated;

-- Admin o'zini adminlikdan chiqarib yoki o'chirib qo'ya olmasin (tizim egasiz qolmasin)
create or replace function xodim_tekshir() returns trigger
language plpgsql as $$
begin
  if old.user_id = auth.uid() and (new.rol is distinct from old.rol or not new.faol) then
    raise exception 'O''zingizning rolingizni o''zgartira yoki o''chira olmaysiz';
  end if;
  return new;
end $$;
create trigger xodim_tekshir before update on xodimlar
  for each row execute function xodim_tekshir();

-- Yozuvni qulflashni faqat admin va rahbar qila oladi
create or replace function c_qulf_huquq() returns trigger
language plpgsql as $$
begin
  if new.qulf and not coalesce(old.qulf, false)
     and auth.uid() is not null and not rol_bor('admin','rahbar') then
    raise exception 'Yozuvni faqat admin yoki rahbar qulflay oladi';
  end if;
  return new;
end $$;
create trigger c_qulf_huquq before update on yozuvlar
  for each row execute function c_qulf_huquq();


-- ---------------------------------------------------------------------
-- 3. TARIX (AUDIT): kim, qachon, qaysi yozuvni, qanday o'zgartirdi
-- ---------------------------------------------------------------------
create table tarix (
  id         bigint generated always as identity primary key,
  vaqt       timestamptz not null default now(),
  kim        uuid default auth.uid(),
  kim_email  text,
  jadval     text not null,
  yozuv_id   bigint,
  amal       text not null check (amal in ('qoshildi','ozgardi','ochirildi')),
  eski       jsonb,
  yangi      jsonb
);
create index tarix_vaqt_idx on tarix (vaqt desc);
create index tarix_yozuv_idx on tarix (jadval, yozuv_id);

create or replace function tarixga() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  e jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  y jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
begin
  if tg_op = 'UPDATE' and e = y then return null; end if;   -- hech narsa o'zgarmagan
  insert into tarix (kim, kim_email, jadval, yozuv_id, amal, eski, yangi)
  values (
    auth.uid(),
    (select email from xodimlar where user_id = auth.uid()),
    tg_table_name,
    case when coalesce(y, e) ? 'id' then (coalesce(y, e) ->> 'id')::bigint end,
    case tg_op when 'INSERT' then 'qoshildi' when 'UPDATE' then 'ozgardi' else 'ochirildi' end,
    e, y
  );
  return null;
end $$;

create trigger tarix after insert or update or delete on mijozlar        for each row execute function tarixga();
create trigger tarix after insert or update or delete on mahsulotlar     for each row execute function tarixga();
create trigger tarix after insert or update or delete on yozuvlar        for each row execute function tarixga();
create trigger tarix after insert or update or delete on kassa_yozuvlar  for each row execute function tarixga();
create trigger tarix after insert or update or delete on ombor_harakat   for each row execute function tarixga();
create trigger tarix after insert or update or delete on ishlab_chiqarish for each row execute function tarixga();
create trigger tarix after insert or update or delete on retseptlar      for each row execute function tarixga();
create trigger tarix after insert or update or delete on xodimlar        for each row execute function tarixga();

alter table tarix enable row level security;
create policy "rol: ko'radi" on tarix for select to authenticated using (rol_bor('admin','rahbar'));
grant select on tarix to authenticated;


-- ---------------------------------------------------------------------
-- 4. MIJOZLARNI BIRLASHTIRISH (faqat admin va rahbar)
--    "ochiriladi" mijozning barcha yozuvlari "qoladi" mijozga o'tadi.
--    Qulflangan yozuvlarda faqat mijoz almashadi — summa va boshqasi o'zgarmaydi.
-- ---------------------------------------------------------------------

-- Qulf tekshiruvi: birlashtirish paytida faqat mijoz/mahsulot almashishiga ruxsat
create or replace function a_qulf_tekshir() returns trigger
language plpgsql as $$
begin
  if old.qulf then
    if tg_op = 'UPDATE'
       and current_setting('lumant.birlashtirish', true) = 'ha'
       and (to_jsonb(new) - 'mijoz_id' - 'mahsulot_id') = (to_jsonb(old) - 'mijoz_id' - 'mahsulot_id') then
      return new;
    end if;
    raise exception 'Bu yozuv qulflangan, uni o''zgartirib bo''lmaydi';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  new.kiritgan        := old.kiritgan;
  new.kiritilgan_vaqt := old.kiritilgan_vaqt;
  return new;
end $$;

-- Summa hisobi: birlashtirish paytida hech narsani qayta hisoblamaydi
create or replace function b_yozuv_tayyorla() returns trigger
language plpgsql as $$
begin
  if current_setting('lumant.birlashtirish', true) = 'ha' then return new; end if;
  if new.miqdor is not null then new.miqdor := abs(new.miqdor); end if;
  if new.summa is null and new.miqdor is not null and new.narx is not null then
    new.summa := new.miqdor * new.narx;
  end if;
  if new.summa is not null and new.turi <> 'tuzatish' then
    new.summa := abs(new.summa) *
      case when new.turi in ('yuk_berildi','pul_berildi') then 1 else -1 end;
  end if;
  return new;
end $$;

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

  perform set_config('lumant.birlashtirish', 'ha', true);   -- faqat shu tranzaksiya uchun
  update yozuvlar set mijoz_id = k.id where mijoz_id = d.id;
  get diagnostics n = row_count;
  perform set_config('lumant.birlashtirish', '', true);

  update mijozlar set
    telefon = coalesce(nullif(k.telefon, ''), d.telefon),
    izoh    = concat_ws(' · ', nullif(k.izoh, ''), nullif(d.izoh, ''), 'birlashtirildi: ' || d.nomi)
  where id = k.id;
  delete from mijozlar where id = d.id;
  return n;
end $$;

revoke execute on function mijoz_birlashtir(bigint, bigint) from public, anon;
grant execute on function mijoz_birlashtir(bigint, bigint) to authenticated;
