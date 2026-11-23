'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {createLogger}=require('./runtime-logs.cjs');
const {createServer}=require('./http-runtime.cjs');
const temporary=()=>fs.mkdtempSync(path.resolve(__dirname,'../../.qa/runtime-logs-test-'));
test('logs rotate by size/day, retain only their own files and close cleanly',()=>{
  const directory=temporary();fs.writeFileSync(path.join(directory,'keep.txt'),'unrelated file');
  let date=new Date('2026-11-20T10:00:00Z');
  const logger=createLogger(directory,{maxBytes:256,maxFiles:2,now:()=>date});
  for(let n=0;n<12;n++)assert.equal(logger.log('http_request',{request_id:'id-'+n,status:200}),true);
  let files=fs.readdirSync(directory).filter(n=>n.endsWith('.jsonl'));
  assert.equal(files.length,2);for(const f of files)assert.ok(fs.statSync(path.join(directory,f)).size<=256);
  date=new Date('2026-11-21T00:00:01Z');logger.log('startup',{port:9091});logger.close();
  files=fs.readdirSync(directory).filter(n=>n.endsWith('.jsonl'));assert.equal(files.length,2);
  assert.ok(files.some(n=>n.includes('2026-11-21')));assert.equal(fs.readFileSync(path.join(directory,'keep.txt'),'utf8'),'unrelated file');
  assert.equal(logger.log('startup'),false);logger.close();
});
test('logging directory cannot be inside the public web root',()=>{
  const web=temporary();assert.throws(()=>createLogger(path.join(web,'logs'),{webRoot:web}),/outside web/);
});
test('request logs have status/duration/correlation without query, path secrets, headers or body',async t=>{
  const directory=temporary(),web=path.join(directory,'web'),logs=path.join(directory,'logs');fs.mkdirSync(web);
  fs.writeFileSync(path.join(web,'index.html'),'<html>test</html>');
  const logger=createLogger(logs,{webRoot:web});const server=createServer(web,(event,fields)=>logger.log(event,fields));
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  t.after(()=>new Promise(resolve=>server.close(()=>{logger.close();resolve();})));
  const base='http://127.0.0.1:'+server.address().port;
  const response=await fetch(base+'/?access_token=SECRET_QUERY&password=SECRET_PASSWORD',{
    headers:{authorization:'Bearer SECRET_HEADER',cookie:'SECRET_COOKIE','x-request-id':'ATTACKER_ID'},
  });await response.text();
  await fetch(base+'/SECRET_PATH.js?token=SECRET_URL');
  await fetch(base+'/',{method:'POST',body:'SECRET_BODY'});
  logger.log('fatal_error',{code:'TEST',message:'SECRET_MESSAGE',stack:'SECRET_STACK'});
  const raw=fs.readdirSync(logs).map(f=>fs.readFileSync(path.join(logs,f),'utf8')).join('');
  assert.ok(!raw.includes('SECRET_'));assert.ok(!raw.includes('ATTACKER_ID'));
  const records=raw.trim().split('\n').map(line=>JSON.parse(line));
  const first=records.find(r=>r.event==='http_request'&&r.status===200);
  assert.equal(first.request_id,response.headers.get('x-request-id'));assert.equal(first.resource,'index.html');
  assert.ok(first.duration_ms>=0);assert.ok(records.some(r=>r.status===404));assert.ok(records.some(r=>r.status===405));
});
