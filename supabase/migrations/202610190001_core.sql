-- Pointage Container core. Apply on a clean Supabase project; never from a client.
begin;

create extension if not exists pgcrypto;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create table public.user_roles (
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('admin','entree','engin','sortie','viewer')),
  primary key (user_id,role)
);
create or replace function public.create_profile_for_auth_user() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  insert into public.profiles(id,display_name) values(new.id,coalesce(new.raw_user_meta_data->>'name',''));
  return new;
end; $$;
create trigger auth_user_profile after insert on auth.users
  for each row execute function public.create_profile_for_auth_user();
create table public.clients (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  active boolean not null default true
);
create table public.armateurs (
  id text primary key,
  name text not null,
  bic text,
  official_logo_path text,
  official_logo_verified boolean not null default false,
  active boolean not null default true
);
create table public.client_armateurs (
  client_id uuid not null references public.clients(id),
  armateur_id text not null references public.armateurs(id),
  valid_from date not null,
  valid_to date,
  primary key(client_id,armateur_id,valid_from),
  check (valid_to is null or valid_to >= valid_from)
);
create table public.containers (
  number text primary key,
  iso_code text not null,
  armateur_id text not null references public.armateurs(id),
  source text not null default 'operator' check(source in ('operator','manual','import')),
  created_at timestamptz not null default now(),
  check(number ~ '^[A-Z]{4}[0-9]{7}$'),
  check(iso_code ~ '^[0-9A-Z]{4}$')
);
create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  reference text not null,
  client_id uuid references public.clients(id),
  armateur_id text references public.armateurs(id),
  iso_code text,
  created_at timestamptz not null default now(),
  check(length(btrim(reference)) between 1 and 150)
);
create table public.truck_visits (
  id uuid primary key default gen_random_uuid(),
  plate text not null,
  driver_cin text not null,
  entry_kind text not null check(entry_kind in ('loaded','empty')),
  container_number text references public.containers(number),
  booking_id uuid references public.bookings(id),
  iso_code text not null,
  armateur_id text not null references public.armateurs(id),
  client_id uuid references public.clients(id),
  entered_at timestamptz not null default now(),
  entered_by uuid not null references public.profiles(id),
  engin_at timestamptz,
  engin_by uuid references public.profiles(id),
  exited_at timestamptz,
  exited_by uuid references public.profiles(id),
  canceled_at timestamptz,
  canceled_by uuid references public.profiles(id),
  cancel_reason text,
  version integer not null default 1,
  check ((entry_kind='loaded' and container_number is not null and booking_id is null)
      or (entry_kind='empty' and booking_id is not null)),
  check (exited_at is null or (engin_at is not null and canceled_at is null)),
  check (canceled_at is null or (exited_at is null and length(btrim(cancel_reason))>0))
);
create index truck_visits_fifo_idx on public.truck_visits(entered_at,id) where exited_at is null and canceled_at is null;
create unique index one_active_container_on_truck on public.truck_visits(container_number)
  where container_number is not null and canceled_at is null and exited_at is null
    and ((entry_kind='loaded' and engin_at is null)
      or (entry_kind='empty' and engin_at is not null));
