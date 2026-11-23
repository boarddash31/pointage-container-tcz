'use strict';
// One SQL batch for JDBC clients. Only fixed, local source SQL is embedded;
// no user-supplied text, passwords or remote data are used.
const fs=require('node:fs/promises'),path=require('node:path');
const root=path.resolve(__dirname,'../migration/sqlserver');
const quote=sql=>"N'"+sql.replaceAll("'","''")+"'";
async function generate({database='toszps',output='01_INITIALISER_SOCLE_DBEAVER.sql'}={}){
 if(!['toszps','toszps_Test'].includes(database)||!['01_INITIALISER_SOCLE_DBEAVER.sql','10_INITIALISER_RECETTE_DBEAVER.sql'].includes(output))throw Error('Unexpected bootstrap target');
 const deployment=path.join(root,'deployment');
 const preflight=(await fs.readFile(path.join(deployment,'00_CONTROLE_CONNEXION.sql'),'utf8')).replaceAll("N'toszps'","N'"+database+"'");
 const verify=(await fs.readFile(path.join(deployment,'02_VERIFIER_SOCLE.sql'),'utf8')).replaceAll("N'toszps'","N'"+database+"'");
 const wrapper=await fs.readFile(path.join(deployment,'01_INITIALISER_SOCLE.sql'),'utf8');
 const checks=wrapper.match(/SET XACT_ABORT ON;([\s\S]*?)-- L'ensemble/);
 if(!checks||!checks[1].includes('compatibility_level')||!checks[1].includes('sys.tables'))throw Error('Bootstrap guards not found');
 const chunks=[];
 for(const name of ['001_schema.sql','002_order_api.sql','005_application_accounts.sql']){
  const sql=(await fs.readFile(path.join(root,name),'utf8')).replaceAll('\r\n','\n');
  if(/^\s*:/m.test(sql))throw Error('SQLCMD source directive not allowed');
  const batches=sql.split(/^\s*GO\s*$/m).map(s=>s.trim()).filter(Boolean);
  if(name!=='002_order_api.sql'){
   // Move only the bootstrap transaction boundaries into the single outer TRY.
   // Stored procedure bodies, including their own transaction logic, stay intact.
   if((batches[0].match(/^BEGIN TRANSACTION;$/gm)??[]).length!==1||(batches.at(-1).match(/^COMMIT TRANSACTION;$/gm)??[]).length!==1)throw Error('Unexpected bootstrap transaction boundaries');
   batches[0]=batches[0].replace(/^BEGIN TRANSACTION;$/m,'-- Transaction managed by the outer deployment batch.');
   batches[batches.length-1]=batches.at(-1).replace(/^COMMIT TRANSACTION;$/m,'-- Commit managed by the outer deployment batch.');
  }
  for(const [index,batch] of batches.entries())chunks.push(`  SET @etape_deploiement=${quote(name+', lot '+(index+1))};\n  EXEC sys.sp_executesql ${quote(batch)};`);
 }
 const sql=`-- SOCLE INITIAL PARTIEL : aucune bascule applicative ni import de donnees.
-- DBeaver : connexion toszps, nouvelle session sans transaction ouverte.
-- Apres sauvegarde DBA : selectionner TOUT le fichier (Ctrl+A), Ctrl+Entree.
-- Envoyer ce bloc en une seule execution, pas instruction par instruction.
-- Genere depuis les sources locales ; aucun mot de passe integre.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF @@TRANCOUNT<>0 THROW 51100, 'Ouvrir une session sans transaction avant de commencer.', 1;
DECLARE @etape_deploiement nvarchar(200)=N'Controle de connexion et cible';
BEGIN TRY
  EXEC sys.sp_executesql ${quote(preflight)};
${checks[1]}
  BEGIN TRANSACTION;
${chunks.join('\n')}
  IF @@TRANCOUNT<>1 THROW 51100, 'Compteur de transaction inattendu.', 1;
  SET @etape_deploiement=N'Verifications finales';
  EXEC sys.sp_executesql ${quote(verify)};
  COMMIT TRANSACTION;
  SELECT N'SOCLE INITIAL CREE ET VALIDE : application encore sur Supabase' AS resultat_final;
END TRY
BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  DECLARE @erreur_deploiement nvarchar(2048)=CONCAT(N'Etape : ',@etape_deploiement,N' ; SQL ',ERROR_NUMBER(),N' ; procedure : ',COALESCE(ERROR_PROCEDURE(),N'(lot)'),N' ; ligne : ',ERROR_LINE(),N' ; ',ERROR_MESSAGE());
  THROW 51101, @erreur_deploiement, 1;
END CATCH;
`;
 const file=path.join(deployment,output);
 await fs.writeFile(file,sql,'utf8');return {file,batches:chunks.length};
}
if(require.main===module)generate().then(result=>console.log(JSON.stringify(result))).catch(error=>{console.error(error.message);process.exitCode=1;});
module.exports={generate};
