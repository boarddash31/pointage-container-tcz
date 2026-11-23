'use strict';
// Explicit export command only. Uses a single repeatable-read, READ ONLY source transaction.
const fs=require('node:fs');
const path=require('node:path');
const {once}=require('node:events');
const {finished}=require('node:stream/promises');
const crypto=require('node:crypto');
const {Client,types}=require('pg');
const {loadManifest,validateCatalog}=require('./transfer-manifest.cjs');
const {validateSourceUrl}=require('./source-connection.cjs');
const {validateRow,manifestHash}=require('./row-validation.cjs');
const root=path.resolve(__dirname,'../../..');
const name=n=>{if(!/^[a-z_][a-z0-9_]*$/.test(n))throw Error('Invalid manifest identifier');return '"'+n+'"';};
async function main(){
  const args=process.argv.slice(2);
  if(![2,4].includes(args.length)||args[0]!=='--out'||args.length===4&&args[2]!=='--manifest')
    throw Error('Usage: export-source.cjs --out .migration-data/snapshot-NAME [--manifest legacy|v5]');
  const {manifest,text:manifestText}=loadManifest(args.length===4?args[3]:'legacy');
  const destination=path.resolve(root,args[1]);
  const relative=path.relative(path.join(root,'.migration-data'),destination);
  if(!relative||relative.startsWith('..')||path.isAbsolute(relative))throw Error('Export must use a new subfolder of .migration-data.');
  if(fs.existsSync(destination))throw Error('Export folder exists; use a new snapshot folder.');
  const connection=process.env.POINTAGE_SOURCE_CONNECTION;
  if(!connection)throw Error('Set POINTAGE_SOURCE_CONNECTION securely; do not place credentials in command arguments.');
  const url=new URL(connection);
  validateSourceUrl(url,manifest.source_project);
  for(const key of ['sslmode','sslcert','sslkey','sslrootcert'])url.searchParams.delete(key);
  const ssl={rejectUnauthorized:true};
  if(process.env.POINTAGE_SOURCE_CA_FILE)ssl.ca=fs.readFileSync(process.env.POINTAGE_SOURCE_CA_FILE,'utf8');
  const client=new Client({connectionString:url.toString(),ssl,application_name:'pointage-read-only-migration'});
  // pg's default Date conversion loses microseconds; bigint/decimal must not become JS floats.
  for(const oid of [20,1082,1184,1700,114,3802])types.setTypeParser(oid,value=>value);
  fs.mkdirSync(destination,{recursive:true,mode:0o700});
  const snapshot={format:1,created_at_utc:new Date().toISOString(),source_project:manifest.source_project,
    manifest_sha256:manifestHash(manifestText),files:[]};
  let transaction=false;
  try{
    await client.connect();
    await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');transaction=true;
    await client.query("SET LOCAL TIME ZONE 'UTC'");
    let freezeId;
    if(process.env.POINTAGE_REQUIRE_FROZEN_SOURCE==='1'){
      const status=(await client.query('SELECT frozen,freeze_id::text FROM migration_control.freeze_state WHERE singleton')).rows;
      if(status.length!==1||status[0].frozen!==true)throw Error('Final export requires frozen source writes across all old sites.');
      freezeId=status[0].freeze_id;snapshot.source_freeze_id=freezeId;
    }
    // Refuse an outdated manifest rather than silently dropping new source tables
    // or fields (especially operational_details and container_blocks).
    const catalogRows=(await client.query(`SELECT c.table_schema,c.table_name,c.column_name AS name,c.udt_name AS type,(c.is_nullable='YES') AS nullable
      FROM information_schema.columns c JOIN information_schema.tables t ON t.table_schema=c.table_schema AND t.table_name=c.table_name
      WHERE t.table_type='BASE TABLE' AND c.table_schema IN ('public','private') ORDER BY c.table_schema,c.table_name,c.ordinal_position`)).rows;
    const catalog=new Map();
    for(const row of catalogRows){
      const key=row.table_schema+'.'+row.table_name;
      if(!catalog.has(key))catalog.set(key,{table_schema:row.table_schema,table_name:row.table_name,columns:[]});
      catalog.get(key).columns.push({name:row.name,type:row.type,nullable:row.nullable});
    }
    validateCatalog(manifest,[...catalog.values()]);
    for(const table of manifest.tables){
      const filename=table.source_schema+'.'+table.source_table+'.ndjson';
      const file=fs.createWriteStream(path.join(destination,filename),{flags:'wx',mode:0o600});
      const completed=finished(file);completed.catch(()=>{});
      const hash=crypto.createHash('sha256');let count=0;
      // No credentials, auth password hashes or profiles.initial_password are selected.
      const select='SELECT '+table.columns.map(c=>name(c.name)).join(',')+' FROM '+name(table.source_schema)+'.'+name(table.source_table)+' ORDER BY '+table.primary_key.map(name).join(',');
      try{
        await client.query('DECLARE migration_rows NO SCROLL CURSOR FOR '+select);
        for(;;){
          const rows=(await client.query('FETCH FORWARD 1000 FROM migration_rows')).rows;
          if(!rows.length)break;
          for(const row of rows){const line=JSON.stringify(validateRow(table,row))+'\n';hash.update(line);if(!file.write(line))await once(file,'drain');count++;}
        }
        await client.query('CLOSE migration_rows');
        file.end();await completed;
      }catch(error){file.destroy();throw error;}
      snapshot.files.push({schema:table.source_schema,table:table.source_table,name:filename,rows:count,sha256:hash.digest('hex')});
      console.log(table.source_table+': '+count+' rows exported');
    }
    await client.query('COMMIT');transaction=false;
    if(freezeId){const status=(await client.query('SELECT frozen,freeze_id::text FROM migration_control.freeze_state WHERE singleton')).rows;
      if(status.length!==1||status[0].frozen!==true||status[0].freeze_id!==freezeId)throw Error('Source freeze changed during final export.');}
    fs.writeFileSync(path.join(destination,'snapshot.json'),JSON.stringify(snapshot,null,2)+'\n',{flag:'wx',mode:0o600});
    console.log('Snapshot complete. Treat this folder as confidential business data.');
  }catch(error){if(transaction)await client.query('ROLLBACK').catch(()=>{});throw error;}
  finally{await client.end().catch(()=>{});}
}
if(require.main===module)main().catch(()=>{console.error('Export failed. No completed snapshot.json was written; verify connectivity and source compatibility. Credentials and row values are intentionally omitted.');process.exitCode=1;});
