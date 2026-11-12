alter table public.profiles add column if not exists username text;
-- Preserve all user ids, passwords, sessions, visits and roles. Prefer a unique
-- existing first name; otherwise keep the phone or a stable generated username.
with candidates as (
  select id, case when lower(btrim(first_name)) ~ '^[a-z][a-z0-9_.-]{2,39}$'
    and count(*) over(partition by lower(btrim(first_name)))=1
    then lower(btrim(first_name)) else null end as candidate
  from public.profiles
)
update public.profiles p set username=coalesce(c.candidate,
  nullif(regexp_replace(p.phone,'\D','','g'),''),'user_'||replace(p.id::text,'-',''))
from candidates c where c.id=p.id and p.username is null;
-- Resolve any legacy collision deterministically, without dropping accounts.
with duplicates as (select id,row_number() over(partition by lower(username) order by created_at,id) n from public.profiles)
update public.profiles p set username='user_'||replace(p.id::text,'-','')
from duplicates d where d.id=p.id and d.n>1;
create unique index if not exists profiles_username_unique on public.profiles(lower(username));
alter table public.profiles alter column username set not null;
alter table public.profiles alter column username set default ('user_'||replace(gen_random_uuid()::text,'-',''));

create or replace function public.get_login_identifier(p_identifier text)
returns jsonb language plpgsql stable security definer set search_path=public,auth,pg_temp as $$
declare v_raw text:=lower(btrim(coalesce(p_identifier,''))); v_phone text; v_email text;
begin
  if v_raw='' then return jsonb_build_object('email','','phone',''); end if;
  if position('@' in v_raw)>0 then return jsonb_build_object('email',v_raw,'phone',''); end if;
  select u.email into v_email from auth.users u join public.profiles p on p.id=u.id
    where lower(p.username)=v_raw and p.active;
  if v_email is not null then return jsonb_build_object('email',v_email,'phone',''); end if;
  if v_raw !~ '^[+0-9() .-]+$' then return jsonb_build_object('email','','phone',''); end if;
  v_phone:=regexp_replace(v_raw,'\D','','g');
  if length(v_phone)=9 and left(v_phone,1) in ('6','7') then v_phone:='0'||v_phone;
  elsif length(v_phone)=12 and left(v_phone,3)='212' then v_phone:='0'||substr(v_phone,4); end if;
  select u.email into v_email from auth.users u join public.profiles p on p.id=u.id
    where p.active and p.phone=v_phone limit 1;
  return jsonb_build_object('email',coalesce(v_email,''),'phone',v_phone);
end; $$;
revoke all on function public.get_login_identifier(text) from public;
grant execute on function public.get_login_identifier(text) to anon,authenticated;

create or replace function public.admin_save_username_account(
  p_username text,p_first_name text,p_last_name text,p_role text,
  p_password text default null,p_phone text default null,p_user_id uuid default null,
  p_active boolean default true,p_avatar_url text default null
) returns jsonb language plpgsql security definer set search_path=public,auth,extensions,pg_temp as $$
declare
  v_actor uuid:=auth.uid(); v_id uuid; v_username text:=lower(btrim(coalesce(p_username,'')));
  v_name text:=btrim(coalesce(p_first_name,''))||' '||btrim(coalesce(p_last_name,''));
  v_phone text:=nullif(btrim(p_phone),''); v_email text; v_before jsonb;
