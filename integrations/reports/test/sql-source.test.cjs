'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {SqlSource}=require('../sql-source.cjs');
const token='a'.repeat(43),key='k'.repeat(43),actor='11111111-1111-4111-8111-111111111111';
const response=value=>new Response(JSON.stringify(value),{headers:{'content-type':'application/json'}});
test('SQL reporting authenticates normal local sessions and rejects viewer/disabled accounts',async()=>{
 for(const [active,role,success] of [[true,'admin',true],[true,'viewer',false],[false,'admin',false]]){
  const source=new SqlSource({key,fetcher:async(url,options)=>{
   assert.equal(url.origin,'http://127.0.0.1:19091');assert.equal(url.pathname,'/api/me');assert.equal(options.headers.authorization,'Bearer '+token);assert.equal(options.redirect,'error');
   return response({id:actor,active,roles:[{role}]});
  }});
  if(success)assert.equal(await source.authorize(token),actor);else await assert.rejects(source.authorize(token),e=>e.code==='admin_required');
 }
});
test('SQL scheduled snapshots use the scoped internal key; preview uses the real user token',async()=>{
 const routes=[];
 const source=new SqlSource({key,fetcher:async(url,options)=>{
  routes.push(url.pathname);assert.equal(url.hostname,'127.0.0.1');assert.equal(url.searchParams.get('from'),'2026-11-21T00:00:00Z');
  if(url.pathname.startsWith('/internal/')){assert.equal(options.headers['X-Pointage-Integration-Key'],key);assert.equal(options.headers.authorization,undefined);}
  else{assert.equal(options.headers.authorization,'Bearer '+token);assert.equal(options.headers['X-Pointage-Integration-Key'],undefined);}
  return response({clients:[],documents:[],stock:[],isoRules:[],evpRules:[]});
 }});
 const window={from:'2026-11-21T00:00:00Z',to:'2026-11-22T00:00:00Z'};
 await source.snapshot(window,null);await source.snapshot(window,token);
 assert.deepEqual(routes,['/internal/source/report-snapshot','/api/data/report-snapshot']);
});
test('there is no fallback source or credential forwarding to an arbitrary HTTP host',async()=>{
 assert.throws(()=>new SqlSource({url:'http://172.17.18.122:9000/'}));
 let requests=0;const source=new SqlSource({key,fetcher:async()=>{requests++;throw Error('network unavailable');}});
 await assert.rejects(source.snapshot({from:'2026-11-21T00:00:00Z',to:'2026-11-22T00:00:00Z'},null),e=>e.code==='data_source_unavailable');assert.equal(requests,1);
 await assert.rejects(source.authorize('old.supabase.jwt'),e=>e.code==='invalid_session');assert.equal(requests,1);
});
