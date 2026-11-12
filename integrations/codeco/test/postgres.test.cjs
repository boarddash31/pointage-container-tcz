'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {PGlite}=require('@electric-sql/pglite');
const {PostgresSource}=require('../postgres-source.cjs');
const {row,config,request}=require('./fixtures.cjs');
const {parseRequest,movementsFor}=require('../core.cjs');
test('source configuration requires verified TLS and the authorized Supabase project',()=>{
  assert.doesNotThrow(()=>new PostgresSource('postgresql://codeco:TEST@db.iparzfqxopcvwqelxlad.supabase.co/postgres'));
  assert.throws(()=>new PostgresSource('postgresql://codeco:TEST@other.invalid/postgres'),/invalid_source_connection/);
  assert.throws(()=>new PostgresSource('postgresql://codeco:TEST@db.iparzfqxopcvwqelxlad.supabase.co/postgres?sslmode=no-verify'),/invalid_source_connection/);
});
test('real PostgreSQL projection uses frozen event snapshots, excludes PII and enforces technical permissions',async t=>{
  const db=new PGlite();t.after(()=>db.close());
  await db.exec(`CREATE TABLE public.visit_events(id bigint PRIMARY KEY,action text,occurred_at timestamptz);
    CREATE TABLE public.generated_documents(id uuid PRIMARY KEY,event_id bigint,kind text,snapshot jsonb);
    CREATE ROLE authenticated NOLOGIN;`);
  await db.exec(fs.readFileSync(path.join(__dirname,'../sql/postgres_setup.sql'),'utf8'));
  const values=[row(),row('9007199254740994','SORTIE'),row('9007199254740995'),row('9007199254740996','ENTREE','2026-07-12T00:08:00Z')];
  values[2].snapshot.armateur_id='MAE';
  let serial=1;
  for(const value of values){
    await db.query('INSERT INTO visit_events VALUES($1,$2,$3)',[value.event_id,value.action,value.occurred_at]);
    await db.query('INSERT INTO generated_documents VALUES($1,$2,$3,$4::jsonb)',[
      '00000000-0000-4000-8000-'+String(serial++).padStart(12,'0'),value.event_id,value.action,
      JSON.stringify({...value.snapshot,driver_cin:'QA-PRIVATE-CIN',agent_name:'QA-PRIVATE-AGENT'})]);
    await db.query('INSERT INTO private.codeco_movement_metadata(event_id,slot,booking_reference,gross_weight,tare_weight,source_reference) VALUES($1,1,$2,2200,2200,$3)',[value.event_id,'MSC-BOOKING-TEST','QA-EDI-SOURCE']);
  }
  await db.exec('SET ROLE codeco_reader');
  const result=await db.query('SELECT * FROM private.codeco_extract($1::timestamptz,$2::timestamptz)',['2026-07-11T23:08:00Z','2026-07-12T00:08:00Z']);
  assert.equal(result.rows.length,2);
  assert.equal(result.rows[0].event_id,'9007199254740993');
  assert.ok(!JSON.stringify(result.rows).includes('QA-PRIVATE'));
  assert.equal(result.rows[0].metadata['1'].grossWeight,'2200.000');
  const normalized=result.rows.map(r=>({...r,occurred_at:r.occurred_at instanceof Date?r.occurred_at.toISOString():r.occurred_at}));
  assert.equal(movementsFor(parseRequest(request,config),normalized,config).length,2);
  await assert.rejects(db.query('SELECT snapshot FROM public.generated_documents'),e=>e.code==='42501');
  await assert.rejects(db.query('SELECT * FROM private.codeco_movement_metadata'),e=>e.code==='42501');
  await db.exec('RESET ROLE; SET ROLE authenticated');
  await assert.rejects(db.query("SELECT * FROM private.codeco_extract('2026-07-11','2026-07-12')"),e=>e.code==='42501');
  await db.exec('RESET ROLE');
});
