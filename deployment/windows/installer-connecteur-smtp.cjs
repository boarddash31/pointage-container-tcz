'use strict';
// Offline installer: only an archive supplied through the IT-approved process is accepted.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {execFileSync}=require('node:child_process');
const {createRequire}=require('node:module');
const tarOptions={encoding:'utf8',windowsHide:true,maxBuffer:4*1024*1024};

function installApprovedArchive(root,archive){
 root=fs.realpathSync(root);archive=fs.realpathSync(archive);
 const reports=fs.realpathSync(path.join(root,'reports'));
 if(path.dirname(reports)!==root)throw Error('Dossier reports hors du runtime.');
 const lock=JSON.parse(fs.readFileSync(path.join(reports,'package-lock.json'),'utf8'));
 const expected=lock.packages?.['node_modules/nodemailer'];
 if(expected?.version!=='10.6.1'||!/^sha512-[A-Za-z0-9+/]+={0,2}$/.test(expected.integrity??''))throw Error('Version/verrou du runtime non pris en charge.');
 const size=fs.statSync(archive).size;
 if(size<1||size>10*1024*1024)throw Error('Taille de paquet invalide.');
 const bytes=fs.readFileSync(archive),integrity='sha512-'+crypto.createHash('sha512').update(bytes).digest('base64');
 if(integrity!==expected.integrity)throw Error('Empreinte du paquet differente du verrou : aucune installation.');
 if(Number(process.versions.node.split('.')[0])<20)throw Error('Node20 ou plus recent requis.');
 const listing=execFileSync('tar.exe',['-tzf',archive],tarOptions).trim().split(/\r?\n/);
 const verbose=execFileSync('tar.exe',['-tvzf',archive],tarOptions).trim().split(/\r?\n/);
 if(listing.length>2000||!listing.includes('package/package.json')||verbose.some(line=>!/^[-d]/.test(line)))throw Error('Archive non reguliere : liens refuses.');
 for(const name of listing){
  const parts=name.replace(/\/$/,'').split('/');
  if(parts[0]!=='package'||parts.some(p=>!p||p==='.'||p==='..'||/[:\\\x00-\x1f]/.test(p)))throw Error('Chemin dangereux dans le paquet.');
 }
 const metadata=JSON.parse(execFileSync('tar.exe',['-xOzf',archive,'package/package.json'],tarOptions));
 if(metadata.name!=='nodemailer'||metadata.version!==expected.version||Object.keys(metadata.dependencies??{}).length)throw Error('Paquet Nodemailer autonome attendu.');
 const modules=path.join(reports,'node_modules');fs.mkdirSync(modules,{recursive:true});
 const base=fs.realpathSync(modules);
 if(path.dirname(base)!==reports)throw Error('Dossier node_modules hors du runtime.');
 const destination=path.join(base,'nodemailer');
 try{fs.lstatSync(destination);throw Error('Connecteur deja present : aucune modification. Redemarrer le runtime et verifier son etat.');}catch(error){if(error.code!=='ENOENT')throw error;}
 const stage=fs.mkdtempSync(path.join(base,'.zenata-smtp-install-'));
 let installed=false;
 try{
  execFileSync('tar.exe',['-xzf',archive,'-C',stage,'--strip-components=1'],tarOptions);
  const local=JSON.parse(fs.readFileSync(path.join(stage,'package.json'),'utf8'));
  if(local.name!==metadata.name||local.version!==metadata.version)throw Error('Metadonnees extraites invalides.');
  const driver=createRequire(path.join(stage,'package.json'))('./');
  if(typeof driver.createTransport!=='function')throw Error('Connecteur non chargeable.');
  if(path.dirname(fs.realpathSync(stage))!==base||path.dirname(destination)!==base)throw Error('Chemin installation invalide.');
  fs.renameSync(stage,destination);installed=true;
  return {version:metadata.version,destination};
 }finally{
  if(!installed&&fs.existsSync(stage)){
   const resolved=fs.realpathSync(stage);
   if(path.dirname(resolved)!==base||!path.basename(resolved).startsWith('.zenata-smtp-install-'))throw Error('Nettoyage refuse hors du dossier temporaire.');
   fs.rmSync(resolved,{recursive:true,force:true});
  }
 }
}

async function main(){
 const root=__dirname;
 if(!fs.existsSync(path.join(root,'node.exe'))||!fs.existsSync(path.join(root,'reports/package-lock.json')))throw Error('Placer les deux fichiers installateur dans le dossier du runtime ZENATA sur208.');
 const {createInterface}=require('node:readline/promises');
 const terminal=createInterface({input:process.stdin,output:process.stdout});
 let archive;
 try{
  console.log('INSTALLATION SMTP HORS LIGNE : aucun telechargement, aucun e-mail, aucun changement SQL.');
  console.log('Utiliser uniquement le paquet nodemailer-10.6.1.tgz fourni et approuve par votre IT.');
  const fallback=path.join(root,'nodemailer-10.6.1.tgz');
  archive=(await terminal.question('Chemin du paquet approuve [Entree : paquet dans ce dossier] : ')).trim()||fallback;
  if(archive.startsWith('"')&&archive.endsWith('"'))archive=archive.slice(1,-1);
 }finally{terminal.close();}
 const result=installApprovedArchive(root,path.resolve(archive));
 console.log('CONNECTEUR SMTP INSTALLE : Nodemailer '+result.version+'.');
 console.log('Fermer la console applicative avec Ctrl+C puis relancer DEMARRER-ZENATA.cmd.');
 console.log('Ensuite : Rapports > Verifier le SMTP. Aucun e-mail n\'a ete envoye par cet installateur.');
}
module.exports={installApprovedArchive};
if(require.main===module)main().catch(error=>{console.error('INSTALLATION NON REALISEE : '+error.message);process.exitCode=1;});
