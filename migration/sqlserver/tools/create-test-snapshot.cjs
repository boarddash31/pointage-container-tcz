'use strict';
// Synthetic fixture only. Never reads Supabase or any environment credential.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const manifest=require('../manifest.json'),source=require('../source-schema.json');
const {validateRow,fileHash,manifestHash}=require('./row-validation.cjs');
const root=path.resolve(__dirname,'../../..');
const args=process.argv.slice(2);
if(args.length!==0&&(args.length!==2||args[0]!=='--out'))throw Error('Usage: create-test-snapshot.cjs [--out .migration-data/new-fixture]');
const privateRoot=path.join(root,'.migration-data');
const out=path.resolve(root,args[1]??'.migration-data/ci-safe');
if(!out.startsWith(privateRoot+path.sep))throw Error('Synthetic fixtures must remain inside ignored .migration-data.');
if(fs.existsSync(out))throw Error('Synthetic snapshot exists; use a clean workspace.');
fs.mkdirSync(out,{recursive:true});
const actor='11111111-1111-4111-8111-111111111111',order='22222222-2222-4222-8222-222222222222',
  item='33333333-3333-4333-8333-333333333333',visit='44444444-4444-4444-8444-444444444444',
  document='55555555-5555-4555-8555-555555555555',stock='66666666-6666-4666-8666-666666666666';
const time='2026-10-27T12:34:56.123456+00:00',large='9007199254740993';
const rows={
  armateurs:[{id:'MAE',name:'Synthetic Maersk',bic:'MAEU'}],
  profiles:[{id:actor,display_name:'Synthetic Clerk',phone:'0600000000',first_name:'Synthetic',last_name:'Clerk'}],
  user_roles:[{user_id:actor,role:'entree'}],
  containers:[{number:'CSQU3054383',iso_code:'22G1',armateur_id:'MAE'}],
  transport_orders:[{id:order,kind:'ERO',direction:'RESTITUTION',reference:'QA-MIGRATION',armateur_id:'MAE',created_by:actor,updated_by:actor}],
  transport_order_items:[{id:item,order_id:order,iso_code:'22G1',armateur_id:'MAE',quantity:5}],
  truck_visits:[{id:visit,plate:'QA-TEST',driver_cin:'QA-CIN',entry_kind:'loaded',container_number:'CSQU3054383',iso_code:'22G1',armateur_id:'MAE',entered_by:actor,order_item_id:item,order_controlled:true,carrier_booking_reference:'QA-MIGRATION',carrier_booking_armateur_id:'MAE'}],
  container_stock_intervals:[{id:stock,container_number:'CSQU3054383',iso_code:'22G1',armateur_id:'MAE',start_visit_id:visit,arrived_at:time}],
  visit_events:[{id:large,visit_id:visit,action:'ENTREE',actor_id:actor,details:'{"source_event":9007199254740993}'}],
  audit_logs:[{id:'9007199254740995',entity:'transport_order',entity_id:order,action:'QA',actor_id:actor,after_data:'{"source_event":9007199254740993}'}],
  generated_documents:[{id:document,visit_id:visit,event_id:large,kind:'ENTREE',snapshot:'{"source_event":9007199254740993}',created_by:actor}],
  evp_rules:[{effective_from:'2026-10-27',size_feet:40,factor:'2.000000000000000001',source_note:'Synthetic precision fixture',created_by:actor}],
  transport_order_controls:[{singleton:true,required:false}],
};
function complete(table,input){
  const sourceTable=source.tables.find(t=>t.schema===table.source_schema&&t.table===table.source_table);
  const result={};
  for(const col of table.columns){
    if(Object.hasOwn(input,col.name)){result[col.name]=input[col.name];continue;}
    const def=sourceTable.columns.find(c=>c.name===col.name).default;
    if(def==='now()'){result[col.name]=time;continue;}
    if(def==='gen_random_uuid()'){result[col.name]=crypto.randomUUID();continue;}
    if(def==='true'||def==='false'){result[col.name]=def==='true';continue;}
    if(def&&/^\d+$/.test(def)){result[col.name]=Number(def);continue;}
    if(def&&def.startsWith("'")){result[col.name]=def.slice(1,def.lastIndexOf("'"));continue;}
    if(col.nullable){result[col.name]=null;continue;}
    throw Error('Missing fixture '+table.source_table+'.'+col.name);
  }
  return validateRow(table,result);
}
const snapshot={format:1,created_at_utc:time,source_project:manifest.source_project,
  manifest_sha256:manifestHash(fs.readFileSync(path.join(__dirname,'../manifest.json'),'utf8')),files:[]};
for(const table of manifest.tables){
  const name=table.source_schema+'.'+table.source_table+'.ndjson';
  const content=(rows[table.source_table]??[]).map(row=>JSON.stringify(complete(table,row))+'\n').join('');
  fs.writeFileSync(path.join(out,name),content);
  snapshot.files.push({schema:table.source_schema,table:table.source_table,name,rows:(rows[table.source_table]??[]).length,sha256:fileHash(content)});
}
fs.writeFileSync(path.join(out,'snapshot.json'),JSON.stringify(snapshot,null,2)+'\n');
console.log('Synthetic snapshot created: exact bigint, microseconds, JSON and decimal fixtures; no source access.');
