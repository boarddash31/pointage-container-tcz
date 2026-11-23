'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),http=require('node:http');
const {createSqlProxy}=require('./sql-api-proxy.cjs');
const listen=server=>new Promise(resolve=>server.listen(0,'127.0.0.1',()=>resolve(server.address().port)));
const stop=server=>new Promise(resolve=>server.close(resolve));
test('same-origin SQL proxy forwards local session credentials and replaces spoofed forwarding headers',async()=>{
 let called=0;
 const backend=http.createServer(async(req,res)=>{
  called++;assert.equal(req.url,'/api/visits');assert.equal(req.headers.authorization,'Bearer local-token');
  assert.equal(req.headers['x-forwarded-for'],'127.0.0.1');assert.equal(req.headers['x-pointage-integration-key'],undefined);assert.equal(req.headers.cookie,undefined);
  let body='';for await(const part of req)body+=part;assert.equal(body,'{"sample":true}');
  res.writeHead(201,{'content-type':'application/json'}).end('{"id":"new-visit"}');
 });
 const backendPort=await listen(backend),proxy=createSqlProxy(`http://127.0.0.1:${backendPort}/`);
 const gateway=http.createServer(async(req,res)=>{if(!await proxy.handle(req,res))res.writeHead(404).end();});const port=await listen(gateway);
 try{
  const result=await fetch(`http://127.0.0.1:${port}/api/visits`,{method:'POST',headers:{authorization:'Bearer local-token','x-forwarded-for':'1.2.3.4','x-pointage-integration-key':'forged',cookie:'irrelevant'},body:'{"sample":true}'});
  assert.equal(result.status,201);assert.deepEqual(await result.json(),{id:'new-visit'});
  assert.equal((await fetch(`http://127.0.0.1:${port}/internal/source/report-snapshot`)).status,404);assert.equal(called,1);
 }finally{await stop(gateway);await stop(backend);}
});
test('SQL proxy cannot be configured to forward browser credentials to a remote service',()=>{
 assert.throws(()=>createSqlProxy('http://172.17.18.209:54013/'));
 assert.throws(()=>createSqlProxy('http://user:secret@127.0.0.1:19091/'));
});
