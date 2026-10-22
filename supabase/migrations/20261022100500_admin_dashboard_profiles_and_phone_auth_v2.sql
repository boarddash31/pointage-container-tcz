-- Migration: 20261022100000_admin_dashboard_profiles_and_phone_auth.sql
-- Terminal Conteneur Zenata (TCZ) - Admin Dashboard, Profile Management with WhatsApp, and Phone Number Authentication

create extension if not exists pgcrypto;

-- 1. Extend public.profiles with phone, names, avatar, and initial password
alter table public.profiles add column if not exists phone text;
alter table public.profiles add column if not exists first_name text;
alter table public.profiles add column if not exists last_name text;
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists initial_password text;

create unique index if not exists idx_profiles_phone_unique on public.profiles(phone) where phone is not null and phone <> '';

-- Allow authenticated users to view profiles and admin/supervisor to manage them
grant select, update, insert on public.profiles to authenticated;
grant select on public.profiles to anon;

-- 2. Resolve login identifier (Phone number or Email) to Auth Email
drop function if exists public.get_login_identifier(text);
create or replace function public.get_login_identifier(p_identifier text)
returns jsonb
language plpgsql stable security definer set search_path=public,auth,pg_temp as $$
declare
  v_raw text := btrim(coalesce(p_identifier, ''));
  v_digits text;
  v_phone_clean text;
  v_email text;
begin
  if v_raw = '' then
    return jsonb_build_object('email', '', 'phone', '');
  end if;

  -- If it already contains '@', it is an email
  if v_raw like '%@%' then
    return jsonb_build_object('email', v_raw, 'phone', '');
  end if;

  -- Clean phone digits
  v_digits := regexp_replace(v_raw, '\D', '', 'g');
  if length(v_digits) = 9 and (v_digits like '6%' or v_digits like '7%') then
    v_phone_clean := '0' || v_digits;
  elsif length(v_digits) = 12 and v_digits like '212%' then
    v_phone_clean := '0' || substr(v_digits, 4);
  elsif length(v_digits) = 10 and v_digits like '0%' then
    v_phone_clean := v_digits;
  else
    v_phone_clean := v_digits;
  end if;

  -- Lookup email in profiles and auth.users
  select u.email into v_email
  from auth.users u
  join public.profiles p on p.id = u.id
  where p.phone = v_phone_clean or u.phone = v_phone_clean
  limit 1;

  if v_email is not null and v_email <> '' then
    return jsonb_build_object('email', v_email, 'phone', v_phone_clean);
  end if;

  -- Standard synthetic fallback for phone
  return jsonb_build_object('email', v_phone_clean || '@tcz.local', 'phone', v_phone_clean);
end; $$;

grant execute on function public.get_login_identifier(text) to authenticated, anon;

