'use strict';
const http=require('node:http'),fs=require('node:fs/promises'),path=require('node:path');
const crypto=require('node:crypto');
const {createLogger}=require('./runtime-logs.cjs');
const mime={'.html':'text/html; charset=utf-8','.js':'application/javascript','.json':'application/json',
  '.css':'text/css','.wasm':'application/wasm','.bin':'application/octet-stream','.png':'image/png',
  '.jpg':'image/jpeg','.jpeg':'image/jpeg','.svg':'image/svg+xml','.ico':'image/x-icon',
  '.ttf':'font/ttf','.otf':'font/otf','.woff':'font/woff','.woff2':'font/woff2','.pdf':'application/pdf',
  '.txt':'text/plain; charset=utf-8','.frag':'application/octet-stream'};
function createServer(root,log=()=>{},reports=null,sqlProxy=null){
  const canonicalRoot=fs.realpath(root);
  return http.createServer(async(req,res)=>{
    const started=process.hrtime.bigint(),requestId=crypto.randomUUID();let logged=false;
    res.setHeader('X-Request-Id',requestId);
    const resource=(()=>{try{
      const p=new URL(req.url,'http://runtime.invalid').pathname;
      return ['/','/index.html','/main.dart.js','/flutter_bootstrap.js','/release.json','/dashboard.html'].includes(p)?(p==='/'?'index.html':p.slice(1)):'static_or_unknown';
    }catch{return 'invalid_request';}})();
    const report=event=>{if(logged)return;logged=true;log(event,{request_id:requestId,
      method:['GET','HEAD','POST','PUT','DELETE','PATCH','OPTIONS'].includes(req.method)?req.method:'OTHER',resource,
      status:res.statusCode,duration_ms:Math.round(Number(process.hrtime.bigint()-started)/1e4)/100});};
    res.on('finish',()=>report('http_request'));res.on('close',()=>report('http_aborted'));
    res.setHeader('Cache-Control','no-store');res.setHeader('X-Content-Type-Options','nosniff');
    res.setHeader('Referrer-Policy','strict-origin-when-cross-origin');
    try{
      if(reports&&await reports.handle(req,res))return;
      if(sqlProxy&&await sqlProxy.handle(req,res))return;
      if(!['GET','HEAD'].includes(req.method)){res.setHeader('Allow','GET, HEAD');res.writeHead(405).end();return;}
      const base=await canonicalRoot;
      let route;try{route=decodeURIComponent(new URL(req.url,'http://runtime.invalid').pathname);}catch{res.writeHead(400).end();return;}
      if(/[\\:\x00%]/.test(route)||route.split('/').some(s=>s.startsWith('.')||/[. ]$/.test(s))){res.writeHead(403).end();return;}
      const relative=route==='/'?'index.html':route.slice(1);
      if(!mime[path.extname(relative).toLowerCase()]&&!['assets/NOTICES'].includes(relative)){res.writeHead(404).end();return;}
      if(path.basename(relative).toLowerCase()==='web.config'){res.writeHead(404).end();return;}
      const resolved=await fs.realpath(path.join(base,relative));
      if(!resolved.startsWith(base+path.sep)){res.writeHead(403).end();return;}
      const file=await fs.open(resolved,'r');
      try{
        const stat=await file.stat();if(!stat.isFile()){res.writeHead(404).end();return;}
        res.writeHead(200,{'Content-Type':mime[path.extname(relative).toLowerCase()]||'text/plain','Content-Length':stat.size});
        if(req.method==='HEAD'){res.end();return;}
        await new Promise(resolve=>{const stream=file.createReadStream({autoClose:false});
          stream.on('error',()=>{log('request_error',{request_id:requestId,code:'STREAM_ERROR'});res.destroy();resolve();});res.on('close',()=>{stream.destroy();resolve();});stream.on('end',resolve);stream.pipe(res);
        });
      }finally{await file.close();}
    }catch(error){const missing=['ENOENT','ENOTDIR'].includes(error.code);
      if(!missing)log('request_error',{request_id:requestId,code:'FILE_ACCESS_ERROR'});
      if(!res.headersSent)res.writeHead(missing?404:500).end();else res.destroy();}
  });
}
if(require.main===module){
  const port=Number(process.env.PORT??9091),host=process.env.HOST??'172.17.18.208';
  if(!Number.isInteger(port)||port<1||port>65535)throw Error('Invalid PORT');
  let logger;
  try{logger=createLogger(path.resolve(process.env.LOG_DIR??path.join(__dirname,'logs')),{webRoot:path.join(__dirname,'web')});}
  catch{console.error('Logging unavailable. Check LOG_DIR is writable and outside web.');process.exitCode=1;return;}
  const log=(event,fields)=>logger.log(event,fields);
  let reports;
  try{
    const {createReports}=require('./reports/feature.cjs');
    reports=createReports({directory:path.join(__dirname,'.state','reports'),webRoot:path.join(__dirname,'web'),log});
  }catch(error){
    if(error.code!=='MODULE_NOT_FOUND')log('report_failed',{code:'reports_initialization_failed'});
    reports={handle:async(req,res)=>{if(!new URL(req.url,'http://runtime.invalid').pathname.startsWith('/api/reports'))return false;
      res.writeHead(503,{'Content-Type':'application/json'}).end(JSON.stringify({error:'reports_unavailable'}));return true;}};
  }
  const sqlProxy=process.env.POINTAGE_BACKEND==='sqlserver'?require('./sql-api-proxy.cjs').createSqlProxy(process.env.POINTAGE_SQL_API_URL):null;
  const server=createServer(path.join(__dirname,'web'),log,reports,sqlProxy);
  server.requestTimeout=30000;server.headersTimeout=15000;
  server.on('error',error=>{log('server_error',{code:['EADDRINUSE','EACCES','EADDRNOTAVAIL'].includes(error.code)?error.code:'LISTEN_ERROR'});
    console.error(error.code==='EADDRINUSE'?'Port already occupied. Check IIS or choose another PORT.':'Unable to start. Check HOST, PORT and web directory.');logger.close();process.exitCode=1;});
  let stopping=false;
  function stop(reason,exitCode=0){if(stopping)return;stopping=true;reports?.stop?.();log('shutdown',{reason});
    server.close(()=>{logger.close();process.exitCode=exitCode;});
    setTimeout(()=>{server.closeAllConnections();logger.close();process.exit(exitCode);},5000).unref();
  }
  process.on('SIGINT',()=>stop('SIGINT'));process.on('SIGTERM',()=>stop('SIGTERM'));
  process.on('uncaughtException',()=>{log('fatal_error',{code:'UNCAUGHT_EXCEPTION'});console.error('Fatal runtime error. See logs.');stop('fatal_error',1);});
  process.on('unhandledRejection',()=>{log('fatal_error',{code:'UNHANDLED_REJECTION'});console.error('Fatal runtime error. See logs.');stop('fatal_error',1);});
  server.listen(port,host,()=>{reports?.start?.();log('startup',{host,port});console.log(`Gestion des flux : http://${host}${port===80?'':':'+port}/\nLogs: ${path.resolve(process.env.LOG_DIR??path.join(__dirname,'logs'))}\nCtrl+C to stop. Keep this process running.`);});
}
module.exports={createServer};
