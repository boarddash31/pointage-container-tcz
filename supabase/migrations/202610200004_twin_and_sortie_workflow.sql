-- Migration: Support Twin containers (2x20' with 2 companies) and Sortie pickup/deposit workflow
alter table public.truck_visits
  add column if not exists is_twin boolean not null default false,
  add column if not exists container_number_2 text references public.containers(number),
  add column if not exists iso_code_2 text,
  add column if not exists armateur_id_2 text references public.armateurs(id),
  add column if not exists booking_reference_2 text;

create unique index if not exists one_active_container_2_on_truck on public.truck_visits(container_number_2)
  where container_number_2 is not null and canceled_at is null and exited_at is null
    and ((entry_kind='loaded' and engin_at is null)
      or (entry_kind='empty' and engin_at is not null));

-- Drop previous enter_truck overload to prevent ambiguous function call
drop function if exists public.enter_truck(text,text,text,text,text,text,text,uuid);

-- Update enter_truck to support Twin containers
create or replace function public.enter_truck(
  p_plate text,
  p_cin text,
  p_entry_kind text,
  p_container text,
  p_booking text,
  p_iso text,
  p_armateur text,
  p_client uuid default null,
  p_is_twin boolean default false,
  p_container_2 text default null,
  p_iso_2 text default null,
  p_armateur_2 text default null,
  p_booking_2 text default null
)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_actor uuid:=auth.uid();
  v_visit public.truck_visits;
  v_number text:=upper(btrim(coalesce(p_container,'')));
  v_number_2 text:=upper(btrim(coalesce(p_container_2,'')));
  v_booking_id uuid:=null;
begin
  if not public.can_do('entree') then raise exception 'permission denied' using errcode='42501'; end if;
  if length(btrim(coalesce(p_plate,'')))<2 or length(btrim(coalesce(p_cin,'')))<2 then
    raise exception 'plate and CIN required';
  end if;
  if p_entry_kind not in ('loaded','empty') then raise exception 'invalid entry kind'; end if;

  if p_entry_kind='loaded' then
    if not public.valid_container_number(v_number) then raise exception 'invalid ISO 6346 container number'; end if;
    insert into public.containers(number,iso_code,armateur_id,source)
      values(v_number,p_iso,p_armateur,'operator')
      on conflict(number) do update set iso_code=excluded.iso_code,armateur_id=excluded.armateur_id;

    if p_is_twin and length(v_number_2) > 0 then
      if not public.valid_container_number(v_number_2) then raise exception 'invalid ISO 6346 second container number'; end if;
      insert into public.containers(number,iso_code,armateur_id,source)
        values(v_number_2,coalesce(p_iso_2, '22G1'),coalesce(p_armateur_2, p_armateur),'operator')
        on conflict(number) do update set iso_code=excluded.iso_code,armateur_id=excluded.armateur_id;
    end if;
  else
    if length(btrim(coalesce(p_booking,'')))=0 then raise exception 'booking required for empty entry'; end if;
    insert into public.bookings(reference,client_id,armateur_id,iso_code)
      values(btrim(p_booking),p_client,p_armateur,p_iso) returning id into v_booking_id;
  end if;

  insert into public.truck_visits(
    plate, driver_cin, entry_kind, container_number, booking_id, iso_code, armateur_id, client_id, entered_by,
    is_twin, container_number_2, iso_code_2, armateur_id_2, booking_reference_2
  )
  values(
    btrim(p_plate), btrim(p_cin), p_entry_kind,
    case when p_entry_kind='loaded' then v_number else null end,
    v_booking_id, p_iso, p_armateur, p_client, v_actor,
    coalesce(p_is_twin, false),
    case when p_entry_kind='loaded' and p_is_twin then v_number_2 else null end,
    case when p_is_twin then p_iso_2 else null end,
    case when p_is_twin then p_armateur_2 else null end,
    case when p_is_twin then p_booking_2 else null end
  ) returning * into v_visit;

  perform public.record_event(v_visit,'ENTREE',v_actor);
  insert into public.audit_logs(entity,entity_id,action,actor_id,before_data,after_data)
    values('truck_visit',v_visit.id::text,'ENTREE',v_actor,null,to_jsonb(v_visit));
  return v_visit.id;
end; $$;

-- Complete exit function supporting pickup verification, twin containers, and deposit
create or replace function public.exit_truck_with_details(
  p_visit uuid,
  p_pickup_container text default null,
  p_pickup_iso text default null,
  p_pickup_armateur text default null,
  p_is_twin boolean default false,
  p_pickup_container_2 text default null,
  p_pickup_iso_2 text default null,
  p_pickup_armateur_2 text default null,
  p_empty_exit_without_pickup boolean default false
)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_actor uuid:=auth.uid();
  v_visit public.truck_visits;
  v_before jsonb;
  v_c1 text:=upper(btrim(coalesce(p_pickup_container,'')));
  v_c2 text:=upper(btrim(coalesce(p_pickup_container_2,'')));
begin
  if not public.can_do('sortie') then raise exception 'permission denied' using errcode='42501'; end if;
  select * into v_visit from public.truck_visits where id=p_visit for update;
  if not found or v_visit.exited_at is not null or v_visit.canceled_at is not null then
    raise exception 'visit unavailable for Exit';
  end if;
  v_before:=to_jsonb(v_visit);

  -- Case A: Truck entered empty
  if v_visit.entry_kind='empty' then
    if p_empty_exit_without_pickup then
      -- Driver left empty without pickup (ki dkhal ki khraj)
      update public.truck_visits
        set canceled_at=now(), canceled_by=v_actor,
            cancel_reason='Sortie sans prise de conteneur (ressorti à vide)',
            version=version+1
        where id=p_visit returning * into v_visit;
      insert into public.visit_events(visit_id,action,actor_id,details)
        values(v_visit.id,'ANNULATION',v_actor,jsonb_build_object('reason','Sortie sans prise de conteneur'));
      insert into public.audit_logs(entity,entity_id,action,actor_id,before_data,after_data)
        values('truck_visit',v_visit.id::text,'ANNULATION',v_actor,v_before,to_jsonb(v_visit));
      return;
    else
      -- Driver picked up container(s)
      if length(v_c1) > 0 then
        if not public.valid_container_number(v_c1) then raise exception 'invalid ISO 6346 container number'; end if;
        insert into public.containers(number,iso_code,armateur_id,source)
          values(v_c1,coalesce(p_pickup_iso,v_visit.iso_code),coalesce(p_pickup_armateur,v_visit.armateur_id),'operator')
          on conflict(number) do update set iso_code=excluded.iso_code,armateur_id=excluded.armateur_id;

        update public.container_stock_intervals
          set departed_at=now(), end_visit_id=v_visit.id
          where container_number=v_c1 and departed_at is null;

        update public.truck_visits
          set container_number=v_c1,
              iso_code=coalesce(p_pickup_iso,v_visit.iso_code),
              armateur_id=coalesce(p_pickup_armateur,v_visit.armateur_id)
          where id=p_visit;
      end if;

      if p_is_twin and length(v_c2) > 0 then
        if not public.valid_container_number(v_c2) then raise exception 'invalid ISO 6346 second container number'; end if;
        insert into public.containers(number,iso_code,armateur_id,source)
          values(v_c2,coalesce(p_pickup_iso_2,'22G1'),coalesce(p_pickup_armateur_2,coalesce(p_pickup_armateur,v_visit.armateur_id)),'operator')
          on conflict(number) do update set iso_code=excluded.iso_code,armateur_id=excluded.armateur_id;

        update public.container_stock_intervals
          set departed_at=now(), end_visit_id=v_visit.id
          where container_number=v_c2 and departed_at is null;

        update public.truck_visits
          set is_twin=true,
              container_number_2=v_c2,
              iso_code_2=coalesce(p_pickup_iso_2,'22G1'),
              armateur_id_2=coalesce(p_pickup_armateur_2,coalesce(p_pickup_armateur,v_visit.armateur_id))
          where id=p_visit;
      end if;

      update public.truck_visits set engin_at=now(),engin_by=v_actor where id=p_visit;
      perform public.record_event(v_visit,'PRISE',v_actor,jsonb_build_object('container',v_c1,'container_2',v_c2));
    end if;

  -- Case B: Truck entered loaded -> auto deposit if not done
  elsif v_visit.entry_kind='loaded' then
    if v_visit.engin_at is null then
      if v_visit.container_number is not null then
        perform 1 from public.containers where number=v_visit.container_number for update;
        insert into public.container_stock_intervals(container_number,client_id,armateur_id,iso_code,start_visit_id,arrived_at,position)
          values(v_visit.container_number,v_visit.client_id,v_visit.armateur_id,v_visit.iso_code,v_visit.id,now(),null)
          on conflict do nothing;
      end if;
      if v_visit.is_twin and v_visit.container_number_2 is not null then
        perform 1 from public.containers where number=v_visit.container_number_2 for update;
        insert into public.container_stock_intervals(container_number,client_id,armateur_id,iso_code,start_visit_id,arrived_at,position)
          values(v_visit.container_number_2,v_visit.client_id,coalesce(v_visit.armateur_id_2,v_visit.armateur_id),coalesce(v_visit.iso_code_2,v_visit.iso_code),v_visit.id,now(),null)
          on conflict do nothing;
      end if;
      update public.truck_visits set engin_at=now(),engin_by=v_actor where id=p_visit;
      perform public.record_event(v_visit,'DEPOSE',v_actor);
    end if;
  end if;

  update public.truck_visits
    set exited_at=now(),exited_by=v_actor,version=version+1
    where id=p_visit returning * into v_visit;

  perform public.record_event(v_visit,'SORTIE',v_actor);
  insert into public.audit_logs(entity,entity_id,action,actor_id,before_data,after_data)
    values('truck_visit',v_visit.id::text,'SORTIE',v_actor,v_before,to_jsonb(v_visit));
end; $$;

-- Keep backward compatibility for exit_truck(uuid)
create or replace function public.exit_truck(p_visit uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
  perform public.exit_truck_with_details(p_visit);
end; $$;

revoke all on function public.enter_truck(text,text,text,text,text,text,text,uuid,boolean,text,text,text,text) from public,anon;
grant execute on function public.enter_truck(text,text,text,text,text,text,text,uuid,boolean,text,text,text,text) to authenticated;

revoke all on function public.exit_truck_with_details(uuid,text,text,text,boolean,text,text,text,boolean) from public,anon;
grant execute on function public.exit_truck_with_details(uuid,text,text,text,boolean,text,text,text,boolean) to authenticated;

revoke all on function public.exit_truck(uuid) from public,anon;
grant execute on function public.exit_truck(uuid) to authenticated;
