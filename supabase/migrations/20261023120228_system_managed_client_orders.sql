-- Client/order attribution belongs to the admin or trusted server-side EDI service.
-- Gate clerks may capture booking references, but may not assign the client/order.
create or replace function public.guard_client_order_assignment()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
declare changed boolean;
begin
  if tg_op='INSERT' then
    changed:=new.client_id is not null or new.client_order_reference is not null;
  else
    changed:=new.client_id is distinct from old.client_id
      or new.client_order_reference is distinct from old.client_order_reference;
  end if;
  if changed and not public.can_do('admin')
    and coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb->>'role'
      is distinct from 'service_role' then
    raise exception 'Affectation client/ordre réservée au système EDI ou à l''administrateur'
      using errcode='42501';
  end if;
  return new;
end; $$;
revoke all on function public.guard_client_order_assignment() from public,anon,authenticated;
create trigger protect_client_order_assignment
  before insert or update of client_id,client_order_reference on public.truck_visits
  for each row execute function public.guard_client_order_assignment();
