'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs/promises'),path=require('node:path'),os=require('node:os');
const {createServer}=require('../../../deployment/windows/http-runtime.cjs'),{createReports}=require('../feature.cjs'),{ReportsError}=require('../calendar.cjs');
test('same-origin API requires admin, protects credentials and generates an Excel preview without SMTP',async t=>{
 const directory=await fs.mkdtemp(path.join(os.tmpdir(),'zenata-reports-api-')),webRoot=path.join(directory,'web');await fs.mkdir(webRoot);await fs.writeFile(path.join(webRoot,'index.html'),'ok');
 const feature=createReports({directory:path.join(directory,'private'),webRoot,source:{configured:false,authorize:async token=>{if(token!=='fixture-admin')throw new ReportsError('admin_required',403);return 'fixture-user';},clients:async()=>[],snapshot:async w=>({clients:[],documents:[],stock:[{container_number:'MSC_ONLY',armateur_id:'MSC',iso_code:'22G1',arrived_at:w.from},{container_number:'CMA_ONLY',armateur_id:'CMACGM',iso_code:'22G1',arrived_at:w.from}]})},mailer:{available:false}});
 const server=createServer(webRoot,()=>{},feature);await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 t.after(async()=>{feature.stop();await new Promise(resolve=>server.close(resolve));feature.store.close();await fs.rm(directory,{recursive:true,force:true});});
 const base='http://127.0.0.1:'+server.address().port,headers={authorization:'Bearer fixture-admin','content-type':'application/json'};
 assert.equal((await fetch(base+'/api/reports/state')).status,401);
 assert.equal((await fetch(base+'/api/reports/state',{headers:{authorization:'Bearer clerk'}})).status,403);
 const result=await(await fetch(base+'/api/reports/state',{headers})).json();assert.equal(result.ready.smtp_driver,false);assert.equal(result.smtp.password,undefined);
 const job={name:'Preview',enabled:false,recipients:[],client_ids:[],schedule:{kind:'daily',time:'08:00',timezone:'Africa/Casablanca'},period:'previous_day'};
 const preview=await fetch(base+'/api/reports/preview',{method:'POST',headers,body:JSON.stringify(job)});assert.equal(preview.status,200);assert.match(preview.headers.get('content-type'),/spreadsheetml/);assert.equal(Buffer.from(await preview.arrayBuffer()).readUInt32LE(),0x04034b50);
 const save=await fetch(base+'/api/reports/jobs',{method:'POST',headers,body:JSON.stringify({version:0,job:{...job,enabled:true,recipients:['test@example.invalid']}})});assert.equal(save.status,422);assert.equal((await save.json()).error,'configuration_required');
 const dedicated=await fetch(base+'/api/reports/preview',{method:'POST',headers,body:JSON.stringify({...job,layout:'shift_client',line_id:'MSC'})});assert.equal(dedicated.status,200);
 const dedicatedBytes=Buffer.from(await dedicated.arrayBuffer());assert.ok(dedicatedBytes.includes(Buffer.from('MSC_ONLY')));assert.ok(!dedicatedBytes.includes(Buffer.from('CMA_ONLY')));assert.ok(!dedicatedBytes.includes(Buffer.from('CMACGM')));
 for(const route of ['/private/reports.sqlite','/.state/reports/smtp-master.key','/reports/feature.cjs'])assert.notEqual((await fetch(base+route)).status,200);
});
