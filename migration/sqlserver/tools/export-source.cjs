'use strict';
// Explicit export command only. Uses a single repeatable-read, READ ONLY source transaction.
const fs=require('node:fs');
const path=require('node:path');
const {once}=require('node:events');
const {finished}=require('node:stream/promises');
const crypto=require('node:crypto');
const {Client,types}=require('pg');
const manifest=require('../manifest.json');
const {validateRow,manifestHash}=require('./row-validation.cjs');
const root=path.resolve(__dirname,'../../..');
const name=n=>{if(!/^[a-z_][a-z0-9_]*$/.test(n))throw Error('Invalid manifest identifier');return '"'+n+'"';};
async function main(){
  const position=process.argv.indexOf('--out');
  if(position<0||!process.argv[position+1])throw Error('Usage: node migration/sqlserver/tools/export-source.cjs --out .migration-data/snapshot-NAME');
  const destination=path.resolve(root,process.argv[position+1]);
  const relative=path.relative(path.join(root,'.migration-data'),destination);
  if(!relative||relative.startsWith('..')||path.isAbsolute(relative))throw Error('Export must use a new subfolder of .migration-data.');
  if(fs.existsSync(destination))throw Error('Export folder exists; use a new snapshot folder.');
  const connection=process.env.POINTAGE_SOURCE_CONNECTION;
  if(!connection)throw Error('Set POINTAGE_SOURCE_CONNECTION securely; do not place credentials in command arguments.');
  const url=new URL(connection);
  if(!['postgres:','postgresql:'].includes(url.protocol))throw Error('Source must be PostgreSQL.');
  if(url.hostname!=='db.'+manifest.source_project+'.supabase.co'&&!decodeURIComponent(url.username).endsWith('.'+manifest.source_project))
    throw Error('Source project differs from the captured migration manifest.');
  for(const key of ['sslmode','sslcert','sslkey','sslrootcert'])url.searchParams.delete(key);
  const ssl={rejectUnauthorized:true};
  if(process.env.POINTAGE_SOURCE_CA_FILE)ssl.ca=fs.readFileSync(process.env.POINTAGE_SOURCE_CA_FILE,'utf8');
  const client=new Client({connectionString:url.toString(),ssl,application_name:'pointage-read-only-migration'});
  // pg's default Date conversion loses microseconds; bigint/decimal must not become JS floats.
  for(const oid of [20,1082,1184,1700,114,3802])types.setTypeParser(oid,value=>value);
  fs.mkdirSync(destination,{recursive:true,mode:0o700});
  const snapshot={format:1,created_at_utc:new Date().toISOString(),source_project:manifest.source_project,
    manifest_sha256:manifestHash(fs.readFileSync(path.join(__dirname,'../manifest.json'),'utf8')),files:[]};
  let transaction=false;
  try{
    await client.connect();
    await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');transaction=true;
    await client.query("SET LOCAL TIME ZONE 'UTC'");
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
    fs.writeFileSync(path.join(destination,'snapshot.json'),JSON.stringify(snapshot,null,2)+'\n',{flag:'wx',mode:0o600});
    console.log('Snapshot complete. Treat this folder as confidential business data.');
  }catch(error){if(transaction)await client.query('ROLLBACK').catch(()=>{});throw error;}
  finally{await client.end().catch(()=>{});}
}
if(require.main===module)main().catch(()=>{console.error('Export failed. No completed snapshot.json was written; verify connectivity and source compatibility. Credentials and row values are intentionally omitted.');process.exitCode=1;});
