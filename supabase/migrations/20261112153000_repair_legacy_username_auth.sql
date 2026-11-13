-- Accounts made by the old phone RPC omitted Auth's empty token fields and
-- email identity. GoTrue cannot scan NULL token strings (HTTP 500 at login).
-- Preserve password hashes, confirmation status, roles and existing tokens.
update auth.users u set
  confirmation_token=coalesce(u.confirmation_token,''),
  recovery_token=coalesce(u.recovery_token,''),
  email_change_token_new=coalesce(u.email_change_token_new,''),
  email_change=coalesce(u.email_change,''),
  updated_at=now()
from public.profiles p
where p.id=u.id and u.email like '%@tcz.local' and u.email_confirmed_at is not null
  and (u.confirmation_token is null or u.recovery_token is null
    or u.email_change_token_new is null or u.email_change is null);

insert into auth.identities(id,user_id,provider_id,identity_data,provider,created_at,updated_at)
select gen_random_uuid(),u.id,u.id::text,
  jsonb_build_object('sub',u.id::text,'email',u.email,'email_verified',true),
  'email',now(),now()
from auth.users u join public.profiles p on p.id=u.id
where u.email like '%@tcz.local' and u.email_confirmed_at is not null
  and not exists(select 1 from auth.identities i where i.user_id=u.id and i.provider='email');
notify pgrst,'reload schema';
