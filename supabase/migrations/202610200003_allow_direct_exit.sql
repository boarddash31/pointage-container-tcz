-- Migration: Allow direct exit without requiring Engin step
create or replace function public.exit_truck(p_visit uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid();v_visit public.truck_visits;v_before jsonb;
begin
  if not public.can_do('sortie') then raise exception 'permission denied' using errcode='42501'; end if;
  select * into v_visit from public.truck_visits where id=p_visit for update;
  if not found or v_visit.exited_at is not null or v_visit.canceled_at is not null then
    raise exception 'visit unavailable for Exit'; end if;
  v_before:=to_jsonb(v_visit);
  -- If Engin was not executed, auto-record deposit if loaded container so stock remains accurate
  if v_visit.engin_at is null and v_visit.entry_kind='loaded' and v_visit.container_number is not null then
    perform 1 from public.containers where number=v_visit.container_number for update;
    insert into public.container_stock_intervals(container_number,client_id,armateur_id,iso_code,start_visit_id,arrived_at,position)
      values(v_visit.container_number,v_visit.client_id,v_visit.armateur_id,v_visit.iso_code,v_visit.id,now(),null)
      on conflict do nothing;
    update public.truck_visits set engin_at=now(),engin_by=v_actor where id=p_visit;
  end if;
  update public.truck_visits set exited_at=now(),exited_by=v_actor,version=version+1 where id=p_visit returning * into v_visit;
  perform public.record_event(v_visit,'SORTIE',v_actor);
  insert into public.audit_logs(entity,entity_id,action,actor_id,before_data,after_data)
    values('truck_visit',v_visit.id::text,'SORTIE',v_actor,v_before,to_jsonb(v_visit));
end; $$;
revoke all on function public.exit_truck(uuid) from public,anon;
grant execute on function public.exit_truck(uuid) to authenticated;
