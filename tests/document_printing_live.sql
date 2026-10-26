begin;
do $$
declare a uuid:=gen_random_uuid(); viewer_id uuid:=gen_random_uuid(); o uuid; item uuid; v uuid; d uuid; ctx jsonb;
begin
  insert into auth.users(id,raw_user_meta_data) values(a,'{"name":"QA Slip Author"}'),(viewer_id,'{"name":"QA Slip Viewer"}');
  insert into public.user_roles(user_id,role) values(a,'entree'),(viewer_id,'viewer');
  update public.profiles set first_name=null,last_name=null,display_name='QA Slip Author' where id=a;
  perform set_config('request.jwt.claim.sub',a::text,true);
  perform set_config('request.jwt.claims','{"role":"authenticated"}',true);
  o:=public.create_transport_order('EDO','LIVRAISON','QA-PRINT-'||a::text,'MAE','[{"iso_code":"22G1","quantity":1}]');
  select id into item from public.transport_order_items where order_id=o;
  v:=public.enter_transport_visit('87784-B-6','QA12345','empty',null,'22G1','MAE',item);
  select id into d from public.generated_documents where visit_id=v and kind='ENTREE';
  update public.generated_documents set created_at='2026-10-23T13:35:06Z' where id=d;
  update public.profiles set display_name='Renamed Author' where id=a;
  perform set_config('request.jwt.claim.sub',viewer_id::text,true);
  ctx:=public.document_print_context(d);
  if ctx->>'agent_name'<>'QA Slip Author' or ctx->>'created_at_local'<>'2026-10-23 13:35:06' or ctx->>'visit_number' is null then
    raise exception 'Invalid archived print context: %',ctx; end if;
  if has_function_privilege('anon','public.document_print_context(uuid)','EXECUTE') then raise exception 'Anonymous metadata access'; end if;
  perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
  begin
    perform public.document_print_context(d);
    raise exception 'Unassigned account read the context';
  exception when insufficient_privilege then null; end;
end $$;
select 'PASS: document author frozen, authorized reprint by another agent, Casablanca date, stable visit number and unauthorized denial' as result;
rollback;
