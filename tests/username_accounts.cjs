const {PGlite}=require('@electric-sql/pglite');
const fs=require('node:fs');const assert=require('node:assert/strict');
(async()=>{const db=new PGlite();try {
  // Auth provider crypto is stubbed only in this isolated SQL fixture.
  await db.exec(`create role anon;create role authenticated;create schema auth;create schema extensions;
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    create function extensions.gen_salt(text) returns text language sql as $$select 'fixture-salt'::text$$;
    create function extensions.crypt(text,text) returns text language sql as $$select 'hash:'||$1$$;
    create table auth.users(instance_id uuid,id uuid primary key,aud text,role text,email text,encrypted_password text,
      email_confirmed_at timestamptz,raw_app_meta_data jsonb,raw_user_meta_data jsonb,created_at timestamptz,updated_at timestamptz,
      confirmation_token text,recovery_token text,email_change text,email_change_token_new text);
    create table auth.identities(id uuid,user_id uuid references auth.users,provider_id text,identity_data jsonb,provider text,created_at timestamptz,updated_at timestamptz);
    create table public.profiles(id uuid primary key references auth.users,display_name text,first_name text,last_name text,phone text,
      avatar_url text,initial_password text,active boolean,created_at timestamptz default now());
    create unique index profiles_phone on public.profiles(phone) where phone is not null and phone<>'';
    create table public.user_roles(user_id uuid references public.profiles,role text,primary key(user_id,role));
    create table public.audit_logs(entity text,entity_id text,action text,actor_id uuid,before_data jsonb,after_data jsonb);
    create function public.can_do(text) returns boolean language sql stable security definer as $$
      select exists(select 1 from public.profiles p join public.user_roles r on r.user_id=p.id where p.active and p.id=auth.uid() and r.role=$1)$$;
    insert into auth.users(id,email,encrypted_password) values('11111111-1111-4111-8111-111111111111','owner@example.test','unchanged');
    insert into public.profiles(id,first_name,last_name,display_name,phone,active) values('11111111-1111-4111-8111-111111111111','admin','admin','admin admin','0600000000',true);
    insert into public.user_roles values('11111111-1111-4111-8111-111111111111','admin');`);
  await db.exec(fs.readFileSync('supabase/migrations/20261112150000_username_accounts.sql','utf8'));
  let owner='11111111-1111-4111-8111-111111111111';
  assert.equal((await db.query('select username from public.profiles')).rows[0].username,'admin');
  assert.equal((await db.query('select encrypted_password from auth.users')).rows[0].encrypted_password,'unchanged');
  const save=async args=>(await db.query(`select public.admin_save_username_account($1,$2,$3,$4,$5,$6,$7,$8) result`,args)).rows[0].result;
  await db.exec("set role anon");
  assert.equal((await db.query("select public.get_login_identifier('ADMIN') result")).rows[0].result.email,'owner@example.test');
  await assert.rejects(save(['newagent','Karim','Test','entree','test123',null,null,true]),/permission denied/);
  await db.exec(`reset role;set request.jwt.claim.sub='${owner}';set role authenticated`);
  let created=await save(['newagent','Karim','Test','entree','test123',null,null,true]);
  assert.equal(created.username,'newagent');assert.equal(created.phone,null);assert.ok(created.user_id);
  const uid=created.user_id;
  await assert.rejects(save(['NEWAGENT','Karim','Other','admin','other123',null,null,true]),/Username déjà utilisé/);
  await assert.rejects(save(['invalid name','Karim','Test','entree','test123',null,null,true]),/Username/);
  await assert.rejects(save(['validuser','Karim','Test','entree','short',null,null,true]),/6 caractères/);
  await assert.rejects(save(['validuser','Karim','Test','bogus','test123',null,null,true]),/Rôle invalide/);
  await assert.rejects(save(['validuser','Karim','Test','sortie','test123','bad',null,true]),/Téléphone/);
  await assert.rejects(save(['admin','admin','admin','sortie',null,null,owner,true]),/au moins un Admin/);
  await assert.rejects(save(['admin','admin','admin','admin',null,null,owner,false]),/au moins un Admin/);
  let updated=await save(['renamed','Karim','Test','sortie',null,'+212 612345678',uid,true]);assert.equal(updated.phone,'0612345678');
  await db.exec('reset role');
  assert.equal((await db.query('select encrypted_password from auth.users where id=$1',[uid])).rows[0].encrypted_password,'hash:test123');
  assert.equal((await db.query('select initial_password from public.profiles where id=$1',[uid])).rows[0].initial_password,null);
  assert.equal((await db.query('select count(*)::int n from auth.identities where user_id=$1',[uid])).rows[0].n,1);
  assert.equal((await db.query("select public.get_login_identifier('renamed') result")).rows[0].result.email.includes('@tcz.local'),true);
  assert.equal((await db.query("select public.get_login_identifier('newagent') result")).rows[0].result.email,'');
  await db.exec(`set request.jwt.claim.sub='${uid}';set role authenticated`);
  await assert.rejects(save(['escalate','Karim','Test','admin','test123',null,null,true]),/Admin requis/);
  assert.equal((await db.query('select count(*)::int n from public.admin_list_username_accounts()')).rows[0].n,0);
  await db.exec(`reset role;set request.jwt.claim.sub='${owner}';set role authenticated`);
  await save(['renamed','Karim','Test','sortie',null,null,uid,false]);
  assert.equal((await db.query("select public.get_login_identifier('renamed') result")).rows[0].result.email,'');
  assert.equal((await db.query('select count(*)::int n from public.admin_list_username_accounts()')).rows[0].n,2);
  await db.exec('reset role');
  assert.equal(JSON.stringify((await db.query('select before_data,after_data from public.audit_logs')).rows).includes('test123'),false);
  console.log('PASS: username creation, optional phone, identity, password hash, edit, preserved password, duplicate denial, role enforcement, last Admin and inactive login');
}finally{await db.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
