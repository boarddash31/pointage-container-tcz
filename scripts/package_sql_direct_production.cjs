'use strict';
const fs=require('node:fs/promises'),path=require('node:path'),crypto=require('node:crypto');
const quote=s=>"N'"+s.replaceAll("'","''")+"'";
async function main(){
 const root=path.resolve(__dirname,'..');
 await require('./generate_sql_gate_upgrade.cjs').generate();
 const sqlRoot=path.join(root,'migration/sqlserver'),deployment=path.join(sqlRoot,'deployment');
 const preflight=await fs.readFile(path.join(deployment,'00_CONTROLE_CONNEXION.sql'),'utf8');
 const upgrade=await fs.readFile(path.join(deployment,'12_GATE_TOSZPS_DBEAVER.sql'),'utf8');
 const sql=`-- Mise a jour DIRECTE du socle toszps, sur demande du proprietaire.
-- Les scenarios de recette SQL n'ont pas ete executes. Aucun test fictif ici.
-- DBeaver : nouvelle connexion auto-commit, base toszps, Ctrl+A puis Ctrl+Entree.
-- Sauvegarde complete COPY_ONLY/CHECKSUM dans le repertoire prive par defaut du serveur SQL.
-- Cette operation ne bascule pas l'application depuis Supabase.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF @@TRANCOUNT<>0 OR (@@OPTIONS & 2)<>0 THROW 51100, 'Nouvelle connexion en auto-commit requise.', 1;
DECLARE @phase_directe nvarchar(200)=N'Controle de cible';
BEGIN TRY
 EXEC sys.sp_executesql ${quote(preflight)};
 IF IS_ROLEMEMBER(N'db_owner')<>1 AND IS_SRVROLEMEMBER(N'sysadmin')<>1 THROW 51100, 'Compte de deploiement requis.', 1;
 IF (SELECT compatibility_level FROM sys.databases WHERE database_id=DB_ID())<>170 THROW 51100, 'Compatibilite170 requise.', 1;
 IF DATABASEPROPERTYEX(DB_NAME(),'Updateability')<>N'READ_WRITE' THROW 51100, 'Base modifiable requise.', 1;
 IF (SELECT COUNT(*) FROM internal.schema_versions WHERE version IN(1,2,3))<>3 OR EXISTS(SELECT 1 FROM internal.schema_versions WHERE version>=4)
  THROW 51100, 'Socle versions1/2/3 attendu ; ne pas rejouer une mise a jour deja installee.', 1;
 SET @phase_directe=N'Sauvegarde avant modification';
 DECLARE @dossier_sauvegarde nvarchar(4000)=CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultBackupPath'));
 IF @dossier_sauvegarde IS NULL OR LEN(TRIM(@dossier_sauvegarde))=0 THROW 51100, 'Repertoire de sauvegarde SQL inconnu : faire configurer le chemin par IT.', 1;
 DECLARE @fichier_sauvegarde nvarchar(4000)=@dossier_sauvegarde+
  CASE WHEN RIGHT(@dossier_sauvegarde,1) IN(N'\\',N'/') THEN N'' ELSE N'\\' END+
  N'toszps_avant_gate4_'+REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(19),SYSUTCDATETIME(),126),N'-',N''),N':',N''),N'T',N'_')+
  N'_'+CONVERT(nvarchar(36),NEWID())+N'.bak';
 BACKUP DATABASE [toszps] TO DISK=@fichier_sauvegarde WITH COPY_ONLY,CHECKSUM,NOINIT,STATS=10;
 SELECT @fichier_sauvegarde AS sauvegarde_sur_serveur_SQL,N'COPY_ONLY avec CHECKSUM terminee ; restauration non testee' AS statut;
 SET @phase_directe=N'Mise a jour transactionnelle Gate4';
 EXEC sys.sp_executesql ${quote(upgrade)};
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 DECLARE @erreur_directe nvarchar(2048)=CONCAT(@phase_directe,N' ; SQL ',ERROR_NUMBER(),N' ; ligne ',ERROR_LINE(),N' ; ',ERROR_MESSAGE());
 THROW 51101,@erreur_directe,1;
END CATCH;
`;
 const stage=await fs.mkdtemp(path.join(root,'.qa/sql-prod-directe-'));
 const packageRoot=path.join(stage,'ZENATA-SQL-PROD-DIRECTE');await fs.mkdir(packageRoot);
 await fs.writeFile(path.join(packageRoot,'APPLIQUER_GATE_PROD_DBEAVER.sql'),sql);
 await fs.copyFile(path.join(deployment,'PROD-DIRECTE.md'),path.join(packageRoot,'LIRE-MOI.md'));
 await fs.mkdir(path.join(packageRoot,'sources'));
 for(const name of ['008_gate_operations.sql','009_gate_lifecycle.sql'])await fs.copyFile(path.join(sqlRoot,name),path.join(packageRoot,'sources',name));
 const files=[];
 async function collect(dir){for(const e of await fs.readdir(dir,{withFileTypes:true})){
  const p=path.join(dir,e.name);if(e.isDirectory())await collect(p);else files.push({path:path.relative(packageRoot,p).split(path.sep).join('/'),sha256:crypto.createHash('sha256').update(await fs.readFile(p)).digest('hex')});
 }}await collect(packageRoot);
 await fs.writeFile(path.join(packageRoot,'INTEGRITE.json'),JSON.stringify({preparedOn:'2026-11-21',purpose:'direct-schema-upgrade-with-prior-backup',sqlRecipeExecuted:false,applicationCutover:false,remoteDeployment:false,files},null,2));
 await fs.writeFile(path.join(root,'.qa/sql-direct-production-stage.json'),JSON.stringify({stage,packageRoot},null,2));
 console.log(JSON.stringify({stage,packageRoot,files:files.length+1}));
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
