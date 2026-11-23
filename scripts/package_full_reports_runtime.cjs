'use strict';
const fs=require('node:fs/promises'),path=require('node:path'),crypto=require('node:crypto');
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
async function main(){
 const root=path.resolve(__dirname,'..'),qa=path.join(root,'.qa');
 const manifest=JSON.parse(await fs.readFile(path.join(qa,'reports-update-stage.json'),'utf8'));
 const source=await fs.realpath(manifest.stage),qaRoot=await fs.realpath(qa);
 if(!source.startsWith(qaRoot+path.sep))throw Error('Source must be an internal validated stage');
 if(hash(await fs.readFile(path.join(source,'web/main.dart.js')))!==manifest.main_sha256)throw Error('Web build hash mismatch');
 const release=JSON.parse(await fs.readFile(path.join(source,'web/release.json'),'utf8'));
 if(release.release!==manifest.release||release.main_sha256!==manifest.main_sha256)throw Error('Release mismatch');
 async function check(dir){for(const entry of await fs.readdir(dir,{withFileTypes:true})){
  if(dir===path.join(source,'web')&&entry.isFile()&&['.assetsignore','.last_build_id'].includes(entry.name))continue;
  if(entry.isSymbolicLink()||entry.name.startsWith('.')||['node_modules','runtime.env','smtp-master.key'].includes(entry.name))throw Error('Unexpected private/staged file');
  if(entry.isDirectory())await check(path.join(dir,entry.name));
 }}
 await check(source);
 const stage=await fs.mkdtemp(path.join(qa,'zenata-runtime-complet-9091-'));
 await fs.cp(source,stage,{recursive:true,filter:file=>!['.assetsignore','.last_build_id'].includes(path.basename(file))});
 await fs.copyFile(process.execPath,path.join(stage,'node.exe'));
 await fs.copyFile(path.join(qa,'node-v22.14.0-LICENSE'),path.join(stage,'NODE-LICENSE.txt'));
 await fs.copyFile(path.join(root,'deployment/windows/INSTALLATION-COMPLETE.md'),path.join(stage,'LIRE-MOI.md'));
 const files=[];
 async function inventory(dir){for(const entry of await fs.readdir(dir,{withFileTypes:true})){
  const file=path.join(dir,entry.name);if(entry.isDirectory())await inventory(file);
  else files.push({path:path.relative(stage,file).split(path.sep).join('/'),sha256:hash(await fs.readFile(file))});
 }}
 await inventory(stage);
 await fs.writeFile(path.join(stage,'RUNTIME.json'),JSON.stringify({release:manifest.release,target:'http://172.17.18.208:9091/',nodeVersion:process.version,backend:'supabase',smtpDriverIncluded:false,sqlServerMigrationComplete:false,remoteDeployment:false,files},null,2));
 await fs.writeFile(path.join(qa,'full-reports-runtime-stage.json'),JSON.stringify({stage,release:manifest.release,nodeVersion:process.version,files:files.length+1},null,2));
 console.log(JSON.stringify({stage,release:manifest.release,nodeVersion:process.version,files:files.length+1}));
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
