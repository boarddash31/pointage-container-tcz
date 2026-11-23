-- Lecture seule, utilisable apres initialisation. Ne charge aucune donnee fictive.
SET NOCOUNT ON;
IF DB_NAME()<>N'toszps' THROW 51100, 'Selectionner toszps.', 1;
IF OBJECT_ID(N'internal.schema_versions',N'U') IS NULL
 THROW 51100, 'Socle non initialise.', 1;
IF (SELECT COUNT(*) FROM internal.schema_versions WHERE version IN (1,2,3))<>3
 THROW 51100, 'Versions 1, 2 et 3 attendues.', 1;
IF OBJECT_ID(N'api.user_context',N'P') IS NULL OR OBJECT_ID(N'internal.bootstrap_admin',N'P') IS NULL
 THROW 51100, 'Procedures du socle manquantes.', 1;
IF DATABASE_PRINCIPAL_ID(N'pointage_api') IS NULL
 THROW 51100, 'Role pointage_api absent.', 1;
SELECT version,applied_at FROM internal.schema_versions ORDER BY version;
SELECT s.name AS schema_nom,COUNT(*) AS nombre_tables FROM sys.tables t
 JOIN sys.schemas s ON s.schema_id=t.schema_id WHERE t.is_ms_shipped=0 GROUP BY s.name;
SELECT N'SOCLE INITIAL UNIQUEMENT : application encore reliee a Supabase' AS resultat;
