-- ==============================================================================
-- Migration: Groupage Clients & Armateurs Drag & Drop Studio RPCs
-- ==============================================================================

-- 1. List Clients with their assigned armateurs
create or replace function public.admin_list_clients_armateurs()
returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  return coalesce(
    (select jsonb_agg(
      jsonb_build_object(
        'id', c.id,
        'code', c.code,
        'name', c.name,
        'active', c.active,
        'armateurs', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', a.id,
              'name', a.name,
              'bic', a.bic,
              'valid_from', ca.valid_from,
              'valid_to', ca.valid_to
            ) order by a.name
          )
          from public.client_armateurs ca
          join public.armateurs a on a.id = ca.armateur_id
          where ca.client_id = c.id and (ca.valid_to is null or ca.valid_to >= current_date)
        ), '[]'::jsonb)
      ) order by c.name
    ) from public.clients c),
    '[]'::jsonb
  );
end; $$;

grant execute on function public.admin_list_clients_armateurs() to authenticated, anon;

-- 2. List all active armateurs
create or replace function public.admin_list_all_armateurs()
returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  return coalesce(
    (select jsonb_agg(
      jsonb_build_object(
        'id', a.id,
        'name', a.name,
        'bic', a.bic,
        'active', a.active
      ) order by a.name
    ) from public.armateurs a where a.active = true),
    '[]'::jsonb
  );
end; $$;

grant execute on function public.admin_list_all_armateurs() to authenticated, anon;

-- 3. Assign armateur to client
create or replace function public.admin_assign_client_armateur(p_client uuid, p_armateur text)
returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  insert into public.client_armateurs(client_id, armateur_id, valid_from, valid_to)
  values (p_client, p_armateur, current_date, null)
  on conflict (client_id, armateur_id, valid_from) do update
  set valid_to = null;
  return jsonb_build_object('success', true);
end; $$;

grant execute on function public.admin_assign_client_armateur(uuid, text) to authenticated, anon;

-- 4. Unassign armateur from client
create or replace function public.admin_unassign_client_armateur(p_client uuid, p_armateur text)
returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  delete from public.client_armateurs
  where client_id = p_client and armateur_id = p_armateur;
  return jsonb_build_object('success', true);
end; $$;

grant execute on function public.admin_unassign_client_armateur(uuid, text) to authenticated, anon;

-- 5. Create new client
create or replace function public.admin_create_client(p_code text, p_name text)
returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_id uuid;
begin
  if length(btrim(coalesce(p_code, '')))<2 or length(btrim(coalesce(p_name, '')))<2 then
    raise exception 'Code et Nom du client obligatoires (minimum 2 caractères)';
  end if;

  insert into public.clients(code, name, active)
  values (upper(btrim(p_code)), btrim(p_name), true)
  returning id into v_id;

  return jsonb_build_object('success', true, 'id', v_id);
end; $$;

grant execute on function public.admin_create_client(text, text) to authenticated, anon;

-- 6. Delete client
create or replace function public.admin_delete_client(p_client uuid)
returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  delete from public.client_armateurs where client_id = p_client;
  delete from public.clients where id = p_client;
  return jsonb_build_object('success', true);
end; $$;

grant execute on function public.admin_delete_client(uuid) to authenticated, anon;

-- 7. Initial seed of standard Groupage / Transit clients if none exist
do $$
declare
  v_timar uuid;
  v_medlog uuid;
  v_martrans uuid;
  v_bollore uuid;
  v_geodis uuid;
begin
  if not exists (select 1 from public.clients) then
    insert into public.clients (code, name, active) values ('TIMAR', 'Timar Groupage & Logistique', true) returning id into v_timar;
    insert into public.clients (code, name, active) values ('MEDLOG', 'Medlog Maroc Transit', true) returning id into v_medlog;
    insert into public.clients (code, name, active) values ('MARTRANS', 'Marsa Transit International', true) returning id into v_martrans;
    insert into public.clients (code, name, active) values ('BOLLORE', 'Bolloré Logistics Maroc', true) returning id into v_bollore;
    insert into public.clients (code, name, active) values ('GEODIS', 'Geodis Freight Forwarding', true) returning id into v_geodis;

    -- Pre-assign some popular armateurs
    insert into public.client_armateurs (client_id, armateur_id, valid_from) values
      (v_timar, 'CMACGM', current_date),
      (v_medlog, 'MSC', current_date),
      (v_martrans, 'MAE', current_date),
      (v_martrans, 'ARK', current_date),
      (v_bollore, 'COSCO', current_date),
      (v_geodis, 'WAFASHP', current_date)
    on conflict do nothing;
  end if;
end $$;
