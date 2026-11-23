'use strict';
const {xlsx}=require('./xlsx.cjs');
const {ReportsError}=require('./calendar.cjs');
function reportData(raw,window,clientIds=[],lineId=''){
 const names=new Map(raw.clients.map(c=>[c.id,c.name])),wanted=new Set(clientIds),inside=id=>!wanted.size||wanted.has(id);
 const client=id=>id?(names.get(id)||id):'Sans client attribué';
 const entries=[],exits=[],stock=[],seen=new Map();
 for(const doc of raw.documents){
  const v=doc.snapshot??{},type=doc.kind==='ENTREE'&&v.entry_kind==='loaded'?'entry':doc.kind==='SORTIE'&&v.entry_kind==='empty'?'exit':null;
  if(!type||!inside(v.client_id))continue;
  const time=type==='entry'?(v.entered_at??doc.created_at):(v.exited_at??doc.created_at);
  const date=Date.parse(time);if(!Number.isFinite(date))throw new ReportsError('invalid_movement_date');
  if(date<Date.parse(window.from)||date>=Date.parse(window.to))continue;
  for(const suffix of ['',...(v.is_twin===true?['_2']:[])]){
   if(lineId&&v['armateur_id'+suffix]!==lineId)continue;
   if(!v['container_number'+suffix]||!v['iso_code'+suffix]||!v['armateur_id'+suffix])throw new ReportsError('incomplete_movement');
   const row={clientId:v.client_id??null,client:client(v.client_id),time:new Date(date).toISOString(),container:v['container_number'+suffix],
    iso:v['iso_code'+suffix],line:v['armateur_id'+suffix],order:suffix?v.booking_reference_2??'':v.carrier_booking_reference??v.event_booking??'',plate:v.plate??''};
   const id=doc.id+suffix,serialized=JSON.stringify(row);if(seen.has(id)){if(seen.get(id)!==serialized)throw new ReportsError('conflicting_snapshot');continue;}seen.set(id,serialized);
   (type==='entry'?entries:exits).push(row);
  }
 }
 const containers=new Set();
 for(const row of raw.stock){
  if(lineId&&row.armateur_id!==lineId)continue;
  if(!inside(row.client_id))continue;
  if(!Number.isFinite(Date.parse(row.arrived_at))||(row.departed_at&&!Number.isFinite(Date.parse(row.departed_at))))throw new ReportsError('invalid_stock_date');
  if(Date.parse(row.arrived_at)>=Date.parse(window.to)||(row.departed_at&&Date.parse(row.departed_at)<Date.parse(window.to)))continue;
  if(containers.has(row.container_number))throw new ReportsError('overlapping_stock');containers.add(row.container_number);
  stock.push({clientId:row.client_id??null,client:client(row.client_id),container:row.container_number,iso:row.iso_code,line:row.armateur_id,time:row.arrived_at,position:row.position??''});
 }
 const groups=new Map();for(const [key,rows] of [['entries',entries],['exits',exits],['stock',stock]])for(const row of rows){
  const id=row.clientId??'unassigned';if(!groups.has(id))groups.set(id,{client:row.client,entries:0,exits:0,stock:0});groups.get(id)[key]++;
 }
 // Selected clients without activity still appear explicitly with zero quantities.
 for(const id of wanted)if(!groups.has(id))groups.set(id,{client:client(id),entries:0,exits:0,stock:0});
 return {entries,exits,stock,lineId,isoRules:raw.isoRules??[],evpRules:raw.evpRules??[],groups:[...groups.values()].sort((a,b)=>a.client.localeCompare(b.client,'fr'))};
}
const local=value=>new Intl.DateTimeFormat('fr-FR',{timeZone:'Africa/Casablanca',dateStyle:'short',timeStyle:'medium'}).format(new Date(value));
async function workbook(data,window,name,layout='standard'){
 const sheets=[];
 function sheet(title,headers,rows){sheets.push({name:title,headers,rows});}
 sheet('Synthèse',['Client','Entrées conteneurs Gate IN','Sorties conteneurs Gate OUT','Stock parc en fin de période'],data.groups.map(r=>[r.client,r.entries,r.exits,r.stock]));
 for(const [title,rows] of [['Entrées',data.entries],['Sorties',data.exits]])sheet(title,['Client','Date/heure Maroc','Conteneur','ISO','Armateur','Référence EDO/ERO','Camion'],rows.map(r=>[r.client,local(r.time),r.container,r.iso,r.line,r.order,r.plate]));
 sheet('Stock',['Client','Conteneur','ISO','Armateur','Arrivée parc (Maroc)','Position'],data.stock.map(r=>[r.client,r.container,r.iso,r.line,local(r.time),r.position]));
 if(layout==='shift_client'){
  const day=require('./calendar.cjs').dateAt(Date.parse(window.to)-1,'Africa/Casablanca');
  const latest=(rules,predicate)=>rules.filter(r=>predicate(r)&&r.effective_from<=day).sort((a,b)=>b.effective_from.localeCompare(a.effective_from))[0];
  const categories=['20 DV','40 DV ST','40 DV HC','45 DV','FRIGO 20','FRIGO 40','OT&FL&HP&CT','NON CLASSES'];
  const classified=data.stock.map(row=>{
    const rule=latest(data.isoRules,r=>r.iso_code===row.iso),factor=rule?latest(data.evpRules,r=>r.size_feet===rule.size_feet):null;
    if(factor&&(!Number.isFinite(Number(factor.factor))||Number(factor.factor)<=0))throw new ReportsError('invalid_evp_rule');
    return {...row,category:categories.includes(rule?.category)?rule.category:'NON CLASSES',size:rule?.size_feet??'',evp:factor?Number(factor.factor):null};
  });
  sheet('RECAP',['STOCK DES CONTENEURS VIDES','Quantité','EVP connus','EVP à vérifier'],[
    ['Armateur',data.lineId||'Tous les armateurs','',''],['Fin du shift / période',local(window.to),'',''],
    ...categories.map(c=>{const rows=classified.filter(r=>r.category===c);return [c,rows.length,rows.reduce((s,r)=>s+(r.evp??0),0),rows.filter(r=>r.evp===null).length];}),
    ['TOTAL',classified.length,classified.reduce((s,r)=>s+(r.evp??0),0),classified.filter(r=>r.evp===null).length],
  ]);
  const date=value=>new Intl.DateTimeFormat('fr-CA',{timeZone:'Africa/Casablanca',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(value));
  const time=value=>new Intl.DateTimeFormat('fr-FR',{timeZone:'Africa/Casablanca',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'}).format(new Date(value));
  for(const category of categories)sheet(category,['CONTENEUR','LIGNE','ISO','TP','LG','HT','DATE D ARRIVEE AU TERMINAL','HEURE D ARRIVEE AU TERMINAL'],classified.filter(r=>r.category===category).map(r=>[r.container,r.line,r.iso,category.includes('DV')?'DV':category.startsWith('FRIGO')?'RF':'',r.size,'',date(r.time),time(r.time)]));
 }
 sheet('Période',['Paramètre','Valeur'],[['Rapport',name],['Début inclus (Maroc)',local(window.from)],['Fin exclue (Maroc)',local(window.to)],['Stock','Présence au parc juste avant la fin exclue'],['Comptage','Un mouvement par conteneur ; les camions vides ne sont pas des sorties de conteneurs'],['Attribution','Client métier enregistré ; aucune déduction depuis l’armateur'],['Fuseau','Africa/Casablanca']]);
 sheets.at(-1).rows.push(['Armateur destinataire',data.lineId||'Tous les armateurs']);
 if(layout==='shift_client')sheets.at(-1).rows.push(['Modèle client','Stock classé selon les règles ISO et EVP enregistrées. Codes sans règle : NON CLASSES ; EVP manquants signalés dans RECAP. HT non renseignée faute de donnée enregistrée.']);
 return xlsx(sheets);
}
module.exports={reportData,workbook};
