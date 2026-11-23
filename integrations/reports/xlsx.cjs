'use strict';
// Narrow Open XML writer: strings/numbers, frozen headers and filters. No formulas,
// macros, hyperlinks or external resources. ZIP entries are stored without compression.
const escape=value=>String(value).replace(/[\x00-\x08\x0b\x0c\x0e-\x1f]/g,'').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&apos;');
const table=Array.from({length:256},(_,n)=>{let c=n;for(let i=0;i<8;i++)c=c&1?0xedb88320^(c>>>1):c>>>1;return c>>>0;});
function crc32(buffer){let c=0xffffffff;for(const byte of buffer)c=table[(c^byte)&255]^(c>>>8);return (c^0xffffffff)>>>0;}
function zip(entries){const local=[],central=[];let offset=0;
 for(const [name,text] of entries){const filename=Buffer.from(name),data=Buffer.from(text),crc=crc32(data),head=Buffer.alloc(30);
  head.writeUInt32LE(0x04034b50);head.writeUInt16LE(20,4);head.writeUInt16LE(0x800,6);head.writeUInt16LE(33,12);head.writeUInt32LE(crc,14);head.writeUInt32LE(data.length,18);head.writeUInt32LE(data.length,22);head.writeUInt16LE(filename.length,26);
  local.push(head,filename,data);const directory=Buffer.alloc(46);directory.writeUInt32LE(0x02014b50);directory.writeUInt16LE(20,4);directory.writeUInt16LE(20,6);directory.writeUInt16LE(0x800,8);directory.writeUInt16LE(33,14);directory.writeUInt32LE(crc,16);directory.writeUInt32LE(data.length,20);directory.writeUInt32LE(data.length,24);directory.writeUInt16LE(filename.length,28);directory.writeUInt32LE(offset,42);central.push(directory,filename);offset+=head.length+filename.length+data.length;
 }
 const directory=Buffer.concat(central),end=Buffer.alloc(22);end.writeUInt32LE(0x06054b50);end.writeUInt16LE(entries.length,8);end.writeUInt16LE(entries.length,10);end.writeUInt32LE(directory.length,12);end.writeUInt32LE(offset,16);
 return Buffer.concat([...local,directory,end]);
}
function column(n){let s='';for(n++;n;n=Math.floor((n-1)/26))s=String.fromCharCode(65+(n-1)%26)+s;return s;}
const declaration='<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
function xlsx(sheets){
 const ns='http://schemas.openxmlformats.org/spreadsheetml/2006/main',rel='http://schemas.openxmlformats.org/officeDocument/2006/relationships';
 const entries=[
  ['[Content_Types].xml',declaration+'<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'+sheets.map((_,i)=>`<Override PartName="/xl/worksheets/sheet${i+1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>`).join('')+'</Types>'],
  ['_rels/.rels',declaration+`<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="${rel}/officeDocument" Target="xl/workbook.xml"/></Relationships>`],
  ['xl/workbook.xml',declaration+`<workbook xmlns="${ns}" xmlns:r="${rel}"><sheets>`+sheets.map((s,i)=>`<sheet name="${escape(s.name)}" sheetId="${i+1}" r:id="rId${i+1}"/>`).join('')+'</sheets></workbook>'],
  ['xl/_rels/workbook.xml.rels',declaration+`<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">`+sheets.map((_,i)=>`<Relationship Id="rId${i+1}" Type="${rel}/worksheet" Target="worksheets/sheet${i+1}.xml"/>`).join('')+'</Relationships>'],
 ];
 const styles=declaration+`<styleSheet xmlns="${ns}"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF185A86"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>`;
 entries[0][1]=entries[0][1].replace('</Types>','<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>');
 entries[3][1]=entries[3][1].replace('</Relationships>',`<Relationship Id="rId${sheets.length+1}" Type="${rel}/styles" Target="styles.xml"/></Relationships>`);
 entries.push(['xl/styles.xml',styles]);
 for(const [i,sheet] of sheets.entries()){
  const rows=[sheet.headers,...sheet.rows];const xml=rows.map((row,r)=>`<row r="${r+1}">`+row.map((value,c)=>{
   const ref=column(c)+(r+1),style=r===0?' s="1"':'';return typeof value==='number'&&Number.isFinite(value)?`<c r="${ref}"${style}><v>${value}</v></c>`:`<c r="${ref}"${style} t="inlineStr"><is><t xml:space="preserve">${escape(value??'')}</t></is></c>`;
  }).join('')+'</row>').join('');
  entries.push([`xl/worksheets/sheet${i+1}.xml`,declaration+`<worksheet xmlns="${ns}"><dimension ref="A1:${column(sheet.headers.length-1)}${rows.length}"/><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols><col min="1" max="${sheet.headers.length}" width="25" customWidth="1"/></cols><sheetData>${xml}</sheetData><autoFilter ref="A1:${column(sheet.headers.length-1)}${rows.length}"/></worksheet>`]);
 }
 const bytes=zip(entries);if(bytes.length>20*1024*1024)throw Error('report_attachment_too_large');return bytes;
}
module.exports={xlsx};
