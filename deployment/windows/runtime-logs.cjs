'use strict';
const fs=require('node:fs'),path=require('node:path');
const pattern=/^zenata-\d{4}-\d{2}-\d{2}-\d{6}\.jsonl$/;
function createLogger(directory,{webRoot,maxBytes=5*1024*1024,maxFiles=14,now=()=>new Date()}={}){
  if(!Number.isInteger(maxBytes)||maxBytes<256||!Number.isInteger(maxFiles)||maxFiles<1)throw Error('Invalid log limits');
  fs.mkdirSync(directory,{recursive:true});const root=fs.realpathSync(directory);
  if(webRoot){const web=fs.realpathSync(webRoot);if(root===web||root.startsWith(web+path.sep))throw Error('Logs must stay outside web');}
  let fd,bytes=0,day='',failed=false,closed=false;
  function rotate(date){
    if(fd!==undefined)fs.closeSync(fd);
    fd=undefined;day=date;bytes=0;
    for(let n=0;n<1000000;n++){
      const file=path.join(root,`zenata-${date}-${String(n).padStart(6,'0')}.jsonl`);
      try{fd=fs.openSync(file,'wx',0o600);break;}catch(error){if(error.code!=='EEXIST')throw error;}
    }
    if(fd===undefined)throw Error('Log rotation limit');
    const owned=fs.readdirSync(root).filter(name=>pattern.test(name)).sort();
    for(const name of owned.slice(0,Math.max(0,owned.length-maxFiles))){
      const file=path.join(root,name),stat=fs.lstatSync(file);
      if(stat.isFile()&&!stat.isSymbolicLink())fs.unlinkSync(file);
    }
  }
  rotate(now().toISOString().slice(0,10));
  return {
    log(event,fields={}){
      if(closed||failed)return false;
      // Strict allowlist: no raw URL, query, headers, body, exception message or stack.
      const allowed=new Set(['startup','shutdown','server_error','request_error','http_request','http_aborted','fatal_error','report_started','report_finished','report_failed']);
      if(!allowed.has(event))return false;
      const record={timestamp:now().toISOString(),pid:process.pid,level:['server_error','request_error','fatal_error'].includes(event)?'error':'info',event};
      for(const key of ['request_id','run_id','method','resource','code','host','reason'])if(typeof fields[key]==='string')record[key]=fields[key].replace(/[\r\n\x00-\x1f]/g,'').slice(0,80);
      for(const key of ['port','status','duration_ms'])if(typeof fields[key]==='number'&&Number.isFinite(fields[key]))record[key]=fields[key];
      const line=JSON.stringify(record)+'\n',size=Buffer.byteLength(line);
      try{
        if(record.timestamp.slice(0,10)!==day||bytes+size>maxBytes)rotate(record.timestamp.slice(0,10));
        fs.writeSync(fd,line);bytes+=size;return true;
      }catch{failed=true;console.error('Application log write failed. Check logs disk space and write permissions.');return false;}
    },
    close(){if(!closed){closed=true;if(fd!==undefined){fs.closeSync(fd);fd=undefined;}}},
  };
}
module.exports={createLogger};
