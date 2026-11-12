'use strict';
const crypto=require('node:crypto');
const SCHEMA='marsa.canonicals.departureConfirmation.validation:ContainerDepartureConfirmationSchema';
const DOCUMENT_TYPE='marsa.canonicals.containerDepartureConfirmation:ContainerDepartureConfirmation';
const FIELDS=['requestType','clientId','messageType','dateRangeFrom','rangeFrom','dateRangeTo','rangeTo','voyageNumber','terminalId','requestGenerationDate','documentType','schema'];
class CodecoError extends Error {
  constructor(code){super(code);this.code=code;}
}
const fail=code=>{throw new CodecoError(code);};
function text(value,max=512){if(typeof value!=='string'||value.length>max||!value.isWellFormed()||/[\x00-\x08\x0b\x0c\x0e-\x1f\ufffe\uffff]/u.test(value))fail('invalid_text');return value;}
function localParts(epoch,formatter){
  const p={};for(const item of formatter.formatToParts(new Date(epoch)))if(item.type!=='literal')p[item.type]=Number(item.value);
  return [p.year,p.month,p.day,p.hour,p.minute,p.second];
}
function localInstant(date,time,zone){
  if(!/^\d{4}-\d{2}-\d{2}$/.test(date)||!/^\d{2}:\d{2}:\d{2}$/.test(time))fail('invalid_date_range');
  const values=(date+'-'+time.replaceAll(':','-')).split('-').map(Number),[y,m,d,h,min,s]=values;
  const naive=Date.UTC(y,m-1,d,h,min,s),check=new Date(naive);
  if(y<1970||m<1||m>12||d<1||h>23||min>59||s>59||check.toISOString().slice(0,19)!==date+'T'+time)fail('invalid_date_range');
  let formatter;
  try{formatter=new Intl.DateTimeFormat('en-CA',{timeZone:zone,calendar:'gregory',numberingSystem:'latn',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'});}
  catch{fail('invalid_time_zone');}
  const offsets=new Set();
  for(let hours=-36;hours<=36;hours+=6){const sample=naive+hours*3600000,p=localParts(sample,formatter);offsets.add(Date.UTC(p[0],p[1]-1,p[2],p[3],p[4],p[5])-sample);}
  const matches=[...offsets].map(offset=>naive-offset).filter(epoch=>localParts(epoch,formatter).every((v,i)=>v===values[i]));
  if(matches.length!==1)fail('ambiguous_or_nonexistent_local_time');
  return new Date(matches[0]);
}
function configCheck(config){
  if(config.clientId!=='MSCMAR'||!Array.isArray(config.armateurIds)||config.armateurIds.length!==1||config.armateurIds[0]!=='MSC')fail('invalid_recipient_configuration');
  if(!config.terminalId||typeof config.terminalId!=='string'||config.terminalId.length>32)fail('terminal_id_required');
  if(!config.requestTimeZone||!config.movementTimeZone)fail('time_zones_required');
  if(!['metadata','carrier_booking_reference'].includes(config.bookingSource)||typeof config.requireWeights!=='boolean'||!['reject','send-empty'].includes(config.emptyResponsePolicy))fail('invalid_export_policy');
  try{new Intl.DateTimeFormat('en',{timeZone:config.requestTimeZone});new Intl.DateTimeFormat('en',{timeZone:config.movementTimeZone});}catch{fail('invalid_time_zone');}
  return config;
}
function parseRequest(input,config){
  configCheck(config);
  if(!input||typeof input!=='object'||Array.isArray(input)||Object.keys(input).some(k=>!FIELDS.includes(k)))fail('invalid_request_shape');
  for(const key of FIELDS)if(!Object.hasOwn(input,key))fail('missing_request_field');else text(input[key]);
  // Each subscriber owns its subscription; unrelated requests are committed without a reply.
  if(input.clientId!==config.clientId||input.terminalId!==config.terminalId||input.messageType!=='CODECO')return null;
  const from=localInstant(input.dateRangeFrom,input.rangeFrom,config.requestTimeZone),to=localInstant(input.dateRangeTo,input.rangeTo,config.requestTimeZone);
  if(to<=from||to-from>31*86400000)fail('invalid_date_range');
  if(!/^\d{4}-\d\d-\d\dT\d\d:\d\d(?::\d\d(?:\.\d+)?)?(?:Z|[+-]\d\d:\d\d)$/.test(input.requestGenerationDate)||!Number.isFinite(Date.parse(input.requestGenerationDate)))fail('invalid_generation_date');
  const parameters=Object.fromEntries(FIELDS.map(k=>[k,input[k]]));
  return {parameters,from,to,key:crypto.createHash('sha256').update(JSON.stringify(parameters)).digest('hex')};
}
function effectiveDate(epoch,zone){
  const f=new Intl.DateTimeFormat('en-CA',{timeZone:zone,calendar:'gregory',numberingSystem:'latn',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'});
  const p={};for(const part of f.formatToParts(new Date(epoch)))p[part.type]=part.value;
  return p.year+p.month+p.day+p.hour+p.minute;
}
function decimal(value,required){
  if(value===null||value===undefined||value===''){if(required)fail('missing_container_weight');return '';}
  if(typeof value!=='string'||!/^\d{1,9}(?:\.\d{1,3})?$/.test(value))fail('invalid_container_weight');
  return value;
}
function movementsFor(request,rows,config){
  if(!Array.isArray(rows)||rows.length>10000)fail('movement_limit');
  const events=new Map(),out=[];
  for(const row of rows){
    if(typeof row.event_id!=='string'||!/^\d{1,19}$/.test(row.event_id))fail('invalid_event_identity');
    const serialized=JSON.stringify(row);
    if(events.has(row.event_id)){if(events.get(row.event_id)!==serialized)fail('conflicting_event_snapshots');continue;}events.set(row.event_id,serialized);
    const when=Date.parse(row.occurred_at);if(!Number.isFinite(when))fail('invalid_movement_date');
    if(when<request.from.getTime()||when>=request.to.getTime())continue;
    const v=row.snapshot??{};
    const gate=row.action==='ENTREE'&&v.entry_kind==='loaded'?'IN':row.action==='SORTIE'&&v.entry_kind==='empty'?'OUT':null;
    if(!gate)continue;
    if(v.is_twin===true&&[v.armateur_id,v.armateur_id_2].some(a=>config.armateurIds.includes(a))&&(!v.container_number_2||!v.armateur_id_2))fail('incomplete_twin_snapshot');
    for(const slot of v.is_twin===true?[1,2]:[1]){
      const suffix=slot===1?'':'_2';
      if(!config.armateurIds.includes(v['armateur_id'+suffix]))continue;
      const number=text(v['container_number'+suffix],11),iso=text(v['iso_code'+suffix],4),plate=text(v.plate,32);
      if(!/^[A-Z]{4}\d{7}$/.test(number)||! /^[A-Z0-9]{4}$/.test(iso)||plate.trim().length<2)fail('invalid_container_snapshot');
      const metadata=row.metadata?.[String(slot)]??{};
      if(metadata.loadingState&&metadata.loadingState!=='EMPTY')fail('non_empty_container_for_dry_port');
      const status=gate==='IN'?'EXPORT':'IMPORT';
      if(metadata.containerStatus&&metadata.containerStatus!==status)fail('inconsistent_movement_status');
      const rawPorts=metadata.ports??(gate==='IN'?config.gateInPorts:config.gateOutPorts);
      if(!Array.isArray(rawPorts)||rawPorts.length<1||rawPorts.length>8)fail('movement_ports_required');
      const ports=rawPorts.map(p=>({...p,terminalCode:p.terminalCode??config.terminalId}));
      const portKinds=new Set();
      for(const p of ports){
        if(!['PORT_OF_LOADING','PORT_OF_DISCHARGE'].includes(p.typeOfPort)||portKinds.has(p.typeOfPort)||! /^[A-Z0-9]{2,8}$/.test(p.portCode)||typeof p.terminalCode!=='string'||!p.terminalCode||p.terminalCode.length>32)fail('invalid_movement_ports');
        portKinds.add(p.typeOfPort);
      }
      if(!portKinds.has('PORT_OF_LOADING'))fail('movement_ports_required');
      const booking=config.bookingSource==='carrier_booking_reference'?v[slot===1?'carrier_booking_reference':'booking_reference_2']:metadata.bookingReference;
      if(typeof booking!=='string'||!booking.trim()||booking.length>150)fail('booking_reference_required');
      out.push({eventId:row.event_id,slot,gate,number,iso,plate,status,loadingState:'EMPTY',
        effectiveDate:effectiveDate(when,config.movementTimeZone),ports,booking,
        gross:decimal(metadata.grossWeight,config.requireWeights!==false),tare:decimal(metadata.tareWeight,config.requireWeights!==false),vgm:decimal(metadata.vgmWeight,false)});
    }
  }
  return out;
}
const escape=value=>text(String(value),10000).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&apos;');
const tag=(name,value='')=>'<'+name+'>'+escape(value)+'</'+name+'>';
const group=(name,parts)=>'<'+name+'>'+parts.join('')+'</'+name+'>';
function party(client){return group('Parties',[group('Party',[
  tag('partyQualifier','AGENT'),tag('partyId',client),...['codeListQualifier','partyAddress','partyName','partyStreetName','partyCityName','partyProvinceCode','partyPostCode','partyCountryCode'].map(k=>tag(k))])]);}
function transport(movement){return group('MeanOfTransportation',[
  tag('voyageNumber'),tag('modeOfTransport',movement?'ROAD':''),tag('typeOfMeansOfTransportIdentification',movement?'TRUCK':''),tag('typeOfMeansOfTransportText'),tag('carrierCode',movement?.plate??''),tag('carrierIdentification'),tag('carrierlName')]);}
function buildResponse(request,movements){
  const p=request.parameters;
  const generation=['clientId','messageType','dateRangeFrom','rangeFrom','dateRangeTo','rangeTo','voyageNumber','terminalId','requestGenerationDate'].map(k=>tag(k,p[k]));
  generation.push(tag('schema',SCHEMA),tag('documentType',DOCUMENT_TYPE));
  const confirmations=movements.map(m=>group('ContainerDepartureConfirmation',[
    group('Properties',[group('MessageDetails',[tag('typeOfTraffic','TRANSPORT_ EQUIPEMENT_GATE_'+m.gate+'_REPORT'),tag('messageFunction','ORIGINAL')]),group('MessageGeneration',generation)]),party(p.clientId),
    group('Containers',[group('Container',[
      tag('containerID',m.number),tag('isoCode',m.iso),tag('containerStatus',m.status),tag('loadingState',m.loadingState),party(p.clientId),
      group('DateTimes',[group('DateTime',[tag('typeOfDateTime','EFFECTIVE_DATE'),tag('dateTime',m.effectiveDate)])]),
      group('Destinations',m.ports.map(port=>group('Destination',['typeOfPort','portCode','terminalCode'].map(k=>tag(k,port[k]))))),
      group('ContainerCharacteristics',[group('ContainerMeasurements',[tag('containerGrossWeight',m.gross),tag('containerTareWeight',m.tare),tag('containerVGMWeight',m.vgm)])]),
      group('ContainerReference',[tag('referenceNumber',m.booking),tag('referenceQualifier','BOOKING_NUMBER')]),transport(m)
    ])]),transport(null)
  ]));
  const xml='<?xml version="1.0" encoding="UTF-8"?>\n'+group('ContainerDepartureConfirmations',confirmations);
  if(Buffer.byteLength(xml)>16000000)fail('response_limit');
  return xml;
}
module.exports={CodecoError,SCHEMA,DOCUMENT_TYPE,FIELDS,parseRequest,movementsFor,buildResponse,localInstant,configCheck};
