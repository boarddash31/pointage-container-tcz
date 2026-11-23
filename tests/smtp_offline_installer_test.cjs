'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const crypto=require('node:crypto'),zlib=require('node:zlib');
const {installApprovedArchive}=require('../deployment/windows/installer-connecteur-smtp.cjs');

function tar(entries){
 const chunks=[];
 for(const {name,text='',type='0',link=''} of entries){
  const data=Buffer.from(text),header=Buffer.alloc(512);
  header.write(name,0,100);header.write('0000644\0',100,8);header.write('0000000\0',108,8);header.write('0000000\0',116,8);
  header.write(data.length.toString(8).padStart(11,'0')+'\0',124,12);header.write('00000000000\0',136,12);header.fill(32,148,156);
  header.write(type,156,1);header.write(link,157,100);header.write('ustar\0',257,6);header.write('00',263,2);
  header.write([...header].reduce((sum,b)=>sum+b,0).toString(8).padStart(6,'0')+'\0 ',148,8);
  chunks.push(header,data,Buffer.alloc((512-data.length%512)%512));
 }
 return zlib.gzipSync(Buffer.concat([...chunks,Buffer.alloc(1024)]));
}
function fixture(t,{extra=[],dependencies}={}){
 const parent=path.resolve(__dirname,'../.qa');fs.mkdirSync(parent,{recursive:true});
 const dir=fs.mkdtempSync(path.join(parent,'smtp-installer-test-')),root=path.join(dir,'runtime');
 fs.mkdirSync(path.join(root,'reports'),{recursive:true});
 const metadata={name:'nodemailer',version:'10.6.1',main:'index.js',...(dependencies?{dependencies}:{})};
 const bytes=tar([{name:'package/package.json',text:JSON.stringify(metadata)},
  {name:'package/index.js',text:'module.exports={createTransport(){throw Error("Synthetic fixture: SMTP must not be called");}};'},...extra]);
 const archive=path.join(dir,'approved-fixture.tgz');fs.writeFileSync(archive,bytes);
 fs.writeFileSync(path.join(root,'reports/package-lock.json'),JSON.stringify({packages:{'node_modules/nodemailer':{
  version:'10.6.1',integrity:'sha512-'+crypto.createHash('sha512').update(bytes).digest('base64')
 }}}));
 t.after(()=>{const resolved=fs.realpathSync(dir);if(path.dirname(resolved)!==fs.realpathSync(parent)||!path.basename(resolved).startsWith('smtp-installer-test-'))throw Error('Unsafe fixture cleanup');fs.rmSync(resolved,{recursive:true,force:true});});
 return {dir,root,archive,target:path.join(root,'reports/node_modules/nodemailer')};
}

test('approved archive installs only under reports/node_modules and never calls SMTP',t=>{
 const f=fixture(t);
 fs.mkdirSync(path.join(f.root,'.state/reports'),{recursive:true});
 const settings=path.join(f.root,'.state/reports/fixture-private.txt');fs.writeFileSync(settings,'unchanged');
 const result=installApprovedArchive(f.root,f.archive);
 assert.equal(result.version,'10.6.1');assert.equal(result.destination,f.target);
 assert.equal(JSON.parse(fs.readFileSync(path.join(f.target,'package.json'),'utf8')).version,'10.6.1');
 assert.equal(fs.readFileSync(settings,'utf8'),'unchanged');
 assert.equal(fs.readdirSync(path.dirname(f.target)).filter(name=>name.startsWith('.zenata-smtp-install-')).length,0);
});
test('wrong archive integrity is rejected before creating a module directory',t=>{
 const f=fixture(t);fs.appendFileSync(f.archive,'tampered');
 assert.throws(()=>installApprovedArchive(f.root,f.archive),/Empreinte/);
 assert.equal(fs.existsSync(path.dirname(f.target)),false);
});
test('traversal entries are rejected before extraction',t=>{
 const f=fixture(t,{extra:[{name:'package/../outside.txt',text:'bad'}]});
 assert.throws(()=>installApprovedArchive(f.root,f.archive),/Chemin dangereux/);
 assert.equal(fs.existsSync(f.target),false);assert.equal(fs.existsSync(path.join(f.root,'outside.txt')),false);
});
test('symlink entries are rejected before extraction',t=>{
 const f=fixture(t,{extra:[{name:'package/escape',type:'2',link:'../../outside'}]});
 assert.throws(()=>installApprovedArchive(f.root,f.archive),/liens refuses/);
 assert.equal(fs.existsSync(f.target),false);
});
test('existing driver is preserved instead of overwritten',t=>{
 const f=fixture(t);fs.mkdirSync(f.target,{recursive:true});fs.writeFileSync(path.join(f.target,'sentinel'),'keep');
 assert.throws(()=>installApprovedArchive(f.root,f.archive),/deja present/);
 assert.equal(fs.readFileSync(path.join(f.target,'sentinel'),'utf8'),'keep');
});
test('unprovided dependencies cannot trigger an online install',t=>{
 const f=fixture(t,{dependencies:{'unavailable-fixture':'1.0.0'}});
 assert.throws(()=>installApprovedArchive(f.root,f.archive),/autonome attendu/);
 assert.equal(fs.existsSync(f.target),false);
});
