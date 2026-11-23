-- SOCLE INITIAL PARTIEL : aucune bascule applicative ni import de donnees.
-- DBeaver : connexion toszps, nouvelle session sans transaction ouverte.
-- Apres sauvegarde DBA : selectionner TOUT le fichier (Ctrl+A), Ctrl+Entree.
-- Envoyer ce bloc en une seule execution, pas instruction par instruction.
-- Genere depuis les sources locales ; aucun mot de passe integre.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF @@TRANCOUNT<>0 THROW 51100, 'Ouvrir une session sans transaction avant de commencer.', 1;
DECLARE @etape_deploiement nvarchar(200)=N'Controle de connexion et cible';
BEGIN TRY
  EXEC sys.sp_executesql N'-- Lecture seule. Ouvrir dans SSMS avec la base toszps selectionnee.
-- Connexion : tcp:PRD-DB-ZENATA,54013 ; authentification SQL ; utilisateur toszps.
-- Ne jamais ecrire le mot de passe dans un fichier SQL.
SET NOCOUNT ON;
DECLARE @port_brut int=TRY_CONVERT(int,CONNECTIONPROPERTY(''local_tcp_port''));
-- Accepter aussi la representation signee sur 16 bits des ports >=32768.
-- Ne normaliser que l''intervalle signe valide ; conserver les autres valeurs pour rejet.
DECLARE @port_observe int=CASE WHEN @port_brut BETWEEN -32768 AND -1 THEN @port_brut+65536 ELSE @port_brut END;
-- Afficher les informations avant tout rejet afin de diagnostiquer la connexion.
SELECT DB_NAME() AS base_active,
  SERVERPROPERTY(''MachineName'') AS serveur,
  SERVERPROPERTY(''InstanceName'') AS instance,
  CONNECTIONPROPERTY(''net_transport'') AS transport,
  CONNECTIONPROPERTY(''physical_net_transport'') AS transport_physique,
  CONNECTIONPROPERTY(''local_net_address'') AS adresse_cote_serveur,
  @port_brut AS port_brut,
  @port_observe AS port_cote_serveur;
IF DB_NAME()<>N''toszps_Test'' THROW 51100, ''Selectionner la base toszps dans SSMS.'', 1;
IF CONVERT(nvarchar(128),SERVERPROPERTY(''InstanceName''))<>N''MMSQL01''
  OR SERVERPROPERTY(''InstanceName'') IS NULL THROW 51100, ''Instance attendue : MMSQL01.'', 1;
IF CONVERT(nvarchar(128),SERVERPROPERTY(''MachineName''))<>N''PRD-DB-ZENATA''
  THROW 51100, ''Serveur attendu : PRD-DB-ZENATA.'', 1;
IF CONVERT(int,SERVERPROPERTY(''ProductMajorVersion''))<17
  THROW 51100, ''SQL Server 2025 ou version ulterieure requis.'', 1;
IF CONVERT(nvarchar(40),CONNECTIONPROPERTY(''net_transport''))<>N''TCP''
  OR CONNECTIONPROPERTY(''net_transport'') IS NULL
  THROW 51100, ''Utiliser une connexion TCP pour ce controle.'', 1;
IF @port_observe IS NULL
  THROW 51100, ''Port cote serveur indisponible (NULL). Connexion SQL etablie ; verifier le diagnostic reseau avant initialisation.'', 1;