create index truck_visits_client_date_idx on public.truck_visits(client_id,entered_at);
create index truck_visits_armateur_date_idx on public.truck_visits(armateur_id,entered_at);
create table public.yard_operations (
  id uuid primary key default gen_random_uuid(),
  visit_id uuid not null unique references public.truck_visits(id),
  kind text not null check(kind in ('depose','prise')),
  container_number text not null references public.containers(number),
  position text,
  performed_at timestamptz not null default now(),
  performed_by uuid not null references public.profiles(id)
);
create table public.container_stock_intervals (
  id uuid primary key default gen_random_uuid(),
  container_number text not null references public.containers(number),
  client_id uuid references public.clients(id),
  armateur_id text not null references public.armateurs(id),
  iso_code text not null,
  start_visit_id uuid not null references public.truck_visits(id),
  end_visit_id uuid references public.truck_visits(id),
  arrived_at timestamptz not null,
  departed_at timestamptz,
  position text,
  check(departed_at is null or departed_at >= arrived_at)
);
create unique index one_open_stock_interval on public.container_stock_intervals(container_number) where departed_at is null;
create unique index one_open_yard_position on public.container_stock_intervals(position) where departed_at is null and position is not null;
create index stock_interval_period_idx on public.container_stock_intervals(arrived_at,departed_at);
create table public.visit_events (
  id bigint generated always as identity primary key,
  visit_id uuid not null references public.truck_visits(id),
  action text not null check(action in ('ENTREE','DEPOSE','PRISE','SORTIE','ANNULATION')),
  occurred_at timestamptz not null default now(),
  actor_id uuid not null references public.profiles(id),
  details jsonb not null default '{}'::jsonb
);
create index visit_events_timeline_idx on public.visit_events(visit_id,occurred_at,id);
create table public.audit_logs (
  id bigint generated always as identity primary key,
  entity text not null,
  entity_id text not null,
  action text not null,
  actor_id uuid not null references public.profiles(id),
  occurred_at timestamptz not null default now(),
  before_data jsonb,
  after_data jsonb,
  reason text
);
create table public.generated_documents (
  id uuid primary key default gen_random_uuid(),
  visit_id uuid not null references public.truck_visits(id),
  event_id bigint not null unique references public.visit_events(id),
  kind text not null check(kind in ('ENTREE','DEPOSE','PRISE','SORTIE')),
  storage_path text unique,
  status text not null default 'pending' check(status in ('pending','uploaded','failed')),
  snapshot jsonb not null,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);
create index generated_documents_visit_idx on public.generated_documents(visit_id,created_at);
create table public.printer_settings (
  user_id uuid not null references public.profiles(id),
  device_id text not null,
  printer_name text,
  updated_at timestamptz not null default now(),
  primary key(user_id,device_id)
);

create or replace function public.can_do(p_permission text) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.profiles p join public.user_roles r on r.user_id=p.id
    where p.id=auth.uid() and p.active and
    (r.role='admin' or (p_permission='entree' and r.role='entree')
      or (p_permission='engin' and r.role='engin')
      or (p_permission='sortie' and r.role='sortie')
      or (p_permission='read' and r.role in ('entree','engin','sortie','viewer')))
  );
$$;
revoke all on function public.can_do(text) from public;
grant execute on function public.can_do(text) to authenticated;

-- ISO 6346 check digit, including the 11,22,33 gap sequence for letters.
create or replace function public.valid_container_number(p_number text) returns boolean
language plpgsql immutable set search_path = public, pg_temp as $$
declare n text:=upper(coalesce(p_number,'')); i integer; value integer; total bigint:=0; c text; code integer;
begin
  if n !~ '^[A-Z]{4}[0-9]{7}$' then return false; end if;
  for i in 1..10 loop
    c:=substr(n,i,1);
    if i>4 then value:=c::integer;
    else
      code:=ascii(c)-ascii('A');
      value:=10+code+(10+code-1)/10;
    end if;
    total:=total+value*(1::bigint << (i-1));
  end loop;
  return (total % 11) % 10 = substr(n,11,1)::integer;
end; $$;
revoke all on function public.valid_container_number(text) from public;
grant execute on function public.valid_container_number(text) to authenticated;

