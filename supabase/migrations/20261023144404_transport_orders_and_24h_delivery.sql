-- Orders are authored by a gate clerk, an administrator, or an authenticated EDI service.
-- Expand/contract rollout: retire legacy unbound entry only after the new web app is published.
create schema if not exists private;
create table private.transport_order_controls(singleton boolean primary key default true check(singleton),required boolean not null default false);
insert into private.transport_order_controls values(true,false);
alter table private.transport_order_controls enable row level security;
revoke all on private.transport_order_controls from public,anon,authenticated;
create function public.require_transport_orders(p_required boolean) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not public.can_do('admin') then raise exception 'admin required' using errcode='42501'; end if;
  update private.transport_order_controls set required=p_required where singleton;
  insert into public.audit_logs(entity,entity_id,action,actor_id,after_data)
    values('workflow','transport_orders','REQUIRE_ORDERS',auth.uid(),jsonb_build_object('required',p_required));
end; $$;
revoke all on function public.require_transport_orders(boolean) from public,anon;
grant execute on function public.require_transport_orders(boolean) to authenticated;
create table public.transport_orders (
  id uuid primary key default gen_random_uuid(),
  kind text not null check(kind in ('BOOKING','EDO','ERO')),
  direction text not null check(direction in ('RESTITUTION','LIVRAISON')),
  reference text not null check(length(btrim(reference)) between 1 and 150),
  armateur_id text not null references public.armateurs(id),
  client_id uuid references public.clients(id),
  client_order_reference text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id),
  check((kind<>'EDO' or direction='LIVRAISON') and (kind<>'ERO' or direction='RESTITUTION')),
  check(client_order_reference is null or client_id is not null)
);
create unique index transport_orders_reference_key on public.transport_orders(kind,direction,armateur_id,upper(btrim(reference)));
create table public.transport_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.transport_orders(id),
  iso_code text not null check(iso_code ~ '^[0-9A-Z]{4}$'),
  quantity integer not null check(quantity between 1 and 1000000),
  unique(order_id,iso_code)
);
create index transport_orders_client_idx on public.transport_orders(client_id) where client_id is not null;
alter table public.transport_orders enable row level security;
alter table public.transport_order_items enable row level security;
revoke all on public.transport_orders,public.transport_order_items from anon,authenticated;
grant select on public.transport_orders,public.transport_order_items to authenticated;
create policy transport_orders_read on public.transport_orders for select to authenticated using(public.can_do('read'));
create policy transport_order_items_read on public.transport_order_items for select to authenticated using(public.can_do('read'));

alter table public.truck_visits
  add column order_item_id uuid references public.transport_order_items(id),
  add column order_item_id_2 uuid references public.transport_order_items(id),
  add column order_controlled boolean not null default false;
create index visits_order_item_idx on public.truck_visits(order_item_id) where canceled_at is null;
create index visits_order_item_2_idx on public.truck_visits(order_item_id_2) where canceled_at is null;

