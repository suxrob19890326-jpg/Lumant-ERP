-- =====================================================================
-- LUMANT ERP — 8-qadam: XODIMNI SAYTDAN QO'SHISH VA PAROLINI ALMASHTIRISH
-- Supabase → SQL Editor → New query → shu faylni to'liq qo'yib → Run
-- (07_rollar_tarix.sql dan keyin, BIR MARTA ishga tushiriladi)
--
-- Shundan keyin admin "Xodimlar" sahifasida:
--   • yangi xodim yaratadi (email + parol + rol) — Supabase'ga kirmasdan;
--   • xodimning parolini almashtiradi (unutgan bo'lsa).
-- Bu ishlarni faqat ADMIN qila oladi — tekshiruv bazaning o'zida.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
-- Yangi xodim: Supabase'ning foydalanuvchilar ro'yxatiga qo'shadi
-- (email tasdiqlangan holda), so'ng xodimlar jadvalida ism va rolni qo'yadi.
-- ---------------------------------------------------------------------
create or replace function xodim_yarat(p_email text, p_parol text, p_ism text, p_rol text)
returns uuid
language plpgsql security definer set search_path = public, extensions, auth as $$
declare
  uid uuid := gen_random_uuid();
  em  text := lower(trim(p_email));
begin
  if not rol_bor('admin') then
    raise exception 'Xodimni faqat admin qo''sha oladi';
  end if;
  if em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Email noto''g''ri yozilgan';
  end if;
  if length(coalesce(p_parol, '')) < 6 then
    raise exception 'Parol kamida 6 ta belgidan iborat bo''lsin';
  end if;
  if p_rol is not null and p_rol not in ('admin','rahbar','sotuvchi','kassir','omborchi') then
    raise exception 'Noma''lum rol: %', p_rol;
  end if;
  if exists (select 1 from auth.users where lower(email) = em) then
    raise exception 'Bu email bilan foydalanuvchi allaqachon bor';
  end if;

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, email_change, email_change_token_new, recovery_token
  ) values (
    '00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', em,
    crypt(p_parol, gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(),
    '', '', '', ''
  );

  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), uid, uid::text,
          jsonb_build_object('sub', uid::text, 'email', em, 'email_verified', true),
          'email', now(), now(), now());

  -- yangi_xodim trigger (07) xodimlar qatorini yaratdi — ism va rolni qo'yamiz
  insert into xodimlar (user_id, email) values (uid, em) on conflict (user_id) do nothing;
  update xodimlar set ism = nullif(trim(p_ism), ''), rol = p_rol where user_id = uid;
  return uid;
end $$;

-- ---------------------------------------------------------------------
-- Parolni almashtirish (xodim unutgan bo'lsa)
-- ---------------------------------------------------------------------
create or replace function xodim_parol(p_user uuid, p_parol text)
returns void
language plpgsql security definer set search_path = public, extensions, auth as $$
begin
  if not rol_bor('admin') then
    raise exception 'Parolni faqat admin almashtira oladi';
  end if;
  if length(coalesce(p_parol, '')) < 6 then
    raise exception 'Parol kamida 6 ta belgidan iborat bo''lsin';
  end if;
  update auth.users set encrypted_password = crypt(p_parol, gen_salt('bf')), updated_at = now()
  where id = p_user;
  if not found then raise exception 'Foydalanuvchi topilmadi'; end if;
end $$;

revoke execute on function xodim_yarat(text, text, text, text) from public, anon;
revoke execute on function xodim_parol(uuid, text) from public, anon;
grant execute on function xodim_yarat(text, text, text, text) to authenticated;
grant execute on function xodim_parol(uuid, text) to authenticated;