begin
  if v_actor is null or not public.can_do('admin') then raise exception 'Admin requis' using errcode='42501'; end if;
  -- Serialize admin account changes, including last-admin protection.
  perform pg_advisory_xact_lock(741391624);
  if v_username !~ '^[a-z0-9][a-z0-9_.-]{2,39}$' then raise exception 'Username : 3 à 40 lettres, chiffres, point, tiret ou underscore'; end if;
  if length(btrim(coalesce(p_first_name,'')))<2 or length(btrim(coalesce(p_last_name,'')))<2 then raise exception 'Nom et prénom requis (2 caractères minimum)'; end if;
  if p_role not in ('admin','entree','sortie','engin','viewer') or p_role is null then raise exception 'Rôle invalide'; end if;
  if p_active is null then raise exception 'État du compte requis'; end if;
  if v_phone is not null then
    if v_phone !~ '^[+0-9() .-]+$' then raise exception 'Téléphone invalide'; end if;
    v_phone:=regexp_replace(v_phone,'\D','','g');
    if length(v_phone)=9 and left(v_phone,1) in ('6','7') then v_phone:='0'||v_phone;
    elsif length(v_phone)=12 and left(v_phone,3)='212' then v_phone:='0'||substr(v_phone,4); end if;
    if v_phone !~ '^0[0-9]{9}$' then raise exception 'Téléphone marocain invalide'; end if;
  end if;
  if p_password is not null and length(p_password)>0 and length(p_password)<6 then raise exception 'Mot de passe : 6 caractères minimum'; end if;
  if exists(select 1 from public.profiles where lower(username)=v_username and (p_user_id is null or id<>p_user_id)) then raise exception 'Username déjà utilisé'; end if;
  if v_phone is not null and exists(select 1 from public.profiles where phone=v_phone and (p_user_id is null or id<>p_user_id)) then raise exception 'Téléphone déjà utilisé'; end if;
  if p_user_id is null then
    if p_password is null or length(p_password)<6 then raise exception 'Mot de passe requis (6 caractères minimum)'; end if;
    v_id:=gen_random_uuid(); v_email:='account_'||replace(v_id::text,'-','')||'@tcz.local';
    insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
      raw_app_meta_data,raw_user_meta_data,created_at,updated_at,
      confirmation_token,recovery_token,email_change,email_change_token_new)
    values('00000000-0000-0000-0000-000000000000',v_id,'authenticated','authenticated',v_email,
      extensions.crypt(p_password,extensions.gen_salt('bf')),now(),
      jsonb_build_object('provider','email','providers',array['email']),
      jsonb_build_object('name',v_name),now(),now(),'','','','');
    insert into auth.identities(id,user_id,provider_id,identity_data,provider,created_at,updated_at)
      values(gen_random_uuid(),v_id,v_id::text,jsonb_build_object('sub',v_id::text,'email',v_email,'email_verified',true),'email',now(),now());
    insert into public.profiles(id,username,display_name,first_name,last_name,phone,avatar_url,active)
      values(v_id,v_username,v_name,btrim(p_first_name),btrim(p_last_name),v_phone,p_avatar_url,p_active)
      on conflict(id) do update set username=excluded.username,display_name=excluded.display_name,
      first_name=excluded.first_name,last_name=excluded.last_name,phone=excluded.phone,avatar_url=excluded.avatar_url,active=excluded.active;
  else
    v_id:=p_user_id;
    select to_jsonb(p)-'initial_password' into v_before from public.profiles p where p.id=v_id for update;
    if v_before is null then raise exception 'Compte introuvable'; end if;
    if (not p_active or p_role<>'admin') and exists(select 1 from public.user_roles where user_id=v_id and role='admin')
      and not exists(select 1 from public.profiles p join public.user_roles r on r.user_id=p.id and r.role='admin' where p.active and p.id<>v_id)
      then raise exception 'Conservez au moins un Admin actif'; end if;
    update public.profiles set username=v_username,display_name=v_name,first_name=btrim(p_first_name),
      last_name=btrim(p_last_name),phone=v_phone,active=p_active,avatar_url=coalesce(p_avatar_url,avatar_url),initial_password=null where id=v_id;
    if coalesce(length(p_password),0)>0 then
      update auth.users set encrypted_password=extensions.crypt(p_password,extensions.gen_salt('bf')),
        updated_at=now() where id=v_id;
    end if;
  end if;
  delete from public.user_roles where user_id=v_id;
  insert into public.user_roles(user_id,role) values(v_id,p_role);
  insert into public.audit_logs(entity,entity_id,action,actor_id,before_data,after_data)
    values('user_profile',v_id::text,case when p_user_id is null then 'CREATE_AGENT' else 'UPDATE_AGENT' end,
      v_actor,v_before,jsonb_build_object('username',v_username,'name',v_name,'role',p_role,'phone',v_phone,'active',p_active));
  return jsonb_build_object('success',true,'user_id',v_id,'username',v_username,'full_name',v_name,'display_name',v_name,'phone',v_phone,'role',p_role,'active',p_active);
end; $$;
revoke all on function public.admin_save_username_account(text,text,text,text,text,text,uuid,boolean,text) from public,anon;
grant execute on function public.admin_save_username_account(text,text,text,text,text,text,uuid,boolean,text) to authenticated;

-- Explicit username edits are Admin-only, even when a caller can edit another
-- profile column under a legacy policy.
create or replace function public.guard_profile_username() returns trigger
language plpgsql set search_path=public,pg_temp as $$
begin
  if new.username is distinct from old.username and auth.uid() is not null and not public.can_do('admin') then
    raise exception 'Admin requis pour changer le username' using errcode='42501';
  end if;
  return new;
end; $$;
create trigger profile_username_guard before update of username on public.profiles
for each row execute function public.guard_profile_username();

create or replace function public.admin_list_username_accounts()
returns table(id uuid,username text,display_name text,first_name text,last_name text,phone text,
  avatar_url text,active boolean,roles text[],created_at timestamptz)
language sql stable security definer set search_path=public,pg_temp as $$
  select p.id,p.username,p.display_name,p.first_name,p.last_name,p.phone,p.avatar_url,p.active,
    coalesce(array_agg(r.role) filter(where r.role is not null),'{}'::text[]),p.created_at
  from public.profiles p left join public.user_roles r on r.user_id=p.id
  where public.can_do('admin') group by p.id order by p.created_at desc;
$$;
revoke all on function public.admin_list_username_accounts() from public,anon;
grant execute on function public.admin_list_username_accounts() to authenticated;
notify pgrst,'reload schema';
