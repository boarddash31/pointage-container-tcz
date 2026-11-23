'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {DatabaseSync}=require('node:sqlite');
const {ReportsError,checkJob,nextDue,reportWindow,email}=require('./calendar.cjs');
const fail=(code,status)=>{throw new ReportsError(code,status);};
class Store{
 constructor(directory,{webRoot}={}){
  fs.mkdirSync(directory,{recursive:true});this.directory=fs.realpathSync(directory);
  if(webRoot){const web=fs.realpathSync(webRoot);if(this.directory===web||this.directory.startsWith(web+path.sep))fail('private_state_required');}
  const keyFile=path.join(this.directory,'smtp-master.key');
  try{fs.writeFileSync(keyFile,crypto.randomBytes(32),{flag:'wx',mode:0o600});}catch(e){if(e.code!=='EEXIST')throw e;}
  this.key=fs.readFileSync(keyFile);if(this.key.length!==32)fail('invalid_encryption_key');
  this.db=new DatabaseSync(path.join(this.directory,'reports.sqlite'));
  this.db.exec(`PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000; PRAGMA foreign_keys=ON;
   CREATE TABLE IF NOT EXISTS config(id INTEGER PRIMARY KEY CHECK(id=1),version INTEGER NOT NULL,payload TEXT NOT NULL,actor TEXT NOT NULL,changed_at TEXT NOT NULL);
   CREATE TABLE IF NOT EXISTS jobs(id TEXT PRIMARY KEY,version INTEGER NOT NULL,payload TEXT NOT NULL,enabled INTEGER NOT NULL,next_due TEXT,actor TEXT NOT NULL,changed_at TEXT NOT NULL);
   CREATE TABLE IF NOT EXISTS runs(id TEXT PRIMARY KEY,job_id TEXT NOT NULL REFERENCES jobs(id),slot TEXT NOT NULL,payload TEXT NOT NULL,state TEXT NOT NULL,scheduled_at TEXT NOT NULL,created_at TEXT NOT NULL,finished_at TEXT,owner TEXT,lease_until TEXT,error_code TEXT,artifact TEXT,summary TEXT,UNIQUE(job_id,slot));
   CREATE INDEX IF NOT EXISTS runs_pending ON runs(state,created_at);
   CREATE TABLE IF NOT EXISTS audit(id INTEGER PRIMARY KEY,at TEXT NOT NULL,actor TEXT NOT NULL,action TEXT NOT NULL,entity TEXT NOT NULL);`);
 }
 transaction(fn){this.db.exec('BEGIN IMMEDIATE');try{const result=fn();this.db.exec('COMMIT');return result;}catch(e){this.db.exec('ROLLBACK');throw e;}}
 audit(actor,action,entity){this.db.prepare('INSERT INTO audit(at,actor,action,entity) VALUES(?,?,?,?)').run(new Date().toISOString(),actor,action,entity);}
 encrypt(password){const iv=crypto.randomBytes(12),cipher=crypto.createCipheriv('aes-256-gcm',this.key,iv),value=Buffer.concat([cipher.update(password,'utf8'),cipher.final()]);return [iv,cipher.getAuthTag(),value].map(b=>b.toString('base64')).join('.');}
 decrypt(value){if(!value)return '';const [iv,tag,body]=value.split('.').map(v=>Buffer.from(v,'base64'));const d=crypto.createDecipheriv('aes-256-gcm',this.key,iv);d.setAuthTag(tag);return Buffer.concat([d.update(body),d.final()]).toString('utf8');}
 smtp(privateValue=false){const row=this.db.prepare('SELECT * FROM config WHERE id=1').get();if(!row)return {version:0,host:'',port:587,from:'',security:'starttls',username:'',has_password:false};
  const c=JSON.parse(row.payload),password=privateValue?this.decrypt(c.password_cipher):undefined;
  delete c.password_cipher;return {...c,version:row.version,...(privateValue?{password}:{})};}
 saveSmtp(input,actor){
  if(!input||Object.keys(input).some(k=>!['version','host','port','from','security','username','password','clear_password'].includes(k)))fail('invalid_smtp');
  if(typeof input.host!=='string'||input.host.length>253||!/^[a-zA-Z0-9.:-]+$/.test(input.host)||!Number.isInteger(input.port)||input.port<1||input.port>65535||!email(input.from)||!['starttls','tls','relay'].includes(input.security))fail('invalid_smtp');
  if(typeof input.username!=='string'||input.username.length>254||/[\r\n]/.test(input.username)||typeof input.password!=='string'||input.password.length>1000||typeof input.clear_password!=='boolean')fail('invalid_smtp');
  if(input.security==='relay'&&(input.username||input.password))fail('smtp_auth_requires_tls');
  return this.transaction(()=>{const old=this.db.prepare('SELECT * FROM config WHERE id=1').get();if((old?.version??0)!==input.version)fail('version_conflict',409);
   const previous=old?JSON.parse(old.payload):{};
   const secret=input.security==='relay'||input.clear_password?'':input.password?this.encrypt(input.password):previous.password_cipher??'';
   if(input.username&&!secret)fail('smtp_password_required');
   const c={host:input.host,port:input.port,from:input.from,security:input.security,username:input.username,has_password:!!secret,password_cipher:secret};
   this.db.prepare('INSERT INTO config VALUES(1,?,?,?,?) ON CONFLICT(id) DO UPDATE SET version=excluded.version,payload=excluded.payload,actor=excluded.actor,changed_at=excluded.changed_at').run(input.version+1,JSON.stringify(c),actor,new Date().toISOString());
   this.audit(actor,'SMTP_UPDATED','smtp');return this.smtp();});
 }
 jobs(){return this.db.prepare('SELECT * FROM jobs ORDER BY changed_at DESC').all().map(r=>({...JSON.parse(r.payload),id:r.id,version:r.version,enabled:!!r.enabled,next_due:r.next_due}));}
 job(id){return this.jobs().find(j=>j.id===id)??null;}
 saveJob(id,input,version,actor,ready){const job=checkJob(input);if(job.enabled&&!ready)fail('configuration_required');
  if(job.enabled&&job.schedule.kind==='once'&&!nextDue(job.schedule,new Date()))fail('schedule_in_past');
  return this.transaction(()=>{const old=id?this.db.prepare('SELECT * FROM jobs WHERE id=?').get(id):null;
   if(id&&!old)fail('not_found',404);if((old?.version??0)!==version)fail('version_conflict',409);
   id=id??crypto.randomUUID();const next=job.enabled?nextDue(job.schedule,new Date()):null;
   this.db.prepare('INSERT INTO jobs VALUES(?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET version=excluded.version,payload=excluded.payload,enabled=excluded.enabled,next_due=excluded.next_due,actor=excluded.actor,changed_at=excluded.changed_at').run(id,version+1,JSON.stringify(job),job.enabled?1:0,next,actor,new Date().toISOString());
   this.db.prepare("UPDATE runs SET state='canceled',finished_at=? WHERE job_id=? AND state IN ('queued','extracting')").run(new Date().toISOString(),id);
   this.audit(actor,'JOB_SAVED',id);return this.job(id);});
 }
 enqueue(job,due,slot,actor){const id=crypto.randomUUID(),window=reportWindow(job,due);
  this.db.prepare("INSERT OR IGNORE INTO runs(id,job_id,slot,payload,state,scheduled_at,created_at) VALUES(?,?,?,?,'queued',?,?)").run(id,job.id,slot,JSON.stringify({job,window,actor}),due,new Date().toISOString());return id;}
 runNow(id,actor){return this.transaction(()=>{const job=this.job(id);if(!job)fail('not_found',404);this.audit(actor,'RUN_REQUESTED',id);return this.enqueue(job,new Date().toISOString(),'manual:'+crypto.randomUUID(),actor);});}
 enqueueDue(now=new Date()){
  return this.transaction(()=>{let count=0;if(this.db.prepare("SELECT count(*) n FROM runs WHERE state IN ('queued','extracting','sending')").get().n>=1000)return 0;
   for(const row of this.db.prepare('SELECT * FROM jobs WHERE enabled=1 AND next_due<=? ORDER BY next_due LIMIT 10').all(now.toISOString())){
    const job={...JSON.parse(row.payload),id:row.id};let due=row.next_due;
    while(due&&due<=now.toISOString()&&count<10){this.enqueue(job,due,due,'scheduler');due=nextDue(job.schedule,due);count++;}
    this.db.prepare('UPDATE jobs SET next_due=?,enabled=? WHERE id=?').run(due,due?1:0,row.id);
   }return count;
  });
 }
 recover(now=new Date()){
  this.db.prepare("UPDATE runs SET state=CASE WHEN state='sending' THEN 'delivery_unknown' ELSE 'failed' END,error_code='worker_interrupted',finished_at=?,owner=NULL WHERE state IN ('extracting','sending') AND lease_until<?").run(now.toISOString(),now.toISOString());
 }
 claim(owner){const now=new Date();return this.db.prepare("UPDATE runs SET state='extracting',owner=?,lease_until=? WHERE id=(SELECT id FROM runs WHERE state='queued' ORDER BY created_at,id LIMIT 1) AND state='queued' RETURNING *").get(owner,new Date(+now+600000).toISOString());}
 heartbeat(id,owner){this.db.prepare("UPDATE runs SET lease_until=? WHERE id=? AND owner=? AND state IN ('extracting','sending')").run(new Date(Date.now()+600000).toISOString(),id,owner);}
 sending(id,owner,artifact,summary){return this.db.prepare("UPDATE runs SET state='sending',artifact=?,summary=? WHERE id=? AND owner=? AND state='extracting'").run(artifact,JSON.stringify(summary),id,owner).changes===1;}
 finish(id,owner,state,errorCode=null,summary=null){this.db.prepare("UPDATE runs SET state=?,error_code=?,finished_at=?,summary=COALESCE(?,summary) WHERE id=? AND owner=? AND state IN ('extracting','sending')").run(state,errorCode,new Date().toISOString(),summary?JSON.stringify(summary):null,id,owner);}
 runs(){return this.db.prepare('SELECT id,job_id,payload,state,scheduled_at,created_at,finished_at,error_code,summary,artifact FROM runs ORDER BY created_at DESC,id DESC LIMIT 200').all().map(({payload,...r})=>({...r,name:JSON.parse(payload).job.name,window:JSON.parse(payload).window,artifact:!!r.artifact,summary:r.summary?JSON.parse(r.summary):null}));}
 artifact(id){const run=this.db.prepare('SELECT artifact FROM runs WHERE id=?').get(id);return run?.artifact??null;}
 close(){this.db.close();}
}
module.exports={Store};
