'use strict';
const crypto = require('node:crypto');
function validateRow(table, row) {
  const result = {};
  const allowed = new Set(table.columns.map(c => c.name));
  if(Object.keys(row).some(key=>!allowed.has(key))) throw Error(table.source_table+': unexpected source column');
  for(const col of table.columns) {
    let value = row[col.name];
    const fail = reason => { throw Error(table.source_table+'.'+col.name+': '+reason); };
    if(value==null) {if(!col.nullable)fail('required value missing');result[col.name]=null;continue;}
    switch(col.type) {
      case 'uuid': if(typeof value!=='string'||!/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i.test(value))fail('invalid UUID');break;
      case 'bool': if(typeof value!=='boolean')fail('expected boolean');break;
      case 'int4': if(!Number.isInteger(value)||value < -2147483648||value>2147483647)fail('outside int range');break;
      case 'int8': {
        if(typeof value==='number'&&!Number.isSafeInteger(value))fail('unsafe bigint conversion');
        value=String(value);
        if(!/^-?\d+$/.test(value)||BigInt(value)<-9223372036854775808n||BigInt(value)>9223372036854775807n)fail('outside bigint range');
        break;
      }
      case 'numeric': {
        if(typeof value!=='string')fail('numeric must remain a decimal string');
        const match=value.match(/^-?(\d+)(?:\.(\d+))?$/);
        if(!match||match[1].replace(/^0+/,'').length>20||(match[2]?.length??0)>18)fail('would round or overflow decimal(38,18)');
        break;
      }
      case 'date':
        if(typeof value!=='string'||!/^\d{4}-\d\d-\d\d$/.test(value)||value.startsWith('0000')||!Number.isFinite(Date.parse(value))||new Date(value).toISOString().slice(0,10)!==value)fail('invalid date');
        break;
      case 'timestamptz':
        if(typeof value!=='string')fail('timestamp must retain source precision');
        value=value.replace(' ','T').replace(/([+-]\d\d)$/,'$1:00');
        if(!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?(?:Z|[+-]\d\d:\d\d)$/.test(value)||value.startsWith('0000')||!Number.isFinite(Date.parse(value)))fail('invalid datetimeoffset(6)');
        break;
      case 'jsonb':
        // pg returns original JSON text: parsing/re-encoding would round large JSON numbers.
        if(typeof value!=='string')fail('JSON must retain its original text');
        try{JSON.parse(value);}catch(_){fail('invalid JSON');}
        break;
      case 'text': {
        if(typeof value!=='string')fail('expected text');
        const bounded=col.sql_type.match(/^nvarchar\((\d+)\)/);
        if(bounded&&(value.length>Number(bounded[1])||value!==value.trim()))fail('would truncate or change key comparison; reconcile source first');
        break;
      }
      default:fail('unsupported source type');
    }
    result[col.name]=value;
  }
  return result;
}
const fileHash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const manifestHash = text => fileHash(text.replace(/^\ufeff/,'').replace(/\r\n/g,'\n'));
module.exports={validateRow,fileHash,manifestHash};
