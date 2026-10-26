-- A reference identifies one order; carrier + ISO identifies an item within it.
alter table public.transport_orders add column version integer not null default 1,
  add column updated_at timestamptz not null default now(),
  add column updated_by uuid references public.profiles(id);
alter table public.transport_order_items add column armateur_id text references public.armateurs(id);
update public.transport_order_items i set armateur_id=o.armateur_id from public.transport_orders o where o.id=i.order_id;
alter table public.transport_order_items alter column armateur_id set not null;
alter table public.transport_order_items drop constraint transport_order_items_order_id_iso_code_key;
alter table public.transport_order_items add constraint transport_order_item_carrier_iso_key unique(order_id,armateur_id,iso_code);
create index transport_order_item_carrier_idx on public.transport_order_items(armateur_id);

-- Preserve every old item ID/visit link and archive merged header IDs for EDI callers.
create table private.transport_order_aliases(alias_id uuid primary key,order_id uuid not null references public.transport_orders(id),original_header jsonb not null);
alter table private.transport_order_aliases enable row level security;
revoke all on private.transport_order_aliases from public,anon,authenticated;
create index transport_order_alias_parent_idx on private.transport_order_aliases(order_id);
do $$
declare d record; canonical public.transport_orders; loser public.transport_orders;
begin
  for d in select upper(btrim(reference)) reference from public.transport_orders group by upper(btrim(reference)) having count(*)>1 loop
    select * into canonical from public.transport_orders where upper(btrim(reference))=d.reference order by created_at,id limit 1;
    for loser in select * from public.transport_orders where upper(btrim(reference))=d.reference and id<>canonical.id loop
      if row(loser.kind,loser.direction,loser.client_id,loser.client_order_reference)
        is distinct from row(canonical.kind,canonical.direction,canonical.client_id,canonical.client_order_reference) then
        raise exception 'RÃ©fÃ©rence % : ordres incompatibles, rÃ©conciliation nÃ©cessaire avant fusion',d.reference using errcode='23514'; end if;
      insert into private.transport_order_aliases values(loser.id,canonical.id,to_jsonb(loser));
      update public.transport_order_items set order_id=canonical.id where order_id=loser.id;
      update public.transport_orders set active=active or loser.active,version=version+1,updated_at=now() where id=canonical.id;
      insert into public.audit_logs(entity,entity_id,action,actor_id,before_data,after_data,reason)
        values('transport_order',loser.id::text,'FUSION_REFERENCE_UNIQUE',null,to_jsonb(loser),jsonb_build_object('canonical_order_id',canonical.id),'MÃªme rÃ©fÃ©rence : articles et liens de visites conservÃ©s');
      delete from public.transport_orders where id=loser.id;
    end loop;
  end loop;
end $$;
update public.transport_orders set reference=upper(btrim(reference));
drop index public.transport_orders_reference_key;
create unique index transport_orders_reference_key on public.transport_orders(upper(btrim(reference)));

create function public.guard_transport_order_item_edit() returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
declare ever_used boolean; allocated bigint;
begin
  if tg_op='DELETE' or (new.order_id is distinct from old.order_id or new.armateur_id is distinct from old.armateur_id or new.iso_code is distinct from old.iso_code) then
    select exists(select 1 from public.truck_visits where order_item_id=old.id or order_item_id_2=old.id) into ever_used;
    if ever_used then raise exception 'Article dÃ©jÃ  utilisÃ© : ISO et armateur conservÃ©s, suppression interdite' using errcode='23514'; end if;
  end if;
  if tg_op='DELETE' then return old; end if;
  select count(*) into allocated from (
    select id from public.truck_visits where order_item_id=old.id and canceled_at is null
    union all select id from public.truck_visits where order_item_id_2=old.id and canceled_at is null) q;
  if new.quantity<allocated then raise exception 'QuantitÃ© minimale : % (rÃ©servÃ©e ou effectuÃ©e)',allocated using errcode='23514'; end if;
  return new;
end; $$;
revoke all on function public.guard_transport_order_item_edit() from public,anon,authenticated;
create trigger protect_order_item_history before update or delete on public.transport_order_items for each row execute function public.guard_transport_order_item_edit();

