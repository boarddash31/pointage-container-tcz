'use strict';
const fs=require('node:fs'),path=require('node:path');

function loadManifest(profile='legacy') {
  if(!['legacy','v5'].includes(profile))throw Error('Manifest must be legacy or v5.');
  const filename=path.join(__dirname,'..',profile==='v5'?'manifest-v5.json':'manifest.json');
  const text=fs.readFileSync(filename,'utf8');
  return {manifest:JSON.parse(text),text,filename};
}

function validateCatalog(manifest,tables) {
  const key=t=>t.table_schema+'.'+t.table_name;
  const actual=new Map(tables.map(t=>[key(t),t]));
  if(actual.size!==manifest.tables.length||tables.length!==actual.size)
    throw Error('Source tables changed; refresh the transfer manifest before exporting.');
  for(const table of manifest.tables) {
    const found=actual.get(table.source_schema+'.'+table.source_table);
    if(!found)throw Error('Source table changed: '+table.source_schema+'.'+table.source_table);
    // The sole intentional omission is this historical password field. No auth schema is read.
    const columns=found.columns.filter(c=>!(table.source_schema==='public'&&table.source_table==='profiles'&&c.name==='initial_password'));
    const expected=new Map(table.columns.map(c=>[c.name,c]));
    if(columns.length!==expected.size||new Set(columns.map(c=>c.name)).size!==expected.size||columns.some(c=>{
      const e=expected.get(c.name);return !e||e.type!==c.type||e.nullable!==c.nullable;
    }))throw Error('Source columns/types/nullability changed: '+table.source_schema+'.'+table.source_table);
  }
}
module.exports={loadManifest,validateCatalog};