IF @port_observe<>54013
BEGIN
  DECLARE @message_port nvarchar(2048)=CONCAT(N''Port cote serveur observe : '',@port_observe,N'' (brut : '',@port_brut,N''). Attendu : 54013. Faire confirmer la configuration ou une redirection par l''''IT avant initialisation.'');
  THROW 51100, @message_port, 1;
END;

SELECT CONVERT(nvarchar(128),SERVERPROPERTY(''MachineName'')) AS serveur,
  CONVERT(nvarchar(128),SERVERPROPERTY(''InstanceName'')) AS instance,
  CONVERT(nvarchar(128),SERVERPROPERTY(''ProductVersion'')) AS version_sql,
  DB_NAME() AS base,ORIGINAL_LOGIN() AS connexion,USER_NAME() AS utilisateur_base,
  CONNECTIONPROPERTY(''local_net_address'') AS adresse_sql,
  @port_brut AS port_brut,
  @port_observe AS port_tcp,
  CONNECTIONPROPERTY(''net_transport'') AS transport,
  IS_ROLEMEMBER(N''db_owner'') AS est_db_owner;
SELECT compatibility_level,state_desc,user_access_desc,is_read_only,recovery_model_desc
  FROM sys.databases WHERE database_id=DB_ID();
SELECT COUNT(*) AS tables_utilisateur_existantes FROM sys.tables WHERE is_ms_shipped=0;
SELECT s.name AS schema_nom,t.name AS table_nom FROM sys.tables t
  JOIN sys.schemas s ON s.schema_id=t.schema_id WHERE t.is_ms_shipped=0 ORDER BY s.name,t.name;
-- Pas de lecture des lignes metier, DDL, export ni modification.
';

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

  BEGIN TRANSACTION;
  SET @etape_deploiement=N'001_schema.sql, lot 1';
  EXEC sys.sp_executesql N'-- SQL Server 2025. Generated from the metadata snapshot; no source rows are embedded.
-- Run against a NEW, empty database selected by your DBA, never master or an existing application database.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() IN (N''master'',N''model'',N''msdb'',N''tempdb'') THROW 51000, ''Select the dedicated Pointage database first.'', 1;
IF CONVERT(int,SERVERPROPERTY(''ProductMajorVersion''))<17 THROW 51000, ''SQL Server 2025 or newer is required.'', 1;
IF OBJECT_ID(N''internal.schema_versions'') IS NOT NULL THROW 51000, ''Migration already initialized; do not replay.'', 1;
IF EXISTS(SELECT 1 FROM sys.tables WHERE is_ms_shipped=0) THROW 51000, ''Destination must be empty.'', 1;
-- Transaction managed by the outer deployment batch.
IF SCHEMA_ID(N''internal'') IS NULL EXEC(N''CREATE SCHEMA internal AUTHORIZATION dbo'');
IF SCHEMA_ID(N''api'') IS NULL EXEC(N''CREATE SCHEMA api AUTHORIZATION dbo'');
CREATE TABLE internal.schema_versions(version int NOT NULL PRIMARY KEY, applied_at datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00''));


CREATE TABLE [internal].[transport_order_aliases] (
  [alias_id] uniqueidentifier NOT NULL,
  [order_id] uniqueidentifier NOT NULL,
  [original_header] nvarchar(max) NOT NULL,
  CHECK ([original_header] IS NULL OR ISJSON([original_header],VALUE)=1),
  CONSTRAINT [transport_order_aliases_pkey] PRIMARY KEY ([alias_id])
);

CREATE TABLE [internal].[transport_order_controls] (
  [singleton] bit NOT NULL DEFAULT 1,
  [required] bit NOT NULL DEFAULT 0,
  CONSTRAINT [transport_order_controls_pkey] PRIMARY KEY ([singleton]),
  CHECK ([singleton]=1)
);

CREATE TABLE [dbo].[armateurs] (
  [id] nvarchar(64) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [name] nvarchar(max) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [bic] nvarchar(max) COLLATE Latin1_General_100_BIN2 NULL,
  [official_logo_path] nvarchar(max) COLLATE Latin1_General_100_BIN2 NULL,
  [official_logo_verified] bit NOT NULL DEFAULT 0,
  [active] bit NOT NULL DEFAULT 1,
  CONSTRAINT [armateurs_pkey] PRIMARY KEY ([id])
);

CREATE TABLE [dbo].[audit_logs] (
  [id] bigint IDENTITY(1,1) NOT NULL,
  [entity] nvarchar(64) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [entity_id] nvarchar(150) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [action] nvarchar(64) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [actor_id] uniqueidentifier NULL,
  [occurred_at] datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00''),
  [before_data] nvarchar(max) NULL,
  CHECK ([before_data] IS NULL OR ISJSON([before_data],VALUE)=1),
  [after_data] nvarchar(max) NULL,
  CHECK ([after_data] IS NULL OR ISJSON([after_data],VALUE)=1),
  [reason] nvarchar(max) COLLATE Latin1_General_100_BIN2 NULL,
  CONSTRAINT [audit_logs_pkey] PRIMARY KEY ([id])
);

CREATE TABLE [dbo].[bookings] (
  [id] uniqueidentifier NOT NULL DEFAULT NEWID(),
  [reference] nvarchar(150) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [client_id] uniqueidentifier NULL,
  [armateur_id] nvarchar(64) COLLATE Latin1_General_100_BIN2 NULL,
  [iso_code] nvarchar(4) COLLATE Latin1_General_100_BIN2 NULL,
  [created_at] datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00''),
  CONSTRAINT [bookings_pkey] PRIMARY KEY ([id]),
  CHECK (LEN(TRIM([reference])) BETWEEN 1 AND 150)
);

CREATE TABLE [dbo].[client_armateurs] (
  [client_id] uniqueidentifier NOT NULL,
  [armateur_id] nvarchar(64) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [valid_from] date NOT NULL,
  [valid_to] date NULL,
  CONSTRAINT [client_armateurs_pkey] PRIMARY KEY ([client_id],[armateur_id],[valid_from]),
  CHECK ([valid_to] IS NULL OR [valid_to]>=[valid_from])
);

CREATE TABLE [dbo].[clients] (
  [id] uniqueidentifier NOT NULL DEFAULT NEWID(),
  [code] nvarchar(150) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [name] nvarchar(max) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [active] bit NOT NULL DEFAULT 1,
  CONSTRAINT [clients_code_key] UNIQUE ([code]),
  CONSTRAINT [clients_pkey] PRIMARY KEY ([id])
);

CREATE TABLE [dbo].[container_stock_intervals] (
  [id] uniqueidentifier NOT NULL DEFAULT NEWID(),
  [container_number] nvarchar(11) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [client_id] uniqueidentifier NULL,
  [armateur_id] nvarchar(64) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [iso_code] nvarchar(4) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [start_visit_id] uniqueidentifier NOT NULL,
  [end_visit_id] uniqueidentifier NULL,
  [arrived_at] datetimeoffset(6) NOT NULL,
  [departed_at] datetimeoffset(6) NULL,
  [position] nvarchar(max) COLLATE Latin1_General_100_BIN2 NULL,
  CONSTRAINT [container_stock_intervals_pkey] PRIMARY KEY ([id]),
  CHECK ([departed_at] IS NULL OR [departed_at]>=[arrived_at])
);

CREATE TABLE [dbo].[containers] (
  [number] nvarchar(11) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [iso_code] nvarchar(4) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [armateur_id] nvarchar(64) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [source] nvarchar(16) COLLATE Latin1_General_100_BIN2 NOT NULL DEFAULT N''operator'',
  [created_at] datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00''),
  CONSTRAINT [containers_pkey] PRIMARY KEY ([number]),
  CHECK (LEN([number])=11 AND LEFT([number],4) NOT LIKE N''%[^A-Z]%'' AND RIGHT([number],7) NOT LIKE N''%[^0-9]%''),
  CHECK (LEN([iso_code])=4 AND [iso_code] NOT LIKE N''%[^0-9A-Z]%''),
  CHECK ([source] IN (N''operator'',N''manual'',N''import''))
);

CREATE TABLE [dbo].[document_actions] (
  [id] bigint IDENTITY(1,1) NOT NULL,
  [document_id] uniqueidentifier NOT NULL,
  [actor_id] uniqueidentifier NOT NULL,
  [action] nvarchar(64) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [occurred_at] datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00''),
  CONSTRAINT [document_actions_pkey] PRIMARY KEY ([id]),
  CHECK ([action] IN (N''PREVIEW_REQUESTED'',N''SHARE_REQUESTED'',N''PRINT_DIALOG_REQUESTED'',N''DIRECT_PRINT_REQUESTED'',N''BRIDGE_ARCHIVE_REQUESTED'',N''BRIDGE_PRINT_REQUESTED''))
);

CREATE TABLE [dbo].[evp_rules] (
  [effective_from] date NOT NULL,
  [size_feet] int NOT NULL,
  [factor] decimal(38,18) NOT NULL,
  [source_note] nvarchar(max) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [created_by] uniqueidentifier NULL,
  [created_at] datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00''),
  CONSTRAINT [evp_rules_pkey] PRIMARY KEY ([effective_from],[size_feet]),
  CHECK ([factor]>0),
  CHECK ([size_feet] IN (20,40,45))
);

CREATE TABLE [dbo].[forced_container_actions] (
  [id] uniqueidentifier NOT NULL DEFAULT NEWID(),
  [visit_id] uniqueidentifier NOT NULL,
  [container_number] nvarchar(11) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [action] nvarchar(64) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [reason] nvarchar(max) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [actor_id] uniqueidentifier NOT NULL,
  [occurred_at] datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00''),
  [resolved_at] datetimeoffset(6) NULL,
  [resolved_by] uniqueidentifier NULL,
  [external_reference] nvarchar(max) COLLATE Latin1_General_100_BIN2 NULL,
  CONSTRAINT [forced_container_actions_pkey] PRIMARY KEY ([id]),
  CONSTRAINT [forced_container_actions_visit_id_key] UNIQUE ([visit_id]),
  CHECK ([action]=N''PRISE_SANS_STOCK''),
  CHECK (LEN(TRIM([reason]))>=10),
  CHECK (([resolved_at] IS NULL AND [resolved_by] IS NULL AND [external_reference] IS NULL) OR ([resolved_at] IS NOT NULL AND [resolved_by] IS NOT NULL AND LEN(TRIM([external_reference]))>=3))
);

CREATE TABLE [dbo].[generated_documents] (
  [id] uniqueidentifier NOT NULL DEFAULT NEWID(),
  [visit_id] uniqueidentifier NOT NULL,
  [event_id] bigint NOT NULL,
  [kind] nvarchar(32) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [storage_path] nvarchar(450) COLLATE Latin1_General_100_BIN2 NULL,
  [status] nvarchar(16) COLLATE Latin1_General_100_BIN2 NOT NULL DEFAULT N''pending'',
  [snapshot] nvarchar(max) NOT NULL,
  CHECK ([snapshot] IS NULL OR ISJSON([snapshot],VALUE)=1),
  [created_by] uniqueidentifier NOT NULL,
  [created_at] datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00''),
  CONSTRAINT [generated_documents_event_id_key] UNIQUE ([event_id]),
  CONSTRAINT [generated_documents_pkey] PRIMARY KEY ([id]),
  CHECK ([kind] IN (N''ENTREE'',N''DEPOSE'',N''PRISE'',N''SORTIE'',N''ANNULATION'')),
  CHECK ([status] IN (N''pending'',N''uploaded'',N''failed''))
);

CREATE TABLE [dbo].[iso_report_types] (
  [iso_code] nvarchar(4) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [effective_from] date NOT NULL,
  [category] nvarchar(max) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [size_feet] int NOT NULL,
  [source_note] nvarchar(max) COLLATE Latin1_General_100_BIN2 NOT NULL,
  CONSTRAINT [iso_report_types_pkey] PRIMARY KEY ([iso_code],[effective_from]),
  CHECK ([category] IN (N''20 DV'',N''40 DV ST'',N''40 DV HC'',N''45 DV'',N''FRIGO 20'',N''FRIGO 40'',N''OT&FL&HP&CT'')),
  CHECK ([size_feet] IN (20,40,45))
);

CREATE TABLE [dbo].[printer_settings] (
  [user_id] uniqueidentifier NOT NULL,
  [device_id] nvarchar(200) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [printer_name] nvarchar(max) COLLATE Latin1_General_100_BIN2 NULL,
  [updated_at] datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00''),
  CONSTRAINT [printer_settings_pkey] PRIMARY KEY ([user_id],[device_id])
);

CREATE TABLE [dbo].[profiles] (
  [id] uniqueidentifier NOT NULL,
  [display_name] nvarchar(max) COLLATE Latin1_General_100_BIN2 NOT NULL DEFAULT N'''',
  [active] bit NOT NULL DEFAULT 1,
  [created_at] datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00''),
  [phone] nvarchar(32) COLLATE Latin1_General_100_BIN2 NULL,
  [first_name] nvarchar(max) COLLATE Latin1_General_100_BIN2 NULL,
  [last_name] nvarchar(max) COLLATE Latin1_General_100_BIN2 NULL,
  [avatar_url] nvarchar(max) COLLATE Latin1_General_100_BIN2 NULL,
  CONSTRAINT [profiles_pkey] PRIMARY KEY ([id])
);

CREATE TABLE [dbo].[transport_order_items] (
  [id] uniqueidentifier NOT NULL DEFAULT NEWID(),
  [order_id] uniqueidentifier NOT NULL,
  [iso_code] nvarchar(4) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [quantity] int NOT NULL,
  [armateur_id] nvarchar(64) COLLATE Latin1_General_100_BIN2 NOT NULL,
  CONSTRAINT [transport_order_item_carrier_iso_key] UNIQUE ([order_id],[armateur_id],[iso_code]),
  CONSTRAINT [transport_order_items_pkey] PRIMARY KEY ([id]),
  CHECK (LEN([iso_code])=4 AND [iso_code] NOT LIKE N''%[^0-9A-Z]%''),
  CHECK ([quantity] BETWEEN 1 AND 1000000)
);

CREATE TABLE [dbo].[transport_orders] (
  [id] uniqueidentifier NOT NULL DEFAULT NEWID(),
  [kind] nvarchar(32) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [direction] nvarchar(16) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [reference] nvarchar(150) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [armateur_id] nvarchar(64) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [client_id] uniqueidentifier NULL,
  [client_order_reference] nvarchar(150) COLLATE Latin1_General_100_BIN2 NULL,
  [active] bit NOT NULL DEFAULT 1,
  [created_at] datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00''),
  [created_by] uniqueidentifier NULL,
  [version] int NOT NULL DEFAULT 1,
  [updated_at] datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00''),
  [updated_by] uniqueidentifier NULL,
  CONSTRAINT [transport_orders_pkey] PRIMARY KEY ([id]),
  CHECK (([kind]<>N''EDO'' OR [direction]=N''LIVRAISON'') AND ([kind]<>N''ERO'' OR [direction]=N''RESTITUTION'')),
  CHECK ([client_order_reference] IS NULL OR [client_id] IS NOT NULL),
  CHECK ([direction] IN (N''RESTITUTION'',N''LIVRAISON'')),
  CHECK ([kind] IN (N''BOOKING'',N''EDO'',N''ERO'')),
  CHECK (LEN(TRIM([reference])) BETWEEN 1 AND 150)
);