create or replace function public.record_event(p_visit public.truck_visits,p_action text,p_actor uuid,p_details jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id bigint;
begin
  insert into public.visit_events(visit_id,action,actor_id,details)
    values(p_visit.id,p_action,p_actor,p_details) returning id into v_id;
  insert into public.generated_documents(visit_id,event_id,kind,snapshot,created_by)
    values(p_visit.id,v_id,p_action,to_jsonb(p_visit)||jsonb_build_object('event',p_details),p_actor);
  return v_id;
end; $$;
revoke all on function public.record_event(public.truck_visits,text,uuid,jsonb) from public,anon,authenticated;

create or replace function public.enter_truck(
  p_plate text,p_cin text,p_entry_kind text,p_container text,p_booking text,p_iso text,p_armateur text,p_client uuid default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid();v_visit public.truck_visits;v_number text:=upper(btrim(coalesce(p_container,'')));v_booking_id uuid;
begin
  if not public.can_do('entree') then raise exception 'permission denied' using errcode='42501'; end if;
  if length(btrim(coalesce(p_plate,'')))<2 or length(btrim(coalesce(p_cin,'')))<2 then raise exception 'plate and CIN required'; end if;
  if p_entry_kind not in ('loaded','empty') then raise exception 'invalid entry kind'; end if;
  if p_iso !~ '^[0-9A-Z]{4}$' then raise exception 'invalid ISO'; end if;
  if not exists(select 1 from public.armateurs where id=p_armateur and active) then raise exception 'unknown armateur'; end if;
  if p_entry_kind='loaded' then
    if not public.valid_container_number(v_number) then raise exception 'invalid ISO 6346 container number'; end if;
    insert into public.containers(number,iso_code,armateur_id,source)
      values(v_number,p_iso,p_armateur,'operator') on conflict(number) do nothing;
    if not exists(select 1 from public.containers
        where number=v_number and iso_code=p_iso and armateur_id=p_armateur) then
      raise exception 'container ISO or armateur mismatch'; end if;
    if exists(select 1 from public.container_stock_intervals where container_number=v_number and departed_at is null) then
      raise exception 'container already on ground'; end if;
  else
    if length(btrim(coalesce(p_booking,'')))<1 then raise exception 'booking required'; end if;
    insert into public.bookings(reference,client_id,armateur_id,iso_code)
      values(btrim(p_booking),p_client,p_armateur,p_iso) returning id into v_booking_id;
    v_number:=null;
  end if;
  insert into public.truck_visits(plate,driver_cin,entry_kind,container_number,booking_id,iso_code,armateur_id,client_id,entered_by)
    values(btrim(p_plate),btrim(p_cin),p_entry_kind,v_number,v_booking_id,p_iso,p_armateur,p_client,v_actor) returning * into v_visit;
  perform public.record_event(v_visit,'ENTREE',v_actor,jsonb_build_object('booking',p_booking));
  insert into public.audit_logs(entity,entity_id,action,actor_id,after_data)
    values('truck_visit',v_visit.id::text,'ENTREE',v_actor,to_jsonb(v_visit));
  return v_visit.id;
end; $$;
revoke all on function public.enter_truck(text,text,text,text,text,text,text,uuid) from public,anon;
grant execute on function public.enter_truck(text,text,text,text,text,text,text,uuid) to authenticated;

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
    if length(btrim(coalesce(p_position,'')))=0 then raise exception 'position required'; end if;
    perform 1 from public.containers where number=v_number for update;
    insert into public.container_stock_intervals(container_number,client_id,armateur_id,iso_code,start_visit_id,arrived_at,position)
      values(v_number,v_visit.client_id,v_visit.armateur_id,v_visit.iso_code,v_visit.id,now(),btrim(p_position));
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
    values(v_visit.id,v_kind,v_number,p_position,v_actor);
  update public.truck_visits set engin_at=now(),engin_by=v_actor,version=version+1 where id=v_visit.id returning * into v_visit;
  perform public.record_event(v_visit,upper(v_kind),v_actor,jsonb_build_object('container',v_number,'position',p_position));
  insert into public.audit_logs(entity,entity_id,action,actor_id,before_data,after_data)
    values('truck_visit',v_visit.id::text,upper(v_kind),v_actor,v_before,to_jsonb(v_visit));
end; $$;
revoke all on function public.perform_engin(uuid,text,text) from public,anon;
grant execute on function public.perform_engin(uuid,text,text) to authenticated;

create or replace function public.exit_truck(p_visit uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid();v_visit public.truck_visits;v_before jsonb;
begin
  if not public.can_do('sortie') then raise exception 'permission denied' using errcode='42501'; end if;
  select * into v_visit from public.truck_visits where id=p_visit for update;
  if not found or v_visit.engin_at is null or v_visit.exited_at is not null or v_visit.canceled_at is not null then
    raise exception 'Engin must be completed before exit'; end if;
  v_before:=to_jsonb(v_visit);
  update public.truck_visits set exited_at=now(),exited_by=v_actor,version=version+1 where id=p_visit returning * into v_visit;
  perform public.record_event(v_visit,'SORTIE',v_actor);
  insert into public.audit_logs(entity,entity_id,action,actor_id,before_data,after_data)
    values('truck_visit',v_visit.id::text,'SORTIE',v_actor,v_before,to_jsonb(v_visit));
end; $$;
revoke all on function public.exit_truck(uuid) from public,anon;
grant execute on function public.exit_truck(uuid) to authenticated;

create or replace function public.cancel_visit(p_visit uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid();v_visit public.truck_visits;v_before jsonb;
begin
  if not public.can_do('admin') then raise exception 'admin required' using errcode='42501'; end if;
  if length(btrim(coalesce(p_reason,'')))<5 then raise exception 'cancellation reason required'; end if;
  select * into v_visit from public.truck_visits where id=p_visit for update;
  if not found or v_visit.engin_at is not null or v_visit.exited_at is not null or v_visit.canceled_at is not null then
    raise exception 'only pending visits may be canceled'; end if;
  v_before:=to_jsonb(v_visit);
  update public.truck_visits set canceled_at=now(),canceled_by=v_actor,cancel_reason=btrim(p_reason),version=version+1
    where id=p_visit returning * into v_visit;
  insert into public.visit_events(visit_id,action,actor_id,details)
    values(p_visit,'ANNULATION',v_actor,jsonb_build_object('reason',p_reason));
  insert into public.audit_logs(entity,entity_id,action,actor_id,before_data,after_data,reason)
    values('truck_visit',p_visit::text,'ANNULATION',v_actor,v_before,to_jsonb(v_visit),p_reason);
end; $$;
revoke all on function public.cancel_visit(uuid,text) from public,anon;
grant execute on function public.cancel_visit(uuid,text) to authenticated;

-- Client may read; all business writes go through the RPCs above.
grant usage on schema public to authenticated;
grant select on public.profiles,public.user_roles,public.clients,public.armateurs,public.client_armateurs,
  public.containers,public.bookings,public.truck_visits,public.yard_operations,public.container_stock_intervals,
  public.visit_events,public.audit_logs,public.generated_documents,public.printer_settings to authenticated;
revoke insert,update,delete on public.profiles,public.user_roles,public.clients,public.armateurs,public.client_armateurs,
  public.containers,public.bookings,public.truck_visits,public.yard_operations,public.container_stock_intervals,
  public.visit_events,public.audit_logs,public.generated_documents from anon,authenticated;

alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.clients enable row level security;
alter table public.armateurs enable row level security;
alter table public.client_armateurs enable row level security;
alter table public.containers enable row level security;
alter table public.bookings enable row level security;
alter table public.truck_visits enable row level security;
alter table public.yard_operations enable row level security;
alter table public.container_stock_intervals enable row level security;
alter table public.visit_events enable row level security;
alter table public.audit_logs enable row level security;
alter table public.generated_documents enable row level security;
alter table public.printer_settings enable row level security;

create policy profile_self on public.profiles for select to authenticated using(id=auth.uid() or public.can_do('admin'));
create policy roles_self on public.user_roles for select to authenticated using(user_id=auth.uid() or public.can_do('admin'));
create policy clients_read on public.clients for select to authenticated using(public.can_do('read'));
create policy armateurs_read on public.armateurs for select to authenticated using(public.can_do('read'));
create policy client_armateurs_read on public.client_armateurs for select to authenticated using(public.can_do('read'));
create policy containers_read on public.containers for select to authenticated using(public.can_do('read'));
create policy bookings_read on public.bookings for select to authenticated using(public.can_do('read'));
create policy truck_visits_read on public.truck_visits for select to authenticated using(public.can_do('read'));
create policy yard_operations_read on public.yard_operations for select to authenticated using(public.can_do('read'));
create policy stock_read on public.container_stock_intervals for select to authenticated using(public.can_do('read'));
create policy visit_events_read on public.visit_events for select to authenticated using(public.can_do('read'));
create policy audit_admin_read on public.audit_logs for select to authenticated using(public.can_do('admin'));
create policy docs_read on public.generated_documents for select to authenticated using(public.can_do('read'));
create policy printer_self on public.printer_settings for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
grant insert,update,delete on public.printer_settings to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
  values('pointage-documents','pointage-documents',false,10000000,array['application/pdf'])
  on conflict(id) do nothing;
create policy private_document_read on storage.objects for select to authenticated
  using(bucket_id='pointage-documents' and public.can_do('read'));
-- Upload/finalization is reserved for a server component, not direct client writes.

commit;
