'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {checkJob,nextDue,reportWindow,ReportsError}=require('../calendar.cjs');
const {Store}=require('../store.cjs'),{Worker}=require('../worker.cjs'),{reportData,workbook}=require('../workbook.cjs');
const {Source}=require('../source.cjs'),{createMailer}=require('../mailer.cjs');
const client='00000000-0000-4000-8000-000000000001',other='00000000-0000-4000-8000-000000000002';
const job=()=>({name:'Rapport test',enabled:false,recipients:['ops@example.invalid'],client_ids:[],schedule:{kind:'daily',time:'08:00',timezone:'Africa/Casablanca'},period:'previous_day',hours:24});
const window={from:'2026-11-19T00:00:00Z',to:'2026-11-20T00:00:00Z'};
const snapshot={client_id:client,entry_kind:'loaded',entered_at:window.from,container_number:'TEST0000001',iso_code:'22G1',armateur_id:'MSC',carrier_booking_reference:'ERO1'};
const raw=()=>({clients:[{id:client,name:'Client A'},{id:other,name:'=CMD(1)'}],documents:[{id:'d1',kind:'ENTREE',created_at:window.from,snapshot}],stock:[{container_number:'TEST0000001',client_id:client,armateur_id:'MSC',iso_code:'22G1',arrived_at:window.from,departed_at:null}]});
function store(t){const dir=fs.mkdtempSync(path.join(os.tmpdir(),'zenata-report-test-')),s=new Store(dir);t.after(()=>{s.close();fs.rmSync(dir,{recursive:true,force:true});});return s;}
function smtp(s){s.saveSmtp({version:0,host:'relay.example.invalid',port:25,from:'zenata@example.invalid',security:'relay',username:'',password:'',clear_password:false},'admin');}