CREATE TABLE [dbo].[truck_visits] (
  [id] uniqueidentifier NOT NULL DEFAULT NEWID(),
  [plate] nvarchar(max) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [driver_cin] nvarchar(max) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [entry_kind] nvarchar(8) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [container_number] nvarchar(11) COLLATE Latin1_General_100_BIN2 NULL,
  [booking_id] uniqueidentifier NULL,
  [iso_code] nvarchar(4) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [armateur_id] nvarchar(64) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [client_id] uniqueidentifier NULL,
  [entered_at] datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00''),
  [entered_by] uniqueidentifier NOT NULL,
  [engin_at] datetimeoffset(6) NULL,
  [engin_by] uniqueidentifier NULL,
  [exited_at] datetimeoffset(6) NULL,
  [exited_by] uniqueidentifier NULL,
  [canceled_at] datetimeoffset(6) NULL,
  [canceled_by] uniqueidentifier NULL,
  [cancel_reason] nvarchar(max) COLLATE Latin1_General_100_BIN2 NULL,
  [version] int NOT NULL DEFAULT 1,
  [is_twin] bit NOT NULL DEFAULT 0,
  [container_number_2] nvarchar(11) COLLATE Latin1_General_100_BIN2 NULL,
  [iso_code_2] nvarchar(4) COLLATE Latin1_General_100_BIN2 NULL,
  [armateur_id_2] nvarchar(64) COLLATE Latin1_General_100_BIN2 NULL,
  [booking_reference_2] nvarchar(150) COLLATE Latin1_General_100_BIN2 NULL,
  [client_order_reference] nvarchar(150) COLLATE Latin1_General_100_BIN2 NULL,
  [carrier_booking_reference] nvarchar(150) COLLATE Latin1_General_100_BIN2 NULL,
  [carrier_booking_armateur_id] nvarchar(64) COLLATE Latin1_General_100_BIN2 NULL,
  [carrier_booking_armateur_id_2] nvarchar(64) COLLATE Latin1_General_100_BIN2 NULL,
  [order_item_id] uniqueidentifier NULL,
  [order_item_id_2] uniqueidentifier NULL,
  [order_controlled] bit NOT NULL DEFAULT 0,
  CONSTRAINT [truck_visits_pkey] PRIMARY KEY ([id]),
  CHECK (([entry_kind]=N''loaded'' AND [container_number] IS NOT NULL) OR ([entry_kind]=N''empty'' AND [booking_id] IS NOT NULL)),
  CHECK ([carrier_booking_reference] IS NULL OR LEN(TRIM([carrier_booking_reference])) BETWEEN 1 AND 150),
  CHECK ([exited_at] IS NULL OR ([engin_at] IS NOT NULL AND [canceled_at] IS NULL)),
  CHECK ([canceled_at] IS NULL OR ([exited_at] IS NULL AND LEN(TRIM([cancel_reason]))>0)),
  CHECK ([client_order_reference] IS NULL OR LEN(TRIM([client_order_reference])) BETWEEN 1 AND 150),
  CHECK ([entry_kind] IN (N''loaded'',N''empty''))
);

CREATE TABLE [dbo].[user_roles] (
  [user_id] uniqueidentifier NOT NULL,
  [role] nvarchar(16) COLLATE Latin1_General_100_BIN2 NOT NULL,
  CONSTRAINT [user_roles_pkey] PRIMARY KEY ([user_id],[role]),
  CHECK ([role] IN (N''admin'',N''entree'',N''engin'',N''sortie'',N''viewer''))
);

CREATE TABLE [dbo].[visit_events] (
  [id] bigint IDENTITY(1,1) NOT NULL,
  [visit_id] uniqueidentifier NOT NULL,
  [action] nvarchar(64) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [occurred_at] datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00''),
  [actor_id] uniqueidentifier NOT NULL,
  [details] nvarchar(max) NOT NULL DEFAULT N''{}'',
  CHECK ([details] IS NULL OR ISJSON([details],VALUE)=1),
  CONSTRAINT [visit_events_pkey] PRIMARY KEY ([id]),
  CHECK ([action] IN (N''ENTREE'',N''DEPOSE'',N''PRISE'',N''SORTIE'',N''ANNULATION''))
);

CREATE TABLE [dbo].[yard_operations] (
  [id] uniqueidentifier NOT NULL DEFAULT NEWID(),
  [visit_id] uniqueidentifier NOT NULL,
  [kind] nvarchar(32) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [container_number] nvarchar(11) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [position] nvarchar(max) COLLATE Latin1_General_100_BIN2 NULL,
  [performed_at] datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00''),
  [performed_by] uniqueidentifier NOT NULL,
  CONSTRAINT [yard_operations_pkey] PRIMARY KEY ([id]),
  CONSTRAINT [yard_operations_visit_id_key] UNIQUE ([visit_id]),
  CHECK ([kind] IN (N''depose'',N''prise''))
);

ALTER TABLE [internal].[transport_order_aliases] WITH CHECK ADD CONSTRAINT [transport_order_aliases_order_id_fkey] FOREIGN KEY ([order_id]) REFERENCES [dbo].[transport_orders] ([id]);

