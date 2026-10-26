import { PDFDocument, StandardFonts, rgb } from 'npm:pdf-lib@1.17.1';
import { marsaLogoBase64 } from './marsa-logo.ts';

type Values = Record<string, unknown>;
const string = (v: unknown) => String(v ?? '').trim().replace(/[^\x20-\x7e\xa0-\xff]/g, '?');
const map = (v: unknown): Values => v && typeof v === 'object' ? v as Values : {};
const footer = [
  "Société d'Exploitation des Ports SA, au capital de 733.956.000,00 DH -",
  "Angle boulevard Route d'El Jadida et Rue les Papillons, Casablanca - Maroc",
  'Tél (00 212) 522 23 23 24 (L.G) Fax (00 212) 522 23 23 35 - RC :',
  'Casablanca 156717 - CNSS : 7374804 - Taxe Professionnelle : 34770868 -',
  'IF : 1104763 - ICE : 000028283000040 - www.marsamaroc.co.ma',
];

export async function terminalSlipPdf(document: Values): Promise<Uint8Array> {
  const v = map(document.snapshot), event = map(v.event), context = map(document.print_context);
  const kind = string(document.kind).toUpperCase();
  const receiving = kind === 'DEPOSE' || (kind !== 'PRISE' && v.entry_kind === 'loaded');
  const pdf = await PDFDocument.create();
  const page = pdf.addPage([419.53, 595.28]);
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  const logo = await pdf.embedPng(Uint8Array.from(atob(marsaLogoBase64), c => c.charCodeAt(0)));
  const text = (value: unknown, x: number, top: number, size = 9) => page.drawText(string(value), {x, y:595.28-top-size, size, font, color:rgb(0,0,0)});
  const center = (value: string, top: number, size: number) => text(value,(419.53-font.widthOfTextAtSize(value,size))/2,top,size);
  const wrap = (value: string, x: number, top: number, width: number, size: number): number => {
    let part = '';
    for (const c of value) {
      if (part && font.widthOfTextAtSize(part+c,size)>width) {text(part,x,top,size);top+=size+3;part='';}
      part+=c;
    }
    text(part,x,top,size);return top+size+3;
  };
  let date = string(context.created_at_local);
  if (!date) {
    const d = new Date(String(document.created_at ?? v.entered_at));
    if (!isNaN(d.getTime())) {
      const p = Object.fromEntries(new Intl.DateTimeFormat('en-GB',{timeZone:'Africa/Casablanca',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'}).formatToParts(d).map(p=>[p.type,p.value]));
      date = `${p.year}-${p.month}-${p.day} ${p.hour}:${p.minute}:${p.second}`;
    }
  }
  page.drawImage(logo,{x:26,y:595.28-25-39.15,width:92,height:39.15});
  text('WE LIFT YOUR GROWTH',34,67,4.8);
  center(receiving?'Bon Décharge':'Bon Charge',86,14);
  text('A Check',18,118);center(date,118,9);text('Instr .Camion',345,118);
  text('Visite :',18,140,13);text(context.visit_number ?? v.visit_number ?? document.visit_id,18,158,8);
  text(`N° Registration : ${string(v.plate)}`,144,140);
  text(`CIN Chauffeur : ${string(v.driver_cin)}`,144,158);
  const widths=[42,21,21,76,58,29,21,21,20];
  let x=18;const headers=['VOIE','Hnd','P/V','Conteneur','Ligne','ISO','Lg','Ht','Tp'];
  headers.forEach((h,i)=>{text(h,x,189);x+=widths[i];});
  let top=203;
  for (const suffix of v.is_twin?['','_2']:['']) {
    const eventContainer=event[suffix?'container_2':'container'];
    const container=(kind==='PRISE'||kind==='DEPOSE')&&string(eventContainer)?eventContainer:v['container_number'+suffix];
    const row=[v['lane'+suffix],receiving?'In':'Out',v['load_status'+suffix],container,v['armateur_id'+suffix],v['iso_code'+suffix],v['length'+suffix],v['height'+suffix],v['type'+suffix]];
    x=18;let nextTop=top+15;
    row.forEach((value,i)=>{nextTop=Math.max(nextTop,wrap(string(value),x,top,widths[i]-3,8.8));x+=widths[i];});
    top=nextTop;
  }
  const refs=[...new Set([v.carrier_booking_reference??event.booking??v.booking,...(v.is_twin?[v.booking_reference_2]:[])].map(string).filter(Boolean))];
  if(refs.length)top=wrap('Booking / EDO / ERO : '+refs.join(' / '),18,top+8,383,7.5);
  top+=12;top=wrap("L'agent du Terminal : "+string(context.agent_name??v.agent_name),38,top,363,10);
  top+=7;text(date,419.53-60-font.widthOfTextAtSize(date,10),top,10);
  top+=33;
  page.drawLine({start:{x:18,y:595.28-top},end:{x:401.53,y:595.28-top},thickness:.6,dashArray:[1.5,1.5]});
  top+=6;for(const line of footer){center(line,top,8);top+=11;}
  return pdf.save();
}
