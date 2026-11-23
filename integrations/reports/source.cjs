'use strict';
const {ReportsError}=require('./calendar.cjs');
const PROJECT='iparzfqxopcvwqelxlad',URL_BASE=`https://${PROJECT}.supabase.co`;
const PUBLIC_KEY='sb_publishable_AgyGT1cfJz9gkXTpVrLsXg_B3VNWHGs';
class Source{
 constructor({secret=process.env.REPORTS_SUPABASE_SECRET_KEY,fetcher=fetch}={}){this.secret=secret;this.fetcher=fetcher;}
 get configured(){
  if(typeof this.secret!=='string')return false;
  if(this.secret.startsWith('sb_secret_')&&this.secret.length>25)return true;
  try{const claims=JSON.parse(Buffer.from(this.secret.split('.')[1],'base64url'));return claims.role==='service_role'&&claims.ref===PROJECT;}catch{return false;}
 }
 headers(token,isSecret=false){const key=isSecret?token:PUBLIC_KEY;
  return {apikey:key,...((!isSecret||!token.startsWith('sb_secret_'))?{authorization:'Bearer '+token}:{}),accept:'application/json'};}
 async request(endpoint,token,isSecret=false){
  let response;try{response=await this.fetcher(URL_BASE+endpoint,{headers:this.headers(token,isSecret),redirect:'error',signal:AbortSignal.timeout(20000)});}catch{throw new ReportsError('data_source_unavailable',503);}
  if(!response.ok)throw new ReportsError(response.status===401?'invalid_session':'data_source_unavailable',response.status===401?401:503);
  let text=await response.text();if(Buffer.byteLength(text)>16*1024*1024)throw new ReportsError('data_limit',503);
  try{return JSON.parse(text);}catch{throw new ReportsError('invalid_data_response',503);}
 }
 async authorize(token){
  if(typeof token!=='string'||token.length>12000)throw new ReportsError('authentication_required',401);
  const user=await this.request('/auth/v1/user',token);if(!user?.id||!/^[-0-9a-f]{36}$/i.test(user.id))throw new ReportsError('invalid_session',401);
  const [profile,roles]=await Promise.all([
   this.request('/rest/v1/profiles?'+new URLSearchParams({select:'active',id:'eq.'+user.id,limit:'1'}),token),
   this.request('/rest/v1/user_roles?'+new URLSearchParams({select:'role',user_id:'eq.'+user.id}),token),
  ]);
  if(!Array.isArray(profile)||profile[0]?.active!==true||!Array.isArray(roles)||!roles.some(r=>r.role==='admin'))throw new ReportsError('admin_required',403);
  return user.id;
 }
 async rows(table,select,filters,token,isSecret=false){
  const rows=[];let after;
  for(let page=0;page<101;page++){
   const params=new URLSearchParams({...filters,select,order:'id.asc',limit:'1000',...(after?{id:'gt.'+after}:{})});
   const batch=await this.request('/rest/v1/'+table+'?'+params,token,isSecret);
   const validId=table==='armateurs'?/^[A-Za-z0-9_-]{1,40}$/:/^[0-9a-f-]{36}$/i;
   if(!Array.isArray(batch)||batch.length>1000||batch.some(r=>typeof r.id!=='string'||!validId.test(r.id)))throw new ReportsError('invalid_data_response',503);
   rows.push(...batch);if(rows.length>100000)throw new ReportsError('report_row_limit',422);
   if(batch.length<1000)return rows;
   const last=batch.at(-1)?.id;if(typeof last!=='string'||last===after)throw new ReportsError('invalid_pagination',503);after=last;
  }throw new ReportsError('report_row_limit',422);
 }
 clients(token){return this.rows('clients','id,name,active',{},token);}
 operators(token){return this.rows('armateurs','id,name,active',{},token);}
 async rules(table,select,order,token,isSecret){
  const result=[];
  for(let page=0;page<100;page++){
   const batch=await this.request('/rest/v1/'+table+'?'+new URLSearchParams({select,order,limit:'1000',offset:String(page*1000)}),token,isSecret);
   if(!Array.isArray(batch)||batch.length>1000)throw new ReportsError('invalid_data_response',503);
   result.push(...batch);if(batch.length<1000)return result;
  }throw new ReportsError('report_row_limit');
 }
 async snapshot(window,token,clientIds=[]){
  const key=token??this.secret,isSecret=!token;
  if(!key||(!token&&!this.configured))throw new ReportsError('report_source_not_configured',503);
  if(clientIds.some(id=>typeof id!=='string'||!/^[0-9a-f-]{36}$/i.test(id)))throw new ReportsError('invalid_clients');
  const clients=await this.rows('clients','id,name,active',{},key,isSecret);
  const fields=['entry_kind','client_id','entered_at','exited_at','container_number','container_number_2','iso_code','iso_code_2','armateur_id','armateur_id_2','carrier_booking_reference','booking_reference_2','plate'];
  const projected=await this.rows('generated_documents','id,kind,created_at,is_twin:snapshot->is_twin,'+fields.map(f=>`${f}:snapshot->>${f}`).join(',')+',event_booking:snapshot->event->>booking',{
    kind:'in.(ENTREE,SORTIE)',created_at:'gte.'+window.from,and:`(created_at.lt.${window.to})`,
    ...(clientIds.length?{'snapshot->>client_id':'in.('+clientIds.join(',')+')'}:{}),
  },key,isSecret);
  const documents=projected.map(({id,kind,created_at,...snapshot})=>({id,kind,created_at,snapshot}));
  const stock=await this.rows('container_stock_intervals','id,container_number,client_id,armateur_id,iso_code,arrived_at,departed_at,position',{
    arrived_at:'lt.'+window.to,or:`(departed_at.is.null,departed_at.gte.${window.to})`,
    ...(clientIds.length?{client_id:'in.('+clientIds.join(',')+')'}:{}),
  },key,isSecret);
  const [isoRules,evpRules]=await Promise.all([
   this.rules('iso_report_types','iso_code,effective_from,category,size_feet','iso_code.asc,effective_from.asc',key,isSecret),
   this.rules('evp_rules','size_feet,effective_from,factor','size_feet.asc,effective_from.asc',key,isSecret),
  ]);
  return {clients,documents,stock,isoRules,evpRules};
 }
}
module.exports={Source,PROJECT};