create function public.update_transport_order(p_order uuid,p_expected_version integer,p_items jsonb) returns integer
language plpgsql security definer set search_path=public,pg_temp as $$
declare h public.transport_orders; item jsonb; existing public.transport_order_items; retained uuid[]:='{}'; current_id uuid;
  before_snapshot jsonb; after_snapshot jsonb; new_version integer; service boolean:=coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb->>'role'='service_role';
begin
  if not (public.can_do('entree') or coalesce(service,false)) then raise exception 'Modification d''ordre non autorisÃ©e' using errcode='42501'; end if;
  select * into h from public.transport_orders where id=coalesce((select order_id from private.transport_order_aliases where alias_id=p_order),p_order) for update;
  if not found then raise exception 'Ordre introuvable' using errcode='P0002'; end if;
  if p_expected_version is distinct from h.version then raise exception 'Ordre modifiÃ© par un autre utilisateur. Actualisez avant d''enregistrer.' using errcode='40001'; end if;
  if jsonb_typeof(p_items) is distinct from 'array' then raise exception 'Articles requis' using errcode='23514'; end if;
  if jsonb_array_length(p_items) not between 1 and 50 then raise exception 'Entre 1 et 50 articles requis' using errcode='23514'; end if;
  perform 1 from public.transport_order_items where order_id=h.id order by id for update;
  select to_jsonb(h)||jsonb_build_object('items',jsonb_agg(to_jsonb(i) order by i.id)) into before_snapshot from public.transport_order_items i where i.order_id=h.id;
  for item in select value from jsonb_array_elements(p_items) loop
    current_id:=nullif(item->>'id','')::uuid;
    if current_id is not null then
      if current_id=any(retained) then raise exception 'Article rÃ©pÃ©tÃ© dans la modification' using errcode='23514'; end if;
      select * into existing from public.transport_order_items where id=current_id and order_id=h.id;
      if not found then raise exception 'Article Ã©tranger Ã  cet ordre' using errcode='23514'; end if;
      if coalesce(nullif(item->>'armateur_id',''),existing.armateur_id) is distinct from existing.armateur_id
        and not exists(select 1 from public.armateurs where id=item->>'armateur_id' and active) then raise exception 'Armateur actif requis' using errcode='23514'; end if;
      update public.transport_order_items set quantity=(item->>'quantity')::integer,
        iso_code=upper(btrim(coalesce(item->>'iso_code',existing.iso_code))),
        armateur_id=coalesce(nullif(item->>'armateur_id',''),existing.armateur_id) where id=current_id;
    else
      if not exists(select 1 from public.armateurs where id=coalesce(nullif(item->>'armateur_id',''),h.armateur_id) and active) then raise exception 'Armateur actif requis' using errcode='23514'; end if;
      insert into public.transport_order_items(order_id,iso_code,armateur_id,quantity)
        values(h.id,upper(btrim(item->>'iso_code')),coalesce(nullif(item->>'armateur_id',''),h.armateur_id),(item->>'quantity')::integer) returning id into current_id;
    end if;
    retained:=array_append(retained,current_id);
  end loop;
  delete from public.transport_order_items where order_id=h.id and not(id=any(retained));
  update public.transport_orders set version=version+1,updated_at=now(),updated_by=auth.uid() where id=h.id returning version into new_version;
  select to_jsonb(o)||jsonb_build_object('items',(select jsonb_agg(to_jsonb(i) order by i.id) from public.transport_order_items i where i.order_id=h.id)) into after_snapshot from public.transport_orders o where o.id=h.id;
  insert into public.audit_logs(entity,entity_id,action,actor_id,before_data,after_data) values('transport_order',h.id::text,'MODIFICATION',auth.uid(),before_snapshot,after_snapshot);
  return new_version;
end; $$;
revoke all on function public.update_transport_order(uuid,integer,jsonb) from public,anon;
grant execute on function public.update_transport_order(uuid,integer,jsonb) to authenticated,service_role;

