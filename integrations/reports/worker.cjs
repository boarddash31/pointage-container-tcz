'use strict';
const fs=require('node:fs/promises'),path=require('node:path'),crypto=require('node:crypto');
const {ReportsError}=require('./calendar.cjs');
const {reportData,workbook}=require('./workbook.cjs');
class Worker{
 constructor(store,source,mailer,log=()=>{}){this.store=store;this.source=source;this.mailer=mailer;this.log=log;this.owner=crypto.randomUUID();this.busy=false;this.timer=null;this.stopped=false;}
 ready(){return this.source.configured&&this.mailer.available&&!!this.store.smtp().host;}
 async tick(){
  if(this.busy||this.stopped)return;this.busy=true;
  try{
   this.store.recover();if(!this.ready())return;this.store.enqueueDue();
   const run=this.store.claim(this.owner);if(!run)return;
   const heartbeat=setInterval(()=>{try{this.store.heartbeat(run.id,this.owner);}catch{}},15000);heartbeat.unref();
   let sending=false;
   try{
    this.log('report_started',{run_id:run.id});
    const {job,window}=JSON.parse(run.payload),raw=await this.source.snapshot(window,undefined,job.client_ids),data=reportData(raw,window,job.client_ids,job.line_id),attachment=await workbook(data,window,job.name,job.layout);
    const directory=path.join(this.store.directory,'artifacts');await fs.mkdir(directory,{recursive:true});
    const temporary=path.join(directory,run.id+'.'+crypto.randomUUID()+'.tmp'),artifact=run.id+'.xlsx';
    await fs.writeFile(temporary,attachment,{flag:'wx',mode:0o600});await fs.rename(temporary,path.join(directory,artifact));
    const summary={entries:data.entries.length,exits:data.exits.length,stock:data.stock.length,clients:data.groups.length};
    if(!this.store.sending(run.id,this.owner,artifact,summary))return;
    sending=true;
    const delivery=await this.mailer.send(this.store.smtp(true),{...job,id:run.id,scheduledAt:run.scheduled_at,window,attachment});
    const state=delivery.rejected||delivery.accepted!==job.recipients.length?'partial':'accepted';
    this.store.finish(run.id,this.owner,state,null,{...summary,...delivery});this.log('report_finished',{run_id:run.id,reason:state});
   }catch(error){
    const uncertain=sending&&error.deliveryUncertain!==false;
    const code=error instanceof ReportsError?error.code:'report_failed';
    this.store.finish(run.id,this.owner,uncertain?'delivery_unknown':'failed',code);
    this.log('report_failed',{run_id:run.id,code});
   }finally{clearInterval(heartbeat);}
  }finally{this.busy=false;}
 }
 start(){if(this.timer)return;this.timer=setInterval(()=>this.tick().catch(()=>this.log('report_failed',{code:'scheduler_error'})),15000);this.timer.unref();this.tick().catch(()=>this.log('report_failed',{code:'scheduler_error'}));}
 stop(){this.stopped=true;clearInterval(this.timer);this.timer=null;}
}
module.exports={Worker};
