-- SOCLE INITIAL PARTIEL. Aucune bascule de l'application ni import metier.
-- SSMS : activer Requete > Mode SQLCMD. Verifier PackageRoot si autre dossier.
-- Le compte toszps/db_owner sert ici au deploiement, pas au futur runtime.
:setvar PackageRoot "C:\Temp\ZENATA-SQL-20261121"
:on error exit
USE [toszps];
GO
:r "$(PackageRoot)\00_CONTROLE_CONNEXION.sql"
GO
SET XACT_ABORT ON;
IF DATABASEPROPERTYEX(DB_NAME(),'Status')<>N'ONLINE'
 OR DATABASEPROPERTYEX(DB_NAME(),'Updateability')<>N'READ_WRITE'
 THROW 51100, 'Base ONLINE et READ_WRITE requise.', 1;
IF (SELECT compatibility_level FROM sys.databases WHERE database_id=DB_ID())<>170
 THROW 51100, 'Faire valider le niveau de compatibilite 170 par le DBA.', 1;
IF IS_ROLEMEMBER(N'db_owner')<>1 AND IS_SRVROLEMEMBER(N'sysadmin')<>1
 THROW 51100, 'Compte de deploiement DBA requis.', 1;
IF EXISTS(SELECT 1 FROM sys.tables WHERE is_ms_shipped=0)
 THROW 51100, 'La base doit etre vide : arret sans suppression ni remplacement.', 1;
IF @@TRANCOUNT<>0 THROW 51100, 'Utiliser une nouvelle session sans transaction ouverte.', 1;
-- L'ensemble reste dans une transaction externe, y compris entre les GO.
-- Une erreur SQLCMD ferme l'execution : ne pas poursuivre dans une autre session.
BEGIN TRANSACTION;
GO
:r "$(PackageRoot)\scripts\001_schema.sql"
GO
:r "$(PackageRoot)\scripts\002_order_api.sql"
GO
:r "$(PackageRoot)\scripts\005_application_accounts.sql"
GO
IF @@TRANCOUNT<>1 THROW 51100, 'Compteur de transaction inattendu : annuler la session.', 1;
IF (SELECT COUNT(*) FROM internal.schema_versions WHERE version IN (1,2,3))<>3
 THROW 51100, 'Versions du socle incompletes.', 1;
COMMIT TRANSACTION;
GO
:r "$(PackageRoot)\02_VERIFIER_SOCLE.sql"