create function public.increase_transport_order_quantity(p_item uuid,p_quantity integer) returns integer
language plpgsql security definer set search_path=public,pg_temp as $$
declare parent uuid; item public.transport_order_items; result integer; service boolean:=coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb->>'role'='service_role';
begin
  if not (public.can_do('entree') or coalesce(service,false)) then raise exception 'Modification d''ordre non autorisÃ©e' using errcode='42501'; end if;
  if p_quantity is null or p_quantity<1 or p_quantity>1000000 then raise exception 'QuantitÃ© Ã  ajouter : entier positif requis' using errcode='23514'; end if;
  select order_id into parent from public.transport_order_items where id=p_item;
  if not found then raise exception 'Article introuvable' using errcode='P0002'; end if;
  perform 1 from public.transport_orders where id=parent for update;
  select * into item from public.transport_order_items where id=p_item for update;
  if not found then raise exception 'Article supprimÃ©, actualisez l''ordre' using errcode='40001'; end if;
  update public.transport_order_items set quantity=quantity+p_quantity where id=p_item returning quantity into result;
  update public.transport_orders set version=version+1,updated_at=now(),updated_by=auth.uid() where id=parent;
  insert into public.audit_logs(entity,entity_id,action,actor_id,before_data,after_data,reason)
    values('transport_order',parent::text,'AJOUT_QUANTITE',auth.uid(),to_jsonb(item),jsonb_build_object('item_id',p_item,'quantity',result,'added',p_quantity),'Ajout de quantitÃ© Ã  l''ordre existant');
  return result;
end; $$;
revoke all on function public.increase_transport_order_quantity(uuid,integer) from public,anon;
grant execute on function public.increase_transport_order_quantity(uuid,integer) to authenticated,service_role;

