'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=__dirname;
const release=JSON.parse(fs.readFileSync(path.join(root,'web/release.json'),'utf8'));
const hash=crypto.createHash('sha256').update(fs.readFileSync(path.join(root,'web/main.dart.js'))).digest('hex');
if(release.backend!=='sqlserver'||hash!==release.main_sha256)throw Error('SQL web build/integrity mismatch.');
for(const file of ['api/Pointage.Api.dll','api/Pointage.Api.runtimeconfig.json','tools/setup/Pointage.Setup.dll','tools/migration/Pointage.Migration.dll','sql-api-proxy.cjs','reports/sql-source.cjs'])if(!fs.existsSync(path.join(root,file)))throw Error('Runtime file missing: '+file);
const bootstrap=fs.readFileSync(path.join(root,'web/flutter_bootstrap.js'),'utf8');
if(!bootstrap.includes(release.release))throw Error('SQL release cache marker mismatch.');
if(!process.versions.sqlite)throw Error('The bundled Node runtime with SQLite support is required.');
fs.writeFileSync(path.join(root,'RUNTIME-COMPILE.json'),JSON.stringify({release:release.release,compiledAtUtc:new Date().toISOString(),main_sha256:hash,
 files:['api/Pointage.Api.dll','tools/setup/Pointage.Setup.dll','tools/migration/Pointage.Migration.dll'].map(file=>({path:file,sha256:crypto.createHash('sha256').update(fs.readFileSync(path.join(root,file))).digest('hex')})),databaseConnectionTested:false},null,2));
console.log('PASS: SQL web hash, cache version, API/tool outputs and required local runtime files. No database connected.');
