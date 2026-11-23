'use strict';
// Stages only explicitly allowed source/build files; never state, credentials or node_modules.
const fs=require('node:fs/promises'),path=require('node:path'),crypto=require('node:crypto');
async function main(){
 const root=path.resolve(__dirname,'..'),release='zps-shift-reports-20261120',base=path.join(root,'.qa');
 const stage=await fs.mkdtemp(path.join(base,'reports-update-'));
 const web=path.join(root,'app','build','web');
 const bootstrap=await fs.readFile(path.join(web,'flutter_bootstrap.js'),'utf8');
 if(!bootstrap.includes(release))throw Error('Build web reports release first');
 await fs.cp(web,path.join(stage,'web'),{recursive:true});
 for(const name of ['http-runtime.cjs','runtime-logs.cjs','LANCER.cmd','LANCER-9091.cmd','runtime.env.example'])await fs.copyFile(path.join(root,'deployment','windows',name),path.join(stage,name));
 await fs.mkdir(path.join(stage,'reports'));
 for(const name of ['calendar.cjs','feature.cjs','mailer.cjs','source.cjs','store.cjs','workbook.cjs','worker.cjs','xlsx.cjs','package.json','package-lock.json','README.md'])await fs.copyFile(path.join(root,'integrations','reports',name),path.join(stage,'reports',name));
 const main=await fs.readFile(path.join(web,'main.dart.js'));
 const metadata={release,built_at:new Date().toISOString(),main_sha256:crypto.createHash('sha256').update(main).digest('hex'),smtp_driver_included:false};
 await fs.writeFile(path.join(stage,'web','release.json'),JSON.stringify(metadata,null,2));
 await fs.copyFile(path.join(root,'integrations','reports','README.md'),path.join(stage,'INSTALLATION-RAPPORTS.md'));
 await fs.writeFile(path.join(base,'reports-update-stage.json'),JSON.stringify({stage,release,...metadata},null,2));
 console.log(JSON.stringify({stage,...metadata}));
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