test('Morocco periods, monthly last day and missing days',()=>{
 assert.deepEqual(reportWindow(job(),'2026-11-20T08:00Z'),{from:'2026-11-18T23:00:00.000Z',to:'2026-11-19T23:00:00.000Z'});
 assert.equal(nextDue({...job().schedule,kind:'monthly',day:0},'2026-11-20T08:00Z'),'2026-11-30T07:00:00.000Z');
 assert.equal(nextDue({...job().schedule,kind:'monthly',day:31},'2026-11-01T00:00Z'),'2026-12-31T07:00:00.000Z');
 assert.equal(nextDue({kind:'once',timezone:'Africa/Casablanca',at_local:'2026-11-25T08:00'},'2026-11-20T00:00Z'),'2026-11-25T07:00:00.000Z');
 assert.throws(()=>checkJob({...job(),recipients:['a@example.com\r\nBcc:x@example.com']}));
 assert.throws(()=>checkJob({...job(),client_ids:['MSC']}));
 assert.equal(checkJob({...job(),recipients:[]},{preview:true}).recipients.length,0);
 assert.throws(()=>nextDue({kind:'once',timezone:'Africa/Casablanca',at_local:'2026-02-30T08:00'},'2026-01-01'),/invalid_schedule_date/);
});
test('client attribution, twins, empty trucks and exclusive period boundary',()=>{
 const r=raw();r.documents.push({id:'d2',kind:'SORTIE',snapshot:{...snapshot,exited_at:window.from}},{id:'d3',kind:'SORTIE',snapshot:{...snapshot,entry_kind:'empty',exited_at:window.to}});
 r.documents[0].snapshot={...snapshot,is_twin:true,container_number_2:'TEST0000002',iso_code_2:'22G1',armateur_id_2:'MAE'};
 r.stock[0].departed_at=window.to;
 const data=reportData(r,window,[client,other]);assert.equal(data.entries.length,2);assert.equal(data.exits.length,0);assert.equal(data.stock.length,1);assert.equal(data.groups.length,2);
 assert.equal(data.groups.find(g=>g.client==='Client A').entries,2);
 assert.throws(()=>reportData({...r,stock:[r.stock[0],r.stock[0]]},window),/overlapping_stock/);
 assert.throws(()=>reportData({...r,stock:[{...r.stock[0],arrived_at:'bad'}]},window),/invalid_stock_date/);
});
test('completed shift uses its local boundaries, including night and delayed sends',()=>{
 const j={...job(),period:'shift',shift_start:'22:00',shift_end:'06:00'};
 assert.deepEqual(reportWindow(j,'2026-11-20T05:05Z'),{from:'2026-11-19T21:00:00.000Z',to:'2026-11-20T05:00:00.000Z'});
 assert.deepEqual(reportWindow(j,'2026-11-20T04:59Z'),{from:'2026-11-18T21:00:00.000Z',to:'2026-11-19T05:00:00.000Z'});
 assert.throws(()=>reportWindow({...j,shift_start:'06:00'},window.to),/invalid_shift/);
});
test('dedicated report filters each twin slot and stock, never leaking another line',async()=>{
 const r=raw();r.documents[0].snapshot={...snapshot,is_twin:true,container_number_2:'OTHER000002',iso_code_2:'45G1',armateur_id_2:'CMACGM'};
 r.stock.push({...r.stock[0],container_number:'OTHER000002',armateur_id:'CMACGM'});
 r.isoRules=[{iso_code:'22G1',category:'20 DV',size_feet:20,effective_from:'2026-01-01'}];r.evpRules=[{size_feet:20,factor:1,effective_from:'2026-01-01'}];
 const d=reportData(r,window,[],'MSC');assert.equal(d.entries.length,1);assert.equal(d.stock.length,1);
 const bytes=await workbook(d,window,'Rapport MSC','shift_client');assert.ok(!bytes.includes(Buffer.from('OTHER000002')));assert.ok(!bytes.includes(Buffer.from('CMACGM')));assert.ok(bytes.includes(Buffer.from('RECAP')));assert.ok(bytes.includes(Buffer.from('NON CLASSES')));
 assert.throws(()=>checkJob({...job(),layout:'shift_client',line_id:''}),/dedicated_line_required/);
 assert.equal(checkJob({...job(),layout:'shift_client',line_id:'MSC'}).line_id,'MSC');
});
test('real XLSX archive uses inline text, never executable formulas',async()=>{
 const r=raw();r.clients[0].name='=HYPERLINK("evil") < &';const bytes=await workbook(reportData(r,window),window,'Fixture');
 assert.equal(bytes.readUInt32LE(),0x04034b50);assert.ok(bytes.includes(Buffer.from('inlineStr')));assert.ok(!bytes.includes(Buffer.from('<f>')));assert.ok(bytes.includes(Buffer.from('&lt; &amp;')));
});
test('SMTP secret encryption, version conflicts and persistence',t=>{
 const s=store(t);let result=s.saveSmtp({version:0,host:'relay.example.invalid',port:587,from:'zenata@example.invalid',security:'starttls',username:'user',password:'TEST-SECRET-ONLY',clear_password:false},'admin');
 assert.equal(result.has_password,true);assert.ok(!JSON.stringify(result).includes('TEST-SECRET'));assert.equal(s.smtp(true).password,'TEST-SECRET-ONLY');
 assert.ok(!s.db.prepare('SELECT payload FROM config').get().payload.includes('TEST-SECRET'));
 const {has_password,...settings}=result;
 assert.throws(()=>s.saveSmtp({...settings,password:'',clear_password:false,version:0},'admin'),/version_conflict/);
 const saved=s.saveJob(null,job(),0,'admin',false);const second=new Store(s.directory);assert.equal(second.job(saved.id).name,'Rapport test');assert.equal(second.smtp(true).password,'TEST-SECRET-ONLY');second.close();
});
test('durable slots, single worker claim, pause cancels extraction, uncertain delivery recovery',t=>{
 const s=store(t),j=s.saveJob(null,{...job(),enabled:true},0,'admin',true);
 s.db.prepare('UPDATE jobs SET next_due=? WHERE id=?').run('2026-11-20T07:00:00.000Z',j.id);
 assert.equal(s.enqueueDue(new Date('2026-11-20T07:01Z')),1);assert.equal(s.enqueueDue(new Date('2026-11-20T07:01Z')),0);
 const run=s.claim('one');assert.ok(run);assert.equal(s.claim('two'),undefined);
 s.saveJob(j.id,job(),j.version,'admin',true);assert.equal(s.sending(run.id,'one','x.xlsx',{}),false);
 const manual=s.runNow(j.id,'admin');s.claim('one');s.sending(manual,'one','x.xlsx',{});
 s.db.prepare('UPDATE runs SET lease_until=? WHERE id=?').run('2020-01-01',manual);s.recover();
 assert.equal(s.runs().find(r=>r.id===manual).state,'delivery_unknown');assert.equal(s.claim('two'),undefined);
});
test('worker sends one attachment and never retries an ambiguous SMTP failure',async t=>{
 const s=store(t);smtp(s);const j=s.saveJob(null,job(),0,'admin',true);const id=s.runNow(j.id,'admin');let sends=0;
 const worker=new Worker(s,{configured:true,snapshot:async()=>raw()},{available:true,send:async(c,m)=>{sends++;assert.ok(Buffer.isBuffer(m.attachment));throw new Error('socket interrupted');}});
 await Promise.all([worker.tick(),worker.tick()]);await worker.tick();assert.equal(sends,1);assert.equal(s.runs().find(r=>r.id===id).state,'delivery_unknown');worker.stop();
});
test('successful manual report persists counts, attachment and accepted status',async t=>{
 const s=store(t);smtp(s);const j=s.saveJob(null,job(),0,'admin',true),id=s.runNow(j.id,'admin');let sends=0;
 const worker=new Worker(s,{configured:true,snapshot:async w=>{const r=raw();r.documents[0].snapshot={...snapshot,entered_at:w.from};r.stock[0].arrived_at=w.from;return r;}},{available:true,send:async()=>{sends++;return {accepted:1,rejected:0};}});
 await worker.tick();await worker.tick();const run=s.runs().find(r=>r.id===id);
 assert.equal(sends,1);assert.equal(run.state,'accepted');assert.equal(run.summary.entries,1);assert.equal(run.summary.stock,1);assert.ok(fs.existsSync(path.join(s.directory,'artifacts',id+'.xlsx')));worker.stop();
});
test('SMTP driver enforces TLS, no file access, private envelope and accepted counts',async()=>{
 let options,message;
 const mailer=createMailer({createTransport:o=>{options=o;return {verify:async()=>{},sendMail:async m=>{message=m;return {accepted:m.envelope.to,rejected:[]};},close(){}};}});
 const result=await mailer.send({host:'smtp.test',port:587,security:'starttls',from:'sender@example.invalid',username:'u',password:'p'},{...job(),id:'run1',scheduledAt:window.to,window,attachment:Buffer.from('test')});
 assert.equal(options.requireTLS,true);assert.equal(options.tls.rejectUnauthorized,true);assert.equal(options.disableFileAccess,true);assert.deepEqual(message.envelope.to,job().recipients);assert.equal(message.attachments[0].contentType,'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');assert.equal(result.accepted,1);
});
test('admin authorization verifies active profile and database role, ignores user_metadata',async()=>{
 const fetcher=async url=>({ok:true,text:async()=>JSON.stringify(url.includes('/auth/')?{id:client,user_metadata:{role:'admin'}}:url.includes('/profiles?')?[{active:true}]:[{role:'entree'}])});
 await assert.rejects(new Source({fetcher}).authorize('token'),e=>e instanceof ReportsError&&e.code==='admin_required');
 const source=new Source({fetcher:async url=>({ok:true,text:async()=>JSON.stringify(url.includes('/auth/')?{id:client}:url.includes('/profiles?')?[{active:true}]:[{role:'admin'}])})});
 assert.equal(await source.authorize('token'),client);
});
test('pagination exceeds a single 1000-row page with bounded data',async()=>{
 const source=new Source();let calls=0;source.request=async endpoint=>{calls++;assert.ok(endpoint.includes('limit=1000'));return calls===1?Array.from({length:1000},(_,i)=>({id:`00000000-0000-4000-8000-${String(i).padStart(12,'0')}`})):[{id:other}];};
 assert.equal((await source.clients('token')).length,1001);assert.equal(calls,2);
});
