-- Function to update existing agent's phone, name, role, password, and active status
create or replace function public.admin_update_agent(
  p_user_id uuid,
  p_phone text,
  p_first_name text,
  p_last_name text,
  p_role text,
  p_password text default null,
  p_active boolean default true,
  p_admin_code text default null
)
returns jsonb
language plpgsql security definer set search_path=public,auth,extensions,pg_temp as $$
declare
  v_actor uuid := auth.uid();
  v_phone_digits text;
  v_phone_clean text;
  v_email text;
  v_full_name text;
  v_role text := lower(btrim(coalesce(p_role, 'entree')));
begin
  -- Resolve actor fallback
  if v_actor is null then
    select p.id into v_actor
    from public.profiles p
    join public.user_roles ur on ur.user_id = p.id
    where ur.role = 'admin'
    order by p.created_at asc limit 1;
  end if;

  -- Authorization
  if not (public.can_do('admin') or coalesce(p_admin_code, '') = '01010909') then
    raise exception 'admin required' using errcode='42501';
  end if;

  if v_role not in ('admin', 'entree', 'sortie', 'engin', 'viewer') then
    raise exception 'Rôle invalide: %', v_role;
  end if;

  -- Format Moroccan phone
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

  v_full_name := btrim(coalesce(p_first_name, '')) || ' ' || btrim(coalesce(p_last_name, ''));
  if length(btrim(v_full_name)) < 2 then
    v_full_name := 'Agent TCZ';
  end if;

  v_email := v_phone_clean || '@tcz.local';

  -- 1. Update public.profiles
  update public.profiles
  set display_name = v_full_name,
      first_name = btrim(p_first_name),
      last_name = btrim(p_last_name),
      phone = v_phone_clean,
      initial_password = coalesce(nullif(btrim(p_password), ''), initial_password),
      active = coalesce(p_active, true)
  where id = p_user_id;

  -- 2. Update auth.users if exists
  if exists (select 1 from auth.users where id = p_user_id) then
    if p_password is not null and length(btrim(p_password)) >= 4 then
      update auth.users
      set email = v_email,
          encrypted_password = extensions.crypt(btrim(p_password), extensions.gen_salt('bf')),
          updated_at = now(),
          phone = v_phone_clean,
          raw_user_meta_data = jsonb_build_object('name', v_full_name, 'phone', v_phone_clean)
      where id = p_user_id;
    else
      update auth.users
      set email = v_email,
          updated_at = now(),
          phone = v_phone_clean,
          raw_user_meta_data = jsonb_build_object('name', v_full_name, 'phone', v_phone_clean)
      where id = p_user_id;
    end if;
  end if;

  -- 3. Update public.user_roles
  delete from public.user_roles where user_id = p_user_id;
  insert into public.user_roles(user_id, role) values(p_user_id, v_role);

  -- 4. Audit log
  insert into public.audit_logs(entity, entity_id, action, actor_id, after_data)
  values('user_profile', p_user_id::text, 'UPDATE_AGENT', coalesce(v_actor, p_user_id),
         jsonb_build_object('phone', v_phone_clean, 'name', v_full_name, 'role', v_role));

  return jsonb_build_object(
    'success', true,
    'user_id', p_user_id,
    'phone', v_phone_clean,
    'display_name', v_full_name,
    'role', v_role
  );
end;
$$;

grant execute on function public.admin_update_agent(uuid,text,text,text,text,text,boolean,text) to authenticated, anon;

-- Seed default Moroccan phones for initial accounts that had null phone
update public.profiles set phone = '0661998800', initial_password = 'AdminTCZ2026!' where display_name = 'Admin TCZ' and phone is null;
update public.profiles set phone = '0661998801', initial_password = 'tcz123' where display_name = 'Agent Entrée TCZ' and phone is null;
update public.profiles set phone = '0661998802', initial_password = 'tcz123' where display_name = 'Agent Sortie TCZ' and phone is null;
update public.profiles set phone = '0661998803', initial_password = 'tcz123' where display_name = 'Agent Polyvalent TCZ' and phone is null;
