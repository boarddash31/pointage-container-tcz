-- Test API protections on TCZ without retaining any test accounts or visits.
begin;
do $$ declare clerk uuid:=gen_random_uuid(); client uuid; visit uuid; admin_id uuid;
begin
  select r.user_id into admin_id from public.user_roles r join public.profiles p on p.id=r.user_id
    where r.role='admin' and p.active limit 1;
  if admin_id is null then raise exception 'Active admin fixture required'; end if;
  insert into auth.users(id,raw_user_meta_data) values(clerk,'{"name":"QA EDI Clerk"}');
  insert into public.user_roles(user_id,role) values(clerk,'entree');
  insert into public.clients(code,name) values('QA-'||gen_random_uuid()::text,'QA EDI Client') returning id into client;
  perform set_config('request.jwt.claim.sub',clerk::text,true);
  perform set_config('request.jwt.claims','{"role":"authenticated","user_metadata":{"role":"service_role"}}',true);
  visit:=public.enter_truck('12345-A-1','QA12345','empty',null,'BOOK-QA-EDI','22G1','MAE');
  begin
    perform public.enter_order_truck('12345-A-2','QA12345','empty',null,'BOOK-QA-EDI','22G1','MAE',client,false,null,null,null,null,'ORDER-QA');
    raise exception 'Clerk assigned a client order';
  exception when insufficient_privilege then null; end;
  begin
    perform public.enter_truck('12345-A-3','QA12345','empty',null,'BOOK-QA-EDI','22G1','MAE',client);
    raise exception 'Legacy entry bypassed assignment protection';
  exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  update public.truck_visits set client_id=client,client_order_reference='ORDER-ADMIN' where id=visit;
  perform set_config('request.jwt.claim.sub',clerk::text,true);
  begin
    update public.truck_visits set client_id=null,client_order_reference=null where id=visit;
    raise exception 'Clerk cleared a system assignment';
  exception when insufficient_privilege then null; end;
  update public.truck_visits set version=version+1 where id=visit;
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  update public.truck_visits set client_order_reference='ORDER-EDI' where id=visit;
  if not exists(select 1 from public.truck_visits where id=visit and client_id=client and client_order_reference='ORDER-EDI') then
    raise exception 'Trusted system assignment failed'; end if;
end $$;
select 'PASS: live clerk entry allowed, assignment APIs and clearing denied, admin and trusted system allowed' as result;
rollback;
