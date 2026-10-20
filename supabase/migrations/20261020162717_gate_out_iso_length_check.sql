create or replace function public.exit_truck_with_details(
  p_visit uuid,
  p_pickup_container text default null,
  p_pickup_iso text default null,
  p_pickup_armateur text default null,
  p_is_twin boolean default false,
  p_pickup_container_2 text default null,
  p_pickup_iso_2 text default null,
  p_pickup_armateur_2 text default null,
  p_empty_exit_without_pickup boolean default false
)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_actor uuid:=auth.uid();
  v_visit public.truck_visits;
  v_before jsonb;
  v_pickup record;
  v_registered_iso text;
  v_stock_iso text;
  v_c1 text:=upper(btrim(coalesce(p_pickup_container,'')));
  v_c2 text:=upper(btrim(coalesce(p_pickup_container_2,'')));
begin
  if not public.can_do('sortie') then raise exception 'permission denied' using errcode='42501'; end if;
  select * into v_visit from public.truck_visits where id=p_visit for update;
  if not found or v_visit.exited_at is not null or v_visit.canceled_at is not null then
    raise exception 'visit unavailable for Exit';
  end if;
  v_before:=to_jsonb(v_visit);
  -- Validate the original requested length BEFORE any upsert can overwrite the ISO.
  if v_visit.entry_kind='empty' and not coalesce(p_empty_exit_without_pickup,false)
    and (v_visit.engin_at is null or length(v_c1)>0 or length(v_c2)>0) then
    p_pickup_iso := upper(btrim(coalesce(p_pickup_iso,v_visit.iso_code)));
    p_pickup_iso_2 := upper(btrim(coalesce(p_pickup_iso_2,v_visit.iso_code_2,v_visit.iso_code)));
    if coalesce(p_is_twin,false) and
      (left(v_visit.iso_code,1)<>'2' or left(coalesce(v_visit.iso_code_2,v_visit.iso_code),1)<>'2') then
      raise exception 'Twin interdit : deux conteneurs de 20 pieds sont requis par la visite'
        using errcode='23514';
    end if;
    for v_pickup in
      select * from (values
        (1,v_c1,p_pickup_iso,v_visit.iso_code),
        (2,v_c2,p_pickup_iso_2,coalesce(v_visit.iso_code_2,v_visit.iso_code))
      ) as pickup(slot,number,actual_iso,expected_iso)
      where slot=1 or coalesce(p_is_twin,false)
      order by number
    loop
      if not public.valid_container_number(v_pickup.number) then
        raise exception 'Numéro de conteneur % ISO 6346 invalide',v_pickup.slot using errcode='23514';
      end if;
      if v_pickup.actual_iso !~ '^[0-9A-Z]{4}$' or v_pickup.expected_iso !~ '^[0-9A-Z]{4}$'
        or left(v_pickup.actual_iso,1) is distinct from left(v_pickup.expected_iso,1) then
        raise exception 'Taille ISO incompatible (conteneur %) : attendu %, reçu %',
          v_pickup.slot,v_pickup.expected_iso,v_pickup.actual_iso using errcode='23514';
      end if;
      select iso_code into v_registered_iso from public.containers
        where number=v_pickup.number for update;
      if found and left(v_registered_iso,1) is distinct from left(v_pickup.expected_iso,1) then
        raise exception 'Taille ISO incompatible (conteneur % enregistré) : attendu %, reçu %',
          v_pickup.slot,v_pickup.expected_iso,v_registered_iso using errcode='23514';
      end if;
      select iso_code into v_stock_iso from public.container_stock_intervals
        where container_number=v_pickup.number and departed_at is null for update;
      if found and left(v_stock_iso,1) is distinct from left(v_pickup.expected_iso,1) then
        raise exception 'Taille ISO incompatible (stock conteneur %) : attendu %, reçu %',
          v_pickup.slot,v_pickup.expected_iso,v_stock_iso using errcode='23514';
      end if;
    end loop;
  end if;


  -- Case A: Truck entered empty
  if v_visit.entry_kind='empty' then
    if p_empty_exit_without_pickup then
      -- Driver left empty without pickup (ki dkhal ki khraj)
      update public.truck_visits
        set canceled_at=now(), canceled_by=v_actor,
            cancel_reason='Sortie sans prise de conteneur (ressorti à vide)',
            version=version+1
        where id=p_visit returning * into v_visit;
      insert into public.visit_events(visit_id,action,actor_id,details)
        values(v_visit.id,'ANNULATION',v_actor,jsonb_build_object('reason','Sortie sans prise de conteneur'));
      insert into public.audit_logs(entity,entity_id,action,actor_id,before_data,after_data)
        values('truck_visit',v_visit.id::text,'ANNULATION',v_actor,v_before,to_jsonb(v_visit));
      return;
    else
      -- Driver picked up container(s)
      if length(v_c1) > 0 then
        if not public.valid_container_number(v_c1) then raise exception 'invalid ISO 6346 container number'; end if;
        insert into public.containers(number,iso_code,armateur_id,source)
          values(v_c1,coalesce(p_pickup_iso,v_visit.iso_code),coalesce(p_pickup_armateur,v_visit.armateur_id),'operator')
          on conflict(number) do update set iso_code=excluded.iso_code,armateur_id=excluded.armateur_id;

        update public.container_stock_intervals
          set departed_at=now(), end_visit_id=v_visit.id
          where container_number=v_c1 and departed_at is null;

        update public.truck_visits
          set container_number=v_c1,
              iso_code=coalesce(p_pickup_iso,v_visit.iso_code),
              armateur_id=coalesce(p_pickup_armateur,v_visit.armateur_id)
          where id=p_visit;
      end if;

      if p_is_twin and length(v_c2) > 0 then
        if not public.valid_container_number(v_c2) then raise exception 'invalid ISO 6346 second container number'; end if;
        insert into public.containers(number,iso_code,armateur_id,source)
          values(v_c2,coalesce(p_pickup_iso_2,'22G1'),coalesce(p_pickup_armateur_2,coalesce(p_pickup_armateur,v_visit.armateur_id)),'operator')
          on conflict(number) do update set iso_code=excluded.iso_code,armateur_id=excluded.armateur_id;

        update public.container_stock_intervals
          set departed_at=now(), end_visit_id=v_visit.id
          where container_number=v_c2 and departed_at is null;

        update public.truck_visits
          set is_twin=true,
              container_number_2=v_c2,
              iso_code_2=coalesce(p_pickup_iso_2,'22G1'),
              armateur_id_2=coalesce(p_pickup_armateur_2,coalesce(p_pickup_armateur,v_visit.armateur_id))
          where id=p_visit;
      end if;

      update public.truck_visits set engin_at=now(),engin_by=v_actor where id=p_visit;
      perform public.record_event(v_visit,'PRISE',v_actor,jsonb_build_object('container',v_c1,'container_2',v_c2));
    end if;

  -- Case B: Truck entered loaded -> auto deposit if not done
  elsif v_visit.entry_kind='loaded' then
    if v_visit.engin_at is null then
      if v_visit.container_number is not null then
        perform 1 from public.containers where number=v_visit.container_number for update;
        insert into public.container_stock_intervals(container_number,client_id,armateur_id,iso_code,start_visit_id,arrived_at,position)
          values(v_visit.container_number,v_visit.client_id,v_visit.armateur_id,v_visit.iso_code,v_visit.id,now(),null)
          on conflict do nothing;
      end if;
      if v_visit.is_twin and v_visit.container_number_2 is not null then
        perform 1 from public.containers where number=v_visit.container_number_2 for update;
        insert into public.container_stock_intervals(container_number,client_id,armateur_id,iso_code,start_visit_id,arrived_at,position)
          values(v_visit.container_number_2,v_visit.client_id,coalesce(v_visit.armateur_id_2,v_visit.armateur_id),coalesce(v_visit.iso_code_2,v_visit.iso_code),v_visit.id,now(),null)
          on conflict do nothing;
      end if;
      update public.truck_visits set engin_at=now(),engin_by=v_actor where id=p_visit;
      perform public.record_event(v_visit,'DEPOSE',v_actor);
    end if;
  end if;

  update public.truck_visits
    set exited_at=now(),exited_by=v_actor,version=version+1
    where id=p_visit returning * into v_visit;

  perform public.record_event(v_visit,'SORTIE',v_actor);
  insert into public.audit_logs(entity,entity_id,action,actor_id,before_data,after_data)
    values('truck_visit',v_visit.id::text,'SORTIE',v_actor,v_before,to_jsonb(v_visit));
end; $$;


revoke all on function public.exit_truck_with_details(uuid,text,text,text,boolean,text,text,text,boolean) from public,anon;
grant execute on function public.exit_truck_with_details(uuid,text,text,text,boolean,text,text,text,boolean) to authenticated;
