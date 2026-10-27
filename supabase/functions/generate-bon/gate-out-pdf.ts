import { PDFDocument, StandardFonts, rgb } from 'npm:pdf-lib@1.17.1';
import { marsaLogoBase64 } from './marsa-logo.ts';
import { tczLogoBase64 } from './tcz-logo.ts';
import { gateOutValues } from './gate-out-values.ts';
const safe = (value: unknown) => String(value ?? '').replace(/[^\n\x20-\x7e\xa0-\xff]/g,'?');
export async function gateOutSlipPdf(document: Record<string,unknown>): Promise<Uint8Array> {
  const slip=gateOutValues(document),pdf=await PDFDocument.create(),page=pdf.addPage([595.28,841.89]);
  const normal=await pdf.embedFont(StandardFonts.Helvetica),bold=await pdf.embedFont(StandardFonts.HelveticaBold);
  const navy=rgb(0.027,0.353,0.553),black=rgb(0,0,0),width=535.28,height=841.89;
  const draw=(value:unknown,x:number,top:number,size=10,strong=false,color=black)=>page.drawText(safe(value),{x,y:height-top-size,size,font:strong?bold:normal,color});
  function lines(value:unknown,maxWidth:number,size=10,strong=false):string[] {
    const font=strong?bold:normal;const rows:string[]=[];
    for(const paragraph of safe(value).split('\n')){
      let line='';
      for(const c of paragraph){if(line&&font.widthOfTextAtSize(line+c,size)>maxWidth){rows.push(line);line='';}line+=c;}
      rows.push(line);
    }
    return rows;
  }
  function row(values:string[],widths:number[],top:number,strongFirst=true,size=10):number {
    const all=values.map((v,i)=>lines(v,widths[i]-12,size,strongFirst&&i===0));
    const rowHeight=Math.max(25,...all.map(v=>v.length*(size+2)+12));
    let x=30;all.forEach((values,i)=>{
      page.drawRectangle({x,y:height-top-rowHeight,width:widths[i],height:rowHeight,borderWidth:.6,borderColor:black});
      values.forEach((value,n)=>draw(value,x+6,top+6+n*(size+2),size,strongFirst&&i===0));x+=widths[i];
    });return top+rowHeight;
  }
  const tcz=await pdf.embedPng(Uint8Array.from(atob(tczLogoBase64),c=>c.charCodeAt(0)));
  const marsa=await pdf.embedPng(Uint8Array.from(atob(marsaLogoBase64),c=>c.charCodeAt(0)));
  page.drawImage(tcz,{x:30,y:height-30-40,width:122,height:40});
  page.drawImage(marsa,{x:460,y:height-30-45,width:105,height:45});
  draw('TERMINAL CONTENEURS ZENATA',30,75,6,false,navy);
  const title='BON DE SORTIE';draw(title,(595.28-bold.widthOfTextAtSize(title,14))/2,106,14,true);
  page.drawRectangle({x:437.28,y:height-145-18,width:128,height:18,borderWidth:.6,borderColor:black});
  draw('DOUANE : '+slip.fields.customs_office,441.28,149,9);
  let top=row(['DATE/HEURE : '+slip.date,'AUTORISATION DE SORTIE N° : '+slip.reference],[width/2,width/2],182,false);
  top+=18;top=row(['IDENTIFICATION'],[width],top);
  const cols=slip.containers.length||1,cellWidth=(width-105)/cols;
  page.drawText('DOUANE',{x:95,y:height-top-48,size:48,font:bold,color:rgb(.5,.5,.5),opacity:.17});
  top=row(['NUMERO',...(slip.containers.length?slip.containers.map(c=>c.number):[''])],[105,...Array(cols).fill(cellWidth)],top);
  top=row(['Statut',...(slip.emptyChassis?['Camion vide / Châssis nu']:slip.containers.map(c=>c.status))],[105,...Array(cols).fill(cellWidth)],top);
  top+=18;
  const containerValue=(key:'iso'|'line'|'weight')=>slip.containers.length<2?
    slip.containers.map(c=>c[key]).join(''):
    slip.containers.map((c,i)=>c[key]?(i+1)+' : '+c[key]:'').filter(Boolean).join(' / ');
  for(const values of [
    ['N° DECLARATION',slip.fields.declaration_number],["MOYEN D'ENLEVEMENT",'CAMION '+slip.plate],
    ['IDENTITE CHAUFFEUR',slip.cin],["L'AGENT DU TERMINAL",slip.agent],['ISO CODE',containerValue('iso')],
    ['LIGNE OPERATEUR',containerValue('line')],['CONNAISSEMENT (B/L)',slip.fields.bill_of_lading],
    ['POIDS BRUT (KG)',containerValue('weight')?(containerValue('weight')+' kg'):''],
  ])top=row(values,[200,width-200],top);
  if(slip.orders.length){top+=6;const parts=lines('ORDRE(S) : '+slip.orders.join(' / '),width,8);parts.forEach((s,i)=>draw(s,30,top+i*10,8));top+=parts.length*10;}
  top+=10;
  top=row(['ECOR','NOM / PRENOM : '+slip.fields.ecor_name,'PPR : '+slip.fields.ecor_ppr],[65,(width-65)*.6,(width-65)*.4],top);
  top=row(['','DATE : '+slip.fields.ecor_date,'HEURE : '+slip.fields.ecor_time],[65,(width-65)*.6,(width-65)*.4],top);
  top=row(['','SCELLES : '+slip.fields.seal_number,''],[65,(width-65)*.6,(width-65)*.4],top);
  top+=20;
  top=row(['SORTIE DU\nTERMINAL','NOM / PRENOM : '+slip.fields.gate_agent_name,'PPR : '+slip.fields.gate_agent_ppr,'PORTE : '+slip.fields.gate_number],
    [65,(width-65)/2,(width-65)/3,(width-65)/6],top);
  top=row(['','DATE : '+slip.fields.gate_date,'HEURE : '+slip.fields.gate_time,''],[65,(width-65)/2,(width-65)/3,(width-65)/6],top);
  if(top>755)throw Error('Gate-out form exceeds its page; review unusually long archived values.');
  const footer=["Terminal Conteneurs Zenata - Marsa Maroc","Société d'Exploitation des Ports SA, au capital de 733.956.000,00 DH -",
    "Angle boulevard Route d'El Jadida et Rue les Papillons, Casablanca - Maroc",
    'Tél (00 212) 522 23 23 24 (L.G) Fax (00 212) 522 23 23 35 - RC :',
    'Casablanca 156717 - CNSS : 7374804 - Taxe Professionnelle : 34770868 -',
    'IF : 1104763 - ICE : 000028283000040 - www.marsamaroc.co.ma'];
  footer.forEach((line,i)=>draw(line,(595.28-normal.widthOfTextAtSize(line,6.2))/2,773+i*8,6.2,false,navy));
  return pdf.save();
}
