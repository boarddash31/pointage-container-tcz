'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs');
const {PGlite}=require('@electric-sql/pglite');
async function main(){
 const db=new PGlite();
 try{
  await db.exec('CREATE ROLE anon;CREATE ROLE authenticated;CREATE SCHEMA private;CREATE TABLE public.freeze_fixture(id integer);CREATE TABLE private.freeze_fixture(id integer);GRANT USAGE ON SCHEMA private TO authenticated;GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE ON public.freeze_fixture,private.freeze_fixture TO authenticated;');
  await db.exec(fs.readFileSync('changes/sqlserver-cutover/source_freeze.sql.in','utf8'));
  await db.exec('SET ROLE authenticated;INSERT INTO public.freeze_fixture VALUES(1);INSERT INTO private.freeze_fixture VALUES(1);RESET ROLE;');
  await db.exec(fs.readFileSync('changes/sqlserver-cutover/ACTIVER_GEL_SOURCE.sql','utf8'));
  const frozen=(await db.query('SELECT frozen,freeze_id FROM migration_control.freeze_state')).rows[0];assert.equal(frozen.frozen,true);
  await db.exec('SET ROLE authenticated');
  for(const table of ['public.freeze_fixture','private.freeze_fixture'])for(const sql of [`INSERT INTO ${table} VALUES(2)`,`UPDATE ${table} SET id=3`,`DELETE FROM ${table}`,`TRUNCATE ${table}`])await assert.rejects(db.exec(sql),e=>e.code==='55000');
  await assert.rejects(db.exec('UPDATE migration_control.freeze_state SET frozen=false'),e=>e.code==='42501');
  assert.equal((await db.query('SELECT count(*)::int AS n FROM public.freeze_fixture')).rows[0].n,1,'read remains available and no rejected write partially committed');
  await db.exec('RESET ROLE');await db.exec(fs.readFileSync('changes/sqlserver-cutover/ANNULER_GEL_AVANT_BASCULE.sql','utf8'));
  const reopened=(await db.query('SELECT frozen,freeze_id FROM migration_control.freeze_state')).rows[0];assert.equal(reopened.frozen,false);assert.notEqual(reopened.freeze_id,frozen.freeze_id);
  await db.exec('SET ROLE authenticated;INSERT INTO public.freeze_fixture VALUES(3);RESET ROLE;');
  console.log('PASS: source guard permits normal writes before freeze, blocks INSERT/UPDATE/DELETE/TRUNCATE in both schemas, preserves reads, prevents user unfreeze and changes export epoch on reopen. Local synthetic PGlite only.');
 }finally{await db.close();}
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
