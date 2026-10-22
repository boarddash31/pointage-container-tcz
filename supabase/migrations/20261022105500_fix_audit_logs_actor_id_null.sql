-- Fix NOT NULL constraint on audit_logs.actor_id to support supervisor PIN operations and admin operations when auth.uid() is null
alter table public.audit_logs alter column actor_id drop not null;

-- Update admin_create_agent with fallback actor
create or replace function public.admin_create_agent(
  p_phone text,
  p_first_name text,
  p_last_name text,
  p_role text,
  p_password text,
  p_avatar_url text default null,
  p_admin_code text default null
)
returns jsonb
language plpgsql security definer set search_path=public,auth,extensions,pg_temp as $$
declare
  v_actor uuid := auth.uid();
  v_phone_digits text;
  v_phone_clean text;
  v_email text;
  v_user_id uuid;
  v_full_name text;
  v_role text := lower(btrim(coalesce(p_role, 'entree')));
begin
  -- Resolve actor fallback if auth.uid() is null (e.g. called from supervisor dashboard with PIN)
  if v_actor is null then
    select p.id into v_actor
    from public.profiles p
    join public.user_roles ur on ur.user_id = p.id
    where ur.role = 'admin'
    order by p.created_at asc
    limit 1;
  end if;

  -- Authorization: Caller is admin OR provides supervisor code 01010909
  if not (public.can_do('admin') or coalesce(p_admin_code, '') = '01010909') then
    raise exception 'admin required' using errcode='42501';
  end if;

  -- Validate role
  if v_role not in ('admin', 'entree', 'sortie', 'engin', 'viewer') then
    raise exception 'Rôle invalide: %', v_role;
  end if;

  -- Format Moroccan phone number to 10 digits (06XXXXXXXX / 07XXXXXXXX)
  v_phone_digits := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  if length(v_phone_digits) = 9 and (v_phone_digits like '6%' or v_phone_digits like '7%') then
    v_phone_clean := '0' || v_phone_digits;
  elsif length(v_phone_digits) = 12 and v_phone_digits like '212%' then
    v_phone_clean := '0' || substr(v_phone_digits, 4);
  elsif length(v_phone_digits) = 10 and v_phone_digits like '0%' then
    v_phone_clean := v_phone_digits;
  else
    v_phone_clean := v_phone_digits;
  end if;

  if length(v_phone_clean) < 8 then
    raise exception 'Numéro de téléphone invalide';
  end if;

  if length(btrim(coalesce(p_first_name, ''))) < 2 or length(btrim(coalesce(p_last_name, ''))) < 2 then
    raise exception 'Nom et Prénom sont obligatoires';
  end if;

  if length(btrim(coalesce(p_password, ''))) < 4 then
    raise exception 'Mot de passe trop court (minimum 4 caractères)';
  end if;

  v_full_name := btrim(p_first_name) || ' ' || btrim(p_last_name);
  v_email := v_phone_clean || '@tcz.local';

  -- Check if profile with phone already exists
  select id into v_user_id from public.profiles where phone = v_phone_clean limit 1;

  if v_user_id is not null then
    -- Existing user: update password and info
    update auth.users
    set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
        updated_at = now(),
        raw_user_meta_data = jsonb_build_object('name', v_full_name, 'phone', v_phone_clean)
    where id = v_user_id;

    update public.profiles
    set display_name = v_full_name,
        first_name = btrim(p_first_name),
        last_name = btrim(p_last_name),
        avatar_url = p_avatar_url,
        initial_password = p_password,
        active = true
    where id = v_user_id;

    delete from public.user_roles where user_id = v_user_id;
    insert into public.user_roles(user_id, role) values (v_user_id, v_role);

    insert into public.audit_logs(entity, entity_id, action, actor_id, after_data)
    values('user_profile', v_user_id::text, 'UPDATE_AGENT', coalesce(v_actor, v_user_id),
           jsonb_build_object('phone', v_phone_clean, 'name', v_full_name, 'role', v_role));
  else
    -- New user: create in auth.users
    v_user_id := gen_random_uuid();

    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      phone, phone_confirmed_at, created_at, updated_at
    ) values (
      '00000000-0000-0000-0000-000000000000',
      v_user_id,
      'authenticated',
      'authenticated',
      v_email,
      extensions.crypt(p_password, extensions.gen_salt('bf')),
      now(),
      jsonb_build_object('provider', 'email', 'providers', array['email']),
      jsonb_build_object('name', v_full_name, 'phone', v_phone_clean),
      v_phone_clean,
      now(),
      now(),
      now()
    );

    -- Ensure profile row exists and has all fields
    insert into public.profiles (id, display_name, first_name, last_name, phone, avatar_url, initial_password, active)
    values (v_user_id, v_full_name, btrim(p_first_name), btrim(p_last_name), v_phone_clean, p_avatar_url, p_password, true)
    on conflict (id) do update
    set display_name = excluded.display_name,
        first_name = excluded.first_name,
        last_name = excluded.last_name,
        phone = excluded.phone,
        avatar_url = excluded.avatar_url,
        initial_password = excluded.initial_password,
        active = true;

    -- Assign role
    insert into public.user_roles(user_id, role)
    values (v_user_id, v_role)
    on conflict (user_id, role) do nothing;

    insert into public.audit_logs(entity, entity_id, action, actor_id, after_data)
    values('user_profile', v_user_id::text, 'CREATE_AGENT', coalesce(v_actor, v_user_id),
           jsonb_build_object('phone', v_phone_clean, 'name', v_full_name, 'role', v_role));
  end if;

  return jsonb_build_object(
    'success', true,
    'user_id', v_user_id,
    'email', v_email,
    'phone', v_phone_clean,
    'display_name', v_full_name,
    'role', v_role
  );
end;
$$;
