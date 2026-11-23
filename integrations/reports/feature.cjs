'use strict';
const fs=require('node:fs/promises'),path=require('node:path');
const {Store}=require('./store.cjs'),{Source}=require('./source.cjs'),{createMailer}=require('./mailer.cjs'),{Worker}=require('./worker.cjs');
const {ReportsError,checkJob,reportWindow}=require('./calendar.cjs');
const {reportData,workbook}=require('./workbook.cjs');
const uuid=/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i;
const json=(res,status,value)=>res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'}).end(JSON.stringify(value));
async function body(req){let size=0;const parts=[];for await(const chunk of req){size+=chunk.length;if(size>65536)throw new ReportsError('request_too_large',413);parts.push(chunk);}
 try{return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(parts)));}catch{throw new ReportsError('invalid_json',400);}}
function createReports({directory,webRoot,log=()=>{},store=new Store(directory,{webRoot}),source=process.env.POINTAGE_BACKEND==='sqlserver'?new (require('./sql-source.cjs').SqlSource)():new Source(),mailer=createMailer()}={}){
 const worker=new Worker(store,source,mailer,log);
 const ready=()=>({source:source.configured,smtp:!!store.smtp().host,smtp_driver:mailer.available});
 let previews=0;
 return {worker,store,start:()=>worker.start(),stop:()=>worker.stop(),
  async handle(req,res){
   const route=new URL(req.url,'http://runtime.invalid').pathname;if(route!=='/api/reports'&&!route.startsWith('/api/reports/'))return false;
   try{
    const authorization=req.headers.authorization??'';if(!authorization.startsWith('Bearer '))throw new ReportsError('authentication_required',401);
    const token=authorization.slice(7),actor=await source.authorize(token),method=req.method;
    if(method==='GET'&&route==='/api/reports/state'){json(res,200,{smtp:store.smtp(),jobs:store.jobs(),runs:store.runs(),ready:ready()});return true;}
    if(method==='GET'&&route==='/api/reports/clients'){json(res,200,await source.clients(token));return true;}
    if(method==='GET'&&route==='/api/reports/operators'){json(res,200,await source.operators(token));return true;}
    if(method==='PUT'&&route==='/api/reports/smtp'){json(res,200,store.saveSmtp(await body(req),actor));return true;}
    if(method==='POST'&&route==='/api/reports/smtp/verify'){
     if(!store.smtp().host)throw new ReportsError('smtp_not_configured');await mailer.verify(store.smtp(true));store.audit(actor,'SMTP_VERIFIED','smtp');json(res,200,{ok:true});return true;
    }
    if(method==='POST'&&route==='/api/reports/jobs'){
     const input=await body(req);if(!input||Object.keys(input).some(k=>!['job','version'].includes(k)))throw new ReportsError('invalid_job');
     json(res,201,store.saveJob(null,input.job,input.version,actor,worker.ready()));return true;
    }
    const jobMatch=route.match(/^\/api\/reports\/jobs\/([^/]+)(\/run)?$/);
    if(jobMatch&&uuid.test(jobMatch[1])){
     if(method==='PUT'&&!jobMatch[2]){const input=await body(req);json(res,200,store.saveJob(jobMatch[1],input.job,input.version,actor,worker.ready()));return true;}
     if(method==='POST'&&jobMatch[2]){if(!worker.ready())throw new ReportsError('configuration_required');const id=store.runNow(jobMatch[1],actor);json(res,202,{id});worker.tick().catch(()=>log('report_failed',{code:'scheduler_error'}));return true;}
    }
    if(method==='POST'&&route==='/api/reports/preview'){
     if(previews)throw new ReportsError('preview_busy',429);previews++;
     try{const job=checkJob(await body(req),{preview:true}),window=reportWindow(job,new Date()),data=reportData(await source.snapshot(window,token,job.client_ids),window,job.client_ids,job.line_id);
      const bytes=await workbook(data,window,job.name,job.layout);store.audit(actor,'REPORT_PREVIEW','preview');
      res.writeHead(200,{'Content-Type':'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','Content-Disposition':'attachment; filename="Zenata-apercu.xlsx"','Cache-Control':'no-store'}).end(bytes);
     }finally{previews--;}return true;
    }
    const runMatch=route.match(/^\/api\/reports\/runs\/([^/]+)\/(download|retry)$/);
    if(runMatch&&uuid.test(runMatch[1])){
     const id=runMatch[1];
     if(method==='POST'&&runMatch[2]==='retry'){
      if(!worker.ready())throw new ReportsError('configuration_required');
      const result=store.db.prepare("UPDATE runs SET state='queued',finished_at=NULL,error_code=NULL,owner=NULL WHERE id=? AND state='failed'").run(id);
      if(!result.changes)throw new ReportsError('retry_not_allowed',409);store.audit(actor,'RUN_RETRIED',id);json(res,202,{id});return true;
     }
     if(method==='GET'&&runMatch[2]==='download'){
      if(!store.artifact(id))throw new ReportsError('not_found',404);
      const directory=await fs.realpath(path.join(store.directory,'artifacts')),file=await fs.realpath(path.join(directory,id+'.xlsx'));
      if(!file.startsWith(directory+path.sep))throw new ReportsError('access_denied',403);
      const bytes=await fs.readFile(file);res.writeHead(200,{'Content-Type':'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','Content-Disposition':`attachment; filename="Zenata-${id}.xlsx"`,'Cache-Control':'no-store'}).end(bytes);return true;
     }
    }
    json(res,404,{error:'not_found'});
   }catch(error){const status=error instanceof ReportsError?error.status:503,code=error instanceof ReportsError?error.code:'reports_unavailable';
    if(!res.headersSent)json(res,status,{error:code});else res.destroy();
   }return true;
  },
 };
}
module.exports={createReports};
