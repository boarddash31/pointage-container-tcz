-- Owner-approved provisioning, 2026-11-12. Run in the TCZ project SQL editor.
-- Auth users must already have been created/invited through Supabase Auth.
-- Missing users remain pending; existing accounts and passwords are preserved.
begin;
do $$
declare
  requested record;
  target_id uuid;
  owner_id uuid;
begin
  select u.id into strict owner_id from auth.users u
    join public.user_roles r on r.user_id=u.id and r.role='admin'
    where u.email='dahhaknouamane@gmail.com';
  for requested in select * from (values
    ('boarddash31@gmail.com','admin','Admin TCZ Boarddash'),
    ('boarddash31+tcz-entree@gmail.com','entree','Agent Entree TCZ Boarddash'),
    ('boarddash31+tcz-sortie@gmail.com','sortie','Agent Sortie TCZ Boarddash')
  ) as accounts(email,role,label) loop
    target_id := null;
    select id into target_id from auth.users where email=requested.email;
    if target_id is null then continue; end if;
    if exists(select 1 from public.user_roles where user_id=target_id and role<>requested.role) then
      raise exception 'Conflicting role on %; no changes applied',requested.email;
    end if;
    insert into public.profiles(id,display_name,active)
      values(target_id,requested.label,true)
      on conflict(id) do update set display_name=excluded.display_name,active=true;
    if not exists(select 1 from public.user_roles where user_id=target_id and role=requested.role) then
      insert into public.user_roles(user_id,role) values(target_id,requested.role);
      insert into public.audit_logs(entity,entity_id,action,actor_id,after_data,reason)
        values('user_profile',target_id::text,'ASSIGN_ROLE',owner_id,
          jsonb_build_object('email',requested.email,'role',requested.role),
          'Owner-approved additional role account, Supabase Dashboard, 2026-11-12');
    end if;
    -- An unactivated invitation must lead to password setup in the app.
    update auth.users set raw_user_meta_data=coalesce(raw_user_meta_data,'{}'::jsonb)
      || jsonb_build_object('must_set_password',true)
      where id=target_id and last_sign_in_at is null
        and coalesce(encrypted_password,'')='';
  end loop;
end $$;
commit;

select requested.email,requested.role as expected_role,
  coalesce(string_agg(r.role,',' order by r.role),'pending_creation') as actual_roles,
  coalesce(p.active,false) as active,u.email_confirmed_at is not null as confirmed
from (values
  ('boarddash31@gmail.com','admin'),
  ('boarddash31+tcz-entree@gmail.com','entree'),
  ('boarddash31+tcz-sortie@gmail.com','sortie')
) as requested(email,role)
left join auth.users u on u.email=requested.email
left join public.profiles p on p.id=u.id
left join public.user_roles r on r.user_id=u.id
group by requested.email,requested.role,p.active,u.email_confirmed_at
order by requested.role;