create function public.create_transport_order(p_kind text,p_direction text,p_reference text,p_armateur text,p_items jsonb,
  p_client uuid default null,p_client_order_reference text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_item jsonb; v_service boolean :=
  coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb->>'role'='service_role';
begin
  if not (public.can_do('entree') or coalesce(v_service,false)) then
    raise exception 'Création d''ordre non autorisée' using errcode='42501'; end if;
  if (p_client is not null or nullif(btrim(p_client_order_reference),'') is not null)
    and not (public.can_do('admin') or coalesce(v_service,false)) then
    raise exception 'Affectation client réservée au système EDI ou à l''administrateur' using errcode='42501'; end if;
  if not exists(select 1 from public.armateurs where id=p_armateur and active) then
    raise exception 'Armateur actif requis' using errcode='23514'; end if;
  if p_client is not null and not exists(select 1 from public.clients where id=p_client and active) then
    raise exception 'Client actif requis' using errcode='23514'; end if;
  if jsonb_typeof(p_items) is distinct from 'array' then raise exception 'Articles requis' using errcode='23514'; end if;
  if jsonb_array_length(p_items) not between 1 and 50 then raise exception 'Entre 1 et 50 articles requis' using errcode='23514'; end if;
  insert into public.transport_orders(kind,direction,reference,armateur_id,client_id,client_order_reference,created_by)
    values(upper(btrim(p_kind)),upper(btrim(p_direction)),upper(btrim(p_reference)),p_armateur,p_client,
      nullif(upper(btrim(p_client_order_reference)),''),auth.uid()) returning id into v_id;
  for v_item in select value from jsonb_array_elements(p_items) loop
    insert into public.transport_order_items(order_id,iso_code,quantity)
      values(v_id,upper(btrim(v_item->>'iso_code')),(v_item->>'quantity')::integer);
  end loop;
  insert into public.audit_logs(entity,entity_id,action,actor_id,after_data)
    values('transport_order',v_id::text,'CREATION',auth.uid(),jsonb_build_object('kind',p_kind,'reference',p_reference,'items',p_items));
  return v_id;
end; $$;
revoke all on function public.create_transport_order(text,text,text,text,jsonb,uuid,text) from public,anon;
grant execute on function public.create_transport_order(text,text,text,text,jsonb,uuid,text) to authenticated,service_role;

-- Row locks serialize reservations, including a twin using the same order item twice.
create function public.bind_visit_order() returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
declare i record; h public.transport_orders; h2 public.transport_orders; v_used integer; v_needed integer;
begin
  if new.order_item_id is null and new.order_item_id_2 is null
    and not (select required from private.transport_order_controls where singleton) then return new; end if;
  if new.order_item_id is null or (new.is_twin and new.order_item_id_2 is null)
    or (not new.is_twin and new.order_item_id_2 is not null) then
    raise exception 'Sélectionnez un article Booking / EDO / ERO pour chaque conteneur' using errcode='23514'; end if;
  if new.entry_kind='loaded' and exists(select 1 from public.container_stock_intervals
      where container_number in (new.container_number,new.container_number_2) and departed_at is null) then
    raise exception 'Conteneur déjà présent au stock' using errcode='23514'; end if;
  if new.is_twin and (left(new.iso_code,1)<>'2' or left(coalesce(new.iso_code_2,''),1)<>'2'
    or (new.entry_kind='loaded' and new.container_number=new.container_number_2)) then
    raise exception 'Deux conteneurs distincts de 20 pieds sont requis' using errcode='23514'; end if;
  for i in select * from public.transport_order_items where id in (new.order_item_id,new.order_item_id_2) order by id for update loop
    select * into h from public.transport_orders where id=i.order_id;
    if not h.active or h.direction<>(case when new.entry_kind='loaded' then 'RESTITUTION' else 'LIVRAISON' end) then
      raise exception 'Sens de l''ordre incompatible ou ordre inactif' using errcode='23514'; end if;
    v_needed:=(case when i.id=new.order_item_id then 1 else 0 end)+(case when i.id=new.order_item_id_2 then 1 else 0 end);
    select count(*) into v_used from public.truck_visits v cross join lateral (values(v.order_item_id),(v.order_item_id_2)) x(item)
      where v.canceled_at is null and x.item=i.id;
    if v_used+v_needed>i.quantity then
      raise exception 'Quantité autorisée épuisée pour % / % (% disponible)',h.reference,i.iso_code,greatest(0,i.quantity-v_used)
        using errcode='23514'; end if;
    if (i.id=new.order_item_id and (new.iso_code is distinct from i.iso_code or new.armateur_id is distinct from h.armateur_id))
      or (i.id=new.order_item_id_2 and (new.iso_code_2 is distinct from i.iso_code or new.armateur_id_2 is distinct from h.armateur_id)) then
      raise exception 'Code ISO ou armateur incompatible avec l''article de l''ordre' using errcode='23514'; end if;
  end loop;
  select o.* into strict h from public.transport_orders o join public.transport_order_items oi on oi.order_id=o.id where oi.id=new.order_item_id;
  if new.is_twin then
    select o.* into strict h2 from public.transport_orders o join public.transport_order_items oi on oi.order_id=o.id where oi.id=new.order_item_id_2;
    if h.client_id is distinct from h2.client_id or h.client_order_reference is distinct from h2.client_order_reference then
      raise exception 'Les deux articles doivent appartenir au même client et ordre client' using errcode='23514'; end if;
  end if;
  new.client_id:=h.client_id; new.client_order_reference:=h.client_order_reference;
  new.carrier_booking_reference:=h.reference; new.carrier_booking_armateur_id:=h.armateur_id;
  new.booking_reference_2:=case when new.is_twin then h2.reference else null end;
  new.carrier_booking_armateur_id_2:=case when new.is_twin then h2.armateur_id else null end;
  new.order_controlled:=true;
  return new;
end; $$;
revoke all on function public.bind_visit_order() from public,anon,authenticated;
create trigger a_bind_visit_order before insert on public.truck_visits for each row execute function public.bind_visit_order();

-- Identity can only be derived from a validated order; callers cannot choose another client.
create or replace function public.guard_client_order_assignment() returns trigger
language plpgsql security invoker set search_path=public,pg_temp as $$
declare changed boolean; derived boolean:=false;
begin
  if tg_op='INSERT' then
    changed:=new.client_id is not null or new.client_order_reference is not null;
    select exists(select 1 from public.transport_order_items i join public.transport_orders o on o.id=i.order_id
      where i.id=new.order_item_id and new.order_controlled and new.client_id is not distinct from o.client_id
      and new.client_order_reference is not distinct from o.client_order_reference) into derived;
  else
    changed:=new.client_id is distinct from old.client_id or new.client_order_reference is distinct from old.client_order_reference;
  end if;
  if changed and not derived and not public.can_do('admin')
    and coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb->>'role' is distinct from 'service_role' then
    raise exception 'Affectation client/ordre réservée au système EDI ou à l''administrateur' using errcode='42501'; end if;
  return new;
end; $$;

create function public.enter_transport_visit(p_plate text,p_cin text,p_entry_kind text,p_container text,
  p_iso text,p_armateur text,p_order_item uuid,p_is_twin boolean default false,
  p_container_2 text default null,p_iso_2 text default null,p_armateur_2 text default null,p_order_item_2 uuid default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.truck_visits; b uuid; ref text;
begin
  if not public.can_do('entree') then raise exception 'permission denied' using errcode='42501'; end if;
  if p_order_item is null or (coalesce(p_is_twin,false) and p_order_item_2 is null) then
    raise exception 'Article Booking / EDO / ERO requis pour chaque conteneur' using errcode='23514'; end if;
  if length(btrim(coalesce(p_plate,'')))<2 or length(btrim(coalesce(p_cin,'')))<2 then raise exception 'Plaque et CIN requis'; end if;
  if p_entry_kind not in ('loaded','empty') then raise exception 'invalid entry kind'; end if;
  p_container:=upper(btrim(p_container)); p_container_2:=upper(btrim(p_container_2));
  if p_entry_kind='loaded' then
    if not coalesce(public.valid_container_number(p_container),false) or (p_is_twin and not coalesce(public.valid_container_number(p_container_2),false)) then
      raise exception 'Numéro ISO 6346 invalide' using errcode='23514'; end if;
    insert into public.containers(number,iso_code,armateur_id,source) values(p_container,p_iso,p_armateur,'operator')
      on conflict(number) do update set iso_code=excluded.iso_code,armateur_id=excluded.armateur_id;
    if p_is_twin then
      insert into public.containers(number,iso_code,armateur_id,source) values(p_container_2,p_iso_2,p_armateur_2,'operator')
        on conflict(number) do update set iso_code=excluded.iso_code,armateur_id=excluded.armateur_id;
    end if;
  else
    select o.reference into ref from public.transport_order_items i join public.transport_orders o on o.id=i.order_id where i.id=p_order_item;
    if ref is null then raise exception 'Article d''ordre requis' using errcode='23514'; end if;
    insert into public.bookings(reference,armateur_id,iso_code) values(ref,p_armateur,p_iso) returning id into b;
  end if;
  insert into public.truck_visits(plate,driver_cin,entry_kind,container_number,booking_id,iso_code,armateur_id,entered_by,
    is_twin,container_number_2,iso_code_2,armateur_id_2,order_item_id,order_item_id_2)
    values(btrim(p_plate),btrim(p_cin),p_entry_kind,case when p_entry_kind='loaded' then p_container end,b,p_iso,p_armateur,auth.uid(),
      p_is_twin,case when p_entry_kind='loaded' and p_is_twin then p_container_2 end,
      case when p_is_twin then p_iso_2 end,case when p_is_twin then p_armateur_2 end,p_order_item,case when p_is_twin then p_order_item_2 end)
    returning * into v;
  perform public.record_event(v,'ENTREE',auth.uid(),jsonb_build_object('booking',v.carrier_booking_reference));
  insert into public.audit_logs(entity,entity_id,action,actor_id,after_data) values('truck_visit',v.id::text,'ENTREE',auth.uid(),to_jsonb(v));
  return v.id;
end; $$;
revoke all on function public.enter_transport_visit(text,text,text,text,text,text,uuid,boolean,text,text,text,uuid) from public,anon;
grant execute on function public.enter_transport_visit(text,text,text,text,text,text,uuid,boolean,text,text,text,uuid) to authenticated;

create function public.transport_order_items_status() returns setof jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not public.can_do('read') then raise exception 'permission denied' using errcode='42501'; end if;
  return query select to_jsonb(i)||jsonb_build_object('kind',o.kind,'direction',o.direction,'reference',o.reference,
    'armateur_id',o.armateur_id,'active',o.active,'reserved',t.reserved,'completed',t.completed,'remaining',i.quantity-t.reserved-t.completed)
    from public.transport_order_items i join public.transport_orders o on o.id=i.order_id
    cross join lateral (select count(*) filter(where v.engin_at is null and v.exited_at is null)::integer reserved,
      count(*) filter(where v.engin_at is not null or v.exited_at is not null)::integer completed
      from public.truck_visits v cross join lateral (values(v.order_item_id),(v.order_item_id_2)) x(item)
      where v.canceled_at is null and x.item=i.id) t order by o.created_at desc,i.iso_code;
end; $$;
revoke all on function public.transport_order_items_status() from public,anon;
grant execute on function public.transport_order_items_status() to authenticated;

-- Authoritative dwell-time check: the clock starts with the receiving truck's gate entry.
create function public.guard_stock_delivery_age() returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_entry timestamptz;
begin
  if new.departed_at is not null and (tg_op='INSERT' or old.departed_at is null) then
    select entered_at into v_entry from public.truck_visits where id=new.start_visit_id and entry_kind='loaded' and canceled_at is null;
    if v_entry is null then raise exception 'Entrée du camion de restitution introuvable' using errcode='23514'; end if;
    if statement_timestamp()<v_entry+interval '24 hours' or new.departed_at<v_entry+interval '24 hours' then
      raise exception 'Livraison interdite avant 24 heures après l''entrée du camion. Disponible le %',v_entry+interval '24 hours' using errcode='23514'; end if;
  end if;
  return new;
end; $$;
revoke all on function public.guard_stock_delivery_age() from public,anon,authenticated;
create trigger check_stock_delivery_age before insert or update on public.container_stock_intervals for each row execute function public.guard_stock_delivery_age();

-- The check on the visit also covers APIs that previously allowed a pickup without any stock row.
create function public.guard_visit_delivery() returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
declare n text; source_entry timestamptz; item record; s public.container_stock_intervals;
  expected_arm text; expected_iso text; slot integer;
begin
  if new.order_item_id is distinct from old.order_item_id or new.order_item_id_2 is distinct from old.order_item_id_2
    or new.order_controlled is distinct from old.order_controlled then
    raise exception 'Articles d''ordre immuables après l''entrée' using errcode='23514'; end if;
  if new.order_controlled and new.canceled_at is not null and old.engin_at is not null then
    raise exception 'Mouvement déjà effectué : annulation de réservation impossible' using errcode='23514'; end if;
  if new.canceled_at is null and ((old.engin_at is null and new.engin_at is not null) or (old.exited_at is null and new.exited_at is not null)) then
    if new.order_controlled then
      if new.is_twin is distinct from old.is_twin then raise exception 'Nombre de conteneurs différent de l''ordre réservé' using errcode='23514'; end if;
      for item in select x.iso,x.arm,i.iso_code,o.armateur_id,o.active from
        (values(new.order_item_id,new.iso_code,new.armateur_id),(new.order_item_id_2,new.iso_code_2,new.armateur_id_2)) x(id,iso,arm)
        join public.transport_order_items i on i.id=x.id join public.transport_orders o on o.id=i.order_id loop
        if not item.active or item.iso<>item.iso_code or item.arm<>item.armateur_id then
          raise exception 'ISO ou armateur différent de l''article réservé' using errcode='23514'; end if;
      end loop;
    end if;
    if new.is_twin and (new.container_number is null or new.container_number_2 is null or new.container_number=new.container_number_2) then
      raise exception 'Deux conteneurs distincts sont requis' using errcode='23514'; end if;
    slot:=0;
    if new.entry_kind='empty' then
      for n in select x from unnest(case when new.is_twin then array[new.container_number,new.container_number_2] else array[new.container_number] end) x loop
        slot:=slot+1;
        select * into s from public.container_stock_intervals where container_number=n and end_visit_id=new.id and departed_at is not null;
        source_entry:=null;
        select entered_at into source_entry from public.truck_visits where id=s.start_visit_id and canceled_at is null and entry_kind='loaded';
        if source_entry is null then raise exception 'Conteneur absent du stock : livraison interdite' using errcode='23514'; end if;
        expected_arm:=case when slot=1 then old.armateur_id else coalesce(old.armateur_id_2,old.armateur_id) end;
        expected_iso:=case when slot=1 then old.iso_code else coalesce(old.iso_code_2,old.iso_code) end;
        if s.armateur_id is distinct from expected_arm or (new.order_controlled and s.iso_code is distinct from expected_iso) then
          raise exception 'Stock incompatible avec l''armateur ou l''ISO demandé' using errcode='23514'; end if;
        if statement_timestamp()<source_entry+interval '24 hours' then
          raise exception 'Livraison interdite avant 24 heures après l''entrée du camion' using errcode='23514'; end if;
      end loop;
    else
      for n in select x from unnest(case when new.is_twin then array[new.container_number,new.container_number_2] else array[new.container_number] end) x loop
        if not exists(select 1 from public.container_stock_intervals where container_number=n and start_visit_id=new.id) then
          raise exception 'Restitution au stock incomplète' using errcode='23514'; end if;
      end loop;
    end if;
  end if;
  return new;
end; $$;
revoke all on function public.guard_visit_delivery() from public,anon,authenticated;
create trigger check_visit_delivery before update on public.truck_visits for each row execute function public.guard_visit_delivery();
