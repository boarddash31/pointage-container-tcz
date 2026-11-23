'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs/promises'),path=require('node:path');
const {generate}=require('../scripts/generate_sql_operator_catalog.cjs');
test('SQL initialization contains the bundled named shipping lines, including searchable ZIMAG',async()=>{
 const {count}=await generate();
 const source=JSON.parse(await fs.readFile(path.join(__dirname,'../app/assets/operators.json'),'utf8'));
 const sql=await fs.readFile(path.join(__dirname,'../migration/sqlserver/deployment/17_INITIALISER_ARMATEURS_DBEAVER.sql'),'utf8');
 const match=sql.match(/OPENJSON\(N'((?:[^']|'')*)'\)/);
 assert.ok(match,'SQL contains a quoted JSON reference catalogue');
 const payload=JSON.parse(match[1].replaceAll("''","'"));
 assert.deepEqual(payload,source.filter(row=>row.name.trim().length>0));
 assert.equal(count,92);assert.equal(new Set(payload.map(row=>row.id)).size,count);
 assert.equal(payload.find(row=>row.id==='ZIMAG').name,'ZIMAG');
 assert.ok(payload.every(row=>row.name.trim().length>0));
 assert.match(sql,/UPPER\(a\.id\) COLLATE Latin1_General_100_BIN2=c\.id/,'existing codes compared without database-default collation');
 assert.match(sql,/WITH\(UPDLOCK,HOLDLOCK\)/,'existing code lookup is protected for repeat/concurrent initialization');
 assert.doesNotMatch(sql,/\b(?:DELETE|TRUNCATE|UPDATE)\s+dbo\./i,'reference initialization does not replace existing data');
 assert.equal(sql,await fs.readFile(path.join(__dirname,'../migration/sqlserver/017_initialize_operator_catalog.sql'),'utf8'));
});
