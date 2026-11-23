'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path');
const {loadManifest,validateCatalog}=require('../migration/sqlserver/tools/transfer-manifest.cjs');
const {manifestHash,fileHash,validateRow}=require('../migration/sqlserver/tools/row-validation.cjs');
const {createFixture}=require('../migration/sqlserver/tools/create-test-snapshot.cjs');
const {validateSourceUrl}=require('../migration/sqlserver/tools/source-connection.cjs');
const catalog=require('../migration/sqlserver/source-columns-20261121.json');
const {manifest:current,text}=loadManifest('v5');
const {manifest:legacy,text:legacyText}=loadManifest();
assert.equal(current.source_project,catalog.source_project);
validateSourceUrl(new URL('postgresql://postgres:synthetic@db.'+current.source_project+'.supabase.co:5432/postgres'),current.source_project);
validateSourceUrl(new URL('postgresql://postgres.'+current.source_project+':synthetic@aws-0-eu-central-1.pooler.supabase.com:5432/postgres'),current.source_project);
for(const host of ['example.invalid','pooler.supabase.com.example.invalid','db.anotherproject.supabase.co'])assert.throws(()=>validateSourceUrl(new URL('postgresql://postgres.'+current.source_project+':synthetic@'+host+':5432/postgres'),current.source_project));
assert.equal(current.target_schema_version,5);
assert.equal(current.base_manifest_sha256,manifestHash(legacyText));
assert.notEqual(manifestHash(text),manifestHash(legacyText),'snapshots cannot switch silently between transfer versions');
validateCatalog(current,catalog.tables);
assert.throws(()=>validateCatalog(legacy,catalog.tables),/public.profiles/,'legacy manifest must reject the new identifier');
assert.throws(()=>loadManifest('../../arbitrary'));
assert.throws(()=>loadManifest('v4'));
const mutate=fn=>{const tables=structuredClone(catalog.tables);fn(tables);assert.throws(()=>validateCatalog(current,tables));};
mutate(t=>t.push({table_schema:'public',table_name:'container_blocks',columns:[]}));
mutate(t=>t.find(x=>x.table_name==='truck_visits').columns.push({name:'operational_details',type:'jsonb',nullable:false}));
mutate(t=>t.find(x=>x.table_name==='profiles').columns.find(c=>c.name==='username').nullable=true);
mutate(t=>t.find(x=>x.table_name==='visit_events').columns.find(c=>c.name==='id').type='numeric');
mutate(t=>t.find(x=>x.table_name==='truck_visits').columns.pop());
mutate(t=>t.pop());
const profile=current.tables.find(t=>t.source_table==='profiles');
assert.equal(profile.columns.find(c=>c.name==='username').nullable,false);
assert.ok(!profile.columns.some(c=>c.name==='initial_password'));
assert.deepEqual(current.tables.map(t=>t.import_order),legacy.tables.map(t=>t.import_order),'FK load order is preserved');
assert.deepEqual(current.target_empty_tables.map(t=>t.target_schema+'.'+t.target_table).sort(),[
  'dbo.container_blocks','internal.application_sessions','internal.local_accounts'
]);
assert.deepEqual(current.target_defaults,[{target_schema:'dbo',target_table:'truck_visits',column:'operational_details',value:'{}'}]);
// Source has no holds/operational fields: no such historical source rows may be invented.
assert.equal(current.tables.length,22);
assert.ok(!current.tables.some(t=>t.source_table==='container_blocks'));
assert.ok(!current.tables.find(t=>t.source_table==='truck_visits').columns.some(c=>c.name==='operational_details'));
const privateRoot=path.resolve(__dirname,'../.migration-data');fs.mkdirSync(privateRoot,{recursive:true});
const testRoot=fs.mkdtempSync(path.join(privateRoot,'manifest-check-'));
for(const version of ['legacy','v5']){
  const {manifest,text}=loadManifest(version);
  const directory=createFixture(path.join(testRoot,version),version);
  const snapshot=JSON.parse(fs.readFileSync(path.join(directory,'snapshot.json'),'utf8'));
  assert.equal(snapshot.manifest_sha256,manifestHash(text));
  assert.equal(snapshot.files.length,22);
  for(const file of snapshot.files){
    const content=fs.readFileSync(path.join(directory,file.name),'utf8');
    assert.equal(file.sha256,fileHash(content));
    const rows=content.split('\n').filter(Boolean).map(line=>JSON.parse(line));
    assert.equal(rows.length,file.rows);
    const table=manifest.tables.find(t=>t.source_schema===file.schema&&t.source_table===file.table);
    for(const row of rows)validateRow(table,row);
    if(file.table==='profiles'){
      assert.equal(rows[0].id,'11111111-1111-4111-8111-111111111111');
      assert.equal(rows[0].username,version==='v5'?'synthetic.clerk':undefined);
      assert.ok(!Object.hasOwn(rows[0],'initial_password'));
    }
    if(file.table==='visit_events')assert.equal(rows[0].id,'9007199254740993');
  }
  assert.throws(()=>createFixture(directory,version),'existing fixture cannot be overwritten');
}
console.log('PASS: live-catalog metadata compatibility, schema drift rejection, password exclusion, preserved usernames/UUID/bigint, distinct hashes and complete legacy/v5 synthetic snapshots.');
