const {PGlite}=require('@electric-sql/pglite');
const fs=require('node:fs');const assert=require('node:assert/strict');
(async()=>{const db=new PGlite();try{
  await db.exec(`create schema auth;
    create table auth.users(id uuid primary key,email text,encrypted_password text,email_confirmed_at timestamptz,
      confirmation_token text,recovery_token text,email_change_token_new text,email_change text,updated_at timestamptz);
    create table public.profiles(id uuid primary key);
    create table auth.identities(id uuid,user_id uuid,provider_id text,identity_data jsonb,provider text,created_at timestamptz,updated_at timestamptz);
    insert into auth.users values
      ('11111111-1111-4111-8111-111111111111','legacy@tcz.local','same-hash',now(),null,null,null,null,null),
      ('22222222-2222-4222-8222-222222222222','current@tcz.local','other-hash',now(),'keep-confirm','keep-recovery','keep-new','keep-email',null),
      ('33333333-3333-4333-8333-333333333333','outside@example.test','external-hash',now(),null,null,null,null,null),
      ('44444444-4444-4444-8444-444444444444','unconfirmed@tcz.local','pending-hash',null,null,null,null,null,null);
    insert into public.profiles select id from auth.users;
    insert into auth.identities values(gen_random_uuid(),'22222222-2222-4222-8222-222222222222','22222222-2222-4222-8222-222222222222','{}','email',now(),now());`);
  const migration=fs.readFileSync('supabase/migrations/20261112153000_repair_legacy_username_auth.sql','utf8');
  await db.exec(migration);await db.exec(migration);
  const rows=(await db.query('select email,encrypted_password,confirmation_token,recovery_token,email_change_token_new,email_change from auth.users order by email')).rows;
  const legacy=rows.find(r=>r.email==='legacy@tcz.local');
  assert.equal(legacy.encrypted_password,'same-hash');
  for(const field of ['confirmation_token','recovery_token','email_change_token_new','email_change'])assert.equal(legacy[field],'');
  const current=rows.find(r=>r.email==='current@tcz.local');assert.equal(current.recovery_token,'keep-recovery');assert.equal(current.confirmation_token,'keep-confirm');
  assert.equal(rows.find(r=>r.email==='outside@example.test').recovery_token,null);
  assert.equal(rows.find(r=>r.email==='unconfirmed@tcz.local').recovery_token,null);
  assert.equal((await db.query('select count(*)::int n from auth.identities')).rows[0].n,2);
  console.log('PASS: legacy Auth repair is idempotent, preserves hashes/active tokens, adds one identity and excludes external/unconfirmed accounts');
}finally{await db.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