-- 3. Security definer function for Admin to create/update an agent with Phone and Easy Password
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
    values('user_profile', v_user_id::text, 'UPDATE_AGENT', v_actor,
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
      '{"provider":"email","providers":["email"]}'::jsonb,
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
    values('user_profile', v_user_id::text, 'CREATE_AGENT', v_actor,
           jsonb_build_object('phone', v_phone_clean, 'name', v_full_name, 'role', v_role));
  end if;

  return jsonb_build_object(
    'success', true,
    'user_id', v_user_id,
    'first_name', btrim(p_first_name),
    'last_name', btrim(p_last_name),
    'full_name', v_full_name,
    'phone', v_phone_clean,
    'email', v_email,
    'role', v_role,
    'password', p_password,
    'avatar_url', p_avatar_url
  );
end; $$;

grant execute on function public.admin_create_agent(text,text,text,text,text,text,text) to authenticated, anon;

-- 4. Admin Dashboard Real-Time KPIs & Statistics
create or replace function public.admin_dashboard_kpis(p_day date default current_date)
returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare
  v_res jsonb;
  v_start timestamptz := (p_day::timestamp at time zone 'Africa/Casablanca');
  v_end timestamptz := ((p_day + 1)::timestamp at time zone 'Africa/Casablanca');
begin
  select jsonb_build_object(
    'day', p_day,
    'trucks_inside', (select count(*) from public.truck_visits where exited_at is null and canceled_at is null),
    'entries_today', (select count(*) from public.truck_visits where entered_at >= v_start and entered_at < v_end),
    'exits_today', (select count(*) from public.truck_visits where exited_at >= v_start and exited_at < v_end and canceled_at is null),
    'cancellations_today', (select count(*) from public.truck_visits where canceled_at >= v_start and canceled_at < v_end),
    'needs_engin_inside', (select count(*) from public.truck_visits where exited_at is null and canceled_at is null and engin_at is null and entry_kind = 'loaded'),
    'twin_today', (select count(*) from public.truck_visits where entered_at >= v_start and entered_at < v_end and is_twin = true),
    'total_containers_today', (select count(*) from public.truck_visits where entered_at >= v_start and entered_at < v_end and container_number is not null) +
                               (select count(*) from public.truck_visits where entered_at >= v_start and entered_at < v_end and is_twin = true and container_number_2 is not null),
    'armateurs_breakdown', (
      select coalesce(jsonb_agg(jsonb_build_object('name', armateur, 'count', cnt)), '[]'::jsonb)
      from (
        select coalesce(nullif(armateur_id, ''), 'AUTRE') as armateur, count(*) as cnt
        from public.truck_visits
        where entered_at >= v_start and entered_at < v_end
        group by 1 order by cnt desc limit 8
      ) arm_stats
    ),
    'hourly_entries', (
      select coalesce(jsonb_agg(jsonb_build_object('hour', h, 'count', coalesce(cnt, 0)) order by h), '[]'::jsonb)
      from generate_series(0, 23) h
      left join (
        select extract(hour from entered_at at time zone 'Africa/Casablanca')::int as eh, count(*) as cnt
        from public.truck_visits
        where entered_at >= v_start and entered_at < v_end
        group by 1
      ) hr on hr.eh = h
    ),
    'hourly_exits', (
      select coalesce(jsonb_agg(jsonb_build_object('hour', h, 'count', coalesce(cnt, 0)) order by h), '[]'::jsonb)
      from generate_series(0, 23) h
      left join (
        select extract(hour from exited_at at time zone 'Africa/Casablanca')::int as xh, count(*) as cnt
        from public.truck_visits
        where exited_at >= v_start and exited_at < v_end and canceled_at is null
        group by 1
      ) hr on hr.xh = h
    ),
    'recent_visits', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', v.id,
        'truck_plate', v.plate,
        'driver_cin', v.driver_cin,
        'entry_kind', v.entry_kind,
        'container_number', v.container_number,
        'container_number_2', v.container_number_2,
        'is_twin', v.is_twin,
        'iso_code', v.iso_code,
        'armateur', v.armateur_id,
        'entered_at', v.entered_at,
        'exited_at', v.exited_at,
        'canceled_at', v.canceled_at,
        'status', case
          when v.canceled_at is not null then 'ANNULE'
          when v.exited_at is not null then 'SORTI'
          else 'AU_PARC'
        end
      ) order by v.entered_at desc), '[]'::jsonb)
      from (select * from public.truck_visits order by entered_at desc limit 25) v
    ),
    'agents_count', (select count(*) from public.profiles where active = true)
  ) into v_res;
  return v_res;
end; $$;

grant execute on function public.admin_dashboard_kpis(date) to authenticated, anon;

-- 5. List agents with full details for Admin Dashboard
create or replace function public.admin_list_agents()
returns table(
  id uuid,
  display_name text,
  first_name text,
  last_name text,
  phone text,
  avatar_url text,
  initial_password text,
  active boolean,
  roles text[],
  created_at timestamptz
)
language sql stable security definer set search_path=public,pg_temp as $$
  select
    p.id,
    p.display_name,
    p.first_name,
    p.last_name,
    p.phone,
    p.avatar_url,
    p.initial_password,
    p.active,
    coalesce(array_agg(r.role) filter (where r.role is not null), '{}'::text[]) as roles,
    p.created_at
  from public.profiles p
  left join public.user_roles r on r.user_id = p.id
  group by p.id, p.display_name, p.first_name, p.last_name, p.phone, p.avatar_url, p.initial_password, p.active, p.created_at
  order by p.created_at desc;
$$;

grant execute on function public.admin_list_agents() to authenticated, anon;
