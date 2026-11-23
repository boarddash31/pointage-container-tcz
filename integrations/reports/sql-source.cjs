'use strict';
const {ReportsError}=require('./calendar.cjs');
class SqlSource {
 constructor({url=process.env.POINTAGE_SQL_API_URL??'http://127.0.0.1:19091/',key=process.env.POINTAGE_INTEGRATION_KEY,fetcher=fetch}={}){
  const base=new URL(url);
  if(base.username||base.password||base.search||base.hash||base.pathname!=='/'||!(base.protocol==='https:'||base.protocol==='http:'&&['127.0.0.1','::1','localhost'].includes(base.hostname)))throw new ReportsError('invalid_sql_source',503);
  this.base=base;this.key=key;this.fetcher=fetcher;
 }
 get configured(){return typeof this.key==='string'&&this.key.length>=43&&this.key.length<=256&&!/[\r\n]/.test(this.key);}
 async request(route,{token,query={}}={}){
  if(token!==undefined&&(typeof token!=='string'||!/^[A-Za-z0-9_-]{43}$/.test(token)))throw new ReportsError('invalid_session',401);
  if(token===undefined&&!this.configured)throw new ReportsError('report_source_not_configured',503);
  const url=new URL(route,this.base);url.search=new URLSearchParams(query).toString();
  let response;try{response=await this.fetcher(url,{headers:token?{authorization:'Bearer '+token}:{'X-Pointage-Integration-Key':this.key},redirect:'error',signal:AbortSignal.timeout(30000)});}catch{throw new ReportsError('data_source_unavailable',503);}
  if(!response.ok)throw new ReportsError(response.status===401?'invalid_session':response.status===403?'admin_required':'data_source_unavailable',response.status===401?401:response.status===403?403:503);
  const reader=response.body?.getReader();let text;
  if(reader){const chunks=[];let size=0;try{for(;;){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>32*1024*1024){await reader.cancel();throw new ReportsError('data_limit',503);}chunks.push(Buffer.from(value));}text=Buffer.concat(chunks).toString('utf8');}finally{reader.releaseLock();}}
  else{text=await response.text();if(Buffer.byteLength(text)>32*1024*1024)throw new ReportsError('data_limit',503);}
  try{return JSON.parse(text);}catch{throw new ReportsError('invalid_data_response',503);}
 }
 async authorize(token){
  const user=await this.request('api/me',{token});
  if(!user?.active||typeof user.id!=='string'||!Array.isArray(user.roles)||!user.roles.some(r=>(r?.role??r)==='admin'))throw new ReportsError('admin_required',403);
  return user.id;
 }
 clients(token){return this.request(token?'api/data/clients':'internal/source/clients',{token});}
 operators(token){return this.request(token?'api/data/operators':'internal/source/operators',{token});}
 async snapshot(window,token,clientIds=[]){
  if(clientIds.some(id=>typeof id!=='string'||!/^[0-9a-f-]{36}$/i.test(id)))throw new ReportsError('invalid_clients');
  const data=await this.request(token?'api/data/report-snapshot':'internal/source/report-snapshot',{token:token??undefined,query:{from:window.from,to:window.to}});
  if(!data||!['clients','documents','stock','isoRules','evpRules'].every(k=>Array.isArray(data[k])))throw new ReportsError('invalid_data_response',503);
  for(const document of data.documents){if(document.snapshot?.event?.booking&&!document.snapshot.event_booking)document.snapshot.event_booking=document.snapshot.event.booking;}
  // One read-only SQL statement supplies a common view of the report data; business-client filters remain in reportData.
  return data;
 }
 async fetch(request){return this.request('internal/source/codeco',{query:{from:request.from.toISOString(),to:request.to.toISOString()}});}
}
module.exports={SqlSource};
