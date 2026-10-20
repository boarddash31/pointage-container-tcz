-- Explicit exception flow for a physically present container without an open yard stock record.
-- Review against the live project schema before applying.
begin;

create table public.forced_container_actions (
  id uuid primary key default gen_random_uuid(),
  visit_id uuid not null unique references public.truck_visits(id),
  container_number text not null references public.containers(number),
  action text not null check (action in ('PRISE_SANS_STOCK')),
  reason text not null check (length(btrim(reason)) >= 10),
  actor_id uuid not null references public.profiles(id),
  occurred_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles(id),
  external_reference text,
  check ((resolved_at is null and resolved_by is null and external_reference is null)
    or (resolved_at is not null and resolved_by is not null and length(btrim(external_reference)) >= 3))
);
create index forced_actions_unresolved_idx on public.forced_container_actions(occurred_at)
  where resolved_at is null;
grant select on public.forced_container_actions to authenticated;
revoke insert,update,delete on public.forced_container_actions from anon,authenticated;
alter table public.forced_container_actions enable row level security;
create policy forced_actions_admin_read on public.forced_container_actions
  for select to authenticated using(public.can_do('admin'));

create or replace function public.force_pickup_without_stock(
  p_visit uuid,p_container text,p_reason text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_actor uuid:=auth.uid();
  v_visit public.truck_visits;
  v_number text:=upper(btrim(coalesce(p_container,'')));
  v_container public.containers;
  v_before jsonb;
  v_forced uuid;
begin
  if not public.can_do('admin') then raise exception 'admin required' using errcode='42501'; end if;
  if length(btrim(coalesce(p_reason,'')))<10 then raise exception 'detailed reason required'; end if;
  if not public.valid_container_number(v_number) then raise exception 'invalid ISO 6346 container number'; end if;
  select * into v_visit from public.truck_visits where id=p_visit for update;
  if not found or v_visit.entry_kind<>'empty' or v_visit.engin_at is not null
      or v_visit.exited_at is not null or v_visit.canceled_at is not null then
    raise exception 'pending empty visit required';
  end if;
  select * into v_container from public.containers where number=v_number for update;
  if not found then
    insert into public.containers(number,iso_code,armateur_id,source)
      values(v_number,v_visit.iso_code,v_visit.armateur_id,'manual');
  elsif v_container.iso_code<>v_visit.iso_code or v_container.armateur_id<>v_visit.armateur_id then
    raise exception 'container ISO or armateur mismatch; reconcile master first';
  end if;
  if exists(select 1 from public.container_stock_intervals
      where container_number=v_number and departed_at is null) then
    raise exception 'container is in stock; use normal pickup';
  end if;
  v_before:=to_jsonb(v_visit);
  insert into public.yard_operations(visit_id,kind,container_number,performed_by)
    values(v_visit.id,'prise',v_number,v_actor);
  update public.truck_visits set container_number=v_number,engin_at=now(),engin_by=v_actor,
    version=version+1 where id=v_visit.id returning * into v_visit;
  perform public.record_event(v_visit,'PRISE',v_actor,
    jsonb_build_object('container',v_number,'forced',true,'reason',btrim(p_reason)));
  insert into public.forced_container_actions(visit_id,container_number,action,reason,actor_id)
    values(v_visit.id,v_number,'PRISE_SANS_STOCK',btrim(p_reason),v_actor)
    returning id into v_forced;
  insert into public.audit_logs(entity,entity_id,action,actor_id,before_data,after_data,reason)
    values('truck_visit',v_visit.id::text,'PRISE_FORCEE',v_actor,v_before,to_jsonb(v_visit),btrim(p_reason));
  return v_forced;
end; $$;
revoke all on function public.force_pickup_without_stock(uuid,text,text) from public,anon;
grant execute on function public.force_pickup_without_stock(uuid,text,text) to authenticated;

create or replace function public.resolve_forced_action(p_action uuid,p_external_reference text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid();v_before jsonb;v_after jsonb;
begin
  if not public.can_do('admin') then raise exception 'admin required' using errcode='42501'; end if;
  if length(btrim(coalesce(p_external_reference,'')))<3 then
    raise exception 'external reconciliation reference required'; end if;
  select to_jsonb(f) into v_before from public.forced_container_actions f
    where id=p_action and resolved_at is null for update;
  if not found then raise exception 'unresolved forced action not found'; end if;
  update public.forced_container_actions set resolved_at=now(),resolved_by=v_actor,
    external_reference=btrim(p_external_reference) where id=p_action returning to_jsonb(forced_container_actions.*) into v_after;
  insert into public.audit_logs(entity,entity_id,action,actor_id,before_data,after_data)
    values('forced_container_action',p_action::text,'RECONCILE',v_actor,v_before,v_after);
end; $$;
revoke all on function public.resolve_forced_action(uuid,text) from public,anon;
grant execute on function public.resolve_forced_action(uuid,text) to authenticated;

commit;
