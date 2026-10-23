-- Preserve the existing dashboard RPC implementations behind admin-only wrappers.
-- The older dashboard sent only the public anon key, which is no longer sufficient.

alter function public.admin_dashboard_kpis(date)
  rename to admin_dashboard_kpis_impl_20261023;
revoke all on function public.admin_dashboard_kpis_impl_20261023(date)
  from public, anon, authenticated;
create function public.admin_dashboard_kpis(p_day date default current_date)
returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
  if not public.can_do('admin') then
    raise exception 'admin required' using errcode='42501';
  end if;
  return public.admin_dashboard_kpis_impl_20261023(p_day);
end; $$;
revoke all on function public.admin_dashboard_kpis(date) from public, anon, authenticated;
grant execute on function public.admin_dashboard_kpis(date) to authenticated;

alter function public.admin_list_clients_armateurs()
  rename to admin_list_clients_armateurs_impl_20261023;
revoke all on function public.admin_list_clients_armateurs_impl_20261023()
  from public, anon, authenticated;
create function public.admin_list_clients_armateurs()
returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
  if not public.can_do('admin') then
    raise exception 'admin required' using errcode='42501';
  end if;
  return public.admin_list_clients_armateurs_impl_20261023();
end; $$;
revoke all on function public.admin_list_clients_armateurs() from public, anon, authenticated;
grant execute on function public.admin_list_clients_armateurs() to authenticated;

alter function public.admin_list_all_armateurs()
  rename to admin_list_all_armateurs_impl_20261023;
revoke all on function public.admin_list_all_armateurs_impl_20261023()
  from public, anon, authenticated;
create function public.admin_list_all_armateurs()
returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
  if not public.can_do('admin') then
    raise exception 'admin required' using errcode='42501';
  end if;
  return public.admin_list_all_armateurs_impl_20261023();
end; $$;
revoke all on function public.admin_list_all_armateurs() from public, anon, authenticated;
grant execute on function public.admin_list_all_armateurs() to authenticated;

alter function public.admin_assign_client_armateur(uuid, text)
  rename to admin_assign_client_armateur_impl_20261023;
revoke all on function public.admin_assign_client_armateur_impl_20261023(uuid, text)
  from public, anon, authenticated;
create function public.admin_assign_client_armateur(p_client uuid, p_armateur text)
returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not public.can_do('admin') then
    raise exception 'admin required' using errcode='42501';
  end if;
  return public.admin_assign_client_armateur_impl_20261023(p_client, p_armateur);
end; $$;
revoke all on function public.admin_assign_client_armateur(uuid, text) from public, anon, authenticated;
grant execute on function public.admin_assign_client_armateur(uuid, text) to authenticated;

alter function public.admin_unassign_client_armateur(uuid, text)
  rename to admin_unassign_client_armateur_impl_20261023;
revoke all on function public.admin_unassign_client_armateur_impl_20261023(uuid, text)
  from public, anon, authenticated;
create function public.admin_unassign_client_armateur(p_client uuid, p_armateur text)
returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not public.can_do('admin') then
    raise exception 'admin required' using errcode='42501';
  end if;
  return public.admin_unassign_client_armateur_impl_20261023(p_client, p_armateur);
end; $$;
revoke all on function public.admin_unassign_client_armateur(uuid, text) from public, anon, authenticated;
grant execute on function public.admin_unassign_client_armateur(uuid, text) to authenticated;

alter function public.admin_create_client(text, text)
  rename to admin_create_client_impl_20261023;
revoke all on function public.admin_create_client_impl_20261023(text, text)
  from public, anon, authenticated;
create function public.admin_create_client(p_code text, p_name text)
returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not public.can_do('admin') then
    raise exception 'admin required' using errcode='42501';
  end if;
  return public.admin_create_client_impl_20261023(p_code, p_name);
end; $$;
revoke all on function public.admin_create_client(text, text) from public, anon, authenticated;
grant execute on function public.admin_create_client(text, text) to authenticated;

alter function public.admin_delete_client(uuid)
  rename to admin_delete_client_impl_20261023;
revoke all on function public.admin_delete_client_impl_20261023(uuid)
  from public, anon, authenticated;
create function public.admin_delete_client(p_client uuid)
returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not public.can_do('admin') then
    raise exception 'admin required' using errcode='42501';
  end if;
  return public.admin_delete_client_impl_20261023(p_client);
end; $$;
revoke all on function public.admin_delete_client(uuid) from public, anon, authenticated;
grant execute on function public.admin_delete_client(uuid) to authenticated;

-- Remove the public supervisor-code fallback from the dashboard account actions.
alter function public.admin_create_agent(text, text, text, text, text, text, text)
  rename to admin_create_agent_impl_20261023;
revoke all on function public.admin_create_agent_impl_20261023(text, text, text, text, text, text, text)
  from public, anon, authenticated;
create function public.admin_create_agent(
  p_phone text, p_first_name text, p_last_name text, p_role text,
  p_password text, p_avatar_url text default null, p_admin_code text default null
)
returns jsonb
language plpgsql security definer set search_path=public,auth,extensions,pg_temp as $$
begin
  if not public.can_do('admin') then
    raise exception 'admin required' using errcode='42501';
  end if;
  return public.admin_create_agent_impl_20261023(
    p_phone, p_first_name, p_last_name, p_role, p_password, p_avatar_url, null
  );
end; $$;
revoke all on function public.admin_create_agent(text, text, text, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.admin_create_agent(text, text, text, text, text, text, text)
  to authenticated;

alter function public.admin_update_agent(uuid, text, text, text, text, text, boolean, text)
  rename to admin_update_agent_impl_20261023;
revoke all on function public.admin_update_agent_impl_20261023(uuid, text, text, text, text, text, boolean, text)
  from public, anon, authenticated;
create function public.admin_update_agent(
  p_user_id uuid, p_phone text, p_first_name text, p_last_name text, p_role text,
  p_password text default null, p_active boolean default true, p_admin_code text default null
)
returns jsonb
language plpgsql security definer set search_path=public,auth,extensions,pg_temp as $$
begin
  if not public.can_do('admin') then
    raise exception 'admin required' using errcode='42501';
  end if;
  return public.admin_update_agent_impl_20261023(
    p_user_id, p_phone, p_first_name, p_last_name, p_role, p_password, p_active, null
  );
end; $$;
revoke all on function public.admin_update_agent(uuid, text, text, text, text, text, boolean, text)
  from public, anon, authenticated;
grant execute on function public.admin_update_agent(uuid, text, text, text, text, text, boolean, text)
  to authenticated;

-- Agent directory is already filtered by can_do('admin'); only signed-in users may invoke it.
create or replace function public.admin_list_agents()
returns table(
  id uuid, display_name text, first_name text, last_name text, phone text,
  avatar_url text, initial_password text, active boolean, roles text[], created_at timestamptz
)
language sql stable security definer set search_path=public,pg_temp as $$
  select p.id, p.display_name, p.first_name, p.last_name, p.phone, p.avatar_url,
    p.initial_password, p.active,
    coalesce(array_agg(r.role) filter (where r.role is not null), '{}'::text[]) as roles,
    p.created_at
  from public.profiles p
  left join public.user_roles r on r.user_id = p.id
  where public.can_do('admin')
  group by p.id, p.display_name, p.first_name, p.last_name, p.phone,
    p.avatar_url, p.initial_password, p.active, p.created_at
  order by p.created_at desc;
$$;
revoke all on function public.admin_list_agents() from public, anon, authenticated;
grant execute on function public.admin_list_agents() to authenticated;

notify pgrst, 'reload schema';
