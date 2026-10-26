-- Run as one transaction; every fixture and workflow setting is rolled back.
begin;
do $$
declare a uuid; clerk uuid:=gen_random_uuid(); suffix text:=gen_random_uuid()::text;
  ero uuid; edo uuid; ri uuid; di uuid; receipt uuid; delivery uuid; canceled uuid;
  c1 text; c2 text; before_events bigint; before_docs bigint; left_qty integer;
begin
  select r.user_id into a from public.user_roles r join public.profiles p on p.id=r.user_id where r.role='admin' and p.active limit 1;
  if a is null then raise exception 'Active admin fixture required'; end if;
  insert into auth.users(id,raw_user_meta_data) values(clerk,'{"name":"QA transport clerk"}');
  insert into public.user_roles(user_id,role) values(clerk,'entree');
  perform set_config('request.jwt.claim.sub',clerk::text,true);
  perform set_config('request.jwt.claims','{"role":"authenticated"}',true);
  ero:=public.create_transport_order('ERO','RESTITUTION','QA-ERO-'||suffix,'MAE','[{"iso_code":"22G1","quantity":2}]');
  edo:=public.create_transport_order('EDO','LIVRAISON','QA-EDO-'||suffix,'MAE','[{"iso_code":"22G1","quantity":2}]');
  select id into ri from public.transport_order_items where order_id=ero;
  select id into di from public.transport_order_items where order_id=edo;
  select 'QAZU987654'||d::text into c1 from generate_series(0,9) d where public.valid_container_number('QAZU987654'||d::text) limit 1;
  select 'QAYU987654'||d::text into c2 from generate_series(0,9) d where public.valid_container_number('QAYU987654'||d::text) limit 1;
  if exists(select 1 from public.containers where number in (c1,c2)) then raise exception 'QA container collision'; end if;
  receipt:=public.enter_transport_visit('12345-A-06','QA12345','loaded',c1,'22G1','MAE',ri,true,c2,'22G1','MAE',ri);
  delivery:=public.enter_transport_visit('12346-A-06','QA12345','empty',null,'22G1','MAE',di,true,null,'22G1','MAE',di);
  begin
    perform public.enter_transport_visit('12347-A-06','QA12345','empty',null,'22G1','MAE',di);
    raise exception 'Quantity limit bypassed';
  exception when check_violation then null; end;
  begin
    perform public.require_transport_orders(true);
    raise exception 'Clerk activated global enforcement';
  exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claim.sub',a::text,true);
  perform public.exit_truck(receipt);
  select count(*) into before_events from public.visit_events;
  select count(*) into before_docs from public.generated_documents;
  begin
    perform public.exit_truck_with_details(delivery,c1,'22G1','MAE',true,c2,'22G1','MAE');
    raise exception '24h limit bypassed';
  exception when check_violation then
    if sqlerrm not like '%24 heures%' then raise; end if;
  end;
  if (select count(*) from public.visit_events)<>before_events or (select count(*) from public.generated_documents)<>before_docs
    or exists(select 1 from public.container_stock_intervals where start_visit_id=receipt and departed_at is not null) then
    raise exception 'Refused delivery changed stock or documents'; end if;
  update public.truck_visits set entered_at=now()-interval '24 hours' where id=receipt;
  perform public.exit_truck_with_details(delivery,c1,'22G1','MAE',true,c2,'22G1','MAE');
  if (select count(*) from public.container_stock_intervals where end_visit_id=delivery and departed_at is not null)<>2 then
    raise exception 'Valid twin delivery did not move both containers'; end if;
  -- Real cancellation RPC releases the reservation and emits its document.
  edo:=public.create_transport_order('BOOKING','LIVRAISON','QA-CANCEL-'||suffix,'MAE','[{"iso_code":"22G1","quantity":1}]');
  select id into di from public.transport_order_items where order_id=edo;
  canceled:=public.enter_transport_visit('12348-A-06','QA12345','empty',null,'22G1','MAE',di);
  perform public.cancel_visit(canceled,'QA cancel before movement');
  select (x->>'remaining')::integer into left_qty from public.transport_order_items_status() x where x->>'id'=di::text;
  if left_qty<>1 then raise exception 'Cancellation did not release reservation'; end if;
  if has_function_privilege('anon','public.enter_transport_visit(text,text,text,text,text,text,uuid,boolean,text,text,text,uuid)','EXECUTE') then
    raise exception 'New entry RPC exposed to anonymous users'; end if;
  perform public.require_transport_orders(true);
  begin
    perform public.enter_truck('12349-A-06','QA12345','empty',null,'FREE','22G1','MAE');
    raise exception 'Legacy entry bypassed mandatory orders';
  exception when check_violation then null; end;
end $$;
select 'PASS: live clerk creation, quantity limit, 24h gate-out and atomic rollback, exact boundary, twin delivery, real cancellation, anon denial and rollout activation' as result;
rollback;
