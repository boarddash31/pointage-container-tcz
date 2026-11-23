'use strict';
const fs=require('node:fs/promises'),path=require('node:path');
const quote=s=>"N'"+s.replaceAll("'","''")+"'";
const batches=s=>s.replaceAll('\r\n','\n').split(/^\s*GO\s*$/m).map(s=>s.trim()).filter(Boolean);
async function generate(){
 const root=path.resolve(__dirname,'../migration/sqlserver');
 const old=batches(await fs.readFile(path.join(root,'009_gate_lifecycle.sql'),'utf8')).find(s=>s.startsWith('CREATE OR ALTER PROCEDURE api.move_visit '));
 if(!old)throw Error('Cannot find the verified baseline gate procedure.');
 const original="IF @controlled=0 THROW 51004, 'Legacy visit requires order reconciliation before migration cutover.', 1;";
 if(!old.includes(original)||!old.includes('IF EXISTS(SELECT 1 FROM dbo.truck_visits v CROSS APPLY'))throw Error('Gate baseline changed: review inherited-visit adaptation.');
 const inherited=old.replace(original,"IF @controlled=0 AND NOT EXISTS(SELECT 1 FROM internal.legacy_imported_visits WHERE visit_id=@VisitId) THROW 51004, 'Unregistered legacy visit; import provenance required.', 1;")
  .replace('IF EXISTS(SELECT 1 FROM dbo.truck_visits v CROSS APPLY','IF @controlled=1 AND EXISTS(SELECT 1 FROM dbo.truck_visits v CROSS APPLY');
 const procFile='014_inherited_visit_lifecycle.sql';
 await fs.writeFile(path.join(root,procFile),'-- Generated from009. Only explicitly registered inherited IDs bypass NEW order allocation.\n-- All stock/ISO/hold/24h/role/version checks remain in the same lifecycle transaction.\n'+inherited+'\nGO\n');
 const entry=batches(await fs.readFile(path.join(root,'008_gate_operations.sql'),'utf8')).find(s=>s.startsWith('CREATE OR ALTER PROCEDURE api.enter_visit '));
 const ending='COMMIT;SELECT (SELECT @id AS id,1 AS version FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);';
 if(!entry||!entry.includes(ending)||!entry.includes('DECLARE @slots table'))throw Error('Entry baseline changed: review idempotent entry adaptation.');
 const once=entry.replace('api.enter_visit @ActorId uniqueidentifier,','api.enter_visit_once @ActorId uniqueidentifier,@RequestId uniqueidentifier,@PayloadHash binary(32),')
  .replace('EXEC internal.validate_operational_details @Details;',"IF @RequestId IS NULL OR @RequestId='00000000-0000-0000-0000-000000000000' OR @PayloadHash IS NULL THROW 51004, 'Entry request ID/hash required.', 1;\n EXEC internal.validate_operational_details @Details;")
  .replace('DECLARE @slots table',`DECLARE @cached nvarchar(max),@cachedHash binary(32);
  SELECT @cached=response_json,@cachedHash=payload_hash FROM internal.gate_entry_requests WITH(UPDLOCK,HOLDLOCK) WHERE actor_id=@ActorId AND request_id=@RequestId;
  IF @cached IS NOT NULL BEGIN
   IF @cachedHash<>@PayloadHash THROW 51009, 'Request ID reused with different entry data.', 1;
   COMMIT;SELECT @cached;RETURN;
  END;
  DECLARE @slots table`)
  .replace(ending,`DECLARE @response nvarchar(max)=(SELECT @id AS id,1 AS version FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
  INSERT internal.gate_entry_requests(actor_id,request_id,payload_hash,visit_id,response_json) VALUES(@ActorId,@RequestId,@PayloadHash,@id,@response);
  COMMIT;SELECT @response;`);
 const onceFile='015_idempotent_gate_entry.sql';await fs.writeFile(path.join(root,onceFile),'-- Generated from008. An identical entry retry replays its original result atomically.\n'+once+'\nGO\n');
 const files=['012_application_api.sql',procFile,onceFile,'013_forced_pickup_api.sql'];
 const operations=[];
 for(const file of files){for(const [i,batch] of batches(await fs.readFile(path.join(root,file),'utf8')).entries())operations.push(` SET @phase=N'${file} / lot${i+1}';\n EXEC sys.sp_executesql ${quote(batch)};`);}
 const preflight=await fs.readFile(path.join(root,'deployment/00_CONTROLE_CONNEXION.sql'),'utf8');
 const sql=`-- DBeaver : toszps, nouvelle session auto-commit, Ctrl+A puis Ctrl+Entree.
-- Version5 ->6 : API application et registre PRIVE des visites historiques. Aucun import ni lancement.
SET NOCOUNT ON;SET XACT_ABORT ON;
IF @@TRANCOUNT<>0 OR (@@OPTIONS & 2)<>0 THROW 51100, 'Nouvelle session auto-commit requise.', 1;
DECLARE @phase nvarchar(200)=N'Controle de cible';
BEGIN TRY
 EXEC sys.sp_executesql ${quote(preflight)};
 IF IS_ROLEMEMBER(N'db_owner')<>1 AND IS_SRVROLEMEMBER(N'sysadmin')<>1 THROW 51100, 'Compte de deploiement requis.', 1;
 IF (SELECT COUNT(*) FROM internal.schema_versions WHERE version IN(1,2,3,4,5))<>5 OR (SELECT MAX(version) FROM internal.schema_versions)<>5 THROW 51100, 'Versions1..5 attendues ; ne pas rejouer.', 1;
 IF EXISTS(SELECT 1 FROM dbo.truck_visits) OR EXISTS(SELECT 1 FROM internal.local_accounts) THROW 51100, 'Mettre a jour API6 AVANT le transfert final et le premier compte local. Des donnees existent : verifier la sequence.', 1;
 SET @phase=N'Sauvegarde avant API6';
 DECLARE @folder nvarchar(4000)=CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultBackupPath'));
 IF @folder IS NULL OR LEN(TRIM(@folder))=0 THROW 51100, 'Repertoire de sauvegarde SQL inconnu.', 1;
 DECLARE @backup nvarchar(4000)=@folder+CASE WHEN RIGHT(@folder,1) IN(N'\\',N'/') THEN N'' ELSE N'\\' END+N'toszps_avant_api6_'+CONVERT(nvarchar(36),NEWID())+N'.bak';
 BACKUP DATABASE [toszps] TO DISK=@backup WITH COPY_ONLY,CHECKSUM,NOINIT,STATS=10;
 SELECT @backup sauvegarde_sur_serveur_SQL;
 BEGIN TRANSACTION;
${operations.join('\n')}
 IF @@TRANCOUNT<>1 THROW 51100, 'Transaction de deploiement inattendue.', 1;
 COMMIT;
 SELECT N'API APPLICATION VERSION6 INSTALLEE - IMPORT ET BASCULE RESTENT A FAIRE' resultat;
END TRY BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 DECLARE @error nvarchar(2048)=CONCAT(@phase,N' ; SQL ',ERROR_NUMBER(),N' ; ligne ',ERROR_LINE(),N' ; ',ERROR_MESSAGE());THROW 51101,@error,1;
END CATCH;
`;
 await fs.writeFile(path.join(root,'deployment/15_APPLICATION_SQL_DBEAVER.sql'),sql);
 return {files,batches:operations.length};
}
if(require.main===module)generate().then(console.log).catch(e=>{console.error(e.message);process.exitCode=1;});
module.exports={generate};
