'use strict';
// Only emits a transfer manifest; never rewrites the installed foundation or connects to a database.
const fs=require('node:fs'),path=require('node:path');
const {loadManifest,validateCatalog}=require('./transfer-manifest.cjs');
const {manifestHash}=require('./row-validation.cjs');
const {manifest:legacy,text}=loadManifest();
const catalog=require('../source-columns-20261121.json');
if(catalog.source_project!==legacy.source_project)throw Error('Unexpected source project.');
const refreshed=structuredClone(legacy);
refreshed.tables.find(t=>t.source_schema==='public'&&t.source_table==='profiles').columns.push({
  name:'username',type:'text',nullable:false,sql_type:'nvarchar(max) COLLATE Latin1_General_100_BIN2',identity:false
});
validateCatalog(refreshed,catalog.tables);
const manifest={...refreshed,captured_on:catalog.captured_on,profile:'zenata-transfer-v5',target_schema_version:5,
  base_manifest_sha256:manifestHash(text),
  target_empty_tables:[
    {target_schema:'dbo',target_table:'container_blocks'},
    {target_schema:'internal',target_table:'local_accounts'},
    {target_schema:'internal',target_table:'application_sessions'}
  ],
  target_defaults:[{target_schema:'dbo',target_table:'truck_visits',column:'operational_details',value:'{}'}],
  source_notes:[
    'The source catalog has 22 tables; profiles.username is newer than the legacy foundation. SQL upgrade 011 preserves it without creating login accounts.',
    'There is no operational_details column or container_blocks table in the source catalog on 2026-11-21.',
    'Historical visit operational_details default to {} in SQL schema 4. No historical holds are invented.',
    'Any later source schema change stops export until the transfer manifest is refreshed.',
    'Local accounts must be provisioned against preserved profiles only after the historical import. Storage/PDF binaries are a separate transfer.'
  ]};
fs.writeFileSync(path.join(__dirname,'../manifest-v5.json'),JSON.stringify(manifest,null,2)+'\n');
console.log('Transfer manifest v5 generated for 22 verified source tables, including profiles.username; foundation DDL unchanged.');