create or replace function public.create_transport_order(p_kind text,p_direction text,p_reference text,p_armateur text,p_items jsonb,
  p_client uuid default null,p_client_order_reference text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_item jsonb; v_service boolean :=
  coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb->>'role'='service_role';
begin
  if not (public.can_do('entree') or coalesce(v_service,false)) then
    raise exception 'CrÃ©ation d''ordre non autorisÃ©e' using errcode='42501'; end if;
  if (p_client is not null or nullif(btrim(p_client_order_reference),'') is not null)
    and not (public.can_do('admin') or coalesce(v_service,false)) then
    raise exception 'Affectation client rÃ©servÃ©e au systÃ¨me EDI ou Ã  l''administrateur' using errcode='42501'; end if;
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
    if not exists(select 1 from public.armateurs where id=coalesce(nullif(v_item->>'armateur_id',''),p_armateur) and active) then raise exception 'Armateur actif requis' using errcode='23514'; end if;
    insert into public.transport_order_items(order_id,iso_code,armateur_id,quantity)
      values(v_id,upper(btrim(v_item->>'iso_code')),coalesce(nullif(v_item->>'armateur_id',''),p_armateur),(v_item->>'quantity')::integer);
  end loop;
  insert into public.audit_logs(entity,entity_id,action,actor_id,after_data)
    values('transport_order',v_id::text,'CREATION',auth.uid(),jsonb_build_object('kind',p_kind,'reference',p_reference,'items',p_items));
  return v_id;
end; $$;
create or replace function public.bind_visit_order() returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
declare i record; h public.transport_orders; h2 public.transport_orders; v_used integer; v_needed integer;
begin
  if new.order_item_id is null and new.order_item_id_2 is null
    and not (select required from private.transport_order_controls where singleton) then return new; end if;
  if new.order_item_id is null or (new.is_twin and new.order_item_id_2 is null)
    or (not new.is_twin and new.order_item_id_2 is not null) then
    raise exception 'SÃ©lectionnez un article Booking / EDO / ERO pour chaque conteneur' using errcode='23514'; end if;
  if new.entry_kind='loaded' and exists(select 1 from public.container_stock_intervals
      where container_number in (new.container_number,new.container_number_2) and departed_at is null) then
    raise exception 'Conteneur dÃ©jÃ  prÃ©sent au stock' using errcode='23514'; end if;
  if new.is_twin and (left(new.iso_code,1)<>'2' or left(coalesce(new.iso_code_2,''),1)<>'2'
    or (new.entry_kind='loaded' and new.container_number=new.container_number_2)) then
    raise exception 'Deux conteneurs distincts de 20 pieds sont requis' using errcode='23514'; end if;
  -- Lock parent orders before items, in the same order as the editor.
  perform 1 from public.transport_orders where id in (select order_id from public.transport_order_items where id in (new.order_item_id,new.order_item_id_2)) order by id for update;
  for i in select * from public.transport_order_items where id in (new.order_item_id,new.order_item_id_2) order by id for update loop
    select * into h from public.transport_orders where id=i.order_id;
    if not h.active or h.direction<>(case when new.entry_kind='loaded' then 'RESTITUTION' else 'LIVRAISON' end) then
      raise exception 'Sens de l''ordre incompatible ou ordre inactif' using errcode='23514'; end if;
    v_needed:=(case when i.id=new.order_item_id then 1 else 0 end)+(case when i.id=new.order_item_id_2 then 1 else 0 end);
    select count(*) into v_used from (select id from public.truck_visits where order_item_id=i.id and canceled_at is null
      union all select id from public.truck_visits where order_item_id_2=i.id and canceled_at is null) allocations;
    if v_used+v_needed>i.quantity then
      raise exception 'QuantitÃ© autorisÃ©e Ã©puisÃ©e pour % / % (% disponible)',h.reference,i.iso_code,greatest(0,i.quantity-v_used)
        using errcode='23514'; end if;
    if (i.id=new.order_item_id and (new.iso_code is distinct from i.iso_code or new.armateur_id is distinct from i.armateur_id))
      or (i.id=new.order_item_id_2 and (new.iso_code_2 is distinct from i.iso_code or new.armateur_id_2 is distinct from i.armateur_id)) then
      raise exception 'Code ISO ou armateur incompatible avec l''article de l''ordre' using errcode='23514'; end if;
  end loop;
  select o.* into strict h from public.transport_orders o join public.transport_order_items oi on oi.order_id=o.id where oi.id=new.order_item_id;
  if new.is_twin then
    select o.* into strict h2 from public.transport_orders o join public.transport_order_items oi on oi.order_id=o.id where oi.id=new.order_item_id_2;
    if h.client_id is distinct from h2.client_id or h.client_order_reference is distinct from h2.client_order_reference then
      raise exception 'Les deux articles doivent appartenir au mÃªme client et ordre client' using errcode='23514'; end if;
  end if;
  new.client_id:=h.client_id; new.client_order_reference:=h.client_order_reference;
  new.carrier_booking_reference:=h.reference; new.carrier_booking_armateur_id:=new.armateur_id;
  new.booking_reference_2:=case when new.is_twin then h2.reference else null end;
  new.carrier_booking_armateur_id_2:=case when new.is_twin then new.armateur_id_2 else null end;
  new.order_controlled:=true;
  return new;
end; $$;
create or replace function public.transport_order_items_status() returns setof jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not public.can_do('read') then raise exception 'permission denied' using errcode='42501'; end if;
  return query select to_jsonb(i)||jsonb_build_object('kind',o.kind,'direction',o.direction,'reference',o.reference,
    'armateur_id',i.armateur_id,'version',o.version,'updated_at',o.updated_at,'ever_used',t.ever_used,'active',o.active,'reserved',t.reserved,'completed',t.completed,'remaining',i.quantity-t.reserved-t.completed)
    from public.transport_order_items i join public.transport_orders o on o.id=i.order_id
    cross join lateral (select count(*)::integer ever_used,
      count(*) filter(where q.canceled_at is null and q.engin_at is null and q.exited_at is null)::integer reserved,
      count(*) filter(where q.canceled_at is null and (q.engin_at is not null or q.exited_at is not null))::integer completed
      from (select engin_at,exited_at,canceled_at from public.truck_visits where order_item_id=i.id
        union all select engin_at,exited_at,canceled_at from public.truck_visits where order_item_id_2=i.id) q) t
    order by o.created_at desc,i.armateur_id,i.iso_code;
end; $$;
