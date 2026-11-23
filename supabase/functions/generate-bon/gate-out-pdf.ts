import { PDFDocument, StandardFonts, rgb } from 'npm:pdf-lib@1.17.1';
import { zpsLogoBase64 } from './zps-logo.ts';
import { gateOutValues } from './gate-out-values.ts';
const safe=(value:unknown)=>String(value??'').replace(/[^\n\x20-\x7e\xa0-\xff]/g,'?');
export async function gateOutSlipPdf(document:Record<string,unknown>):Promise<Uint8Array> {
  const slip=gateOutValues(document),pdf=await PDFDocument.create();
  const normal=await pdf.embedFont(StandardFonts.Helvetica),bold=await pdf.embedFont(StandardFonts.HelveticaBold);
  const logo=await pdf.embedJpg(Uint8Array.from(atob(zpsLogoBase64),c=>c.charCodeAt(0)));
  const containerValue=(key:'number'|'iso'|'line'|'seal'|'status')=>slip.containers.map((c,i)=>`TC${i+1} : ${c[key]}`).join('\n');
  const values=[
    ['TRANSPORTEUR',slip.fields.haulier],['DATE ET HEURE',slip.date],['AUTORISATION N°',slip.reference],
    ['RÉF. '+slip.orderKind,slip.orders.join(' / ')],['CAMION IMM.',slip.plate],['CIN CHAUFFEUR',slip.cin],
    ['CONTENEUR N°',containerValue('number')],['ISO CODE',containerValue('iso')],['LIGNE OPÉRATEUR',containerValue('line')],
    ['SCELLÉ',containerValue('seal')],['STATUT',slip.emptyChassis?'Camion vide / Châssis nu':containerValue('status')],
    ['ID AGENT',slip.fields.agent_id||slip.agent],
  ];
  const wrap=(value:string,width:number,strong=false)=>{
    const font=strong?bold:normal,result:string[]=[];
    for(const paragraph of safe(value).split('\n')){
      let line='';for(const char of paragraph){if(line&&font.widthOfTextAtSize(line+char,9)>width){result.push(line);line='';}line+=char;}result.push(line);
    }return result;
  };
  for(const copy of ['Client','Transporteur','Sécurité']) {
    const page=pdf.addPage([419.53,595.28]),height=595.28,width=379.53;
    const text=(value:string,x:number,top:number,size=9,strong=false)=>page.drawText(safe(value),{x,y:height-top-size,size,font:strong?bold:normal,color:rgb(0,0,0)});
    page.drawImage(logo,{x:20,y:height-20-49,width:84,height:49});
    text('Exemplaire '+copy,270,32,9);
    const title='BON DE SORTIE';text(title,(419.53-bold.widthOfTextAtSize(title,15))/2,78,15,true);
    let top=108;
    for(const [label,value] of values){
      const cells=[wrap(label,width*.4-14,true),wrap(value,width*.6-14)];
      const rowHeight=Math.max(...cells.map(c=>c.length))*11+14;
      let x=20;
      cells.forEach((lines,i)=>{const w=width*(i===0?.4:.6);
        page.drawRectangle({x,y:height-top-rowHeight,width:w,height:rowHeight,borderWidth:.6,borderColor:rgb(0,0,0),color:rgb(1,1,1)});
        lines.forEach((line,n)=>text(line,x+7,top+7+n*11,9,i===0));x+=w;
      });top+=rowHeight;
    }
    if(top>550)throw Error('A5 gate-out form exceeds its page; review unusually long archived values.');
    const footer='Zenata Port Sec';text(footer,(419.53-normal.widthOfTextAtSize(footer,9))/2,567,9);
  }
  return pdf.save();
}
