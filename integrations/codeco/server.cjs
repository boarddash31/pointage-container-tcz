'use strict';
const http=require('node:http'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {CodecoService,FileCache}=require('./service.cjs');
const {CodecoError}=require('./core.cjs');
const digest=value=>crypto.createHash('sha256').update(value).digest();
function createServer(service,token,log=()=>{}){
  if(typeof token!=='string'||token.length<32||/[\r\n]/.test(token))throw new CodecoError('api_token_required');
  const expected=digest('Bearer '+token);let active=0;
  return http.createServer(async(req,res)=>{
    res.setHeader('Cache-Control','no-store');
    if(req.method==='GET'&&req.url==='/health/live'){res.writeHead(200,{'Content-Type':'application/json'}).end('{"service":"pointage-codeco"}');return;}
    if(!crypto.timingSafeEqual(expected,digest(req.headers.authorization??''))){res.writeHead(401).end();return;}
    if(req.method!=='POST'||req.url!=='/internal/codeco/responses'){res.writeHead(404).end();return;}
    if(!(req.headers['content-type']??'').toLowerCase().startsWith('application/json')){res.writeHead(415).end();return;}
    if(active>=4){res.writeHead(503).end();return;}
    active++;
    try{
      const chunks=[];let size=0;
      for await(const chunk of req){size+=chunk.length;if(size>16384)throw new CodecoError('request_limit');chunks.push(chunk);}
      let parameters;try{parameters=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(chunks)));}catch{throw new CodecoError('invalid_json');}
      const result=await service.process(parameters);
      if(result.ignored){res.writeHead(204).end();return;}
      res.setHeader('X-Codeco-Request-Key',result.key);
      res.writeHead(200,{'Content-Type':'application/xml; charset=utf-8'}).end(result.xml);
      log({event:'response_prepared',key:result.key,count:result.count,cached:result.cached});
    }catch(error){
      const code=error instanceof CodecoError?error.code:'processing_failed';
      const retry=['source_unavailable','cache_unavailable','processing_failed'].includes(code);
      if(!res.headersSent)res.writeHead(retry?503:422,{'Content-Type':'application/json'}).end(JSON.stringify({error:code}));
      log({event:'request_failed',code});
    }finally{active--;}
  });
}
if(require.main===module){
  try{
    const config=JSON.parse(fs.readFileSync(process.env.CODECO_CONFIG_FILE??path.join(__dirname,'config.local.json'),'utf8'));
    const source=process.env.POINTAGE_BACKEND==='sqlserver'?new (require('./sql-source.cjs').SqlCodecoSource)():new (require('./postgres-source.cjs').PostgresSource)(process.env.CODECO_PG_CONNECTION,process.env.CODECO_PG_CA_FILE);
    const state=path.resolve(process.env.CODECO_STATE_DIR??path.join(__dirname,'.state'));
    for(const relative of ['../../site','../../app/web','../../app/build/web']){
      const publicRoot=path.resolve(__dirname,relative);
      if(state===publicRoot||state.startsWith(publicRoot+path.sep))throw new CodecoError('private_cache_required');
    }
    const cache=new FileCache(state);
    const service=new CodecoService(config,source,cache);
    const port=Number(process.env.CODECO_API_PORT??8794);if(!Number.isInteger(port)||port<1024||port>65535)throw new Error();
    const server=createServer(service,process.env.CODECO_API_TOKEN,record=>process.stdout.write(JSON.stringify(record)+'\n'));
    server.requestTimeout=60000;server.headersTimeout=15000;
    server.on('error',()=>{console.error('codeco_api_unavailable');process.exitCode=1;});
    server.listen(port,'127.0.0.1',()=>console.log('CODECO API ready on loopback.'));
  }catch{console.error('CODECO configuration unavailable or invalid. Review the private local configuration and required environment variables.');process.exitCode=1;}
}
module.exports={createServer};
