-- Freeze the event author on new documents; avoid exposing the private profiles table.
create or replace function public.record_event(p_visit public.truck_visits,p_action text,p_actor uuid,p_details jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id bigint; v_name text;
begin
  select coalesce(nullif(btrim(concat_ws(' ',first_name,last_name)),''),nullif(display_name,''),id::text)
    into v_name from public.profiles where id=p_actor;
  insert into public.visit_events(visit_id,action,actor_id,details)
    values(p_visit.id,p_action,p_actor,p_details) returning id into v_id;
  insert into public.generated_documents(visit_id,event_id,kind,snapshot,created_by)
    values(p_visit.id,v_id,p_action,to_jsonb(p_visit)||jsonb_build_object('event',p_details,'agent_name',coalesce(v_name,p_actor::text)),p_actor);
  return v_id;
end; $$;
revoke all on function public.record_event(public.truck_visits,text,uuid,jsonb) from public,anon,authenticated;

create function public.document_print_context(p_document uuid) returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_result jsonb;
begin
  if auth.uid() is null or not public.can_do('read') then raise exception 'permission denied' using errcode='42501'; end if;
  select jsonb_build_object('agent_name',coalesce(nullif(d.snapshot->>'agent_name',''),
    nullif(btrim(concat_ws(' ',p.first_name,p.last_name)),''),nullif(p.display_name,''),d.created_by::text),
    'visit_number',(select min(e.id) from public.visit_events e where e.visit_id=d.visit_id and e.action='ENTREE'),
    'created_at_local',to_char(d.created_at at time zone 'Africa/Casablanca','YYYY-MM-DD HH24:MI:SS'))
    into v_result from public.generated_documents d left join public.profiles p on p.id=d.created_by where d.id=p_document;
  if not found then raise exception 'Document unavailable' using errcode='P0002'; end if;
  return v_result;
end; $$;
revoke all on function public.document_print_context(uuid) from public,anon;
grant execute on function public.document_print_context(uuid) to authenticated;
