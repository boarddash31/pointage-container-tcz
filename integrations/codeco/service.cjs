'use strict';
const fs=require('node:fs/promises'),path=require('node:path'),crypto=require('node:crypto');
const {CodecoError,parseRequest,movementsFor,buildResponse,configCheck}=require('./core.cjs');
const hash=value=>crypto.createHash('sha256').update(value).digest('hex');
const canonical=value=>Array.isArray(value)?value.map(canonical):value&&typeof value==='object'?Object.fromEntries(Object.keys(value).sort().map(key=>[key,canonical(value[key])])):value;
class FileCache {
  constructor(directory){this.directory=path.resolve(directory);}
  file(key){if(!/^[a-f0-9]{64}$/.test(key))throw new CodecoError('invalid_cache_key');return path.join(this.directory,key+'.json');}
  async get(key){try{return JSON.parse(await fs.readFile(this.file(key),'utf8'));}catch(e){if(e.code==='ENOENT')return null;throw new CodecoError('cache_unavailable');}}
  async put(key,value){
    await fs.mkdir(this.directory,{recursive:true,mode:0o700});
    const temporary=this.file(key)+'.'+crypto.randomUUID()+'.tmp';
    await fs.writeFile(temporary,JSON.stringify(value),{flag:'wx',mode:0o600});
    try{await fs.link(temporary,this.file(key));}catch(e){if(e.code!=='EEXIST')throw new CodecoError('cache_unavailable');}
    finally{await fs.unlink(temporary);}
    return this.get(key); // First completed response wins, including concurrent processes.
  }
}
class CodecoService {
  constructor(config,source,cache){this.config=configCheck(config);this.source=source;this.cache=cache;this.pending=new Map();this.configHash=hash(JSON.stringify(canonical(config)));}
  check(value,key){
    if(!value||value.requestKey!==key||value.configHash!==this.configHash||typeof value.xml!=='string'||value.xmlHash!==hash(value.xml)||!Number.isInteger(value.count)||value.count<0)throw new CodecoError('cached_response_mismatch');
    return value;
  }
  async process(parameters){
    const request=parseRequest(parameters,this.config);if(!request)return {ignored:true};
    if(this.pending.has(request.key))return this.pending.get(request.key);
    const work=(async()=>{
      const previous=await this.cache.get(request.key);if(previous)return {...this.check(previous,request.key),cached:true,key:request.key};
      const rows=await this.source.fetch(request),movements=movementsFor(request,rows,this.config);
      if(movements.length===0&&this.config.emptyResponsePolicy!=='send-empty')throw new CodecoError('empty_response_contract_unconfirmed');
      const xml=buildResponse(request,movements),value={requestKey:request.key,configHash:this.configHash,xmlHash:hash(xml),xml,count:movements.length,createdAt:new Date().toISOString()};
      const saved=this.check(await this.cache.put(request.key,value),request.key);
      return {...saved,key:request.key,cached:false};
    })();
    this.pending.set(request.key,work);
    try{return await work;}finally{this.pending.delete(request.key);}
  }
}
module.exports={CodecoService,FileCache};
