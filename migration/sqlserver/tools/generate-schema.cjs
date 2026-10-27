'use strict';
// Reproducible conversion of the captured catalog; never connects to production.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const source = require('../source-schema.json');
const id = name => { if (!/^[a-z_][a-z0-9_]*$/.test(name)) throw Error('Invalid identifier'); return '[' + name + ']'; };
const schema = name => name === 'private' ? 'internal' : 'dbo';
const full = table => id(schema(table.schema)) + '.' + id(table.table);
const limits = {armateur_id:64,armateur_id_2:64,carrier_booking_armateur_id:64,carrier_booking_armateur_id_2:64,
  number:11,container_number:11,container_number_2:11,iso_code:4,iso_code_2:4,role:16,source:16,
  entry_kind:8,kind:32,direction:16,action:64,status:16,reference:150,client_order_reference:150,
  carrier_booking_reference:150,booking_reference_2:150,code:150,storage_path:450,device_id:200,phone:32,entity:64,entity_id:150};
const checks = {
  transport_order_controls:['[singleton]=1'],
  bookings:["LEN(TRIM([reference])) BETWEEN 1 AND 150"],
  client_armateurs:['[valid_to] IS NULL OR [valid_to]>=[valid_from]'],
  container_stock_intervals:['[departed_at] IS NULL OR [departed_at]>=[arrived_at]'],
  containers:["LEN([number])=11 AND LEFT([number],4) NOT LIKE N'%[^A-Z]%' AND RIGHT([number],7) NOT LIKE N'%[^0-9]%'",
    "LEN([iso_code])=4 AND [iso_code] NOT LIKE N'%[^0-9A-Z]%'","[source] IN (N'operator',N'manual',N'import')"],
  document_actions:["[action] IN (N'PREVIEW_REQUESTED',N'SHARE_REQUESTED',N'PRINT_DIALOG_REQUESTED',N'DIRECT_PRINT_REQUESTED',N'BRIDGE_ARCHIVE_REQUESTED',N'BRIDGE_PRINT_REQUESTED')"],
  evp_rules:['[factor]>0','[size_feet] IN (20,40,45)'],
  forced_container_actions:["[action]=N'PRISE_SANS_STOCK'",'LEN(TRIM([reason]))>=10',
    '([resolved_at] IS NULL AND [resolved_by] IS NULL AND [external_reference] IS NULL) OR ([resolved_at] IS NOT NULL AND [resolved_by] IS NOT NULL AND LEN(TRIM([external_reference]))>=3)'],
  generated_documents:["[kind] IN (N'ENTREE',N'DEPOSE',N'PRISE',N'SORTIE',N'ANNULATION')","[status] IN (N'pending',N'uploaded',N'failed')"],
  iso_report_types:["[category] IN (N'20 DV',N'40 DV ST',N'40 DV HC',N'45 DV',N'FRIGO 20',N'FRIGO 40',N'OT&FL&HP&CT')",'[size_feet] IN (20,40,45)'],
  transport_order_items:["LEN([iso_code])=4 AND [iso_code] NOT LIKE N'%[^0-9A-Z]%'",'[quantity] BETWEEN 1 AND 1000000'],
  transport_orders:["([kind]<>N'EDO' OR [direction]=N'LIVRAISON') AND ([kind]<>N'ERO' OR [direction]=N'RESTITUTION')",
    '[client_order_reference] IS NULL OR [client_id] IS NOT NULL',"[direction] IN (N'RESTITUTION',N'LIVRAISON')",
    "[kind] IN (N'BOOKING',N'EDO',N'ERO')",'LEN(TRIM([reference])) BETWEEN 1 AND 150'],
  truck_visits:["([entry_kind]=N'loaded' AND [container_number] IS NOT NULL) OR ([entry_kind]=N'empty' AND [booking_id] IS NOT NULL)",
    '[carrier_booking_reference] IS NULL OR LEN(TRIM([carrier_booking_reference])) BETWEEN 1 AND 150',
    '[exited_at] IS NULL OR ([engin_at] IS NOT NULL AND [canceled_at] IS NULL)',
    '[canceled_at] IS NULL OR ([exited_at] IS NULL AND LEN(TRIM([cancel_reason]))>0)',
    '[client_order_reference] IS NULL OR LEN(TRIM([client_order_reference])) BETWEEN 1 AND 150',"[entry_kind] IN (N'loaded',N'empty')"],
  user_roles:["[role] IN (N'admin',N'entree',N'engin',N'sortie',N'viewer')"],
  visit_events:["[action] IN (N'ENTREE',N'DEPOSE',N'PRISE',N'SORTIE',N'ANNULATION')"],
  yard_operations:["[kind] IN (N'depose',N'prise')"],
};
function columnType(table, col) {
  const types={uuid:'uniqueidentifier',bool:'bit',int4:'int',int8:'bigint',date:'date',timestamptz:'datetimeoffset(6)',numeric:'decimal(38,18)',jsonb:'nvarchar(max)'};
  if(col.udt!=='text') {if(!types[col.udt])throw Error('Unmapped type '+col.udt);return types[col.udt];}
  const limit=table.table==='armateurs'&&col.name==='id'?64:limits[col.name];
  return 'nvarchar('+(limit??'max')+') COLLATE Latin1_General_100_BIN2';
}
function defaultSql(value) {
  if(value==null)return '';
  if(value==='gen_random_uuid()')return ' DEFAULT NEWID()';
  if(value==='now()')return ' DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),\'+00:00\')';
  if(value==='true'||value==='false')return ' DEFAULT '+(value==='true'?1:0);
  if(/^\d+$/.test(value))return ' DEFAULT '+value;
  const m=value.match(/^'((?:[^']|'')*)'::(?:text|jsonb)$/);
  if(m)return " DEFAULT N'"+m[1]+"'";
  throw Error('Unmapped default: '+value);
}
const manifest={format:1,source_project:source.source_project,captured_on:source.captured_on,
  authentication:'Admin-managed application accounts link to preserved profiles; no Supabase passwords or initial_password are exported.',tables:[]};
