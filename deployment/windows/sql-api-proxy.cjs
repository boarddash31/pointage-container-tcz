'use strict';
const http=require('node:http');
function createSqlProxy(base='http://127.0.0.1:19091/'){
 const target=new URL(base);
 if(target.protocol!=='http:'||!['127.0.0.1','localhost','[::1]'].includes(target.hostname)||target.pathname!=='/'||target.username||target.password||target.search||target.hash)throw Error('SQL API proxy must target a loopback HTTP listener.');
 return {async handle(req,res){
  const incoming=new URL(req.url,'http://runtime.invalid');
  if(!incoming.pathname.startsWith('/api/')&&!['/health/live','/health/ready'].includes(incoming.pathname))return false;
  if(!['GET','POST','PUT','OPTIONS'].includes(req.method)){res.writeHead(405).end();return true;}
  const headers={host:target.host,'x-forwarded-for':req.socket.remoteAddress??'127.0.0.1'};
  for(const key of ['authorization','content-type','accept','origin','access-control-request-method','access-control-request-headers'])if(typeof req.headers[key]==='string')headers[key]=req.headers[key];
  const upstream=http.request({hostname:target.hostname,port:target.port||80,path:incoming.pathname+incoming.search,method:req.method,headers},response=>{
   const responseHeaders={'Cache-Control':'no-store'};
   for(const key of ['content-type','content-disposition','retry-after','access-control-allow-origin','access-control-allow-headers','access-control-allow-methods','vary'])if(response.headers[key])responseHeaders[key]=response.headers[key];
   res.writeHead(response.statusCode,responseHeaders);response.on('error',()=>res.destroy());response.pipe(res);
  });
  const fail=()=>{if(res.headersSent){res.destroy();return;}res.writeHead(503,{'Content-Type':'application/json','Cache-Control':'no-store'}).end('{"error":"database_unavailable"}');};
  upstream.setTimeout(35000,()=>upstream.destroy());upstream.on('error',fail);
  req.on('aborted',()=>upstream.destroy());res.on('close',()=>{if(!res.writableEnded)upstream.destroy();});req.pipe(upstream);
  return true;
 }};
}
module.exports={createSqlProxy};
