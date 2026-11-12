const { PGlite } = require('@electric-sql/pglite');
const fs = require('node:fs');
const assert = require('node:assert/strict');
(async () => {
  const db = new PGlite();
  try {
    await db.exec(`create role anon; create role authenticated; create schema auth;
      create table auth.users(id int primary key,email text,phone text);
      create table public.profiles(id int primary key,first_name text,display_name text,phone text,active boolean);
      insert into auth.users values(1,'0600000000@tcz.local',null),(2,'other@example.test',null);
      insert into public.profiles values(1,'admin','admin admin','0600000000',true),(2,'Other','Other User','0612345678',true);`);
    await db.exec(fs.readFileSync('supabase/migrations/20261112143000_named_login_identifiers.sql','utf8'));
    const resolve = async value => (await db.query('select public.get_login_identifier($1) as result',[value])).rows[0].result;
    await db.exec('set role anon');
    assert.equal((await resolve(' admin ')).email,'0600000000@tcz.local');
    assert.equal((await resolve('ADMIN')).email,'0600000000@tcz.local');
    assert.equal((await resolve('0600000000')).email,'0600000000@tcz.local');
    assert.equal((await resolve('+212 600 000 000')).email,'0600000000@tcz.local');
    assert.equal((await resolve('600000000')).email,'0600000000@tcz.local');
    assert.equal((await resolve('Other')).email,'other@example.test');
    assert.equal((await resolve(' OTHER@EXAMPLE.TEST ')).email,'other@example.test');
    for(const invalid of ['','unknown','admin123missing','admin 123']) assert.equal((await resolve(invalid)).email,'');
    await db.exec("reset role; update public.profiles set first_name='admin' where id=2; set role anon;");
    assert.equal((await resolve('admin')).email,'','ambiguous names must not select another account');
    await db.exec('reset role; update public.profiles set active=false where id=2; set role anon;');
    assert.equal((await resolve('admin')).email,'0600000000@tcz.local');
    await db.exec('reset role; update public.profiles set active=false where id=1; set role anon;');
    assert.equal((await resolve('admin')).email,'');
    console.log('PASS: named login, phone aliases, anonymous resolver, ambiguity and inactive accounts');
  } finally { await db.close(); }
})().catch(error => { console.error(error); process.exitCode=1; });
