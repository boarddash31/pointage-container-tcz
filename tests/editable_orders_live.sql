-- No test records are retained.
begin;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
do $$
declare v_order uuid; v_item uuid; v_ver integer; v_total integer; v_payload jsonb;
  v_ref text:='QA-EDITABLE-'||gen_random_uuid()::text;
begin
  v_order:=public.create_transport_order('ERO','RESTITUTION',v_ref,'MAE',
    '[{"iso_code":"22G1","armateur_id":"MAE","quantity":1},{"iso_code":"22G1","armateur_id":"MSC","quantity":2}]'::jsonb);
  select id into v_item from public.transport_order_items where order_id=v_order and armateur_id='MAE';
  v_total:=public.increase_transport_order_quantity(v_item,5);
  if v_total<>6 then raise exception 'Increment total mismatch'; end if;
  select jsonb_agg(jsonb_build_object('id',id,'iso_code',iso_code,'armateur_id',armateur_id,'quantity',quantity)) into v_payload
    from public.transport_order_items where order_id=v_order;
  select version into v_ver from public.transport_orders where id=v_order;
  if public.update_transport_order(v_order,v_ver,v_payload)<>v_ver+1 then raise exception 'Edit version mismatch'; end if;
  begin
    perform public.update_transport_order(v_order,v_ver,v_payload);
    raise exception 'Expected stale version rejection';
  exception when serialization_failure then null; end;
  begin
    perform public.create_transport_order('EDO','LIVRAISON',' '||lower(v_ref)||' ','MSC',
      '[{"iso_code":"45G1","quantity":9}]'::jsonb);
    raise exception 'Expected global reference rejection';
  exception when unique_violation then null; end;
  if has_function_privilege('anon','public.update_transport_order(uuid,integer,jsonb)','execute')
    or has_function_privilege('anon','public.increase_transport_order_quantity(uuid,integer)','execute') then
    raise exception 'Unexpected anonymous execution'; end if;
end $$;
rollback;
select 'PASS: live creation, carrier items, quantity increment, edit version, stale rejection, global uniqueness and anonymous denial; all test rows rolled back' result;
