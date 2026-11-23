'use strict';
const fs=require('node:fs/promises'),path=require('node:path'),crypto=require('node:crypto');
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const quote=s=>"N'"+s.replaceAll("'","''")+"'";
async function main(){
 const root=path.resolve(__dirname,'..'),sqlRoot=path.join(root,'migration/sqlserver');
 require('../migration/sqlserver/tools/generate-transfer-manifest.cjs');
 const stage=await fs.mkdtemp(path.join(root,'.qa/sql-transfer-'));
 const packageRoot=path.join(stage,'ZENATA-PREPARATION-TRANSFERT');
 const project=path.join(packageRoot,'backend/Pointage.Migration');await fs.mkdir(project,{recursive:true});
 for(const name of ['Program.cs','Pointage.Migration.csproj'])await fs.copyFile(path.join(root,'backend/Pointage.Migration',name),path.join(project,name));
 await fs.copyFile(path.join(root,'backend/global.json'),path.join(packageRoot,'backend/global.json'));
 const manifests=path.join(packageRoot,'migration/sqlserver');await fs.mkdir(manifests,{recursive:true});
 for(const name of ['manifest.json','manifest-v5.json','source-columns-20261121.json'])await fs.copyFile(path.join(sqlRoot,name),path.join(manifests,name));
 await fs.mkdir(path.join(packageRoot,'SQL/sources'),{recursive:true});
 const preflight=await fs.readFile(path.join(sqlRoot,'deployment/00_CONTROLE_CONNEXION.sql'),'utf8');
 const upgrade=await fs.readFile(path.join(sqlRoot,'011_profile_source_identifiers.sql'),'utf8');
 await fs.writeFile(path.join(packageRoot,'SQL/sources/011_profile_source_identifiers.sql'),upgrade);
 const wrapper=`-- DBeaver : nouvelle session auto-commit, selectionner toszps, Ctrl+A puis Ctrl+Entree.
-- Complement ADDITIF : aucun import, compte, lancement d'API ou bascule.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF @@TRANCOUNT<>0 OR (@@OPTIONS & 2)<>0 THROW 51100, 'Nouvelle connexion en auto-commit requise.', 1;
DECLARE @phase_identifiants nvarchar(200)=N'Controle de cible';
BEGIN TRY
 EXEC sys.sp_executesql ${quote(preflight)};
 IF IS_ROLEMEMBER(N'db_owner')<>1 AND IS_SRVROLEMEMBER(N'sysadmin')<>1 THROW 51100, 'Compte de deploiement requis.', 1;
 IF (SELECT COUNT(*) FROM internal.schema_versions WHERE version IN(1,2,3,4))<>4 OR
  (SELECT MAX(version) FROM internal.schema_versions)<>4
  THROW 51100, 'Versions1/2/3/4 attendues ; ne pas rejouer un complement deja installe.', 1;
 IF COL_LENGTH(N'dbo.profiles',N'username') IS NOT NULL THROW 51100, 'Colonne username deja presente : verifier la cible.', 1;
 SET @phase_identifiants=N'Sauvegarde avant complement';
 DECLARE @dossier_sauvegarde nvarchar(4000)=CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultBackupPath'));
 IF @dossier_sauvegarde IS NULL OR LEN(TRIM(@dossier_sauvegarde))=0 THROW 51100, 'Repertoire de sauvegarde SQL inconnu.', 1;
 DECLARE @fichier_sauvegarde nvarchar(4000)=@dossier_sauvegarde+
  CASE WHEN RIGHT(@dossier_sauvegarde,1) IN(N'\\',N'/') THEN N'' ELSE N'\\' END+
  N'toszps_avant_identifiants5_'+CONVERT(nvarchar(36),NEWID())+N'.bak';
 BACKUP DATABASE [toszps] TO DISK=@fichier_sauvegarde WITH COPY_ONLY,CHECKSUM,NOINIT,STATS=10;
 SELECT @fichier_sauvegarde AS sauvegarde_sur_serveur_SQL,N'COPY_ONLY avec CHECKSUM terminee ; restauration non testee' AS statut;
 SET @phase_identifiants=N'Complement transactionnel identifiants';
 BEGIN TRANSACTION;
 EXEC sys.sp_executesql ${quote(upgrade)};
 COMMIT TRANSACTION;
 SELECT N'COMPLEMENT IDENTIFIANTS VERSION5 INSTALLE' AS resultat,MAX(version) AS version_schema FROM internal.schema_versions;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 DECLARE @erreur_identifiants nvarchar(2048)=CONCAT(@phase_identifiants,N' ; SQL ',ERROR_NUMBER(),N' ; ligne ',ERROR_LINE(),N' ; ',ERROR_MESSAGE());
 THROW 51101,@erreur_identifiants,1;
END CATCH;
`;
 await fs.writeFile(path.join(packageRoot,'SQL/14_COMPLETER_IDENTIFIANTS_DBEAVER.sql'),wrapper);
 // A new ignored folder holds only the fixture created by the synthetic generator.
 await fs.mkdir(path.join(root,'.migration-data'),{recursive:true});
 const fixtureRoot=await fs.mkdtemp(path.join(root,'.migration-data/transfer-selftest-'));
 const fixture=path.join(fixtureRoot,'snapshot-v5');
 require('../migration/sqlserver/tools/create-test-snapshot.cjs').createFixture(path.relative(root,fixture),'v5');
 const fixtureTarget=path.join(packageRoot,'TESTS-FICTIFS/snapshot-v5');await fs.mkdir(fixtureTarget,{recursive:true});
 for(const name of await fs.readdir(fixture)){
  if(name!=='snapshot.json'&&!/^(public|private)\.[a-z_]+\.ndjson$/.test(name))throw Error('Unexpected synthetic fixture filename');
  await fs.copyFile(path.join(fixture,name),path.join(fixtureTarget,name));
 }
 await fs.copyFile(path.join(sqlRoot,'deployment/TRANSFERT-V5.md'),path.join(packageRoot,'LIRE-MOI.md'));
 const launcher=(await fs.readFile(path.join(root,'deployment/windows/VALIDER-TRANSFERT.cmd'),'utf8')).replace(/\r?\n/g,'\r\n');
 await fs.writeFile(path.join(packageRoot,'VALIDER-TRANSFERT.cmd'),launcher);
 const files=[];
 async function collect(dir){for(const e of await fs.readdir(dir,{withFileTypes:true})){
  const file=path.join(dir,e.name);if(e.isSymbolicLink())throw Error('Unexpected symbolic link');
  if(e.isDirectory())await collect(file);else files.push({path:path.relative(packageRoot,file).split(path.sep).join('/'),sha256:hash(await fs.readFile(file))});
 }}await collect(packageRoot);
 await fs.writeFile(path.join(packageRoot,'INTEGRITE.json'),JSON.stringify({preparedOn:'2026-11-21',purpose:'prepare-version5-transfer-preserving-source-usernames',sourceMetadataReadOnly:true,realDataExported:false,applicationCutover:false,remoteDeployment:false,files},null,2));
 await fs.writeFile(path.join(root,'.qa/sql-transfer-stage.json'),JSON.stringify({stage,packageRoot,fixture},null,2));
 console.log(JSON.stringify({stage,packageRoot,files:files.length+1}));
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
