begin;

create table public.evp_rules (
  effective_from date not null,
  size_feet integer not null check(size_feet in (20,40,45)),
  factor numeric(6,3) not null check(factor>0),
  source_note text not null,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  primary key(effective_from,size_feet)
);
insert into public.evp_rules(effective_from,size_feet,factor,source_note)
  values('2026-10-19',20,1,'Supplied Modele_REP_FREEPOOL_automatique.xlsx PARAMETRES!B5'),
        ('2026-10-19',40,2,'Supplied Modele_REP_FREEPOOL_automatique.xlsx PARAMETRES!B6'),
        ('2026-10-19',45,2.25,'Supplied Modele_REP_FREEPOOL_automatique.xlsx PARAMETRES!B7');
alter table public.evp_rules enable row level security;
create policy evp_rules_read on public.evp_rules for select to authenticated using(public.can_do('read'));
grant select on public.evp_rules to authenticated;

-- Exact ISO-to-report mapping is versioned. Unknown codes stay unclassified;
-- the source Freepool template uses an explicit TYPE column, not an ISO prefix formula.
create table public.iso_report_types (
  iso_code text not null,
  effective_from date not null,
  category text not null check(category in
    ('20 DV','40 DV ST','40 DV HC','45 DV','FRIGO 20','FRIGO 40','OT&FL&HP&CT')),
  size_feet integer not null check(size_feet in (20,40,45)),
  source_note text not null,
  primary key(iso_code,effective_from)
);
insert into public.iso_report_types(iso_code,effective_from,category,size_feet,source_note) values
  ('22G1','2026-10-19','20 DV',20,'Supplied REP_FREE_POOL sample'),
  ('42G1','2026-10-19','40 DV ST',40,'Supplied type convention; verify with terminal'),
  ('45G1','2026-10-19','40 DV HC',40,'Supplied REP_FREE_POOL sample'),
  ('22R1','2026-10-19','FRIGO 20',20,'Provisional rule; verify with terminal'),
  ('42R1','2026-10-19','FRIGO 40',40,'Provisional rule; verify with terminal'),
  ('45R1','2026-10-19','FRIGO 40',40,'Provisional rule; verify with terminal');
alter table public.iso_report_types enable row level security;
create policy iso_types_read on public.iso_report_types for select to authenticated using(public.can_do('read'));
grant select on public.iso_report_types to authenticated;

-- Inclusive at arrival and exclusive at departure. Date boundaries use Morocco time.
create or replace function public.freepool_rows(p_day date,p_client uuid default null,p_any_time boolean default false)
returns table(container_number text,client_id uuid,armateur_id text,iso_code text,
  category text,arrived_at timestamptz,departed_at timestamptz,"position" text,evp numeric)
language sql stable security invoker set search_path=public,pg_temp as $$
  with bounds as (
    select (p_day::timestamp at time zone 'Africa/Casablanca') as day_start,
      ((p_day+1)::timestamp at time zone 'Africa/Casablanca') as day_end
  ), listed as (
    select s.*,t.category,t.size_feet
    from public.container_stock_intervals s cross join bounds b
    left join lateral (
      select category,size_feet from public.iso_report_types t
      where t.iso_code=s.iso_code and t.effective_from<=p_day
      order by t.effective_from desc limit 1
    ) t on true
    where s.arrived_at<b.day_end
      and (case when p_any_time then s.departed_at is null or s.departed_at>b.day_start
                else s.departed_at is null or s.departed_at>=b.day_end end)
      and (p_client is null or s.client_id=p_client)
  )
  select s.container_number,s.client_id,s.armateur_id,s.iso_code,s.category,
    s.arrived_at,s.departed_at,s.position,
    (select r.factor from public.evp_rules r where r.size_feet=s.size_feet
      and r.effective_from<=p_day order by r.effective_from desc limit 1) as evp
  from listed s order by s.category,s.armateur_id,s.container_number;
$$;
revoke all on function public.freepool_rows(date,uuid,boolean) from public,anon;
grant execute on function public.freepool_rows(date,uuid,boolean) to authenticated;

