-- Keep client orders independent from each shipping line's booking reference.
alter table public.truck_visits
  add column client_order_reference text check (length(btrim(client_order_reference)) between 1 and 150),
  add column carrier_booking_reference text check (length(btrim(carrier_booking_reference)) between 1 and 150),
  add column carrier_booking_armateur_id text references public.armateurs(id),
  add column carrier_booking_armateur_id_2 text references public.armateurs(id);

create or replace function public.enter_order_truck(
  p_plate text, p_cin text, p_entry_kind text, p_container text, p_booking text,
  p_iso text, p_armateur text, p_client uuid default null,
  p_is_twin boolean default false, p_container_2 text default null,
  p_iso_2 text default null, p_armateur_2 text default null, p_booking_2 text default null,
  p_order_reference text default null
)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_actor uuid:=auth.uid();
  v_id uuid;
  v_order text:=nullif(btrim(p_order_reference),'');
  v_booking text:=nullif(btrim(p_booking),'');
  v_visit public.truck_visits;
  v_details jsonb;
begin
  if not public.can_do('entree') then raise exception 'permission denied' using errcode='42501'; end if;
  if (p_client is null) <> (v_order is null) then
    raise exception 'Client et référence d''ordre doivent être renseignés ensemble' using errcode='23514';
  end if;
  if v_order is not null and (length(v_order)>150 or v_booking is null) then
    raise exception 'Ordre client et booking armateur requis (maximum 150 caractères)' using errcode='23514';
  end if;
  if p_client is not null and not exists(select 1 from public.clients where id=p_client and active) then
    raise exception 'Client inactif ou inconnu' using errcode='23514';
  end if;
  -- The existing entry transaction, stock checks and permissions remain authoritative.
  v_id:=public.enter_truck(p_plate,p_cin,p_entry_kind,p_container,p_booking,p_iso,p_armateur,
    p_client,p_is_twin,p_container_2,p_iso_2,p_armateur_2,p_booking_2);
  update public.truck_visits set client_order_reference=v_order, carrier_booking_reference=v_booking,
    carrier_booking_armateur_id=p_armateur,
    carrier_booking_armateur_id_2=case when p_is_twin then coalesce(p_armateur_2,p_armateur) end
    where id=v_id returning * into v_visit;
  v_details:=jsonb_build_object('client_id',p_client,'client_order_reference',v_order,'booking',v_booking);
  -- Complete the new entry's document snapshot before it can be generated externally.
  update public.visit_events set details=details||v_details where visit_id=v_id and action='ENTREE';
  update public.generated_documents d set snapshot=to_jsonb(v_visit)||jsonb_build_object('event',e.details)
    from public.visit_events e where d.event_id=e.id and e.visit_id=v_id and e.action='ENTREE';
  insert into public.audit_logs(entity,entity_id,action,actor_id,after_data)
    values('truck_visit',v_id::text,'ENTRY_REFERENCES',v_actor,to_jsonb(v_visit));
  return v_id;
end; $$;
revoke all on function public.enter_order_truck(text,text,text,text,text,text,text,uuid,boolean,text,text,text,text,text) from public,anon;
grant execute on function public.enter_order_truck(text,text,text,text,text,text,text,uuid,boolean,text,text,text,text,text) to authenticated;

create or replace function public.data_transactions()
returns setof jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
begin
  if not public.can_do('read') then
    raise exception 'permission denied' using errcode = '42501';
  end if;
  return query
  select to_jsonb(v) || jsonb_build_object(
    'transaction_number', entry.id::text,
    'client_name', order_client.name,
    'bookings', jsonb_build_object('reference', coalesce(v.carrier_booking_reference,b.reference)),
    'creator_name', coalesce(nullif(btrim(creator.display_name), ''), v.entered_by::text),
    'changer_name', coalesce(nullif(btrim(changer.display_name), ''),
      coalesce(last_change.actor_id, v.entered_by)::text),
    'changed_at', coalesce(last_change.occurred_at, v.entered_at)
  )
  from (select * from public.truck_visits order by entered_at desc, id desc limit 500) v
  left join public.bookings b on b.id = v.booking_id
  left join public.clients order_client on order_client.id = v.client_id
  left join public.profiles creator on creator.id = v.entered_by
  left join lateral (
    select e.id from public.visit_events e
    where e.visit_id = v.id and e.action = 'ENTREE'
    order by e.occurred_at, e.id limit 1
  ) entry on true
  left join lateral (
    select a.actor_id, a.occurred_at from public.audit_logs a
    where a.entity = 'truck_visit' and a.entity_id = v.id::text
    order by a.occurred_at desc, a.id desc limit 1
  ) last_change on true
  left join public.profiles changer on changer.id = coalesce(last_change.actor_id, v.entered_by)
  order by v.entered_at desc, v.id desc;
end;
$$;
revoke all on function public.data_transactions() from public, anon;
grant execute on function public.data_transactions() to authenticated;
