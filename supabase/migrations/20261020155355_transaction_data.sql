-- Read-only transaction summary; no broader access to operator profiles.
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
    'bookings', jsonb_build_object('reference', b.reference),
    'creator_name', coalesce(nullif(btrim(creator.display_name), ''), v.entered_by::text),
    'changer_name', coalesce(nullif(btrim(changer.display_name), ''),
      coalesce(last_change.actor_id, v.entered_by)::text),
    'changed_at', coalesce(last_change.occurred_at, v.entered_at)
  )
  from (select * from public.truck_visits order by entered_at desc, id desc limit 500) v
  left join public.bookings b on b.id = v.booking_id
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
create index if not exists audit_logs_visit_latest_idx
  on public.audit_logs(entity_id, occurred_at desc, id desc)
  where entity = 'truck_visit';
