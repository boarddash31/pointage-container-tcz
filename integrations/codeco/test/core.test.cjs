'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {parseRequest,movementsFor,buildResponse,localInstant,SCHEMA,DOCUMENT_TYPE}=require('../core.cjs');
const {config,request,row,sampleRows}=require('./fixtures.cjs');
const parsed=()=>parseRequest(request,config);
test('request echo retains lexical parameters, ignores other clients/types/terminals',()=>{
  assert.deepEqual(parsed().parameters,request);
  for(const change of [{clientId:'OTHER'},{terminalId:'OTHER'},{messageType:'COARRI'}])assert.equal(parseRequest({...request,...change},config),null);
  assert.throws(()=>parseRequest({...request,unexpected:'ignored?'},config),/invalid_request_shape/);
  assert.throws(()=>parseRequest({...request,rangeTo:'25:08:00'},config),/invalid_date_range/);
  assert.throws(()=>parseRequest(request,{...config,terminalId:''}),/terminal_id_required/);
});
test('UTC and Morocco timezone conversion reject DST ambiguity and nonexistent dates',()=>{
  assert.equal(localInstant('2026-07-12','00:08:00','Africa/Casablanca').toISOString(),'2026-07-11T23:08:00.000Z');
  assert.throws(()=>localInstant('2026-02-30','00:00:00','UTC'),/invalid_date_range/);
  assert.throws(()=>localInstant('2026-03-08','02:30:00','America/New_York'),/ambiguous_or_nonexistent_local_time/);
  assert.throws(()=>localInstant('2026-11-01','01:30:00','America/New_York'),/ambiguous_or_nonexistent_local_time/);
});
test('real gate movements: entry EXPORT, exit IMPORT, always EMPTY; empty trucks and yard moves excluded',()=>{
  const out=row('1','SORTIE');
  const emptyEntry=row('2');emptyEntry.snapshot.entry_kind='empty';
  const emptyExit=row('3','SORTIE');emptyExit.snapshot.entry_kind='loaded';
  const yard=row('4','PRISE');
  const selected=movementsFor(parsed(),[row(),out,emptyEntry,emptyExit,yard],config);
  assert.deepEqual(selected.map(m=>[m.gate,m.status,m.loadingState]),[['IN','EXPORT','EMPTY'],['OUT','IMPORT','EMPTY']]);
  assert.equal(selected[0].eventId,'9007199254740993');
});
test('half-open hourly windows and overlapping requests retain distinct event identities',()=>{
  const start=row('1','ENTREE','2026-07-11T23:08:00Z'),end=row('2','ENTREE','2026-07-12T00:08:00Z');
  assert.deepEqual(movementsFor(parsed(),[start,end],config).map(m=>m.eventId),['1']);
  assert.equal(movementsFor(parsed(),sampleRows(),config).length,4);
  const next=parseRequest({...request,rangeFrom:'23:38:00',rangeTo:'00:38:00',requestGenerationDate:'2026-07-12T00:38Z'},config);
  assert.equal(movementsFor(next,sampleRows(),config).length,3);
});
test('twins produce separate container movements; mixed carriers export only MSC',()=>{
  const twin=row();Object.assign(twin.snapshot,{is_twin:true,container_number_2:'TEMU1234567',iso_code_2:'22G1',armateur_id_2:'MSC'});
  twin.metadata['2']={...twin.metadata['1'],bookingReference:'SECOND-BOOKING'};
  assert.deepEqual(movementsFor(parsed(),[twin],config).map(m=>m.slot),[1,2]);
  twin.snapshot.armateur_id_2='MAE';assert.deepEqual(movementsFor(parsed(),[twin],config).map(m=>m.slot),[1]);
  twin.snapshot.armateur_id='MAE';assert.equal(movementsFor(parsed(),[twin],config).length,0);
});
test('duplicate snapshots are collapsed; conflicting snapshots and incomplete data stop the complete response',()=>{
  const one=row();assert.equal(movementsFor(parsed(),[one,structuredClone(one)],config).length,1);
  const changed=structuredClone(one);changed.snapshot.plate='CHANGED';
  assert.throws(()=>movementsFor(parsed(),[one,changed],config),/conflicting_event_snapshots/);
  const missing=row();delete missing.metadata['1'].tareWeight;
  assert.throws(()=>movementsFor(parsed(),[one, {...missing,event_id:'7'}],config),/missing_container_weight/);
  missing.metadata={};assert.throws(()=>movementsFor(parsed(),[missing],config),/booking_reference_required/);
  const full=row();full.metadata['1'].loadingState='FULL';assert.throws(()=>movementsFor(parsed(),[full],config),/non_empty_container/);
});
test('booking is explicit; internal EDO/ERO reference is never substituted unless configured',()=>{
  const missing=row();missing.metadata={};
  assert.throws(()=>movementsFor(parsed(),[missing],{...config,requireWeights:false}),/booking_reference_required/);
  const selected=movementsFor(parsed(),[missing],{...config,requireWeights:false,bookingSource:'carrier_booking_reference'});
  assert.equal(selected[0].booking,'INTERNAL-ERO-NOT-A-BOOKING');
  assert.equal(selected[0].gross,'');assert.equal(selected[0].tare,'');
});
test('confirmed ZDP contract uses the EDO/ERO reference, leaves weights pending and inherits the assigned terminal',()=>{
  const confirmed={...config,bookingSource:'carrier_booking_reference',requireWeights:false,
    gateInPorts:[{typeOfPort:'PORT_OF_LOADING',portCode:'ZDP'}]};
  const movement=row();movement.metadata={};
  const selected=movementsFor(parseRequest(request,confirmed),[movement],confirmed);
  assert.equal(selected[0].booking,movement.snapshot.carrier_booking_reference);
  assert.deepEqual(selected[0].ports,[{typeOfPort:'PORT_OF_LOADING',portCode:'ZDP',terminalCode:'TCZ_TEST'}]);
  assert.equal(selected[0].gross,'');assert.equal(selected[0].tare,'');
});
test('canonical response uses the sample spellings, schema, function, echo fields and escaped XML text',()=>{
  const movement=row();movement.metadata['1'].bookingReference='BOOK<&"\'é';
  const xml=buildResponse(parsed(),movementsFor(parsed(),[movement],config));
  for(const value of [SCHEMA,DOCUMENT_TYPE,'TRANSPORT_ EQUIPEMENT_GATE_IN_REPORT','EFFECTIVE_DATE','BOOKING_NUMBER','<carrierlName>','<modeOfTransport>ROAD</modeOfTransport>'])assert.ok(xml.includes(value));
  assert.ok(xml.includes('BOOK&lt;&amp;&quot;&apos;é'));
  assert.ok(xml.includes('<requestGenerationDate>2026-07-12T00:08Z</requestGenerationDate>'));
  assert.ok(!xml.includes('INTERNAL-ERO-NOT-A-BOOKING'));
});
