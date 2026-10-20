-- An administrator may register an observed container without inventing yard stock.
begin;
create or replace function public.register_observed_container(
  p_number text,p_iso text,p_armateur text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid();v_number text:=upper(btrim(coalesce(p_number,'')));
  v_iso text:=upper(btrim(coalesce(p_iso,'')));
begin
  if not public.can_do('admin') then raise exception 'admin required' using errcode='42501'; end if;
  if not public.valid_container_number(v_number) then raise exception 'invalid ISO 6346 container number'; end if;
  if v_iso !~ '^[0-9A-Z]{4}$' then raise exception 'invalid ISO code'; end if;
  if not exists(select 1 from public.armateurs where id=p_armateur and active) then
    raise exception 'unknown armateur'; end if;
  insert into public.containers(number,iso_code,armateur_id,source)
    values(v_number,v_iso,p_armateur,'manual');
  insert into public.audit_logs(entity,entity_id,action,actor_id,after_data)
    values('container',v_number,'MANUAL_REGISTER',v_actor,
      jsonb_build_object('number',v_number,'iso_code',v_iso,'armateur_id',p_armateur));
end; $$;
revoke all on function public.register_observed_container(text,text,text) from public,anon;
grant execute on function public.register_observed_container(text,text,text) to authenticated;
commit;