create or replace function public.hourly_activity(p_day date)
returns table(stage text,hour integer,total bigint)
language sql stable security invoker set search_path=public,pg_temp as $$
  with bounds as (
    select (p_day::timestamp at time zone 'Africa/Casablanca') as day_start,
      ((p_day+1)::timestamp at time zone 'Africa/Casablanca') as day_end
  ), stages(stage) as (values ('ENTREE'),('ENGIN'),('SORTIE')),
  hours(hour) as (select generate_series(0,23)),
  counted as (
    select case when e.action in ('DEPOSE','PRISE') then 'ENGIN' else e.action end as stage,
      extract(hour from e.occurred_at at time zone 'Africa/Casablanca')::integer as hour,
      count(*) as total from public.visit_events e cross join bounds b
      where e.occurred_at>=b.day_start and e.occurred_at<b.day_end
        and e.action in ('ENTREE','DEPOSE','PRISE','SORTIE')
      group by 1,2
  )
  select s.stage,h.hour,coalesce(c.total,0) from stages s cross join hours h
  left join counted c on c.stage=s.stage and c.hour=h.hour
  order by s.stage,h.hour;
$$;
revoke all on function public.hourly_activity(date) from public,anon;
grant execute on function public.hourly_activity(date) to authenticated;

create or replace function public.set_user_role(p_user uuid,p_role text,p_enabled boolean)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid();v_before jsonb;
begin
  if not public.can_do('admin') then raise exception 'admin required' using errcode='42501'; end if;
  if p_user=v_actor and p_role='admin' and not p_enabled then
    raise exception 'cannot remove own admin role'; end if;
  if p_role not in ('admin','entree','engin','sortie','viewer') then raise exception 'invalid role'; end if;
  select to_jsonb(r) into v_before from public.user_roles r where user_id=p_user and role=p_role;
  if p_enabled then
    insert into public.user_roles(user_id,role) values(p_user,p_role) on conflict do nothing;
  else delete from public.user_roles where user_id=p_user and role=p_role; end if;
  insert into public.audit_logs(entity,entity_id,action,actor_id,before_data,after_data)
    values('user_role',p_user::text,'SET_ROLE',v_actor,v_before,
      jsonb_build_object('role',p_role,'enabled',p_enabled));
end; $$;
revoke all on function public.set_user_role(uuid,text,boolean) from public,anon;
grant execute on function public.set_user_role(uuid,text,boolean) to authenticated;

create or replace function public.assign_client_armateur(p_client uuid,p_armateur text,p_from date,p_to date default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid();
begin
  if not public.can_do('admin') then raise exception 'admin required' using errcode='42501'; end if;
  if p_to is not null and p_to<p_from then raise exception 'invalid period'; end if;
  if exists(select 1 from public.client_armateurs where client_id=p_client and armateur_id=p_armateur
      and daterange(valid_from,coalesce(valid_to,'infinity'::date),'[]') &&
          daterange(p_from,coalesce(p_to,'infinity'::date),'[]')) then
    raise exception 'overlapping client-armateur period'; end if;
  insert into public.client_armateurs(client_id,armateur_id,valid_from,valid_to)
    values(p_client,p_armateur,p_from,p_to);
  insert into public.audit_logs(entity,entity_id,action,actor_id,after_data)
    values('client_armateur',p_client::text,'ASSIGN',v_actor,
      jsonb_build_object('armateur',p_armateur,'from',p_from,'to',p_to));
end; $$;
revoke all on function public.assign_client_armateur(uuid,text,date,date) from public,anon;
grant execute on function public.assign_client_armateur(uuid,text,date,date) to authenticated;

create or replace function public.create_client(p_code text,p_name text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;v_actor uuid:=auth.uid();
begin
  if not public.can_do('admin') then raise exception 'admin required' using errcode='42501'; end if;
  if length(btrim(coalesce(p_code,'')))<2 or length(btrim(coalesce(p_name,'')))<2 then
    raise exception 'client code and name required'; end if;
  insert into public.clients(code,name) values(upper(btrim(p_code)),btrim(p_name)) returning id into v_id;
  insert into public.audit_logs(entity,entity_id,action,actor_id,after_data)
    values('client',v_id::text,'CREATE',v_actor,
      jsonb_build_object('code',upper(btrim(p_code)),'name',btrim(p_name)));
  return v_id;
end; $$;
revoke all on function public.create_client(text,text) from public,anon;
grant execute on function public.create_client(text,text) to authenticated;

commit;
