'use strict';
// Offline preparation only: no database connection and no JMS publication.
const fs=require('node:fs/promises'),path=require('node:path');
const {parseRequest,movementsFor,buildResponse}=require('./core.cjs');
(async()=>{
  const args=process.argv.slice(2);
  if(args.length!==4)throw Error('usage');
  const [configuration,requestFile,rowsFile,output]=args;
  const target=path.resolve(output),privateRoot=path.resolve(__dirname,'../../.qa');
  if(!target.startsWith(privateRoot+path.sep))throw Error('private_output_required');
  const read=async file=>JSON.parse(await fs.readFile(file,'utf8'));
  const config=await read(configuration),request=parseRequest(await read(requestFile),config);
  if(!request)throw Error('request_not_for_this_terminal');
  const movements=movementsFor(request,await read(rowsFile),config),xml=buildResponse(request,movements);
  await fs.writeFile(target,xml,{flag:'wx',mode:0o600});
  console.log(JSON.stringify({status:'offline_preview',count:movements.length,publication:false}));
})().catch(()=>{console.error('Dry-run failed. Usage: node dry-run.cjs config.json request.json movements.json .qa/new-preview.xml');process.exitCode=1;});
