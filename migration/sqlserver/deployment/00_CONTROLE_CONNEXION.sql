-- Lecture seule. Ouvrir dans SSMS avec la base toszps selectionnee.
-- Connexion : tcp:PRD-DB-ZENATA,54013 ; authentification SQL ; utilisateur toszps.
-- Ne jamais ecrire le mot de passe dans un fichier SQL.
SET NOCOUNT ON;
DECLARE @port_brut int=TRY_CONVERT(int,CONNECTIONPROPERTY('local_tcp_port'));
-- Accepter aussi la representation signee sur 16 bits des ports >=32768.
-- Ne normaliser que l'intervalle signe valide ; conserver les autres valeurs pour rejet.
DECLARE @port_observe int=CASE WHEN @port_brut BETWEEN -32768 AND -1 THEN @port_brut+65536 ELSE @port_brut END;
-- Afficher les informations avant tout rejet afin de diagnostiquer la connexion.
SELECT DB_NAME() AS base_active,
  SERVERPROPERTY('MachineName') AS serveur,
  SERVERPROPERTY('InstanceName') AS instance,
  CONNECTIONPROPERTY('net_transport') AS transport,
  CONNECTIONPROPERTY('physical_net_transport') AS transport_physique,
  CONNECTIONPROPERTY('local_net_address') AS adresse_cote_serveur,
  @port_brut AS port_brut,
  @port_observe AS port_cote_serveur;
IF DB_NAME()<>N'toszps' THROW 51100, 'Selectionner la base toszps dans SSMS.', 1;
IF CONVERT(nvarchar(128),SERVERPROPERTY('InstanceName'))<>N'MMSQL01'
  OR SERVERPROPERTY('InstanceName') IS NULL THROW 51100, 'Instance attendue : MMSQL01.', 1;
IF CONVERT(nvarchar(128),SERVERPROPERTY('MachineName'))<>N'PRD-DB-ZENATA'
  THROW 51100, 'Serveur attendu : PRD-DB-ZENATA.', 1;
IF CONVERT(int,SERVERPROPERTY('ProductMajorVersion'))<17
  THROW 51100, 'SQL Server 2025 ou version ulterieure requis.', 1;
IF CONVERT(nvarchar(40),CONNECTIONPROPERTY('net_transport'))<>N'TCP'
  OR CONNECTIONPROPERTY('net_transport') IS NULL
  THROW 51100, 'Utiliser une connexion TCP pour ce controle.', 1;
IF @port_observe IS NULL
  THROW 51100, 'Port cote serveur indisponible (NULL). Connexion SQL etablie ; verifier le diagnostic reseau avant initialisation.', 1;
IF @port_observe<>54013
BEGIN
  DECLARE @message_port nvarchar(2048)=CONCAT(N'Port cote serveur observe : ',@port_observe,N' (brut : ',@port_brut,N'). Attendu : 54013. Faire confirmer la configuration ou une redirection par l''IT avant initialisation.');
  THROW 51100, @message_port, 1;
END;

SELECT CONVERT(nvarchar(128),SERVERPROPERTY('MachineName')) AS serveur,
  CONVERT(nvarchar(128),SERVERPROPERTY('InstanceName')) AS instance,
  CONVERT(nvarchar(128),SERVERPROPERTY('ProductVersion')) AS version_sql,
  DB_NAME() AS base,ORIGINAL_LOGIN() AS connexion,USER_NAME() AS utilisateur_base,
  CONNECTIONPROPERTY('local_net_address') AS adresse_sql,
  @port_brut AS port_brut,
  @port_observe AS port_tcp,
  CONNECTIONPROPERTY('net_transport') AS transport,
  IS_ROLEMEMBER(N'db_owner') AS est_db_owner;
SELECT compatibility_level,state_desc,user_access_desc,is_read_only,recovery_model_desc
  FROM sys.databases WHERE database_id=DB_ID();
SELECT COUNT(*) AS tables_utilisateur_existantes FROM sys.tables WHERE is_ms_shipped=0;
SELECT s.name AS schema_nom,t.name AS table_nom FROM sys.tables t
  JOIN sys.schemas s ON s.schema_id=t.schema_id WHERE t.is_ms_shipped=0 ORDER BY s.name,t.name;
-- Pas de lecture des lignes metier, DDL, export ni modification.
