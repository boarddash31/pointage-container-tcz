'use strict';
const fs=require('node:fs/promises'),path=require('node:path'),crypto=require('node:crypto');
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
async function main(){
 await require('./generate_sql_gate_upgrade.cjs').generate();
 const root=path.resolve(__dirname,'..'),qa=path.join(root,'.qa');
 const stage=await fs.mkdtemp(path.join(qa,'backend-validation-208-'));
 const packageRoot=path.join(stage,'ZENATA-BACKEND-VALIDATION');
 const projects=['Pointage.Api','Pointage.Checks','Pointage.Migration','Pointage.Admin'];
 for(const project of projects){
  const destination=path.join(packageRoot,'backend',project);await fs.mkdir(destination,{recursive:true});
  for(const entry of await fs.readdir(path.join(root,'backend',project),{withFileTypes:true})){
   if(!entry.isFile()||!(/\.(cs|csproj)$/.test(entry.name)||project==='Pointage.Api'&&entry.name==='appsettings.json'))continue;
   const source=path.join(root,'backend',project,entry.name);
   if(entry.name==='appsettings.json'){
    const config=JSON.parse(await fs.readFile(source,'utf8'));
    if(config.ConnectionStrings?.Pointage!=='')throw Error('Refusing to package configured connection');
   }
   await fs.copyFile(source,path.join(destination,entry.name));
  }
 }
 await fs.copyFile(path.join(root,'backend/global.json'),path.join(packageRoot,'backend/global.json'));
 const sqlDir=path.join(packageRoot,'migration/sqlserver');await fs.mkdir(sqlDir,{recursive:true});
 for(const name of ['001_schema.sql','002_order_api.sql','003_smoke_test.sql','004_verify_import.sql','005_application_accounts.sql','006_account_smoke_test.sql','008_gate_operations.sql','009_gate_lifecycle.sql','010_gate_smoke_test.sql','011_profile_source_identifiers.sql','manifest.json','manifest-v5.json'])await fs.copyFile(path.join(root,'migration/sqlserver',name),path.join(sqlDir,name));
 await fs.mkdir(path.join(packageRoot,'SQL-RECETTE'),{recursive:true});
 await fs.mkdir(path.join(packageRoot,'SQL-MISE-A-JOUR'),{recursive:true});
 for(const name of ['10_INITIALISER_RECETTE_DBEAVER.sql','11_GATE_RECETTE_DBEAVER.sql','13_TESTER_GATE_DBEAVER.sql'])await fs.copyFile(path.join(root,'migration/sqlserver/deployment',name),path.join(packageRoot,'SQL-RECETTE',name));
 await fs.copyFile(path.join(root,'migration/sqlserver/deployment/12_GATE_TOSZPS_DBEAVER.sql'),path.join(packageRoot,'SQL-MISE-A-JOUR/12_GATE_TOSZPS_DBEAVER.sql'));
 await fs.copyFile(path.join(root,'migration/sqlserver/deployment/GATE-VERSION4.md'),path.join(packageRoot,'ETAPES-GATE.md'));
 const launcher=(await fs.readFile(path.join(root,'deployment/windows/VALIDER-BACKEND.cmd'),'utf8')).replace(/\r?\n/g,'\r\n');
 await fs.writeFile(path.join(packageRoot,'VALIDER-BACKEND.cmd'),launcher);
 await fs.copyFile(path.join(root,'deployment/windows/VALIDATION-BACKEND.md'),path.join(packageRoot,'LIRE-MOI.md'));
 const files=[];
 async function collect(directory){for(const entry of await fs.readdir(directory,{withFileTypes:true})){
  const file=path.join(directory,entry.name);if(entry.isSymbolicLink())throw Error('Unexpected symbolic link');
  if(entry.isDirectory())await collect(file);else files.push({path:path.relative(packageRoot,file).split(path.sep).join('/'),sha256:hash(await fs.readFile(file))});
 }}await collect(packageRoot);
 await fs.writeFile(path.join(packageRoot,'INTEGRITE.json'),JSON.stringify({date:'2026-11-21',purpose:'backend-and-gate-recette',launcher:'build-and-offline-checks-only',databaseScriptsIncluded:true,remoteDeployment:false,files},null,2));
 await fs.writeFile(path.join(qa,'backend-validation-stage.json'),JSON.stringify({stage,packageRoot,files:files.length+1},null,2));
 console.log(JSON.stringify({stage,packageRoot,files:files.length+1}));
}main().catch(error=>{console.error(error.message);process.exitCode=1;});
