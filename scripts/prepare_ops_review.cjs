'use strict';
// Prepares a private IT review directory. Does not deploy, run SQL or publish.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'..'),build=path.join(root,'app/build/web');
const read=file=>fs.readFileSync(file,'utf8');
if(!fs.existsSync(path.join(build,'main.dart.js')))throw Error('Build Flutter web first.');
const checksum=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const marker='zps-ops-20261116';
// Only static bootstrap/index content changed after the last Dart compilation.
fs.writeFileSync(path.join(build,'index.html'),read(path.join(root,'app/web/index.html')).replace('$FLUTTER_BASE_HREF','/'));
fs.writeFileSync(path.join(build,'flutter_bootstrap.js'),read(path.join(build,'flutter_bootstrap.js')).replace("const release = 'marsa-bons-v1';",`const release = '${marker}';`));
if(!read(path.join(build,'flutter_bootstrap.js')).includes(`const release = '${marker}';`))throw Error('Unexpected Flutter bootstrap.');
const release={release:marker,application_version:'3.1.1+3',status:'local-ops-review',
  bundle_sha256:checksum(path.join(build,'main.dart.js')),prepared_for_ip:'172.17.18.208',
  backend:'supabase',database_update_required:true,remote_deployment:false,
  features:['zps-brand','three-form-sections','visit-history','stock-picker','damage-reservations','container-blocks',
    'twin-seals','a5-three-gate-out-copies','automatic-closure-after-deposit','no-demurrage-control']};
fs.writeFileSync(path.join(build,'release.json'),JSON.stringify(release,null,2));
const stage=fs.mkdtempSync(path.join(root,'.qa/ops-it-20261116-'));
function copy(source,destination,accept=()=>true){
  const stat=fs.lstatSync(source);if(stat.isSymbolicLink())throw Error('Unexpected symbolic link.');
  if(stat.isDirectory()){
    fs.mkdirSync(destination,{recursive:true});
    for(const name of fs.readdirSync(source))if(accept(name))copy(path.join(source,name),path.join(destination,name),accept);
  }else{fs.mkdirSync(path.dirname(destination),{recursive:true});fs.copyFileSync(source,destination);}
}
copy(build,path.join(stage,'web'),name=>!name.startsWith('.')&&!['_worker.js','_headers','_redirects','downloads','200.html'].includes(name)&&!name.endsWith('.map')&&!name.endsWith('.apk'));
copy(path.join(root,'changes/ops-20261116/web.config'),path.join(stage,'web/web.config'));
copy(path.join(root,'changes/ops-20261116'),path.join(stage,'changes'));
copy(path.join(root,'supabase/functions/generate-bon'),path.join(stage,'source/supabase/functions/generate-bon'));
for(const dir of ['app/lib','app/test'])copy(path.join(root,dir),path.join(stage,'source',dir));
copy(path.join(root,'app/assets'),path.join(stage,'source/app/assets'));
copy(path.join(root,'app/web'),path.join(stage,'source/app/web'),name=>!name.startsWith('.')&&!['downloads','_worker.js','release.json'].includes(name));
for(const name of ['pubspec.yaml','pubspec.lock','analysis_options.yaml'])
  copy(path.join(root,'app',name),path.join(stage,'source/app',name));
copy(path.join(root,'tests/ops_review.cjs'),path.join(stage,'source/tests/ops_review.cjs'));
for(const file of ['ops-bon-sortie.pdf','ops-bon-decharge.pdf','ops-server-sortie.pdf','ops-server-decharge.pdf','ops-slip-preview.png','ops-login-preview.png'])
  copy(path.join(root,'.qa',file),path.join(stage,'previews',file));
const files=[];
function inventory(dir){for(const name of fs.readdirSync(dir)){const p=path.join(dir,name);if(fs.statSync(p).isDirectory())inventory(p);else files.push({path:path.relative(stage,p).split(path.sep).join('/'),sha256:checksum(p)});}}
inventory(stage);
if(files.some(f=>/(^|\/)(\.env[^/]*|\.git|\.qa|config\.local\.json|_worker\.js)(\/|$)|\.apk$/i.test(f.path)))throw Error('Unexpected private/runtime file in package.');
const metadata={release:marker,target_ip:'172.17.18.208',status:'prepared-for-IT-review',
  database_schema_template_applied:false,edge_function_published:false,remote_deployment:false,files};
fs.writeFileSync(path.join(stage,'IT-REVIEW.json'),JSON.stringify(metadata,null,2));
fs.writeFileSync(path.join(root,'.qa/ops-it-stage.json'),JSON.stringify({stage,release:marker,bundle_sha256:release.bundle_sha256},null,2));
console.log(JSON.stringify({stage,release:marker,files:files.length,bundle_sha256:release.bundle_sha256,remote_deployment:false}));
