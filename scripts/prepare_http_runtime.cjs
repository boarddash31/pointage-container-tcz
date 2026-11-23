'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'..'),web=path.join(root,'app/build/web');
const hash=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const release=JSON.parse(fs.readFileSync(path.join(web,'release.json'),'utf8'));
if(hash(path.join(web,'main.dart.js'))!==release.bundle_sha256)throw Error('Build/release mismatch');
const stage=fs.mkdtempSync(path.join(root,'.qa/zenata-http-runtime-20261120-'));
function copy(source,dest){const stat=fs.lstatSync(source);if(stat.isSymbolicLink())throw Error('Unexpected symlink');
  if(stat.isDirectory()){fs.mkdirSync(dest,{recursive:true});for(const name of fs.readdirSync(source)){
    if(name.startsWith('.')||['downloads','_worker.js','_headers','_redirects','web.config'].includes(name)||/\.(apk|map)$/i.test(name))continue;
    copy(path.join(source,name),path.join(dest,name));
  }}else{fs.mkdirSync(path.dirname(dest),{recursive:true});fs.copyFileSync(source,dest);}
}
copy(web,path.join(stage,'web'));
copy(process.execPath,path.join(stage,'node.exe'));
copy(path.join(root,'.qa/node-v22.14.0-LICENSE'),path.join(stage,'NODE-LICENSE.txt'));
for(const file of ['http-runtime.cjs','runtime-logs.cjs','LANCER.cmd','LANCER-9091.cmd'])copy(path.join(root,'deployment/windows',file),path.join(stage,file));
copy(path.join(root,'deployment/windows/HTTP-RUNTIME.md'),path.join(stage,'LIRE-MOI.txt'));
const files=[];function collect(dir){for(const name of fs.readdirSync(dir)){const f=path.join(dir,name);if(fs.statSync(f).isDirectory())collect(f);else files.push({path:path.relative(stage,f).split(path.sep).join('/'),sha256:hash(f)});}}
collect(stage);
fs.writeFileSync(path.join(stage,'RUNTIME.json'),JSON.stringify({target:'http://172.17.18.208:9091/',nodeVersion:process.version,release:release.release,
  backend:'supabase',sqlServerMigrationComplete:false,remoteDeployment:false,files},null,2));
fs.writeFileSync(path.join(root,'.qa/http-runtime-stage.json'),JSON.stringify({stage,nodeVersion:process.version,files:files.length+1},null,2));
console.log(JSON.stringify({stage,files:files.length+1,nodeVersion:process.version,remoteDeployment:false}));