const ddl=[`-- SQL Server 2025. Generated from the metadata snapshot; no source rows are embedded.
-- Run against a NEW, empty database selected by your DBA, never master or an existing application database.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() IN (N'master',N'model',N'msdb',N'tempdb') THROW 51000, 'Select the dedicated Pointage database first.', 1;
IF CONVERT(int,SERVERPROPERTY('ProductMajorVersion'))<17 THROW 51000, 'SQL Server 2025 or newer is required.', 1;
IF OBJECT_ID(N'internal.schema_versions') IS NOT NULL THROW 51000, 'Migration already initialized; do not replay.', 1;
IF EXISTS(SELECT 1 FROM sys.tables WHERE is_ms_shipped=0) THROW 51000, 'Destination must be empty.', 1;
BEGIN TRANSACTION;
IF SCHEMA_ID(N'internal') IS NULL EXEC(N'CREATE SCHEMA internal AUTHORIZATION dbo');
IF SCHEMA_ID(N'api') IS NULL EXEC(N'CREATE SCHEMA api AUTHORIZATION dbo');
CREATE TABLE internal.schema_versions(version int NOT NULL PRIMARY KEY, applied_at datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00'));
`];
for(const table of source.tables) {
  const columns=table.columns.filter(c=>c.name!=='initial_password');
  const definitions=[];
  for(const col of columns) {
    const identity=col.udt==='int8'&&col.name==='id';
    definitions.push('  '+id(col.name)+' '+columnType(table,col)+(identity?' IDENTITY(1,1)':'')+
      (col.nullable==='YES'?' NULL':' NOT NULL')+(identity?'':defaultSql(col.default)));
    if(col.udt==='jsonb')definitions.push('  CHECK ('+id(col.name)+' IS NULL OR ISJSON('+id(col.name)+',VALUE)=1)');
  }
  for(const c of source.constraints.filter(c=>c.table===table.table&&c.schema===table.schema&&(c.type==='p'||c.type==='u'))) {
    const cols=c.definition.match(/\(([^)]+)\)/)[1].split(',').map(s=>s.trim());
    if(c.type==='u'&&cols.length===1&&cols[0]==='storage_path')continue;
    definitions.push('  CONSTRAINT '+id(c.name)+' '+(c.type==='p'?'PRIMARY KEY':'UNIQUE')+' ('+cols.map(id).join(',')+')');
  }
  for(const check of checks[table.table]??[])definitions.push('  CHECK ('+check+')');
  ddl.push('CREATE TABLE '+full(table)+' (\n'+definitions.join(',\n')+'\n);');
  manifest.tables.push({source_schema:table.schema,source_table:table.table,target_schema:schema(table.schema),target_table:table.table,
    columns:columns.map(c=>({name:c.name,type:c.udt,nullable:c.nullable==='YES',sql_type:columnType(table,c),identity:c.udt==='int8'&&c.name==='id'})),
    primary_key:source.constraints.find(c=>c.schema===table.schema&&c.table===table.table&&c.type==='p').definition.match(/\(([^)]+)\)/)[1].split(',').map(s=>s.trim())});
}
for(const c of source.constraints.filter(c=>c.type==='f'&&!c.definition.includes('auth.users'))) {
  const match=c.definition.match(/^FOREIGN KEY \(([^)]+)\) REFERENCES (?:(public|private)\.)?([a-z_]+)\(([^)]+)\)/);
  if(!match)throw Error('Unmapped FK '+c.name);
  const target=source.tables.find(t=>t.table===match[3]);
  ddl.push('ALTER TABLE '+id(schema(c.schema))+'.'+id(c.table)+' WITH CHECK ADD CONSTRAINT '+id(c.name)+' FOREIGN KEY ('+match[1].split(',').map(x=>id(x.trim())).join(',')+') REFERENCES '+full(target)+' ('+match[4].split(',').map(x=>id(x.trim())).join(',')+');');
}
ddl.push(`
ALTER TABLE dbo.transport_orders ADD normalized_reference AS UPPER(TRIM(reference)) PERSISTED;
CREATE UNIQUE INDEX transport_orders_reference_key ON dbo.transport_orders(normalized_reference);
CREATE UNIQUE INDEX generated_documents_path_key ON dbo.generated_documents(storage_path) WHERE storage_path IS NOT NULL;
CREATE UNIQUE INDEX one_open_stock_interval ON dbo.container_stock_intervals(container_number) WHERE departed_at IS NULL;
-- A computed SHA-256 key permits indexing arbitrary-length historical position strings.
ALTER TABLE dbo.container_stock_intervals ADD position_hash AS CONVERT(binary(32),HASHBYTES('SHA2_256',position)) PERSISTED;
CREATE UNIQUE INDEX one_open_yard_position ON dbo.container_stock_intervals(position_hash) WHERE departed_at IS NULL AND position IS NOT NULL;
CREATE UNIQUE INDEX idx_profiles_phone_unique ON dbo.profiles(phone) WHERE phone IS NOT NULL AND phone<>N'';
-- SQL Server filtered indexes cannot express the PostgreSQL OR predicate. Inactive rows
-- use their UUID as a distinct key, while active rows use the container number.
ALTER TABLE dbo.truck_visits ADD active_container_key AS
  CASE WHEN container_number IS NOT NULL AND canceled_at IS NULL AND exited_at IS NULL
    AND ((entry_kind=N'loaded' AND engin_at IS NULL) OR (entry_kind=N'empty' AND engin_at IS NOT NULL))
    THEN CONVERT(nvarchar(36),container_number) ELSE CONVERT(nvarchar(36),id) END PERSISTED;
ALTER TABLE dbo.truck_visits ADD active_container_2_key AS
  CASE WHEN container_number_2 IS NOT NULL AND canceled_at IS NULL AND exited_at IS NULL
    AND ((entry_kind=N'loaded' AND engin_at IS NULL) OR (entry_kind=N'empty' AND engin_at IS NOT NULL))
    THEN CONVERT(nvarchar(36),container_number_2) ELSE CONVERT(nvarchar(36),id) END PERSISTED;
CREATE UNIQUE INDEX one_active_container_on_truck ON dbo.truck_visits(active_container_key);
CREATE UNIQUE INDEX one_active_container_2_on_truck ON dbo.truck_visits(active_container_2_key);
CREATE INDEX visits_order_item_idx ON dbo.truck_visits(order_item_id) INCLUDE(canceled_at,engin_at,exited_at);
CREATE INDEX visits_order_item_2_idx ON dbo.truck_visits(order_item_id_2) INCLUDE(canceled_at,engin_at,exited_at);
CREATE INDEX visits_inside_idx ON dbo.truck_visits(entered_at,id) WHERE exited_at IS NULL AND canceled_at IS NULL;
CREATE INDEX audit_entity_idx ON dbo.audit_logs(entity,entity_id,occurred_at);
CREATE INDEX documents_visit_idx ON dbo.generated_documents(visit_id,created_at);
INSERT internal.schema_versions(version) VALUES(1);
COMMIT TRANSACTION;
GO
`);
// Stable FK dependency order for bulk import, preserving every source identifier.
const ordered=[],visiting=new Set(),visited=new Set();
function visit(table) {
  const key=table.source_schema+'.'+table.source_table;
  if(visited.has(key))return;
  if(visiting.has(key))throw Error('FK cycle needs an explicit import strategy: '+key);
  visiting.add(key);
  for(const fk of source.constraints.filter(c=>c.type==='f'&&c.schema===table.source_schema&&c.table===table.source_table&&!c.definition.includes('auth.users'))) {
    const target=fk.definition.match(/REFERENCES (?:(?:public|private)\.)?([a-z_]+)\(/)[1];
    visit(manifest.tables.find(t=>t.source_table===target));
  }
  visiting.delete(key);visited.add(key);ordered.push(table);
}
for(const table of manifest.tables)visit(table);
ordered.forEach((table,index)=>table.import_order=index);
fs.writeFileSync(path.join(root,'001_schema.sql'),ddl.join('\n\n'));
fs.writeFileSync(path.join(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
console.log('Generated '+manifest.tables.length+' tables, constraints and a credential-free migration manifest.');
