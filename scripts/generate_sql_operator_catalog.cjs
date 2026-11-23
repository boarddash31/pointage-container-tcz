'use strict';
const fs=require('node:fs/promises'),path=require('node:path');
async function generate(){
 const root=path.resolve(__dirname,'..');
 const source=JSON.parse(await fs.readFile(path.join(root,'app/assets/operators.json'),'utf8'));
 if(!Array.isArray(source))throw Error('Operator catalogue must be an array.');
 // Blank-name placeholder codes are not selectable business shipping lines.
 const rows=source.filter(r=>typeof r.name==='string'&&r.name.trim().length>0);
 if(!Array.isArray(rows)||rows.length===0||new Set(rows.map(r=>r.id)).size!==rows.length||rows.some(r=>
  typeof r.id!=='string'||!/^[-A-Z0-9_]{1,64}$/.test(r.id)||typeof r.name!=='string'||!r.name.trim()||r.name.length>200||
  typeof r.bic!=='string'||r.bic.length>20))throw Error('Review the bundled operator reference catalogue.');
 const json=JSON.stringify(rows).replaceAll("'","''");
 const sql=`-- Initialise only missing shipping-line reference records from app/assets/operators.json.
-- No visits, stock, accounts or orders are imported; existing records are preserved.
-- DBeaver: select the entire script and execute in a fresh auto-commit session.
USE [toszps];
SET NOCOUNT ON;SET XACT_ABORT ON;
IF @@TRANCOUNT<>0 OR (@@OPTIONS & 2)<>0 THROW 51100, 'Nouvelle session auto-commit requise.', 1;
IF CONVERT(nvarchar(128),SERVERPROPERTY('MachineName'))<>N'PRD-DB-ZENATA'
 OR CONVERT(nvarchar(128),SERVERPROPERTY('InstanceName'))<>N'MMSQL01'
 OR SERVERPROPERTY('InstanceName') IS NULL THROW 51100, 'Cible attendue : PRD-DB-ZENATA / MMSQL01.', 1;
DECLARE @port_brut int=TRY_CONVERT(int,CONNECTIONPROPERTY('local_tcp_port'));
DECLARE @port int=CASE WHEN @port_brut BETWEEN -32768 AND -1 THEN @port_brut+65536 ELSE @port_brut END;
IF @port IS NULL OR @port<>54013 THROW 51100, 'Port TCP attendu : 54013.', 1;
IF IS_ROLEMEMBER(N'db_owner')<>1 AND IS_SRVROLEMEMBER(N'sysadmin')<>1 THROW 51100, 'Compte de deploiement requis.', 1;
IF (SELECT MAX(version) FROM internal.schema_versions)<>6
 OR (SELECT COUNT(*) FROM internal.schema_versions WHERE version BETWEEN 1 AND 6)<>6
 THROW 51100, 'Schema application6 requis.', 1;
DECLARE @catalogue table(id nvarchar(64) COLLATE Latin1_General_100_BIN2 PRIMARY KEY,name nvarchar(200),bic nvarchar(20));
INSERT @catalogue(id,name,bic)
 SELECT id,name,bic FROM OPENJSON(N'${json}') WITH(id nvarchar(64),name nvarchar(200),bic nvarchar(20));
IF (SELECT COUNT(*) FROM @catalogue)<>${rows.length} THROW 51100, 'Catalogue incomplet.', 1;
BEGIN TRY
 BEGIN TRANSACTION;
 INSERT dbo.armateurs(id,name,bic)
 SELECT c.id,c.name,NULLIF(c.bic,N'') FROM @catalogue c
 WHERE NOT EXISTS(SELECT 1 FROM dbo.armateurs a WITH(UPDLOCK,HOLDLOCK)
  WHERE UPPER(a.id) COLLATE Latin1_General_100_BIN2=c.id);
 DECLARE @ajoutes int=@@ROWCOUNT;
 COMMIT;
 SELECT N'CATALOGUE ARMATEURS INITIALISE' AS resultat,@ajoutes AS armateurs_ajoutes,
  (SELECT COUNT(*) FROM dbo.armateurs WHERE active=1) AS armateurs_actifs;
END TRY BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 THROW;
END CATCH;
`;
 const target=path.join(root,'migration/sqlserver');
 await fs.writeFile(path.join(target,'017_initialize_operator_catalog.sql'),sql);
 await fs.writeFile(path.join(target,'deployment/17_INITIALISER_ARMATEURS_DBEAVER.sql'),sql);
 return {count:rows.length};
}
module.exports={generate};
if(require.main===module)generate().then(result=>console.log(JSON.stringify(result))).catch(error=>{console.error(error.message);process.exitCode=1;});