ALTER TABLE [dbo].[audit_logs] WITH CHECK ADD CONSTRAINT [audit_logs_actor_id_fkey] FOREIGN KEY ([actor_id]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[bookings] WITH CHECK ADD CONSTRAINT [bookings_armateur_id_fkey] FOREIGN KEY ([armateur_id]) REFERENCES [dbo].[armateurs] ([id]);

ALTER TABLE [dbo].[bookings] WITH CHECK ADD CONSTRAINT [bookings_client_id_fkey] FOREIGN KEY ([client_id]) REFERENCES [dbo].[clients] ([id]);

ALTER TABLE [dbo].[client_armateurs] WITH CHECK ADD CONSTRAINT [client_armateurs_armateur_id_fkey] FOREIGN KEY ([armateur_id]) REFERENCES [dbo].[armateurs] ([id]);

ALTER TABLE [dbo].[client_armateurs] WITH CHECK ADD CONSTRAINT [client_armateurs_client_id_fkey] FOREIGN KEY ([client_id]) REFERENCES [dbo].[clients] ([id]);

ALTER TABLE [dbo].[container_stock_intervals] WITH CHECK ADD CONSTRAINT [container_stock_intervals_armateur_id_fkey] FOREIGN KEY ([armateur_id]) REFERENCES [dbo].[armateurs] ([id]);

ALTER TABLE [dbo].[container_stock_intervals] WITH CHECK ADD CONSTRAINT [container_stock_intervals_client_id_fkey] FOREIGN KEY ([client_id]) REFERENCES [dbo].[clients] ([id]);

ALTER TABLE [dbo].[container_stock_intervals] WITH CHECK ADD CONSTRAINT [container_stock_intervals_container_number_fkey] FOREIGN KEY ([container_number]) REFERENCES [dbo].[containers] ([number]);

ALTER TABLE [dbo].[container_stock_intervals] WITH CHECK ADD CONSTRAINT [container_stock_intervals_end_visit_id_fkey] FOREIGN KEY ([end_visit_id]) REFERENCES [dbo].[truck_visits] ([id]);

ALTER TABLE [dbo].[container_stock_intervals] WITH CHECK ADD CONSTRAINT [container_stock_intervals_start_visit_id_fkey] FOREIGN KEY ([start_visit_id]) REFERENCES [dbo].[truck_visits] ([id]);

ALTER TABLE [dbo].[containers] WITH CHECK ADD CONSTRAINT [containers_armateur_id_fkey] FOREIGN KEY ([armateur_id]) REFERENCES [dbo].[armateurs] ([id]);

ALTER TABLE [dbo].[document_actions] WITH CHECK ADD CONSTRAINT [document_actions_actor_id_fkey] FOREIGN KEY ([actor_id]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[document_actions] WITH CHECK ADD CONSTRAINT [document_actions_document_id_fkey] FOREIGN KEY ([document_id]) REFERENCES [dbo].[generated_documents] ([id]);

ALTER TABLE [dbo].[evp_rules] WITH CHECK ADD CONSTRAINT [evp_rules_created_by_fkey] FOREIGN KEY ([created_by]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[forced_container_actions] WITH CHECK ADD CONSTRAINT [forced_container_actions_actor_id_fkey] FOREIGN KEY ([actor_id]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[forced_container_actions] WITH CHECK ADD CONSTRAINT [forced_container_actions_container_number_fkey] FOREIGN KEY ([container_number]) REFERENCES [dbo].[containers] ([number]);

ALTER TABLE [dbo].[forced_container_actions] WITH CHECK ADD CONSTRAINT [forced_container_actions_resolved_by_fkey] FOREIGN KEY ([resolved_by]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[forced_container_actions] WITH CHECK ADD CONSTRAINT [forced_container_actions_visit_id_fkey] FOREIGN KEY ([visit_id]) REFERENCES [dbo].[truck_visits] ([id]);

ALTER TABLE [dbo].[generated_documents] WITH CHECK ADD CONSTRAINT [generated_documents_created_by_fkey] FOREIGN KEY ([created_by]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[generated_documents] WITH CHECK ADD CONSTRAINT [generated_documents_event_id_fkey] FOREIGN KEY ([event_id]) REFERENCES [dbo].[visit_events] ([id]);

ALTER TABLE [dbo].[generated_documents] WITH CHECK ADD CONSTRAINT [generated_documents_visit_id_fkey] FOREIGN KEY ([visit_id]) REFERENCES [dbo].[truck_visits] ([id]);

ALTER TABLE [dbo].[printer_settings] WITH CHECK ADD CONSTRAINT [printer_settings_user_id_fkey] FOREIGN KEY ([user_id]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[transport_order_items] WITH CHECK ADD CONSTRAINT [transport_order_items_armateur_id_fkey] FOREIGN KEY ([armateur_id]) REFERENCES [dbo].[armateurs] ([id]);

ALTER TABLE [dbo].[transport_order_items] WITH CHECK ADD CONSTRAINT [transport_order_items_order_id_fkey] FOREIGN KEY ([order_id]) REFERENCES [dbo].[transport_orders] ([id]);

ALTER TABLE [dbo].[transport_orders] WITH CHECK ADD CONSTRAINT [transport_orders_armateur_id_fkey] FOREIGN KEY ([armateur_id]) REFERENCES [dbo].[armateurs] ([id]);

ALTER TABLE [dbo].[transport_orders] WITH CHECK ADD CONSTRAINT [transport_orders_client_id_fkey] FOREIGN KEY ([client_id]) REFERENCES [dbo].[clients] ([id]);

ALTER TABLE [dbo].[transport_orders] WITH CHECK ADD CONSTRAINT [transport_orders_created_by_fkey] FOREIGN KEY ([created_by]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[transport_orders] WITH CHECK ADD CONSTRAINT [transport_orders_updated_by_fkey] FOREIGN KEY ([updated_by]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[truck_visits] WITH CHECK ADD CONSTRAINT [truck_visits_armateur_id_2_fkey] FOREIGN KEY ([armateur_id_2]) REFERENCES [dbo].[armateurs] ([id]);

ALTER TABLE [dbo].[truck_visits] WITH CHECK ADD CONSTRAINT [truck_visits_armateur_id_fkey] FOREIGN KEY ([armateur_id]) REFERENCES [dbo].[armateurs] ([id]);

ALTER TABLE [dbo].[truck_visits] WITH CHECK ADD CONSTRAINT [truck_visits_booking_id_fkey] FOREIGN KEY ([booking_id]) REFERENCES [dbo].[bookings] ([id]);

ALTER TABLE [dbo].[truck_visits] WITH CHECK ADD CONSTRAINT [truck_visits_canceled_by_fkey] FOREIGN KEY ([canceled_by]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[truck_visits] WITH CHECK ADD CONSTRAINT [truck_visits_carrier_booking_armateur_id_2_fkey] FOREIGN KEY ([carrier_booking_armateur_id_2]) REFERENCES [dbo].[armateurs] ([id]);

ALTER TABLE [dbo].[truck_visits] WITH CHECK ADD CONSTRAINT [truck_visits_carrier_booking_armateur_id_fkey] FOREIGN KEY ([carrier_booking_armateur_id]) REFERENCES [dbo].[armateurs] ([id]);

ALTER TABLE [dbo].[truck_visits] WITH CHECK ADD CONSTRAINT [truck_visits_client_id_fkey] FOREIGN KEY ([client_id]) REFERENCES [dbo].[clients] ([id]);

ALTER TABLE [dbo].[truck_visits] WITH CHECK ADD CONSTRAINT [truck_visits_container_number_2_fkey] FOREIGN KEY ([container_number_2]) REFERENCES [dbo].[containers] ([number]);

ALTER TABLE [dbo].[truck_visits] WITH CHECK ADD CONSTRAINT [truck_visits_container_number_fkey] FOREIGN KEY ([container_number]) REFERENCES [dbo].[containers] ([number]);

ALTER TABLE [dbo].[truck_visits] WITH CHECK ADD CONSTRAINT [truck_visits_engin_by_fkey] FOREIGN KEY ([engin_by]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[truck_visits] WITH CHECK ADD CONSTRAINT [truck_visits_entered_by_fkey] FOREIGN KEY ([entered_by]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[truck_visits] WITH CHECK ADD CONSTRAINT [truck_visits_exited_by_fkey] FOREIGN KEY ([exited_by]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[truck_visits] WITH CHECK ADD CONSTRAINT [truck_visits_order_item_id_2_fkey] FOREIGN KEY ([order_item_id_2]) REFERENCES [dbo].[transport_order_items] ([id]);

ALTER TABLE [dbo].[truck_visits] WITH CHECK ADD CONSTRAINT [truck_visits_order_item_id_fkey] FOREIGN KEY ([order_item_id]) REFERENCES [dbo].[transport_order_items] ([id]);

ALTER TABLE [dbo].[user_roles] WITH CHECK ADD CONSTRAINT [user_roles_user_id_fkey] FOREIGN KEY ([user_id]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[visit_events] WITH CHECK ADD CONSTRAINT [visit_events_actor_id_fkey] FOREIGN KEY ([actor_id]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[visit_events] WITH CHECK ADD CONSTRAINT [visit_events_visit_id_fkey] FOREIGN KEY ([visit_id]) REFERENCES [dbo].[truck_visits] ([id]);

ALTER TABLE [dbo].[yard_operations] WITH CHECK ADD CONSTRAINT [yard_operations_container_number_fkey] FOREIGN KEY ([container_number]) REFERENCES [dbo].[containers] ([number]);

ALTER TABLE [dbo].[yard_operations] WITH CHECK ADD CONSTRAINT [yard_operations_performed_by_fkey] FOREIGN KEY ([performed_by]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[yard_operations] WITH CHECK ADD CONSTRAINT [yard_operations_visit_id_fkey] FOREIGN KEY ([visit_id]) REFERENCES [dbo].[truck_visits] ([id]);


ALTER TABLE dbo.transport_orders ADD normalized_reference AS UPPER(TRIM(reference)) PERSISTED;
CREATE UNIQUE INDEX transport_orders_reference_key ON dbo.transport_orders(normalized_reference);
CREATE UNIQUE INDEX generated_documents_path_key ON dbo.generated_documents(storage_path) WHERE storage_path IS NOT NULL;
CREATE UNIQUE INDEX one_open_stock_interval ON dbo.container_stock_intervals(container_number) WHERE departed_at IS NULL;
-- A computed SHA-256 key permits indexing arbitrary-length historical position strings.
ALTER TABLE dbo.container_stock_intervals ADD position_hash AS CONVERT(binary(32),HASHBYTES(''SHA2_256'',position)) PERSISTED;
CREATE UNIQUE INDEX one_open_yard_position ON dbo.container_stock_intervals(position_hash) WHERE departed_at IS NULL AND position IS NOT NULL;
CREATE UNIQUE INDEX idx_profiles_phone_unique ON dbo.profiles(phone) WHERE phone IS NOT NULL AND phone<>N'''';
-- SQL Server filtered indexes cannot express the PostgreSQL OR predicate. Inactive rows
-- use their UUID as a distinct key, while active rows use the container number.
ALTER TABLE dbo.truck_visits ADD active_container_key AS
  CASE WHEN container_number IS NOT NULL AND canceled_at IS NULL AND exited_at IS NULL
    AND ((entry_kind=N''loaded'' AND engin_at IS NULL) OR (entry_kind=N''empty'' AND engin_at IS NOT NULL))
    THEN CONVERT(nvarchar(36),container_number) ELSE CONVERT(nvarchar(36),id) END PERSISTED;
ALTER TABLE dbo.truck_visits ADD active_container_2_key AS
  CASE WHEN container_number_2 IS NOT NULL AND canceled_at IS NULL AND exited_at IS NULL
    AND ((entry_kind=N''loaded'' AND engin_at IS NULL) OR (entry_kind=N''empty'' AND engin_at IS NOT NULL))
    THEN CONVERT(nvarchar(36),container_number_2) ELSE CONVERT(nvarchar(36),id) END PERSISTED;
CREATE UNIQUE INDEX one_active_container_on_truck ON dbo.truck_visits(active_container_key);
CREATE UNIQUE INDEX one_active_container_2_on_truck ON dbo.truck_visits(active_container_2_key);
CREATE INDEX visits_order_item_idx ON dbo.truck_visits(order_item_id) INCLUDE(canceled_at,engin_at,exited_at);
CREATE INDEX visits_order_item_2_idx ON dbo.truck_visits(order_item_id_2) INCLUDE(canceled_at,engin_at,exited_at);
CREATE INDEX visits_inside_idx ON dbo.truck_visits(entered_at,id) WHERE exited_at IS NULL AND canceled_at IS NULL;
CREATE INDEX audit_entity_idx ON dbo.audit_logs(entity,entity_id,occurred_at);
CREATE INDEX documents_visit_idx ON dbo.generated_documents(visit_id,created_at);
INSERT internal.schema_versions(version) VALUES(1);
-- Commit managed by the outer deployment batch.';
  SET @etape_deploiement=N'002_order_api.sql, lot 1';
  EXEC sys.sp_executesql N'-- First API slice. Apply after 001_schema.sql using the DBA deployment identity.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF NOT EXISTS(SELECT 1 FROM internal.schema_versions WHERE version=1) THROW 51000, ''Schema version 1 is required.'', 1;
IF EXISTS(SELECT 1 FROM internal.schema_versions WHERE version=2) THROW 51000, ''Version 2 is already installed.'', 1;';
  SET @etape_deploiement=N'002_order_api.sql, lot 2';
  EXEC sys.sp_executesql N'CREATE OR ALTER FUNCTION api.can_do(@actor uniqueidentifier,@permission nvarchar(16)) RETURNS bit AS
BEGIN
  RETURN CASE WHEN EXISTS(SELECT 1 FROM dbo.profiles p JOIN dbo.user_roles r ON r.user_id=p.id
    WHERE p.id=@actor AND p.active=1 AND (r.role=N''admin'' OR r.role=@permission OR @permission=N''read'')) THEN 1 ELSE 0 END;
END;';
  SET @etape_deploiement=N'002_order_api.sql, lot 3';
  EXEC sys.sp_executesql N'CREATE OR ALTER FUNCTION api.parse_items(@items nvarchar(max)) RETURNS TABLE AS RETURN
  -- OPENJSON inherits the database/input collation. These identifiers join
  -- BIN2 business columns, including when the database default is French_CI_AS.
  SELECT id,UPPER(TRIM(iso_code)) COLLATE Latin1_General_100_BIN2 AS iso_code,
    armateur_id COLLATE Latin1_General_100_BIN2 AS armateur_id,quantity
  FROM OPENJSON(@items) WITH(id uniqueidentifier ''$.id'',iso_code nvarchar(max) ''$.iso_code'',
    armateur_id nvarchar(max) ''$.armateur_id'',quantity int ''$.quantity'');';
  SET @etape_deploiement=N'002_order_api.sql, lot 4';
  EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.user_context @ActorId uniqueidentifier AS
BEGIN
  SET NOCOUNT ON;
  IF api.can_do(@ActorId,N''read'')=0 THROW 51003, ''Access denied.'', 1;
  SELECT (SELECT p.id,p.display_name,p.first_name,p.last_name,p.phone,p.active,
    JSON_QUERY((SELECT role FROM dbo.user_roles WHERE user_id=p.id FOR JSON PATH)) roles
    FROM dbo.profiles p WHERE p.id=@ActorId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
END;';
  SET @etape_deploiement=N'002_order_api.sql, lot 5';
  EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.operators @ActorId uniqueidentifier AS
BEGIN
  SET NOCOUNT ON;
  IF api.can_do(@ActorId,N''read'')=0 THROW 51003, ''Access denied.'', 1;
  SELECT (SELECT id,name,bic FROM dbo.armateurs WHERE active=1 ORDER BY name FOR JSON PATH);
END;';
  SET @etape_deploiement=N'002_order_api.sql, lot 6';
  EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.order_items_status @ActorId uniqueidentifier,@Direction nvarchar(16)=NULL AS
BEGIN
  SET NOCOUNT ON;
  IF api.can_do(@ActorId,N''read'')=0 THROW 51003, ''Access denied.'', 1;
  SELECT (SELECT i.id,i.order_id,i.armateur_id,i.iso_code,i.quantity,o.reference,o.kind,o.direction,
    o.active,o.version,o.updated_at,t.ever_used,t.reserved,t.completed,i.quantity-t.reserved-t.completed remaining
    FROM dbo.transport_order_items i JOIN dbo.transport_orders o ON o.id=i.order_id
    CROSS APPLY (SELECT COUNT_BIG(*) ever_used,
      COALESCE(SUM(CASE WHEN canceled_at IS NULL AND engin_at IS NULL AND exited_at IS NULL THEN 1 ELSE 0 END),0) reserved,
      COALESCE(SUM(CASE WHEN canceled_at IS NULL AND (engin_at IS NOT NULL OR exited_at IS NOT NULL) THEN 1 ELSE 0 END),0) completed
      FROM (SELECT canceled_at,engin_at,exited_at FROM dbo.truck_visits WHERE order_item_id=i.id
        UNION ALL SELECT canceled_at,engin_at,exited_at FROM dbo.truck_visits WHERE order_item_id_2=i.id) a) t
    WHERE @Direction IS NULL OR o.direction=@Direction
    ORDER BY o.created_at DESC,i.armateur_id,i.iso_code FOR JSON PATH);
END;';
  SET @etape_deploiement=N'002_order_api.sql, lot 7';
  EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.validate_items @Items nvarchar(max) AS
BEGIN
  SET NOCOUNT ON;
  IF ISJSON(@Items)<>1 OR LEFT(TRIM(@Items),1)<>N''['' THROW 51004, ''Items must be a JSON array.'', 1;
  IF (SELECT COUNT(*) FROM api.parse_items(@Items)) NOT BETWEEN 1 AND 50 THROW 51004, ''Provide 1 to 50 items.'', 1;
  IF EXISTS(SELECT 1 FROM OPENJSON(@Items) i WHERE i.type<>5 OR NOT EXISTS(
    SELECT 1 FROM OPENJSON(i.value) p WHERE p.[key]=N''quantity'' AND p.type=2 AND p.value NOT LIKE N''%[^0-9]%'' COLLATE Latin1_General_100_BIN2))
    THROW 51004, ''Each item requires an integer quantity.'', 1;
  IF EXISTS(SELECT 1 FROM api.parse_items(@Items) WHERE iso_code IS NULL OR LEN(iso_code)<>4
    OR iso_code COLLATE Latin1_General_100_BIN2 LIKE N''%[^0-9A-Z]%''
    OR quantity IS NULL OR quantity NOT BETWEEN 1 AND 1000000 OR armateur_id IS NULL OR LEN(armateur_id)>64
    OR DATALENGTH(armateur_id)<>DATALENGTH(TRIM(armateur_id)))
    THROW 51004, ''Invalid item ISO, carrier or quantity.'', 1;
  IF EXISTS(SELECT 1 FROM api.parse_items(@Items) GROUP BY armateur_id,iso_code HAVING COUNT(*)>1)
    THROW 51004, ''An item already exists for this carrier and ISO.'', 1;
END;';
  SET @etape_deploiement=N'002_order_api.sql, lot 8';
  EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.create_order @ActorId uniqueidentifier,@Kind nvarchar(32),@Reference nvarchar(max),@Items nvarchar(max) AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  IF api.can_do(@ActorId,N''entree'')=0 THROW 51003, ''Order creation denied.'', 1;
  IF @Kind NOT IN (N''EDO'',N''ERO'') OR @Kind IS NULL THROW 51004, ''Only EDO and ERO can be created.'', 1;
  SET @Reference=UPPER(TRIM(@Reference));
  IF @Reference IS NULL OR LEN(@Reference) NOT BETWEEN 1 AND 150 THROW 51004, ''Reference is required, up to 150 characters.'', 1;
  EXEC api.validate_items @Items;
  IF EXISTS(SELECT 1 FROM api.parse_items(@Items) i LEFT JOIN dbo.armateurs a ON a.id=i.armateur_id WHERE a.id IS NULL OR a.active=0)
    THROW 51004, ''Active carrier required.'', 1;
  IF EXISTS(SELECT 1 FROM api.parse_items(@Items) WHERE id IS NOT NULL) THROW 51004, ''New items cannot supply existing IDs.'', 1;
  BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @id uniqueidentifier=NEWID(),@carrier nvarchar(64)=(SELECT TOP(1) armateur_id FROM api.parse_items(@Items) ORDER BY armateur_id,iso_code);
    INSERT dbo.transport_orders(id,kind,direction,reference,armateur_id,created_by,updated_by)
      VALUES(@id,@Kind,CASE WHEN @Kind=N''EDO'' THEN N''LIVRAISON'' ELSE N''RESTITUTION'' END,@Reference,@carrier,@ActorId,@ActorId);
    INSERT dbo.transport_order_items(order_id,armateur_id,iso_code,quantity)
      SELECT @id,armateur_id,iso_code,quantity FROM api.parse_items(@Items);
    INSERT dbo.audit_logs(entity,entity_id,action,actor_id,after_data)
      VALUES(N''transport_order'',CONVERT(nvarchar(36),@id),N''CREATION'',@ActorId,
        (SELECT @Reference reference,@Kind kind,JSON_QUERY(@Items) items FOR JSON PATH,WITHOUT_ARRAY_WRAPPER));
    COMMIT;
    SELECT (SELECT @id id,1 version FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
  END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;';
  SET @etape_deploiement=N'002_order_api.sql, lot 9';
  EXEC sys.sp_executesql N'CREATE OR ALTER TRIGGER dbo.protect_order_item_history ON dbo.transport_order_items AFTER UPDATE,DELETE AS
BEGIN
  SET NOCOUNT ON;
  IF EXISTS(SELECT 1 FROM deleted d LEFT JOIN inserted i ON i.id=d.id
    WHERE (i.id IS NULL OR i.order_id<>d.order_id OR i.armateur_id<>d.armateur_id OR i.iso_code<>d.iso_code)
      AND EXISTS(SELECT 1 FROM dbo.truck_visits WHERE order_item_id=d.id OR order_item_id_2=d.id))
    THROW 51004, ''Used items cannot be removed or change order, carrier or ISO.'', 1;
  IF EXISTS(SELECT 1 FROM inserted i CROSS APPLY(SELECT COUNT_BIG(*) allocated FROM (
    SELECT id FROM dbo.truck_visits WHERE order_item_id=i.id AND canceled_at IS NULL
    UNION ALL SELECT id FROM dbo.truck_visits WHERE order_item_id_2=i.id AND canceled_at IS NULL) a) q WHERE i.quantity<q.allocated)
    THROW 51004, ''Quantity is below the reserved or completed total.'', 1;
END;';
  SET @etape_deploiement=N'002_order_api.sql, lot 10';
  EXEC sys.sp_executesql N'CREATE OR ALTER TRIGGER dbo.protect_delivery_age ON dbo.container_stock_intervals AFTER INSERT,UPDATE AS
BEGIN
  SET NOCOUNT ON;
  IF EXISTS(SELECT 1 FROM inserted i LEFT JOIN deleted d ON d.id=i.id JOIN dbo.truck_visits received ON received.id=i.start_visit_id
    WHERE i.departed_at IS NOT NULL AND (d.departed_at IS NULL OR i.departed_at<>d.departed_at)
      AND (received.entry_kind<>N''loaded'' OR i.departed_at<DATEADD(hour,24,received.entered_at)))
    THROW 51004, ''Delivery requires 24 hours from the receiving truck entry.'', 1;
END;';
  SET @etape_deploiement=N'002_order_api.sql, lot 11';
  EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.increase_order_quantity @ActorId uniqueidentifier,@ItemId uniqueidentifier,@Quantity int AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  IF api.can_do(@ActorId,N''entree'')=0 THROW 51003, ''Order modification denied.'', 1;
  IF @Quantity IS NULL OR @Quantity NOT BETWEEN 1 AND 1000000 THROW 51004, ''Positive quantity required.'', 1;
  BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @parent uniqueidentifier,@before int,@total int,@version int;
    SELECT @parent=order_id FROM dbo.transport_order_items WHERE id=@ItemId;
    IF @parent IS NULL THROW 51002, ''Item not found.'', 1;
    SELECT @version=version FROM dbo.transport_orders WITH(UPDLOCK,HOLDLOCK) WHERE id=@parent;
    SELECT @before=quantity FROM dbo.transport_order_items WITH(UPDLOCK,HOLDLOCK) WHERE id=@ItemId;
    IF @before IS NULL THROW 51009, ''Item was removed. Refresh the order.'', 1;
    IF @before+@Quantity>1000000 THROW 51004, ''Maximum total is 1000000.'', 1;
    SET @total=@before+@Quantity;
    UPDATE dbo.transport_order_items SET quantity=@total WHERE id=@ItemId;
    UPDATE dbo.transport_orders SET version=version+1,updated_at=TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00''),updated_by=@ActorId WHERE id=@parent;
    INSERT dbo.audit_logs(entity,entity_id,action,actor_id,before_data,after_data)
      VALUES(N''transport_order'',CONVERT(nvarchar(36),@parent),N''AJOUT_QUANTITE'',@ActorId,
        (SELECT @ItemId item_id,@before quantity FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
        (SELECT @ItemId item_id,@total quantity,@Quantity added FOR JSON PATH,WITHOUT_ARRAY_WRAPPER));
    COMMIT;
    SELECT (SELECT @total quantity,@version+1 version FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
  END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;';
  SET @etape_deploiement=N'002_order_api.sql, lot 12';
  EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.update_order @ActorId uniqueidentifier,@OrderId uniqueidentifier,@ExpectedVersion int,@Items nvarchar(max) AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  IF api.can_do(@ActorId,N''entree'')=0 THROW 51003, ''Order modification denied.'', 1;
  EXEC api.validate_items @Items;
  BEGIN TRY
    BEGIN TRANSACTION;
    SET @OrderId=COALESCE((SELECT order_id FROM internal.transport_order_aliases WHERE alias_id=@OrderId),@OrderId);
    DECLARE @version int,@before nvarchar(max),@after nvarchar(max);
    SELECT @version=version FROM dbo.transport_orders WITH(UPDLOCK,HOLDLOCK) WHERE id=@OrderId;
    IF @version IS NULL THROW 51002, ''Order not found.'', 1;
    IF @ExpectedVersion IS NULL OR @version<>@ExpectedVersion THROW 51009, ''Order changed. Refresh before saving.'', 1;
    DECLARE @locked int;
    SELECT @locked=COUNT(*) FROM dbo.transport_order_items WITH(UPDLOCK,HOLDLOCK) WHERE order_id=@OrderId;
    IF EXISTS(SELECT 1 FROM api.parse_items(@Items) i LEFT JOIN dbo.transport_order_items d ON d.id=i.id AND d.order_id=@OrderId WHERE i.id IS NOT NULL AND d.id IS NULL)
      THROW 51004, ''Item does not belong to this order.'', 1;
    IF EXISTS(SELECT id FROM api.parse_items(@Items) WHERE id IS NOT NULL GROUP BY id HAVING COUNT(*)>1)
      THROW 51004, ''Repeated item ID.'', 1;
    IF EXISTS(SELECT 1 FROM api.parse_items(@Items) i LEFT JOIN dbo.transport_order_items d ON d.id=i.id
      LEFT JOIN dbo.armateurs a ON a.id=i.armateur_id WHERE a.id IS NULL OR (a.active=0 AND (d.id IS NULL OR d.armateur_id<>i.armateur_id)))
      THROW 51004, ''Active carrier required for new or changed items.'', 1;
    SET @before=(SELECT o.*,JSON_QUERY((SELECT * FROM dbo.transport_order_items WHERE order_id=@OrderId FOR JSON PATH)) items FROM dbo.transport_orders o WHERE id=@OrderId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
    -- Remove unused omitted rows before changing keys; used rows are protected by the trigger.
    DELETE d FROM dbo.transport_order_items d WHERE d.order_id=@OrderId AND NOT EXISTS(SELECT 1 FROM api.parse_items(@Items) i WHERE i.id=d.id);
    UPDATE d SET iso_code=i.iso_code,armateur_id=i.armateur_id,quantity=i.quantity
      FROM dbo.transport_order_items d JOIN api.parse_items(@Items) i ON i.id=d.id WHERE d.order_id=@OrderId;
    INSERT dbo.transport_order_items(order_id,armateur_id,iso_code,quantity)
      SELECT @OrderId,armateur_id,iso_code,quantity FROM api.parse_items(@Items) WHERE id IS NULL;
    UPDATE dbo.transport_orders SET version=version+1,updated_at=TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00''),updated_by=@ActorId WHERE id=@OrderId;
    SET @after=(SELECT o.*,JSON_QUERY((SELECT * FROM dbo.transport_order_items WHERE order_id=@OrderId FOR JSON PATH)) items FROM dbo.transport_orders o WHERE id=@OrderId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
    INSERT dbo.audit_logs(entity,entity_id,action,actor_id,before_data,after_data) VALUES(N''transport_order'',CONVERT(nvarchar(36),@OrderId),N''MODIFICATION'',@ActorId,@before,@after);
    COMMIT;
    SELECT (SELECT @version+1 version FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
  END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;';
  SET @etape_deploiement=N'002_order_api.sql, lot 13';
  EXEC sys.sp_executesql N'-- The API identity receives procedure execution only, never direct access to business tables.
IF DATABASE_PRINCIPAL_ID(N''pointage_api'') IS NULL CREATE ROLE pointage_api;
GRANT EXECUTE ON SCHEMA::api TO pointage_api;
DENY SELECT,INSERT,UPDATE,DELETE ON SCHEMA::dbo TO pointage_api;
DENY SELECT,INSERT,UPDATE,DELETE ON SCHEMA::internal TO pointage_api;
INSERT internal.schema_versions(version) VALUES(2);';
  SET @etape_deploiement=N'005_application_accounts.sql, lot 1';
  EXEC sys.sp_executesql N'-- Local application accounts. Apply after 001/002, using the DBA deployment identity.
-- No AD, Entra, professional email or source password is required/imported.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF NOT EXISTS(SELECT 1 FROM internal.schema_versions WHERE version=2) THROW 51000, ''Schema version 2 is required.'', 1;
IF EXISTS(SELECT 1 FROM internal.schema_versions WHERE version=3) THROW 51000, ''Version 3 is already installed.'', 1;
-- Transaction managed by the outer deployment batch.
CREATE TABLE internal.local_accounts (
  user_id uniqueidentifier NOT NULL PRIMARY KEY REFERENCES dbo.profiles(id),
  username nvarchar(100) COLLATE Latin1_General_100_BIN2 NOT NULL,
  normalized_username AS UPPER(username) PERSISTED,
  password_hash nvarchar(512) NOT NULL,
  must_change_password bit NOT NULL DEFAULT 1,
  version int NOT NULL DEFAULT 1 CHECK(version>0),
  failed_attempts int NOT NULL DEFAULT 0 CHECK(failed_attempts BETWEEN 0 AND 5),
  locked_until datetimeoffset(6) NULL,
  created_at datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00''),
  CHECK (DATALENGTH(username) BETWEEN 6 AND 200 AND username NOT LIKE N''%[^A-Za-z0-9@._+-]%''),
  CHECK (LEN(password_hash) BETWEEN 40 AND 512)
);
CREATE UNIQUE INDEX local_accounts_username_key ON internal.local_accounts(normalized_username);
CREATE TABLE internal.application_sessions (
  token_hash binary(32) NOT NULL PRIMARY KEY,
  user_id uniqueidentifier NOT NULL REFERENCES internal.local_accounts(user_id),
  expires_at datetimeoffset(6) NOT NULL,
  created_at datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00'')
);
CREATE INDEX application_sessions_user_idx ON internal.application_sessions(user_id);
CREATE INDEX application_sessions_expiry_idx ON internal.application_sessions(expires_at);';
  SET @etape_deploiement=N'005_application_accounts.sql, lot 2';
  EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE internal.account_admin_lock AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @lock int;
  EXEC @lock=sys.sp_getapplock @Resource=N''pointage-admin-accounts'',@LockMode=N''Exclusive'',@LockOwner=N''Transaction'',@LockTimeout=10000;
  IF @lock<0 THROW 51009, ''Account management busy; retry after refresh.'', 1;
END;';
  SET @etape_deploiement=N'005_application_accounts.sql, lot 3';
  EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.account_credentials @Username nvarchar(100) AS
BEGIN
  SET NOCOUNT ON;
  SELECT (SELECT a.user_id,a.password_hash,a.version FROM internal.local_accounts a
    WHERE a.normalized_username=@Username FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
END;';
  SET @etape_deploiement=N'005_application_accounts.sql, lot 4';
  EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.account_own_credentials @ActorId uniqueidentifier AS
BEGIN
  SET NOCOUNT ON;
  SELECT (SELECT a.password_hash,a.version FROM internal.local_accounts a JOIN dbo.profiles p ON p.id=a.user_id
    WHERE a.user_id=@ActorId AND p.active=1 FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
END;';
  SET @etape_deploiement=N'005_application_accounts.sql, lot 5';
  EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.account_login @UserId uniqueidentifier,@ExpectedVersion int,@ExpectedHash nvarchar(512),
  @Verified bit,@ReplacementHash nvarchar(512)=NULL,@TokenHash varbinary(32),@SessionHours int AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  IF @SessionHours NOT BETWEEN 1 AND 12 OR DATALENGTH(@TokenHash)<>32 OR @TokenHash IS NULL
    THROW 51004, ''Invalid session settings.'', 1;
  DECLARE @now datetimeoffset(6)=TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00''),@failed int,@locked datetimeoffset(6),@change bit;
  BEGIN TRY
    BEGIN TRANSACTION;
    SELECT @failed=a.failed_attempts,@locked=a.locked_until,@change=a.must_change_password
      FROM internal.local_accounts a WITH(UPDLOCK,HOLDLOCK) JOIN dbo.profiles p ON p.id=a.user_id
      WHERE a.user_id=@UserId AND a.version=@ExpectedVersion AND p.active=1
        AND a.password_hash COLLATE Latin1_General_100_BIN2=@ExpectedHash COLLATE Latin1_General_100_BIN2;
    IF @failed IS NULL OR @locked>@now BEGIN COMMIT; RETURN; END;
    IF @Verified<>1 OR @Verified IS NULL
    BEGIN
      SET @failed=CASE WHEN @locked IS NOT NULL AND @locked<=@now THEN 1 WHEN @failed<5 THEN @failed+1 ELSE 5 END;
      UPDATE internal.local_accounts SET failed_attempts=@failed,locked_until=CASE WHEN @failed>=5 THEN DATEADD(minute,15,@now) ELSE NULL END WHERE user_id=@UserId;
      COMMIT; RETURN;
    END;
    UPDATE internal.local_accounts SET failed_attempts=0,locked_until=NULL,password_hash=COALESCE(@ReplacementHash,password_hash) WHERE user_id=@UserId;
    DECLARE @expires datetimeoffset(6)=DATEADD(hour,@SessionHours,@now);
    DELETE internal.application_sessions WHERE user_id=@UserId AND expires_at<=@now;
    INSERT internal.application_sessions(token_hash,user_id,expires_at) VALUES(@TokenHash,@UserId,@expires);
    INSERT dbo.audit_logs(entity,entity_id,action,actor_id) VALUES(N''account'',CONVERT(nvarchar(36),@UserId),N''LOGIN'',@UserId);
    COMMIT;
    SELECT (SELECT @expires expires_at,@change must_change_password FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
  END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;';
  SET @etape_deploiement=N'005_application_accounts.sql, lot 6';
  EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.account_session @TokenHash varbinary(32) AS
BEGIN
  SET NOCOUNT ON;
  SELECT (SELECT a.user_id,a.must_change_password FROM internal.application_sessions s
    JOIN internal.local_accounts a ON a.user_id=s.user_id JOIN dbo.profiles p ON p.id=a.user_id
    WHERE s.token_hash=@TokenHash AND s.expires_at>TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00'') AND p.active=1
    FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
END;';
  SET @etape_deploiement=N'005_application_accounts.sql, lot 7';
  EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.account_logout @TokenHash varbinary(32) AS
BEGIN
  SET NOCOUNT ON;
  DELETE internal.application_sessions WHERE token_hash=@TokenHash;
END;';
  SET @etape_deploiement=N'005_application_accounts.sql, lot 8';
  EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.account_change_password @ActorId uniqueidentifier,@ExpectedVersion int,
  @PasswordHash nvarchar(512),@TokenHash varbinary(32) AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE a WITH(UPDLOCK) SET password_hash=@PasswordHash,must_change_password=0,version=version+1,failed_attempts=0,locked_until=NULL
      FROM internal.local_accounts a JOIN dbo.profiles p ON p.id=a.user_id
      WHERE a.user_id=@ActorId AND a.version=@ExpectedVersion AND p.active=1
        AND EXISTS(SELECT 1 FROM internal.application_sessions s WHERE s.user_id=@ActorId AND s.token_hash=@TokenHash
          AND s.expires_at>TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00''));
    IF @@ROWCOUNT<>1 BEGIN COMMIT; SELECT 0; RETURN; END;
    DELETE internal.application_sessions WHERE user_id=@ActorId;
    INSERT dbo.audit_logs(entity,entity_id,action,actor_id) VALUES(N''account'',CONVERT(nvarchar(36),@ActorId),N''PASSWORD_CHANGED'',@ActorId);
    COMMIT; SELECT 1;
  END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;';
  SET @etape_deploiement=N'005_application_accounts.sql, lot 9';
  EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE internal.validate_account @Username nvarchar(100),@PasswordHash nvarchar(512),@Roles nvarchar(max) AS
BEGIN
  SET NOCOUNT ON;
  IF @Username IS NULL OR DATALENGTH(@Username) NOT BETWEEN 6 AND 200 OR @Username COLLATE Latin1_General_100_BIN2 LIKE N''%[^A-Za-z0-9@._+-]%''
    OR @PasswordHash IS NULL OR LEN(@PasswordHash) NOT BETWEEN 40 AND 512 THROW 51004, ''Invalid account.'', 1;
  IF ISJSON(@Roles,ARRAY)<>1 OR @Roles IS NULL THROW 51004, ''Roles must be an array.'', 1;
  IF (SELECT COUNT(*) FROM OPENJSON(@Roles)) NOT BETWEEN 1 AND 5
    OR EXISTS(SELECT 1 FROM OPENJSON(@Roles) WHERE type<>1 OR value COLLATE Latin1_General_100_BIN2 NOT IN(N''admin'',N''entree'',N''engin'',N''sortie'',N''viewer''))
    OR EXISTS(SELECT 1 FROM OPENJSON(@Roles) GROUP BY value COLLATE Latin1_General_100_BIN2 HAVING COUNT(*)>1)
    THROW 51004, ''Invalid roles.'', 1;
END;';
  SET @etape_deploiement=N'005_application_accounts.sql, lot 10';
  EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.account_create @ActorId uniqueidentifier,@Username nvarchar(100),@DisplayName nvarchar(200),
  @PasswordHash nvarchar(512),@Roles nvarchar(max),@ExistingProfileId uniqueidentifier=NULL AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  IF api.can_do(@ActorId,N''admin'')=0 THROW 51003, ''Only Admin creates accounts.'', 1;
  EXEC internal.validate_account @Username,@PasswordHash,@Roles;
  IF @DisplayName IS NULL OR LEN(TRIM(@DisplayName))=0 THROW 51004, ''Display name required.'', 1;
  BEGIN TRY
    BEGIN TRANSACTION;
    EXEC internal.account_admin_lock;
    IF api.can_do(@ActorId,N''admin'')=0 THROW 51003, ''Only Admin creates accounts.'', 1;
    DECLARE @user uniqueidentifier=COALESCE(@ExistingProfileId,NEWID());
    IF @ExistingProfileId IS NULL INSERT dbo.profiles(id,display_name) VALUES(@user,TRIM(@DisplayName));
    ELSE IF NOT EXISTS(SELECT 1 FROM dbo.profiles WHERE id=@user) THROW 51002, ''Historical profile not found.'', 1;
    ELSE IF EXISTS(SELECT 1 FROM internal.local_accounts WHERE user_id=@user) THROW 51009, ''Profile already has an account.'', 1;
    -- Existing profile UUID/identity are retained; roles are an explicit Admin decision.
    INSERT internal.local_accounts(user_id,username,password_hash) VALUES(@user,@Username,@PasswordHash);
    DELETE dbo.user_roles WHERE user_id=@user;
    INSERT dbo.user_roles(user_id,role) SELECT @user,value FROM OPENJSON(@Roles);
    INSERT dbo.audit_logs(entity,entity_id,action,actor_id,after_data) VALUES(N''account'',CONVERT(nvarchar(36),@user),N''CREATION'',@ActorId,
      (SELECT @Username username,JSON_QUERY(@Roles) roles FOR JSON PATH,WITHOUT_ARRAY_WRAPPER));
    COMMIT;
    SELECT (SELECT @user id,1 version,CAST(1 AS bit) must_change_password FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
  END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;';
  SET @etape_deploiement=N'005_application_accounts.sql, lot 11';
  EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.account_list @ActorId uniqueidentifier AS
BEGIN
  SET NOCOUNT ON;
  IF api.can_do(@ActorId,N''admin'')=0 THROW 51003, ''Only Admin lists accounts.'', 1;
  SELECT (SELECT p.id,p.display_name,p.active,a.username,a.version,a.must_change_password,
    JSON_QUERY((SELECT role FROM dbo.user_roles WHERE user_id=p.id FOR JSON PATH)) roles
    FROM internal.local_accounts a JOIN dbo.profiles p ON p.id=a.user_id ORDER BY a.username FOR JSON PATH);
END;';
  SET @etape_deploiement=N'005_application_accounts.sql, lot 12';
  EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.account_update @ActorId uniqueidentifier,@UserId uniqueidentifier,@ExpectedVersion int,@Active bit,@Roles nvarchar(max) AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  IF api.can_do(@ActorId,N''admin'')=0 THROW 51003, ''Only Admin manages accounts.'', 1;
  -- Reuse role validation with valid non-credential placeholder values; no password changes here.
  DECLARE @placeholder nvarchar(512)=REPLICATE(N''x'',40);
  EXEC internal.validate_account N''validation'',@placeholder,@Roles;
  IF @Active IS NULL THROW 51004, ''Active flag required.'', 1;
  BEGIN TRY
    BEGIN TRANSACTION;
    EXEC internal.account_admin_lock;
    IF api.can_do(@ActorId,N''admin'')=0 THROW 51003, ''Only Admin manages accounts.'', 1;
    IF NOT EXISTS(SELECT 1 FROM internal.local_accounts WITH(UPDLOCK,HOLDLOCK) WHERE user_id=@UserId AND version=@ExpectedVersion)
      THROW 51009, ''Account changed; refresh required.'', 1;
    UPDATE dbo.profiles SET active=@Active WHERE id=@UserId;
    DELETE dbo.user_roles WHERE user_id=@UserId;
    INSERT dbo.user_roles(user_id,role) SELECT @UserId,value FROM OPENJSON(@Roles);
    IF NOT EXISTS(SELECT 1 FROM internal.local_accounts a JOIN dbo.profiles p ON p.id=a.user_id
      JOIN dbo.user_roles r ON r.user_id=p.id WHERE p.active=1 AND r.role=N''admin'') THROW 51004, ''Keep at least one active Admin account.'', 1;
    UPDATE internal.local_accounts SET version=version+1 WHERE user_id=@UserId;
    DELETE internal.application_sessions WHERE user_id=@UserId;
    INSERT dbo.audit_logs(entity,entity_id,action,actor_id,after_data) VALUES(N''account'',CONVERT(nvarchar(36),@UserId),N''MODIFICATION'',@ActorId,
      (SELECT @Active active,JSON_QUERY(@Roles) roles FOR JSON PATH,WITHOUT_ARRAY_WRAPPER));
    COMMIT;
    SELECT (SELECT @UserId id,@ExpectedVersion+1 version FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
  END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;';
  SET @etape_deploiement=N'005_application_accounts.sql, lot 13';
  EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.account_reset_password @ActorId uniqueidentifier,@UserId uniqueidentifier,@ExpectedVersion int,@PasswordHash nvarchar(512) AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  IF api.can_do(@ActorId,N''admin'')=0 THROW 51003, ''Only Admin resets passwords.'', 1;
  IF @ActorId=@UserId THROW 51004, ''Use authenticated password change for your own account.'', 1;
  BEGIN TRY
    BEGIN TRANSACTION;
    EXEC internal.account_admin_lock;
    IF api.can_do(@ActorId,N''admin'')=0 THROW 51003, ''Only Admin resets passwords.'', 1;
    UPDATE internal.local_accounts SET password_hash=@PasswordHash,must_change_password=1,version=version+1,failed_attempts=0,locked_until=NULL
      WHERE user_id=@UserId AND version=@ExpectedVersion;
    IF @@ROWCOUNT<>1 THROW 51009, ''Account changed; refresh required.'', 1;
    DELETE internal.application_sessions WHERE user_id=@UserId;
    INSERT dbo.audit_logs(entity,entity_id,action,actor_id) VALUES(N''account'',CONVERT(nvarchar(36),@UserId),N''PASSWORD_RESET'',@ActorId);
    COMMIT;
    SELECT (SELECT @UserId id,@ExpectedVersion+1 version,CAST(1 AS bit) must_change_password FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
  END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;';
  SET @etape_deploiement=N'005_application_accounts.sql, lot 14';
  EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE internal.bootstrap_admin @Username nvarchar(100),@DisplayName nvarchar(200),@PasswordHash nvarchar(512),@ExistingProfileId uniqueidentifier=NULL AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  EXEC internal.validate_account @Username,@PasswordHash,N''["admin"]'';
  IF @DisplayName IS NULL OR LEN(TRIM(@DisplayName))=0 THROW 51004, ''Display name required.'', 1;
  BEGIN TRY
    BEGIN TRANSACTION;
    EXEC internal.account_admin_lock;
    IF EXISTS(SELECT 1 FROM internal.local_accounts) THROW 51004, ''Bootstrap only permits the first account.'', 1;
    DECLARE @user uniqueidentifier=COALESCE(@ExistingProfileId,NEWID());
    IF @ExistingProfileId IS NULL INSERT dbo.profiles(id,display_name) VALUES(@user,TRIM(@DisplayName));
    ELSE IF NOT EXISTS(SELECT 1 FROM dbo.profiles WHERE id=@user) THROW 51002, ''Historical profile not found.'', 1;
    INSERT internal.local_accounts(user_id,username,password_hash) VALUES(@user,@Username,@PasswordHash);
    IF NOT EXISTS(SELECT 1 FROM dbo.user_roles WHERE user_id=@user AND role=N''admin'') INSERT dbo.user_roles(user_id,role) VALUES(@user,N''admin'');
    UPDATE dbo.profiles SET active=1 WHERE id=@user;
    INSERT dbo.audit_logs(entity,entity_id,action,actor_id) VALUES(N''account'',CONVERT(nvarchar(36),@user),N''BOOTSTRAP'',@user);
    COMMIT; SELECT @user;
  END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;';
  SET @etape_deploiement=N'005_application_accounts.sql, lot 15';
  EXEC sys.sp_executesql N'-- pointage_api has EXECUTE on api from 002; internal.bootstrap_admin remains DBA-only.
INSERT internal.schema_versions(version) VALUES(3);
-- Commit managed by the outer deployment batch.';
  IF @@TRANCOUNT<>1 THROW 51100, 'Compteur de transaction inattendu.', 1;
  SET @etape_deploiement=N'Verifications finales';
  EXEC sys.sp_executesql N'-- Lecture seule, utilisable apres initialisation. Ne charge aucune donnee fictive.
SET NOCOUNT ON;
IF DB_NAME()<>N''toszps_Test'' THROW 51100, ''Selectionner toszps.'', 1;
IF OBJECT_ID(N''internal.schema_versions'',N''U'') IS NULL
 THROW 51100, ''Socle non initialise.'', 1;
IF (SELECT COUNT(*) FROM internal.schema_versions WHERE version IN (1,2,3))<>3
 THROW 51100, ''Versions 1, 2 et 3 attendues.'', 1;
IF OBJECT_ID(N''api.user_context'',N''P'') IS NULL OR OBJECT_ID(N''internal.bootstrap_admin'',N''P'') IS NULL
 THROW 51100, ''Procedures du socle manquantes.'', 1;
IF DATABASE_PRINCIPAL_ID(N''pointage_api'') IS NULL
 THROW 51100, ''Role pointage_api absent.'', 1;
SELECT version,applied_at FROM internal.schema_versions ORDER BY version;
SELECT s.name AS schema_nom,COUNT(*) AS nombre_tables FROM sys.tables t
 JOIN sys.schemas s ON s.schema_id=t.schema_id WHERE t.is_ms_shipped=0 GROUP BY s.name;
SELECT N''SOCLE INITIAL UNIQUEMENT : application encore reliee a Supabase'' AS resultat;
';
  COMMIT TRANSACTION;
  SELECT N'SOCLE INITIAL CREE ET VALIDE : application encore sur Supabase' AS resultat_final;
END TRY
BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  DECLARE @erreur_deploiement nvarchar(2048)=CONCAT(N'Etape : ',@etape_deploiement,N' ; SQL ',ERROR_NUMBER(),N' ; procedure : ',COALESCE(ERROR_PROCEDURE(),N'(lot)'),N' ; ligne : ',ERROR_LINE(),N' ; ',ERROR_MESSAGE());
  THROW 51101, @erreur_deploiement, 1;
END CATCH;
