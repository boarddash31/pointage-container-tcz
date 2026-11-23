'use strict';
const fs=require('node:fs/promises'),path=require('node:path'),crypto=require('node:crypto');
async function main(){
 await require('./generate_sql_bootstrap_dbeaver.cjs').generate();
 const root=path.resolve(__dirname,'..'),qa=path.join(root,'.qa'),stage=await fs.mkdtemp(path.join(qa,'sql-bootstrap-20261121-'));
 const packageRoot=path.join(stage,'ZENATA-SQL-20261121');await fs.mkdir(path.join(packageRoot,'scripts'),{recursive:true});
 for(const name of ['00_DIAGNOSTIC_RESEAU.sql','00_CONTROLE_CONNEXION.sql','01_INITIALISER_SOCLE.sql','01_INITIALISER_SOCLE_DBEAVER.sql','02_VERIFIER_SOCLE.sql','LISEZ-MOI.md'])await fs.copyFile(path.join(root,'migration/sqlserver/deployment',name),path.join(packageRoot,name));
 for(const name of ['001_schema.sql','002_order_api.sql','005_application_accounts.sql'])await fs.copyFile(path.join(root,'migration/sqlserver',name),path.join(packageRoot,'scripts',name));
 const target=JSON.parse(await fs.readFile(path.join(root,'deployment/windows/target.json'),'utf8'));
 await fs.writeFile(path.join(packageRoot,'cible.json'),JSON.stringify({database:target.databaseServer,phase:'initial-foundation-only',schemaCurrentForAllFeatures:false,sourceDataIncluded:false,ownerReportedSqlConnectionSuccessful:true,sqlAuthenticationTestedByPreparation:false,schemaAppliedByPreparation:false,applicationCutover:false},null,2));
 const files=[];
 async function inventory(dir){for(const item of await fs.readdir(dir,{withFileTypes:true})){
  const file=path.join(dir,item.name);if(item.isDirectory())await inventory(file);
  else files.push({path:path.relative(packageRoot,file).split(path.sep).join('/'),sha256:crypto.createHash('sha256').update(await fs.readFile(file)).digest('hex')});
 }}await inventory(packageRoot);
 await fs.writeFile(path.join(packageRoot,'INTEGRITE.json'),JSON.stringify({preparedOn:'2026-11-21',files},null,2));
 await fs.writeFile(path.join(qa,'sql-bootstrap-stage.json'),JSON.stringify({stage,packageRoot,files:files.length+1},null,2));
 console.log(JSON.stringify({stage,packageRoot,files:files.length+1}));
}main().catch(error=>{console.error(error.message);process.exitCode=1;});
