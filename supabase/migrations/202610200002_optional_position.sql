-- Migration: Make yard position optional for Engin (Dépose) operations
create or replace function public.perform_engin(p_visit uuid,p_container text default null,p_position text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid();v_visit public.truck_visits;v_number text:=upper(btrim(coalesce(p_container,'')));v_kind text;v_before jsonb;
begin
  if not (public.can_do('engin') or public.can_do('sortie')) then raise exception 'permission denied' using errcode='42501'; end if;
  select * into v_visit from public.truck_visits where id=p_visit for update;
  if not found or v_visit.engin_at is not null or v_visit.exited_at is not null or v_visit.canceled_at is not null then
    raise exception 'visit unavailable for Engin'; end if;
  v_before:=to_jsonb(v_visit);
  if v_visit.entry_kind='loaded' then
    v_kind:='depose';v_number:=v_visit.container_number;
    perform 1 from public.containers where number=v_number for update;
    insert into public.container_stock_intervals(container_number,client_id,armateur_id,iso_code,start_visit_id,arrived_at,position)
      values(v_number,v_visit.client_id,v_visit.armateur_id,v_visit.iso_code,v_visit.id,now(),nullif(btrim(coalesce(p_position,'')),''));
  else
    v_kind:='prise';
    if not public.valid_container_number(v_number) then raise exception 'invalid ISO 6346 container number'; end if;
    perform 1 from public.container_stock_intervals where container_number=v_number and departed_at is null for update;
    if not found then raise exception 'container not available in stock'; end if;
    if not exists(select 1 from public.containers where number=v_number and iso_code=v_visit.iso_code and armateur_id=v_visit.armateur_id) then
      raise exception 'container ISO or armateur mismatch'; end if;
    if exists(select 1 from public.container_stock_intervals
        where container_number=v_number and departed_at is null
          and client_id is not null and v_visit.client_id is not null
          and client_id <> v_visit.client_id) then
      raise exception 'container client mismatch'; end if;
    update public.container_stock_intervals set departed_at=now(),end_visit_id=v_visit.id
      where container_number=v_number and departed_at is null;
    update public.truck_visits set container_number=v_number where id=v_visit.id;
  end if;
  insert into public.yard_operations(visit_id,kind,container_number,position,performed_by)
    values(v_visit.id,v_kind,v_number,nullif(btrim(coalesce(p_position,'')),''),v_actor);
  update public.truck_visits set engin_at=now(),engin_by=v_actor,version=version+1 where id=v_visit.id returning * into v_visit;
  perform public.record_event(v_visit,upper(v_kind),v_actor,jsonb_build_object('container',v_number,'position',nullif(btrim(coalesce(p_position,'')),'')));
  insert into public.audit_logs(entity,entity_id,action,actor_id,before_data,after_data)
    values('truck_visit',v_visit.id::text,upper(v_kind),v_actor,v_before,to_jsonb(v_visit));
end; $$;
revoke all on function public.perform_engin(uuid,text,text) from public,anon;
grant execute on function public.perform_engin(uuid,text,text) to authenticated;
