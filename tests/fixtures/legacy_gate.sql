CREATE OR REPLACE FUNCTION public.complete_gate_visit(p_visit uuid, p_container text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_actor uuid:=auth.uid(); v_visit public.truck_visits; v_before jsonb;
  v_number text:=upper(btrim(coalesce(p_container,''))); v_booking text;
begin
  if not public.can_do('sortie') then
    raise exception 'permission denied' using errcode='42501'; end if;
  select * into v_visit from public.truck_visits where id=p_visit for update;
  if not found or v_visit.exited_at is not null or v_visit.canceled_at is not null then
    raise exception 'visit unavailable for gate exit'; end if;
  v_before:=to_jsonb(v_visit);
  -- Legacy visits with an already completed movement must not move stock twice.
  if v_visit.engin_at is null then
    if v_visit.entry_kind='loaded' then
      v_number:=v_visit.container_number;
      perform 1 from public.containers where number=v_number for update;
      insert into public.container_stock_intervals(
        container_number,client_id,armateur_id,iso_code,start_visit_id,arrived_at)
        values(v_number,v_visit.client_id,v_visit.armateur_id,v_visit.iso_code,v_visit.id,now());
    else
      if not public.valid_container_number(v_number) then
        raise exception 'invalid ISO 6346 container number'; end if;
      perform 1 from public.containers where number=v_number for update;
      perform 1 from public.container_stock_intervals
        where container_number=v_number and departed_at is null for update;
      if not found then raise exception 'container not available in stock'; end if;
      if not exists(select 1 from public.containers where number=v_number
          and iso_code=v_visit.iso_code and armateur_id=v_visit.armateur_id) then
        raise exception 'container ISO or armateur mismatch'; end if;
      if exists(select 1 from public.container_stock_intervals
          where container_number=v_number and departed_at is null
            and client_id is not null and v_visit.client_id is not null
            and client_id<>v_visit.client_id) then
        raise exception 'container client mismatch'; end if;
      update public.container_stock_intervals set departed_at=now(),end_visit_id=v_visit.id
        where container_number=v_number and departed_at is null;
      v_visit.container_number:=v_number;
    end if;
  end if;
  -- These legacy columns record movement completion, not a separate user step.
  update public.truck_visits set container_number=v_visit.container_number,
    engin_at=coalesce(engin_at,now()),engin_by=coalesce(engin_by,v_actor),
    exited_at=now(),exited_by=v_actor,version=version+1
    where id=p_visit returning * into v_visit;
  select reference into v_booking from public.bookings where id=v_visit.booking_id;
  perform public.record_event(v_visit,'SORTIE',v_actor,
    jsonb_build_object('container',v_visit.container_number,'booking',v_booking,
      'operation',case when v_visit.entry_kind='loaded' then 'RECEPTION' else 'LIVRAISON' end));
  insert into public.audit_logs(entity,entity_id,action,actor_id,before_data,after_data)
    values('truck_visit',v_visit.id::text,'SORTIE',v_actor,v_before,to_jsonb(v_visit));
end; $function$
