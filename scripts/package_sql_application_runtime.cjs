'use strict';
const fs=require('node:fs/promises'),path=require('node:path'),crypto=require('node:crypto');
const {createRequire}=require('node:module');
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const release='zps-sqlserver-ui-session-20261122';
async function main(){
 const root=path.resolve(__dirname,'..'),qa=path.join(root,'.qa'),web=path.join(root,'app/build/web');
 const logBytes=await fs.readFile(path.join(qa,'sql-flutter-build-final.log'));
 const log=logBytes.toString(logBytes[0]===0xff&&logBytes[1]===0xfe?'utf16le':'utf8');
 if(!log.includes('Built build'))throw Error('Complete and validate the final SQL web build first.');
 await require('./generate_sql_application_upgrade.cjs').generate();
 await require('./generate_sql_operator_catalog.cjs').generate();
 require('../migration/sqlserver/tools/generate-transfer-manifest.cjs');
 const stage=await fs.mkdtemp(path.join(qa,'sql-application-runtime-'));
 const packageRoot=path.join(stage,'ZENATA-RUNTIME-SQL');await fs.mkdir(packageRoot);
 async function copy(source,destination,{webFiles=false}={}){
  const stat=await fs.lstat(source);if(stat.isSymbolicLink())throw Error('Unexpected symbolic link.');
  if(stat.isDirectory()){
   await fs.mkdir(destination,{recursive:true});
   for(const name of await fs.readdir(source)){
    if(name.startsWith('.')||['node_modules','bin','obj'].includes(name)||webFiles&&(['downloads','_worker.js','_headers','_redirects','web.config','dashboard.html','release.json'].includes(name)||/\.(map|apk)$/i.test(name)))continue;
    await copy(path.join(source,name),path.join(destination,name),{webFiles});
   }
  }else{await fs.mkdir(path.dirname(destination),{recursive:true});await fs.copyFile(source,destination);}
 }
 await copy(web,path.join(packageRoot,'web'),{webFiles:true});
 const bootstrap=path.join(packageRoot,'web/flutter_bootstrap.js');
 let js=await fs.readFile(bootstrap,'utf8');
 if(!js.includes("const release = 'zps-shift-reports-20261120';"))throw Error('Unexpected bootstrap cache marker.');
 js=js.replace("const release = 'zps-shift-reports-20261120';",`const release = '${release}';`);
 await fs.writeFile(bootstrap,js);
 const index=path.join(packageRoot,'web/index.html');
 await fs.writeFile(index,(await fs.readFile(index,'utf8')).replaceAll('zps-shift-reports-20261120',release));
 const mainHash=hash(await fs.readFile(path.join(web,'main.dart.js')));
 await fs.writeFile(path.join(packageRoot,'web/release.json'),JSON.stringify({release,backend:'sqlserver',main_sha256:mainHash,required_schema:6,preparedOn:'2026-11-22',webTestsPassed:72,nodeTestsPassed:37,backendCompiledLocally:false,remoteDeployment:false},null,2));
 await copy(process.execPath,path.join(packageRoot,'node.exe'));
 await copy(path.join(qa,'node-v22.14.0-LICENSE'),path.join(packageRoot,'NODE-LICENSE.txt'));
 const windows=path.join(root,'deployment/windows');
 for(const name of ['http-runtime.cjs','runtime-logs.cjs','sql-api-proxy.cjs','verifier-runtime-sql.cjs','COMPILER-RUNTIME-SQL.cmd','DEMARRER-ZENATA.cmd','ACTUALISER-INITIALISATION-ADMIN.cmd','LANCER-SQL-9091.cmd']){
  if(name.endsWith('.cmd'))await fs.writeFile(path.join(packageRoot,name),(await fs.readFile(path.join(windows,name),'utf8')).replace(/\r?\n/g,'\r\n'));
  else await copy(path.join(windows,name),path.join(packageRoot,name));
 }
 const modes={
  'TESTER-ET-PREPARER-CONNEXION-SQL.cmd':'--preflight', 'UTILISER-COMPTE-TOSZPS.cmd':'--preflight-existing-login',
  'UTILISER-TOSZPS-SANS-VALIDATION-CERTIFICAT.cmd':'--preflight-existing-login-unverified', 'EXPORTER-SOURCE-FINALE.cmd':'--export',
  'IMPORTER-DONNEES-SQL.cmd':'--import','CREER-PREMIER-ADMIN-SQL.cmd':'--bootstrap-admin',
  'CONFIGURER-RUNTIME-SQL.cmd':'--configure','LANCER-CODECO-HTTP-SQL.cmd':'--start-codeco'
 };
 for(const [filename,mode] of Object.entries(modes)){
  const command=`@echo off\nsetlocal\ncd /d "%~dp0"\nif not exist "%~dp0tools\\setup\\Pointage.Setup.dll" (\n echo Lancer COMPILER-RUNTIME-SQL.cmd sur208 avant cette etape.\n pause\n exit /b 1\n)\ndotnet "%~dp0tools\\setup\\Pointage.Setup.dll" ${mode} "%~dp0."\nset "ZENATA_SQL_STEP_EXIT=%ERRORLEVEL%"\npause\nexit /b %ZENATA_SQL_STEP_EXIT%\n`;
  await fs.writeFile(path.join(packageRoot,filename),command.replaceAll('\n','\r\n'));
 }
 for(const name of ['calendar.cjs','feature.cjs','mailer.cjs','sql-source.cjs','store.cjs','workbook.cjs','worker.cjs','xlsx.cjs','package.json','package-lock.json'])await copy(path.join(root,'integrations/reports',name),path.join(packageRoot,'reports',name));
 const featureFile=path.join(packageRoot,'reports/feature.cjs');
 const feature=await fs.readFile(featureFile,'utf8');
 if(!feature.includes("{Source}=require('./source.cjs')"))throw Error('Unexpected report source factory.');
 await fs.writeFile(featureFile,feature.replace("{Source}=require('./source.cjs')","{SqlSource:Source}=require('./sql-source.cjs')"));
 for(const name of ['server.cjs','service.cjs','core.cjs','sql-source.cjs'])await copy(path.join(root,'integrations/codeco',name),path.join(packageRoot,'codeco',name));
 await copy(path.join(root,'integrations/codeco/config.example.json'),path.join(packageRoot,'CODECO-CONFIG-EXEMPLE.json'));
 for(const project of ['Pointage.Api','Pointage.Checks','Pointage.Migration','Pointage.Setup']){
  const folder=path.join(root,'backend',project);
  for(const entry of await fs.readdir(folder,{withFileTypes:true})){
   if(!entry.isFile()||!(/\.(cs|csproj)$/.test(entry.name)||project==='Pointage.Api'&&entry.name==='appsettings.json'))continue;
   if(entry.name==='appsettings.json'&&JSON.parse(await fs.readFile(path.join(folder,entry.name),'utf8')).ConnectionStrings?.Pointage!=='')throw Error('Refusing a configured source backend.');
   await copy(path.join(folder,entry.name),path.join(packageRoot,'backend',project,entry.name));
  }
 }
 await copy(path.join(root,'backend/global.json'),path.join(packageRoot,'backend/global.json'));
 const sqlRoot=path.join(root,'migration/sqlserver');
 for(const entry of await fs.readdir(sqlRoot,{withFileTypes:true}))if(entry.isFile()&&(/\.sql$/.test(entry.name)||['manifest.json','manifest-v5.json'].includes(entry.name)))await copy(path.join(sqlRoot,entry.name),path.join(packageRoot,'migration/sqlserver',entry.name));
 for(const name of ['export-source.cjs','row-validation.cjs','transfer-manifest.cjs','source-connection.cjs'])await copy(path.join(sqlRoot,'tools',name),path.join(packageRoot,'migration/sqlserver/tools',name));
 await copy(path.join(sqlRoot,'deployment/15_APPLICATION_SQL_DBEAVER.sql'),path.join(packageRoot,'SQL/15_APPLICATION_SQL_DBEAVER.sql'));
 await copy(path.join(sqlRoot,'deployment/16_AUTORISER_COMPTE_APPLICATIF.sql'),path.join(packageRoot,'SQL/16_AUTORISER_COMPTE_APPLICATIF.sql'));
 await copy(path.join(sqlRoot,'deployment/17_INITIALISER_ARMATEURS_DBEAVER.sql'),path.join(packageRoot,'SQL/17_INITIALISER_ARMATEURS_DBEAVER.sql'));
 for(const name of ['source_freeze.sql.in','ACTIVER_GEL_SOURCE.sql','ANNULER_GEL_AVANT_BASCULE.sql'])await copy(path.join(root,'changes/sqlserver-cutover',name),path.join(packageRoot,'SOURCE',name));
 // The source exporter reuses only the approved pg dependency already installed locally.
 async function npmPackage(name,parentSource,parentTarget,ancestors=[]){
  let entry;try{entry=createRequire(path.join(parentSource,'package.json')).resolve(name);}catch(error){throw Error('Required existing package unavailable: '+name);}
  let folder=path.dirname(entry),metadata;
  for(;;){try{metadata=JSON.parse(await fs.readFile(path.join(folder,'package.json'),'utf8'));if(metadata.name===name)break;}catch{}const next=path.dirname(folder);if(next===folder)throw Error('Cannot identify package '+name);folder=next;}
  const id=name+'@'+metadata.version;if(ancestors.includes(id))throw Error('Unexpected dependency cycle.');
  const target=path.join(parentTarget,'node_modules',name);await copy(folder,target);
  for(const dependency of Object.keys(metadata.dependencies??{}))await npmPackage(dependency,folder,target,[...ancestors,id]);
 }
 await npmPackage('pg',root,packageRoot);
 await fs.mkdir(path.join(root,'.migration-data'),{recursive:true});
 const fixtureBase=await fs.mkdtemp(path.join(root,'.migration-data/runtime-sql-selftest-'));
 const fixture=require('../migration/sqlserver/tools/create-test-snapshot.cjs').createFixture(path.relative(root,path.join(fixtureBase,'snapshot-v5')),'v5');
 await copy(fixture,path.join(packageRoot,'TESTS-FICTIFS/snapshot-v5'));
 await copy(path.join(windows,'INSTALLATION-SQL.md'),path.join(packageRoot,'INSTALLATION-SQL-NEUF.md'));
 for(const name of ['00-MISE-A-JOUR.txt','COMMENCER-ICI.txt','LIRE-MOI.md'])
  await copy(path.join(windows,'MISE-A-JOUR-ARMATEURS-SESSION.txt'),path.join(packageRoot,name));
 const files=[];
 async function collect(dir){for(const entry of await fs.readdir(dir,{withFileTypes:true})){
  const file=path.join(dir,entry.name);if(entry.isDirectory())await collect(file);else files.push({path:path.relative(packageRoot,file).split(path.sep).join('/'),sha256:hash(await fs.readFile(file))});
 }}await collect(packageRoot);
 if(files.some(f=>/(^|\/)(\.state|\.env[^/]*|runtime\.env|appsettings\.(Local|Production)\.json)(\/|$)|\.secret$|\.bak$/i.test(f.path)))throw Error('Private state/configuration cannot be packaged.');
 await fs.writeFile(path.join(packageRoot,'RUNTIME.json'),JSON.stringify({release,target:'http://172.17.18.208:9091/',sqlTarget:'PRD-DB-ZENATA:54013/toszps',nodeVersion:process.version,backend:'sqlserver',requiredSchema:6,main_sha256:mainHash,backendCompilation:'required-on208',smtpDriverIncluded:false,realBusinessDataIncluded:false,sourceDataRequired:false,freshLocalAdminSupported:true,sessionPersistence:'browser-tab-server-validated',operatorCatalogueCount:92,operatorGuide:'00-MISE-A-JOUR.txt',sourceFrozen:false,remoteDeployment:false,files},null,2));
 await fs.writeFile(path.join(qa,'sql-application-runtime-stage.json'),JSON.stringify({stage,packageRoot,release,mainHash,files:files.length+1},null,2));
 console.log(JSON.stringify({stage,packageRoot,release,mainHash,files:files.length+1}));
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
