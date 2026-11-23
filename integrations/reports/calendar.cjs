'use strict';
class ReportsError extends Error{constructor(code,status=422){super(code);this.code=code;this.status=status;}}
const fail=code=>{throw new ReportsError(code);};
function parts(epoch,zone){const p={};for(const x of new Intl.DateTimeFormat('en-CA',{timeZone:zone,calendar:'gregory',numberingSystem:'latn',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'}).formatToParts(new Date(epoch)))if(x.type!=='literal')p[x.type]=x.value;return p;}
function dateAt(epoch,zone){const p=parts(epoch,zone);return `${p.year}-${p.month}-${p.day}`;}
const addDays=(date,n)=>new Date(Date.parse(date+'T00:00:00Z')+n*86400000).toISOString().slice(0,10);
function instants(date,time,zone){
  const naive=Date.parse(date+'T'+time+':00Z'),offsets=new Set();
  for(let h=-36;h<=36;h+=6){const epoch=naive+h*3600000,p=parts(epoch,zone);offsets.add(Date.parse(`${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}:${p.second}Z`)-epoch);}
  return [...offsets].map(o=>naive-o).filter(epoch=>{const p=parts(epoch,zone);return `${p.year}-${p.month}-${p.day}`===date&&`${p.hour}:${p.minute}`===time;}).sort((a,b)=>a-b);
}
function checkSchedule(s){
  if(!s||!['once','interval','daily','weekly','monthly'].includes(s.kind))fail('invalid_schedule');
  const allowed={once:['at','at_local'],interval:['minutes'],daily:['time'],weekly:['time','days'],monthly:['time','day']}[s.kind];
  if(Object.keys(s).some(k=>!['kind','timezone',...allowed].includes(k)))fail('invalid_schedule');
  if(s.timezone!=='Africa/Casablanca')fail('invalid_timezone');
  const validDate=value=>typeof value==='string'&&/^\d{4}-\d\d-\d\d$/.test(value)&&Number.isFinite(Date.parse(value+'T00:00Z'))&&new Date(value+'T00:00Z').toISOString().slice(0,10)===value;
  if(s.kind==='once'&&s.at_local){
    if(!/^\d{4}-\d\d-\d\dT([01]\d|2[0-3]):[0-5]\d$/.test(s.at_local)||!validDate(s.at_local.slice(0,10)))fail('invalid_schedule_date');
    const matches=instants(s.at_local.slice(0,10),s.at_local.slice(11),'Africa/Casablanca');if(!matches.length)fail('invalid_schedule_date');
    s={kind:s.kind,timezone:s.timezone,at:new Date(matches[0]).toISOString()};
  }
  if(s.kind==='once'&&(!/^\d{4}-\d\d-\d\dT\d\d:\d\d(?::\d\d(?:\.\d{3})?)?(?:Z|[+-]\d\d:\d\d)$/.test(s.at??'')||!Number.isFinite(Date.parse(s.at))||!validDate(s.at.slice(0,10))))fail('invalid_schedule_date');
  if(s.kind==='interval'&&(!Number.isInteger(s.minutes)||s.minutes<5||s.minutes>10080))fail('invalid_interval');
  if(['daily','weekly','monthly'].includes(s.kind)&&!/^([01]\d|2[0-3]):[0-5]\d$/.test(s.time??''))fail('invalid_schedule_time');
  if(s.kind==='weekly'&&(!Array.isArray(s.days)||s.days.length<1||s.days.length>7||s.days.some(n=>!Number.isInteger(n)||n<0||n>6)))fail('invalid_schedule_days');
  if(s.kind==='monthly'&&(!Number.isInteger(s.day)||s.day<0||s.day>31))fail('invalid_schedule_days');
  return s;
}
function nextDue(s,after){
  s=checkSchedule(s);const epoch=new Date(after).getTime();if(!Number.isFinite(epoch))fail('invalid_date');
  if(s.kind==='once')return Date.parse(s.at)>epoch?new Date(s.at).toISOString():null;
  if(s.kind==='interval')return new Date(epoch+s.minutes*60000).toISOString();
  const start=dateAt(epoch,s.timezone);
  for(let n=0;n<70;n++){const date=addDays(start,n);if(s.kind==='weekly'&&!s.days.includes(new Date(date+'T00:00Z').getUTCDay()))continue;
    if(s.kind==='monthly'&&(s.day===0?addDays(date,1).slice(0,7)===date.slice(0,7):Number(date.slice(8))!==s.day))continue;
    // Nonexistent local time is skipped; ambiguous time runs at its first occurrence only.
    const first=instants(date,s.time,s.timezone)[0];if(first!==undefined&&first>epoch)return new Date(first).toISOString();
  }fail('no_next_occurrence');
}
function reportWindow(job,due){
  const to=new Date(due);if(!Number.isFinite(to.getTime()))fail('invalid_date');
  if(job.period==='shift'){
    const pattern=/^([01]\d|2[0-3]):[0-5]\d$/;
    if(!pattern.test(job.shift_start??'')||!pattern.test(job.shift_end??'')||job.shift_start===job.shift_end)fail('invalid_shift');
    const date=dateAt(+to,'Africa/Casablanca');
    for(let n=0;n<3;n++){
      const endDate=addDays(date,-n),end=instants(endDate,job.shift_end,'Africa/Casablanca')[0];
      if(end===undefined)fail('invalid_shift');
      if(end>+to)continue;
      const startDate=job.shift_start>job.shift_end?addDays(endDate,-1):endDate;
      const start=instants(startDate,job.shift_start,'Africa/Casablanca')[0];
      if(start===undefined||start>=end)fail('invalid_shift');
      return {from:new Date(start).toISOString(),to:new Date(end).toISOString()};
    }fail('invalid_shift');
  }
  if(['previous_day','previous_month'].includes(job.period)){
    const current=dateAt(to.getTime(),'Africa/Casablanca');
    const date=job.period==='previous_month'?current.slice(0,7)+'-01':current;
    const fromDate=job.period==='previous_month'?addDays(date,-1).slice(0,7)+'-01':addDays(date,-1);
    return {from:new Date(instants(fromDate,'00:00','Africa/Casablanca')[0]).toISOString(),to:new Date(instants(date,'00:00','Africa/Casablanca')[0]).toISOString()};
  }
  if(job.period!=='rolling'||!Number.isInteger(job.hours)||job.hours<1||job.hours>744)fail('invalid_period');
  return {from:new Date(to.getTime()-job.hours*3600000).toISOString(),to:to.toISOString()};
}
const email=value=>typeof value==='string'&&value.length<=254&&/^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/.test(value);
function checkJob(input,{preview=false}={}){
  const keys=['name','enabled','recipients','client_ids','schedule','period','hours','line_id','layout','shift_start','shift_end'];
  if(!input||Object.keys(input).some(k=>!keys.includes(k)))fail('invalid_job');
  if(typeof input.name!=='string'||input.name.trim().length<1||input.name.length>100||/[\r\n]/.test(input.name)||typeof input.enabled!=='boolean')fail('invalid_job');
  if(!Array.isArray(input.recipients)||input.recipients.length<(preview?0:1)||input.recipients.length>50||input.recipients.some(v=>!email(v)))fail('invalid_recipients');
  if(!Array.isArray(input.client_ids)||input.client_ids.length>500||input.client_ids.some(v=>typeof v!=='string'||!/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(v)))fail('invalid_clients');
  if(input.line_id!==undefined&&(typeof input.line_id!=='string'||(input.line_id!==''&&!/^[A-Za-z0-9_-]{1,40}$/.test(input.line_id))))fail('invalid_line');
  if(input.layout!==undefined&&!['standard','shift_client'].includes(input.layout))fail('invalid_layout');
  if(input.layout==='shift_client'&&!input.line_id)fail('dedicated_line_required');
  const schedule=checkSchedule(input.schedule);reportWindow(input,new Date());
  return {...input,schedule,name:input.name.trim(),recipients:[...new Set(input.recipients)],client_ids:[...new Set(input.client_ids)]};
}
module.exports={ReportsError,checkJob,checkSchedule,nextDue,reportWindow,dateAt,email};
