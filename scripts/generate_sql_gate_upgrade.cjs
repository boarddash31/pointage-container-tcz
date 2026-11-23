'use strict';
const fs=require('node:fs/promises'),path=require('node:path');
const root=path.resolve(__dirname,'../migration/sqlserver'),deployment=path.join(root,'deployment');
const quote=value=>"N'"+value.replaceAll("'","''")+"'";
const batches=value=>value.replaceAll('\r\n','\n').split(/^\s*GO\s*$/m).map(s=>s.trim()).filter(Boolean);
async function generate(){
 await require('./generate_sql_gate_tests.cjs').generate();
 await require('./generate_sql_bootstrap_dbeaver.cjs').generate({database:'toszps_Test',output:'10_INITIALISER_RECETTE_DBEAVER.sql'});
 const source=[];
 for(const name of ['008_gate_operations.sql','009_gate_lifecycle.sql']){
  const chunks=batches(await fs.readFile(path.join(root,name),'utf8'));
  for(const [index,chunk] of chunks.entries())source.push(` SET @stage=${quote(name+', lot '+(index+1))};\n EXEC sys.sp_executesql ${quote(chunk)};`);
 }
 for(const [database,name] of [['toszps_Test','11_GATE_RECETTE_DBEAVER.sql'],['toszps','12_GATE_TOSZPS_DBEAVER.sql']]){
  const preflight=(await fs.readFile(path.join(deployment,'00_CONTROLE_CONNEXION.sql'),'utf8')).replaceAll("N'toszps'","N'"+database+"'");
  const sql=`-- VERSION4: mise a jour du socle existant, jamais reinitialisation ni import.
-- Cible unique : ${database}. Nouvelle session, selectionner tout, Ctrl+Entree.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF @@TRANCOUNT<>0 THROW 51100, 'Session sans transaction requise.', 1;
DECLARE @stage nvarchar(200)=N'Controle de cible';
BEGIN TRY
 EXEC sys.sp_executesql ${quote(preflight)};
 IF (SELECT compatibility_level FROM sys.databases WHERE database_id=DB_ID())<>170 THROW 51100, 'Compatibilite170 requise.', 1;
 IF DATABASEPROPERTYEX(DB_NAME(),'Updateability')<>N'READ_WRITE' THROW 51100, 'Base modifiable requise.', 1;
 IF IS_ROLEMEMBER(N'db_owner')<>1 AND IS_SRVROLEMEMBER(N'sysadmin')<>1 THROW 51100, 'Compte de deploiement requis.', 1;
 BEGIN TRANSACTION;
${source.join('\n')}
 IF @@TRANCOUNT<>1 THROW 51100, 'Transaction de deploiement inattendue.', 1;
 COMMIT TRANSACTION;
 SELECT N'GATE VERSION4 INSTALLEE - application non basculee' AS resultat;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 DECLARE @message nvarchar(2048)=CONCAT(@stage,N' ; SQL ',ERROR_NUMBER(),N' ; ',COALESCE(ERROR_PROCEDURE(),N'lot'),N' ; ligne ',ERROR_LINE(),N' ; ',ERROR_MESSAGE());
 THROW 51101,@message,1;
END CATCH;
`;
  await fs.writeFile(path.join(deployment,name),sql);
 }
 const tests=batches(await fs.readFile(path.join(root,'010_gate_smoke_test.sql'),'utf8'));
 const sql=`-- RECETTE UNIQUEMENT : aucune donnee de production. Fixtures annulees.
SET NOCOUNT ON;SET XACT_ABORT ON;
IF DB_NAME()<>N'toszps_Test' THROW 51100, 'Utiliser seulement toszps_Test.', 1;
IF @@TRANCOUNT<>0 THROW 51100, 'Session sans transaction requise.', 1;
DECLARE @test nvarchar(100);
BEGIN TRY
${tests.map((s,i)=>` SET @test=N'Controle ${i}';\n EXEC sys.sp_executesql ${quote(s)};`).join('\n')}
 SELECT N'RECETTE GATE REUSSIE - 9 scenarios, donnees fictives annulees' AS resultat;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 DECLARE @message nvarchar(2048)=CONCAT(@test,N' ; SQL ',ERROR_NUMBER(),N' ; ligne ',ERROR_LINE(),N' ; ',ERROR_MESSAGE());
 THROW 51101,@message,1;
END CATCH;
`;
 await fs.writeFile(path.join(deployment,'13_TESTER_GATE_DBEAVER.sql'),sql);
 return {upgradeBatches:source.length,testBatches:tests.length};
}
if(require.main===module)generate().then(console.log).catch(e=>{console.error(e.message);process.exitCode=1;});
module.exports={generate};
