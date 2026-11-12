-- Named identifiers keep password authentication and existing role checks.
-- A name is usable only when it identifies exactly one active account.
create or replace function public.get_login_identifier(p_identifier text)
returns jsonb
language plpgsql stable security definer
set search_path=public,auth,pg_temp as $$
declare
  v_raw text := btrim(coalesce(p_identifier,''));
  v_digits text;
  v_phone text;
  v_emails text[];
  v_email text;
begin
  if v_raw='' then return jsonb_build_object('email','','phone',''); end if;
  if position('@' in v_raw)>0 then
    return jsonb_build_object('email',lower(v_raw),'phone','');
  end if;
  if v_raw ~ '^[A-Za-z][A-Za-z0-9_.-]{1,59}$' then
    select array_agg(distinct u.email) into v_emails
      from auth.users u join public.profiles p on p.id=u.id
      where p.active and u.email is not null and (
        lower(btrim(p.first_name))=lower(v_raw)
        or lower(btrim(p.display_name))=lower(v_raw)
        or lower(split_part(u.email,'@',1))=lower(v_raw));
    if cardinality(v_emails)=1 then
      return jsonb_build_object('email',v_emails[1],'phone','');
    end if;
    return jsonb_build_object('email','','phone','');
  end if;
  if v_raw !~ '^[+0-9() .-]+$' then
    return jsonb_build_object('email','','phone','');
  end if;
  v_digits:=regexp_replace(v_raw,'\D','','g');
  if length(v_digits)=9 and left(v_digits,1) in ('6','7') then
    v_phone:='0'||v_digits;
  elsif length(v_digits)=12 and left(v_digits,3)='212' then
    v_phone:='0'||substr(v_digits,4);
  else v_phone:=v_digits;
  end if;
  select u.email into v_email from auth.users u
    join public.profiles p on p.id=u.id
    where p.active and (p.phone=v_phone or u.phone=v_phone)
    order by (p.phone=v_phone) desc limit 1;
  return jsonb_build_object('email',coalesce(v_email,v_phone||'@tcz.local'),'phone',v_phone);
end;
$$;
revoke all on function public.get_login_identifier(text) from public;
grant execute on function public.get_login_identifier(text) to anon,authenticated;
