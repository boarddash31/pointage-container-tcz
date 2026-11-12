'use strict';
const config={clientId:'MSCMAR',armateurIds:['MSC'],terminalId:'TCZ_TEST',requestTimeZone:'UTC',movementTimeZone:'UTC',
  gateInPorts:[{typeOfPort:'PORT_OF_LOADING',portCode:'ZZTST',terminalCode:'TCZ_TEST'}],
  gateOutPorts:[{typeOfPort:'PORT_OF_LOADING',portCode:'ZZTST',terminalCode:'TCZ_TEST'},{typeOfPort:'PORT_OF_DISCHARGE',portCode:'ZZTST',terminalCode:'TCZ_TEST'}],
  bookingSource:'metadata',requireWeights:true,emptyResponsePolicy:'send-empty'};
const request={requestType:'Automatique',clientId:'MSCMAR',messageType:'CODECO',dateRangeFrom:'2026-07-11',rangeFrom:'23:08:00',
  dateRangeTo:'2026-07-12',rangeTo:'00:08:00',voyageNumber:'',terminalId:'TCZ_TEST',requestGenerationDate:'2026-07-12T00:08Z',documentType:'',schema:''};
function row(id='9007199254740993',action='ENTREE',time='2026-07-11T23:40:00Z'){
  return {event_id:id,action,occurred_at:time,snapshot:{entry_kind:action==='SORTIE'?'empty':'loaded',plate:'QA-1234',is_twin:false,
    container_number:'CSQU3054383',iso_code:'22G1',armateur_id:'MSC',carrier_booking_reference:'INTERNAL-ERO-NOT-A-BOOKING'},
    metadata:{'1':{bookingReference:'MSC-BOOKING-TEST',grossWeight:'2200',tareWeight:'2200',vgmWeight:''}}};
}
function sampleRows(){return [row('9007199254740993','SORTIE','2026-07-11T23:37:00Z'),row('9007199254740994','ENTREE','2026-07-11T23:40:00Z'),
  row('9007199254740995','ENTREE','2026-07-11T23:42:00Z'),row('9007199254740996','ENTREE','2026-07-11T23:59:00Z')];}
module.exports={config,request,row,sampleRows};
