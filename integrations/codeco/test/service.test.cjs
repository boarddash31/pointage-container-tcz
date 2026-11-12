'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs/promises'),path=require('node:path');
const {CodecoService,FileCache}=require('../service.cjs');
const {createServer}=require('../server.cjs');
const {config,request,row}=require('./fixtures.cjs');
const memory=()=>{const values=new Map();return {get:async k=>values.get(k),put:async(k,v)=>{values.set(k,v);return v;}};};
test('simultaneous requests share extraction and replays use the first completed snapshot',async()=>{
  let calls=0;const source={fetch:async()=>{calls++;return [row()];}},service=new CodecoService(config,source,memory());
  const [first,parallel]=await Promise.all([service.process(request),service.process(request)]);
  assert.equal(first.xml,parallel.xml);assert.equal(calls,1);
  source.fetch=async()=>{throw Error('must not query a changing source for a replay');};
  assert.equal((await service.process(request)).cached,true);
  assert.equal((await service.process({...request,messageType:'COARRI'})).ignored,true);
});
test('private cache survives service restart and detects changed configuration or tampered XML',async()=>{
  const directory=await fs.mkdtemp(path.resolve(__dirname,'../../../.qa/codeco-cache-'));
  const cache=new FileCache(directory),service=new CodecoService(config,{fetch:async()=>[row()]},cache);
  const prepared=await service.process(request);
  const restarted=new CodecoService(config,{fetch:async()=>{throw Error('no requery');}},cache);
  assert.equal((await restarted.process(request)).xml,prepared.xml);
  const changed=new CodecoService({...config,requireWeights:false},{fetch:async()=>[]},cache);
  await assert.rejects(changed.process(request),/cached_response_mismatch/);
  const file=path.join(directory,prepared.key+'.json'),value=JSON.parse(await fs.readFile(file,'utf8'));
  value.xml='tampered';await fs.writeFile(file,JSON.stringify(value));
  await assert.rejects(restarted.process(request),/cached_response_mismatch/);
});
test('internal HTTP API authenticates, refuses unrelated requests and never publishes JMS itself',async t=>{
  const records=[],service=new CodecoService(config,{fetch:async()=>[row()]},memory()),token='TEST_ONLY_'.repeat(5);
  const server=createServer(service,token,record=>records.push(record));await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  t.after(()=>new Promise(resolve=>server.close(resolve)));
  const base='http://127.0.0.1:'+server.address().port;
  const post=(body,secret=token)=>fetch(base+'/internal/codeco/responses',{method:'POST',headers:{authorization:'Bearer '+secret,'content-type':'application/json',connection:'close'},body:JSON.stringify(body)});
  assert.equal((await post(request,'WRONG')).status,401);
  const response=await post(request);assert.equal(response.status,200);assert.ok((await response.text()).includes('<ContainerDepartureConfirmations>'));
  assert.equal((await post({...request,clientId:'OTHER'})).status,204);
  assert.equal((await post({...request,rangeFrom:'invalid'})).status,422);
  assert.ok(records.some(r=>r.event==='response_prepared'&&r.count===1));
  assert.ok(!JSON.stringify(records).includes(token));assert.ok(!JSON.stringify(records).includes('CSQU3054383'));
});
test('empty reply policy and missing weights cause a visible failure, without a partial XML response',async()=>{
  const empty=new CodecoService({...config,emptyResponsePolicy:'reject'},{fetch:async()=>[]},memory());
  await assert.rejects(empty.process(request),/empty_response_contract_unconfirmed/);
  const bad=row();bad.metadata={};
  const service=new CodecoService(config,{fetch:async()=>[row(),{...bad,event_id:'2'}]},memory());
  await assert.rejects(service.process(request),/booking_reference_required/);
});
