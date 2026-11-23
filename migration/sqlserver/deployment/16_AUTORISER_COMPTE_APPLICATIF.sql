-- Execute in toszps AFTER IT creates SQL login pointage_runtime with its own strong password.
-- No password is stored in this file. The deployment login toszps is not used by the web runtime.
SET NOCOUNT ON;SET XACT_ABORT ON;
IF DB_NAME()<>N'toszps' OR (SELECT MAX(version) FROM internal.schema_versions)<>6 THROW 51100, 'Base toszps/schema6 requise.', 1;
IF SUSER_ID(N'pointage_runtime') IS NULL THROW 51100, 'IT doit creer le login SQL pointage_runtime sur MMSQL01 avant cette affectation.', 1;
IF IS_ROLEMEMBER(N'db_owner')<>1 AND IS_SRVROLEMEMBER(N'sysadmin')<>1 THROW 51100, 'Compte de deploiement requis.', 1;
BEGIN TRANSACTION;
IF USER_ID(N'pointage_runtime') IS NULL CREATE USER [pointage_runtime] FOR LOGIN [pointage_runtime];
IF IS_ROLEMEMBER(N'db_owner',N'pointage_runtime')=1 THROW 51100, 'Le compte applicatif ne doit pas etre db_owner.', 1;
IF IS_ROLEMEMBER(N'pointage_api',N'pointage_runtime')<>1 ALTER ROLE pointage_api ADD MEMBER pointage_runtime;
COMMIT;
SELECT N'COMPTE SQL APPLICATIF AUTORISE VIA PROCEDURES API' resultat;
