-- DBeaver : toszps, nouvelle session auto-commit, Ctrl+A puis Ctrl+Entree.
-- Version5 ->6 : API application et registre PRIVE des visites historiques. Aucun import ni lancement.
SET NOCOUNT ON;SET XACT_ABORT ON;
IF @@TRANCOUNT<>0 OR (@@OPTIONS & 2)<>0 THROW 51100, 'Nouvelle session auto-commit requise.', 1;
DECLARE @phase nvarchar(200)=N'Controle de cible';
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
IF DB_NAME()<>N''toszps'' THROW 51100, ''Selectionner la base toszps dans SSMS.'', 1;
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
 IF IS_ROLEMEMBER(N'db_owner')<>1 AND IS_SRVROLEMEMBER(N'sysadmin')<>1 THROW 51100, 'Compte de deploiement requis.', 1;
 IF (SELECT COUNT(*) FROM internal.schema_versions WHERE version IN(1,2,3,4,5))<>5 OR (SELECT MAX(version) FROM internal.schema_versions)<>5 THROW 51100, 'Versions1..5 attendues ; ne pas rejouer.', 1;
 IF EXISTS(SELECT 1 FROM dbo.truck_visits) OR EXISTS(SELECT 1 FROM internal.local_accounts) THROW 51100, 'Mettre a jour API6 AVANT le transfert final et le premier compte local. Des donnees existent : verifier la sequence.', 1;
 SET @phase=N'Sauvegarde avant API6';
 DECLARE @folder nvarchar(4000)=CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultBackupPath'));
 IF @folder IS NULL OR LEN(TRIM(@folder))=0 THROW 51100, 'Repertoire de sauvegarde SQL inconnu.', 1;
 DECLARE @backup nvarchar(4000)=@folder+CASE WHEN RIGHT(@folder,1) IN(N'\',N'/') THEN N'' ELSE N'\' END+N'toszps_avant_api6_'+CONVERT(nvarchar(36),NEWID())+N'.bak';
 BACKUP DATABASE [toszps] TO DISK=@backup WITH COPY_ONLY,CHECKSUM,NOINIT,STATS=10;
 SELECT @backup sauvegarde_sur_serveur_SQL;
 BEGIN TRANSACTION;
 SET @phase=N'012_application_api.sql / lot1';
 EXEC sys.sp_executesql N'-- Application reads, reference maintenance and integration reads. Upgrade 5 -> 6.
-- Run with 013 in a single deployment transaction. No business rows are imported here.
SET NOCOUNT ON;SET XACT_ABORT ON;
IF @@TRANCOUNT=0 OR (SELECT MAX(version) FROM internal.schema_versions)<>5
 OR (SELECT COUNT(*) FROM internal.schema_versions WHERE version IN(1,2,3,4,5))<>5
 THROW 51000, ''Transactional upgrade from exactly schema5 required.'', 1;
-- Only the offline importer may register inherited, already-open visits. New entries always require order items.
CREATE TABLE internal.legacy_imported_visits(
 visit_id uniqueidentifier NOT NULL PRIMARY KEY REFERENCES dbo.truck_visits(id),
 source_snapshot_sha256 char(64) COLLATE Latin1_General_100_BIN2 NOT NULL,
 registered_at datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00'')
);
CREATE TABLE internal.gate_entry_requests(
 actor_id uniqueidentifier NOT NULL REFERENCES dbo.profiles(id),request_id uniqueidentifier NOT NULL,
 payload_hash binary(32) NOT NULL,visit_id uniqueidentifier NOT NULL REFERENCES dbo.truck_visits(id),
 response_json nvarchar(max) NOT NULL CHECK(ISJSON(response_json,OBJECT)=1),
 created_at datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00''),
 PRIMARY KEY(actor_id,request_id)
);';
 SET @phase=N'012_application_api.sql / lot2';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.readiness AS
BEGIN
 SET NOCOUNT ON;
 IF (SELECT MAX(version) FROM internal.schema_versions)<>6 THROW 51004, ''Application schema6 required.'', 1;
 IF EXISTS(SELECT 1 FROM dbo.truck_visits v WHERE order_controlled=0 AND exited_at IS NULL AND canceled_at IS NULL
  AND NOT EXISTS(SELECT 1 FROM internal.legacy_imported_visits l WHERE l.visit_id=v.id)) THROW 51004, ''Unregistered inherited visits: verify the import provenance.'', 1;
 IF NOT EXISTS(SELECT 1 FROM internal.local_accounts a JOIN dbo.profiles p ON p.id=a.user_id JOIN dbo.user_roles r ON r.user_id=p.id WHERE p.active=1 AND r.role=N''admin'') THROW 51004, ''Provision the first local Admin after import.'', 1;
 SELECT N''{"ready":true,"backend":"sqlserver","schema_version":6}'';
END;';
 SET @phase=N'012_application_api.sql / lot3';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.runtime_metadata AS
BEGIN
 SET NOCOUNT ON;
 SELECT DB_NAME(),CONVERT(nvarchar(128),SERVERPROPERTY(''MachineName'')),CONVERT(nvarchar(128),SERVERPROPERTY(''InstanceName'')),(SELECT MAX(version) FROM internal.schema_versions);
END;';
 SET @phase=N'012_application_api.sql / lot4';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.runtime_integration_actor AS
BEGIN
 SET NOCOUNT ON;
 SELECT TOP(1) CONVERT(nvarchar(36),a.user_id) FROM internal.local_accounts a JOIN dbo.profiles p ON p.id=a.user_id
  JOIN dbo.user_roles r ON r.user_id=p.id WHERE p.active=1 AND r.role=N''admin'' ORDER BY a.created_at,a.user_id;
END;';
 SET @phase=N'012_application_api.sql / lot5';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.app_read @ActorId uniqueidentifier,@Operation nvarchar(40),@Id uniqueidentifier=NULL,
 @Text nvarchar(150)=NULL,@Day date=NULL,@Limit int=500,@AnyTime bit=0,@From datetimeoffset(6)=NULL,@To datetimeoffset(6)=NULL AS
BEGIN
 SET NOCOUNT ON;
 IF api.can_do(@ActorId,N''read'')=0 THROW 51003, ''Read denied.'', 1;
 IF @Operation IN(N''profiles'',N''audit'',N''hourly'',N''dashboard'',N''forced'',N''report-snapshot'') AND api.can_do(@ActorId,N''admin'')=0
  THROW 51003, ''Admin required.'', 1;
 IF @Limit IS NULL OR @Limit NOT BETWEEN 1 AND 1000 THROW 51004, ''Invalid read limit.'', 1;
 SET @Day=COALESCE(@Day,CONVERT(date,SYSUTCDATETIME() AT TIME ZONE ''UTC'' AT TIME ZONE ''Morocco Standard Time''));
 DECLARE @start datetimeoffset(6)=CONVERT(datetime2,@Day) AT TIME ZONE ''Morocco Standard Time'',
  @finish datetimeoffset(6)=CONVERT(datetime2,DATEADD(day,1,@Day)) AT TIME ZONE ''Morocco Standard Time'';
 IF @Operation=N''clients'' BEGIN SELECT (SELECT id,code,name,active FROM dbo.clients ORDER BY name,id FOR JSON PATH);RETURN;END;
 IF @Operation=N''operators'' BEGIN SELECT (SELECT id,name,active,bic FROM dbo.armateurs ORDER BY name,id FOR JSON PATH);RETURN;END;
 IF @Operation=N''container'' BEGIN SELECT (SELECT number,iso_code,armateur_id FROM dbo.containers WHERE number=@Text FOR JSON PATH);RETURN;END;
 IF @Operation=N''profiles'' BEGIN
  SELECT (SELECT p.id,p.display_name,p.first_name,p.last_name,p.active,p.avatar_url,p.created_at,
   COALESCE(a.username,p.username) username,CONVERT(bit,CASE WHEN a.user_id IS NOT NULL THEN 1 ELSE 0 END) account_linked,
   a.version,JSON_QUERY((SELECT role FROM dbo.user_roles r WHERE r.user_id=p.id FOR JSON PATH)) user_roles
   FROM dbo.profiles p LEFT JOIN internal.local_accounts a ON a.user_id=p.id ORDER BY p.created_at DESC,p.id FOR JSON PATH);RETURN;
 END;
 IF @Operation=N''audit'' BEGIN SELECT (SELECT TOP(100) entity,entity_id,action,actor_id,occurred_at,reason FROM dbo.audit_logs ORDER BY occurred_at DESC,id DESC FOR JSON PATH);RETURN;END;
 IF @Operation=N''forced'' BEGIN SELECT (SELECT TOP(1000) id,visit_id,container_number,action,reason,actor_id,occurred_at,resolved_at,external_reference FROM dbo.forced_container_actions WHERE resolved_at IS NULL ORDER BY occurred_at,id FOR JSON PATH);RETURN;END;
 IF @Operation=N''visits'' BEGIN
  SELECT (SELECT TOP(@Limit) v.*,JSON_QUERY(v.operational_details) operational_fields,
   JSON_QUERY((SELECT COALESCE(v.carrier_booking_reference,b.reference) reference FOR JSON PATH,WITHOUT_ARRAY_WRAPPER)) bookings
   FROM dbo.truck_visits v LEFT JOIN dbo.bookings b ON b.id=v.booking_id
   WHERE (@Id IS NULL OR v.id=@Id) AND (@Text IS NULL OR v.plate=@Text) ORDER BY v.entered_at DESC,v.id DESC FOR JSON PATH);RETURN;
 END;
 IF @Operation=N''transactions'' BEGIN
  SELECT (SELECT TOP(500) v.*,JSON_QUERY(v.operational_details) operational_fields,CONVERT(nvarchar(20),entry.id) transaction_number,c.name client_name,
   COALESCE(NULLIF(creator.display_name,N''''),CONVERT(nvarchar(36),v.entered_by)) creator_name,
   COALESCE(NULLIF(changer.display_name,N''''),CONVERT(nvarchar(36),COALESCE(last_change.actor_id,v.entered_by))) changer_name,
   COALESCE(last_change.occurred_at,v.entered_at) changed_at,
   JSON_QUERY((SELECT COALESCE(v.carrier_booking_reference,b.reference) reference FOR JSON PATH,WITHOUT_ARRAY_WRAPPER)) bookings
   FROM dbo.truck_visits v LEFT JOIN dbo.bookings b ON b.id=v.booking_id LEFT JOIN dbo.clients c ON c.id=v.client_id
   LEFT JOIN dbo.profiles creator ON creator.id=v.entered_by
   OUTER APPLY(SELECT TOP(1) id FROM dbo.visit_events e WHERE e.visit_id=v.id AND e.action=N''ENTREE'' ORDER BY e.occurred_at,e.id) entry
   OUTER APPLY(SELECT TOP(1) actor_id,occurred_at FROM dbo.audit_logs a WHERE a.entity=N''truck_visit'' AND a.entity_id=CONVERT(nvarchar(36),v.id) ORDER BY a.occurred_at DESC,a.id DESC) last_change
   LEFT JOIN dbo.profiles changer ON changer.id=COALESCE(last_change.actor_id,v.entered_by) ORDER BY v.entered_at DESC,v.id DESC FOR JSON PATH);RETURN;
 END;
 IF @Operation=N''documents'' BEGIN
  SELECT (SELECT TOP(@Limit) id,visit_id,CONVERT(nvarchar(20),event_id) event_id,kind,status,storage_path,created_at,JSON_QUERY(snapshot) snapshot
   FROM dbo.generated_documents WHERE (@Id IS NULL OR visit_id=@Id) AND (@Text IS NULL OR kind=@Text) ORDER BY created_at DESC,event_id DESC,id DESC FOR JSON PATH);RETURN;
 END;
 IF @Operation=N''document-context'' BEGIN
  IF @Id IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.generated_documents WHERE id=@Id) THROW 51002, ''Document not found.'', 1;
  SELECT (SELECT COALESCE(JSON_VALUE(d.snapshot,''$.agent_name''),p.display_name,CONVERT(nvarchar(36),d.created_by)) agent_name,
   CONVERT(nvarchar(19),d.created_at AT TIME ZONE ''Morocco Standard Time'',120) created_at_local,
   CONVERT(nvarchar(20),e.id) visit_number,CONVERT(nvarchar(20),d.event_id) authorization_number
   FROM dbo.generated_documents d LEFT JOIN dbo.profiles p ON p.id=d.created_by
   OUTER APPLY(SELECT TOP(1) id FROM dbo.visit_events e WHERE e.visit_id=d.visit_id AND e.action=N''ENTREE'' ORDER BY occurred_at,id) e
   WHERE d.id=@Id FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);RETURN;
 END;
 IF @Operation=N''hourly'' BEGIN
  ;WITH hours(h) AS(SELECT * FROM(VALUES(0),(1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12),(13),(14),(15),(16),(17),(18),(19),(20),(21),(22),(23))v(h)),
  stages(stage) AS(SELECT * FROM(VALUES(N''ENTREE''),(N''ENGIN''),(N''SORTIE''))v(stage)),
  counted AS(SELECT CASE WHEN action IN(N''DEPOSE'',N''PRISE'') THEN N''ENGIN'' ELSE action END COLLATE Latin1_General_100_BIN2 stage,
   DATEPART(hour,occurred_at AT TIME ZONE ''Morocco Standard Time'') h,COUNT(*) total FROM dbo.visit_events
   WHERE occurred_at>=@start AND occurred_at<@finish AND action IN(N''ENTREE'',N''DEPOSE'',N''PRISE'',N''SORTIE'')
   GROUP BY CASE WHEN action IN(N''DEPOSE'',N''PRISE'') THEN N''ENGIN'' ELSE action END,DATEPART(hour,occurred_at AT TIME ZONE ''Morocco Standard Time''))
  SELECT (SELECT s.stage,h.h hour,COALESCE(c.total,0) total FROM stages s CROSS JOIN hours h LEFT JOIN counted c ON c.stage=s.stage COLLATE Latin1_General_100_BIN2 AND c.h=h.h ORDER BY s.stage,h.h FOR JSON PATH);RETURN;
 END;
 IF @Operation=N''dashboard'' BEGIN
  SELECT (SELECT @Day day,
   (SELECT COUNT(*) FROM dbo.truck_visits WHERE entered_at>=@start AND entered_at<@finish) entries_today,
   (SELECT COUNT(*) FROM dbo.truck_visits WHERE exited_at>=@start AND exited_at<@finish AND canceled_at IS NULL) exits_today,
   (SELECT COUNT(*) FROM dbo.truck_visits WHERE exited_at IS NULL AND canceled_at IS NULL) trucks_in_yard,
   (SELECT COUNT(*) FROM dbo.container_stock_intervals WHERE departed_at IS NULL) containers_in_stock,
   (SELECT COUNT(*) FROM internal.local_accounts a JOIN dbo.profiles p ON p.id=a.user_id WHERE p.active=1) agents_count,
   JSON_QUERY((SELECT TOP(100) id,plate truck_plate,container_number,container_number_2,entered_at,exited_at,canceled_at,
    CASE WHEN canceled_at IS NOT NULL THEN N''ANNULE'' WHEN exited_at IS NOT NULL THEN N''SORTI'' ELSE N''AU_PARC'' END status
    FROM dbo.truck_visits ORDER BY entered_at DESC,id DESC FOR JSON PATH)) recent_visits FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);RETURN;
 END;
 IF @Operation=N''freepool'' BEGIN
  IF (SELECT COUNT_BIG(*) FROM dbo.container_stock_intervals WHERE arrived_at<@finish AND (departed_at IS NULL OR departed_at>=CASE WHEN @AnyTime=1 THEN @start ELSE @finish END) AND (@Id IS NULL OR client_id=@Id))>100000 THROW 51004, ''Report exceeds row limit.'', 1;
  SELECT (SELECT s.container_number,s.client_id,s.armateur_id,s.iso_code,t.category,s.arrived_at,s.departed_at,s.position,r.factor evp
   FROM dbo.container_stock_intervals s
   OUTER APPLY(SELECT TOP(1) category,size_feet FROM dbo.iso_report_types t WHERE t.iso_code=s.iso_code AND effective_from<=@Day ORDER BY effective_from DESC)t
   OUTER APPLY(SELECT TOP(1) factor FROM dbo.evp_rules r WHERE r.size_feet=t.size_feet AND effective_from<=@Day ORDER BY effective_from DESC)r
   WHERE s.arrived_at<@finish AND (s.departed_at IS NULL OR CASE WHEN @AnyTime=1 AND s.departed_at>@start THEN 1 WHEN @AnyTime=0 AND s.departed_at>=@finish THEN 1 ELSE 0 END=1)
    AND (@Id IS NULL OR s.client_id=@Id) ORDER BY t.category,s.armateur_id,s.container_number FOR JSON PATH);RETURN;
 END;
 IF @Operation=N''report-snapshot'' BEGIN
  IF @From IS NULL OR @To IS NULL OR @To<=@From OR @To>DATEADD(day,32,@From) THROW 51004, ''Invalid report window.'', 1;
  IF (SELECT COUNT_BIG(*) FROM dbo.generated_documents WHERE kind IN(N''ENTREE'',N''SORTIE'') AND created_at>=@From AND created_at<@To)>100000
   OR (SELECT COUNT_BIG(*) FROM dbo.container_stock_intervals WHERE arrived_at<@To AND (departed_at IS NULL OR departed_at>=@To))>100000 THROW 51004, ''Report exceeds row limit.'', 1;
  SELECT (SELECT JSON_QUERY((SELECT id,name,active FROM dbo.clients ORDER BY id FOR JSON PATH)) clients,
   JSON_QUERY((SELECT id,kind,created_at,JSON_QUERY(snapshot) snapshot FROM dbo.generated_documents WHERE kind IN(N''ENTREE'',N''SORTIE'') AND created_at>=@From AND created_at<@To ORDER BY id FOR JSON PATH)) documents,
   JSON_QUERY((SELECT id,container_number,client_id,armateur_id,iso_code,arrived_at,departed_at,position FROM dbo.container_stock_intervals WHERE arrived_at<@To AND (departed_at IS NULL OR departed_at>=@To) ORDER BY id FOR JSON PATH)) stock,
   JSON_QUERY((SELECT iso_code,effective_from,category,size_feet FROM dbo.iso_report_types ORDER BY iso_code,effective_from FOR JSON PATH)) isoRules,
   JSON_QUERY((SELECT size_feet,effective_from,factor FROM dbo.evp_rules ORDER BY size_feet,effective_from FOR JSON PATH)) evpRules FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);RETURN;
 END;
 IF @Operation=N''codeco'' BEGIN
  IF @From IS NULL OR @To IS NULL OR @To<=@From OR @To>DATEADD(day,31,@From) THROW 51004, ''Invalid CODECO window.'', 1;
  SELECT (SELECT TOP(10001) CONVERT(nvarchar(20),e.id) event_id,e.action,e.occurred_at,JSON_QUERY(d.snapshot) snapshot,JSON_QUERY(N''{}'') metadata
   FROM dbo.visit_events e JOIN dbo.generated_documents d ON d.event_id=e.id AND d.kind=e.action
   WHERE e.occurred_at>=@From AND e.occurred_at<@To AND ((e.action=N''ENTREE'' AND JSON_VALUE(d.snapshot,''$.entry_kind'')=N''loaded'') OR (e.action=N''SORTIE'' AND JSON_VALUE(d.snapshot,''$.entry_kind'')=N''empty''))
    AND (JSON_VALUE(d.snapshot,''$.armateur_id'')=N''MSC'' OR (JSON_VALUE(d.snapshot,''$.is_twin'')=N''true'' AND JSON_VALUE(d.snapshot,''$.armateur_id_2'')=N''MSC''))
   ORDER BY e.occurred_at,e.id,d.id FOR JSON PATH);RETURN;
 END;
 THROW 51004, ''Unknown read operation.'', 1;
END;';
 SET @phase=N'012_application_api.sql / lot6';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.app_write @ActorId uniqueidentifier,@Operation nvarchar(40),@Payload nvarchar(max) AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF ISJSON(@Payload,OBJECT)<>1 THROW 51004, ''JSON object required.'', 1;
 IF api.can_do(@ActorId,CASE WHEN @Operation=N''document-action'' THEN N''read'' ELSE N''admin'' END)=0 THROW 51003, ''Operation denied.'', 1;
 DECLARE @id uniqueidentifier=TRY_CONVERT(uniqueidentifier,JSON_VALUE(@Payload,''$.id'')),
  @number nvarchar(64)=UPPER(TRIM(JSON_VALUE(@Payload,''$.number''))),@iso nvarchar(64)=UPPER(TRIM(JSON_VALUE(@Payload,''$.iso''))),
  @line nvarchar(64)=JSON_VALUE(@Payload,''$.armateur''),@code nvarchar(max)=TRIM(JSON_VALUE(@Payload,''$.code'')),
  @name nvarchar(max)=TRIM(JSON_VALUE(@Payload,''$.name'')),@before nvarchar(max),@after nvarchar(max),@now datetimeoffset(6)=TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00'');
 BEGIN TRY
  BEGIN TRANSACTION;
  IF @Operation=N''document-action'' BEGIN
   DECLARE @action nvarchar(64)=JSON_VALUE(@Payload,''$.action'');
   IF @id IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.generated_documents WHERE id=@id) OR @action IS NULL OR @action NOT IN(N''PREVIEW_REQUESTED'',N''SHARE_REQUESTED'',N''PRINT_DIALOG_REQUESTED'',N''DIRECT_PRINT_REQUESTED'') THROW 51004, ''Invalid document action.'', 1;
   INSERT dbo.document_actions(document_id,actor_id,action) VALUES(@id,@ActorId,@action);
  END ELSE BEGIN
   EXEC internal.account_admin_lock;
   IF api.can_do(@ActorId,N''admin'')=0 THROW 51003, ''Admin required.'', 1;
   IF @Operation=N''client'' BEGIN
    IF @code IS NULL OR LEN(@code) NOT BETWEEN 1 AND 150 OR @name IS NULL OR LEN(@name) NOT BETWEEN 1 AND 200 THROW 51004, ''Client code and name required.'', 1;
    SET @id=NEWID();INSERT dbo.clients(id,code,name) VALUES(@id,@code,@name);
   END ELSE IF @Operation=N''assignment'' BEGIN
    SET @id=TRY_CONVERT(uniqueidentifier,JSON_VALUE(@Payload,''$.client''));
    DECLARE @valid date=TRY_CONVERT(date,JSON_VALUE(@Payload,''$.from''),23);
    IF @id IS NULL OR @line IS NULL OR @valid IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.clients WHERE id=@id AND active=1) OR NOT EXISTS(SELECT 1 FROM dbo.armateurs WHERE id=@line AND active=1) THROW 51004, ''Active client/carrier and valid start date required.'', 1;
    IF EXISTS(SELECT 1 FROM dbo.client_armateurs WITH(UPDLOCK,HOLDLOCK) WHERE armateur_id=@line AND (valid_to IS NULL OR valid_to>=@valid)) THROW 51009, ''Overlapping carrier allocation; reconcile the existing assignment.'', 1;
    INSERT dbo.client_armateurs(client_id,armateur_id,valid_from) VALUES(@id,@line,@valid);
   END ELSE IF @Operation=N''container'' BEGIN
    IF internal.valid_container_number(@number)=0 OR DATALENGTH(@iso)<>8 OR @iso COLLATE Latin1_General_100_BIN2 LIKE N''%[^A-Z0-9]%'' OR @line IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.armateurs WHERE id=@line AND active=1) THROW 51004, ''Valid container/ISO/carrier required.'', 1;
    IF EXISTS(SELECT 1 FROM dbo.containers WITH(UPDLOCK,HOLDLOCK) WHERE number=@number) THROW 51009, ''Container already exists.'', 1;
    INSERT dbo.containers(number,iso_code,armateur_id,source) VALUES(@number,@iso,@line,N''manual'');
   END ELSE IF @Operation=N''profile'' BEGIN
    DECLARE @first nvarchar(max)=TRIM(JSON_VALUE(@Payload,''$.first_name'')),@last nvarchar(max)=TRIM(JSON_VALUE(@Payload,''$.last_name'')),
     @expected int=TRY_CONVERT(int,JSON_VALUE(@Payload,''$.expected_version''));
    IF @id IS NULL OR @first IS NULL OR @last IS NULL OR LEN(@first) NOT BETWEEN 1 AND 100 OR LEN(@last) NOT BETWEEN 1 AND 100 OR @expected IS NULL OR @expected<1 THROW 51004, ''Profile names/version required.'', 1;
    IF NOT EXISTS(SELECT 1 FROM internal.local_accounts WITH(UPDLOCK,HOLDLOCK) WHERE user_id=@id AND version=@expected) THROW 51009, ''Account changed. Refresh.'', 1;
    SET @before=(SELECT id,display_name,first_name,last_name FROM dbo.profiles WHERE id=@id FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
    UPDATE dbo.profiles SET first_name=@first,last_name=@last,display_name=CONCAT(@first,N'' '',@last) WHERE id=@id;
    IF EXISTS(SELECT 1 FROM OPENJSON(@Payload) WHERE [key]=N''avatar_url'') UPDATE dbo.profiles SET avatar_url=NULLIF(JSON_VALUE(@Payload,''$.avatar_url''),N'''') WHERE id=@id;
    UPDATE internal.local_accounts SET version=version+1 WHERE user_id=@id;
    DELETE internal.application_sessions WHERE user_id=@id;
   END ELSE IF @Operation=N''reconcile'' BEGIN
    DECLARE @reference nvarchar(max)=TRIM(JSON_VALUE(@Payload,''$.external_reference''));
    IF @id IS NULL OR @reference IS NULL OR LEN(@reference) NOT BETWEEN 3 AND 150 THROW 51004, ''Reconciliation reference required.'', 1;
    IF NOT EXISTS(SELECT 1 FROM dbo.forced_container_actions WITH(UPDLOCK,HOLDLOCK) WHERE id=@id AND resolved_at IS NULL) THROW 51009, ''Unresolved action not found.'', 1;
    UPDATE dbo.forced_container_actions SET resolved_at=@now,resolved_by=@ActorId,external_reference=@reference WHERE id=@id;
   END ELSE THROW 51004, ''Unknown maintenance operation.'', 1;
   INSERT dbo.audit_logs(entity,entity_id,action,actor_id,occurred_at,before_data)
    VALUES(N''application'',COALESCE(CONVERT(nvarchar(36),@id),@number),UPPER(@Operation),@ActorId,@now,@before);
  END;
  COMMIT;SELECT N''{"ok":true}'';
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK;THROW;END CATCH;
END;';
 SET @phase=N'014_inherited_visit_lifecycle.sql / lot1';
 EXEC sys.sp_executesql N'-- Generated from009. Only explicitly registered inherited IDs bypass NEW order allocation.
-- All stock/ISO/hold/24h/role/version checks remain in the same lifecycle transaction.
CREATE OR ALTER PROCEDURE api.move_visit @ActorId uniqueidentifier,@VisitId uniqueidentifier,@ExpectedVersion int,
 @Mode nvarchar(16),@Container nvarchar(64)=NULL,@Container2 nvarchar(64)=NULL,
 @Position nvarchar(max)=NULL,@Position2 nvarchar(max)=NULL,@Reason nvarchar(max)=NULL,@Details nvarchar(max)=N''{}'' AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF @Mode IS NULL OR @Mode NOT IN(N''YARD'',N''EXIT'',N''EMPTY_EXIT'',N''CANCEL'') OR @ExpectedVersion IS NULL OR @ExpectedVersion<1 THROW 51004, ''Invalid lifecycle request.'', 1;
 IF (@Mode=N''CANCEL'' AND api.can_do(@ActorId,N''admin'')=0)
  OR (@Mode IN(N''EXIT'',N''EMPTY_EXIT'') AND api.can_do(@ActorId,N''sortie'')=0)
  OR (@Mode=N''YARD'' AND api.can_do(@ActorId,N''engin'')=0 AND api.can_do(@ActorId,N''sortie'')=0) THROW 51003, ''Lifecycle permission denied.'', 1;
 EXEC internal.validate_operational_details @Details;
 SET @Container=NULLIF(UPPER(TRIM(@Container)),N'''');SET @Container2=NULLIF(UPPER(TRIM(@Container2)),N'''');
 SET @Position=NULLIF(TRIM(@Position),N'''');SET @Position2=NULLIF(TRIM(@Position2),N'''');SET @Reason=TRIM(@Reason);
 IF DATALENGTH(@Position)>2000 OR DATALENGTH(@Position2)>2000 THROW 51004, ''Position too long.'', 1;
 IF @Mode=N''CANCEL'' AND (@Reason IS NULL OR LEN(@Reason)<3 OR DATALENGTH(@Reason)>2000) THROW 51004, ''Cancellation reason required.'', 1;
 BEGIN TRY
  BEGIN TRANSACTION;EXEC internal.gate_lock @VisitId=@VisitId;
  IF (@Mode=N''CANCEL'' AND api.can_do(@ActorId,N''admin'')=0)
   OR (@Mode IN(N''EXIT'',N''EMPTY_EXIT'') AND api.can_do(@ActorId,N''sortie'')=0)
   OR (@Mode=N''YARD'' AND api.can_do(@ActorId,N''engin'')=0 AND api.can_do(@ActorId,N''sortie'')=0) THROW 51003, ''Lifecycle permission denied.'', 1;
  DECLARE @kind nvarchar(8),@version int,@twin bit,@engin datetimeoffset(6),@closed datetimeoffset(6),@canceled datetimeoffset(6),@controlled bit,
   @before nvarchar(max),@merged nvarchar(max),@now datetimeoffset(6)=TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00'');
  SELECT @kind=entry_kind,@version=version,@twin=is_twin,@engin=engin_at,@closed=exited_at,@canceled=canceled_at,@controlled=order_controlled,@merged=operational_details,
    @before=(SELECT v.* FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER)
    FROM dbo.truck_visits v WITH(UPDLOCK,HOLDLOCK) WHERE id=@VisitId;
  IF @version IS NULL THROW 51002, ''Visit not found.'', 1;
  IF @version<>@ExpectedVersion THROW 51009, ''Visit changed. Refresh.'', 1;
  IF @closed IS NOT NULL OR @canceled IS NOT NULL THROW 51004, ''Visit already closed.'', 1;
  IF @twin=0 AND (@Container2 IS NOT NULL OR @Position2 IS NOT NULL) THROW 51004, ''Second slot was not reserved.'', 1;
  IF @Mode IN(N''CANCEL'',N''EMPTY_EXIT'') BEGIN
   IF @engin IS NOT NULL OR (@Mode=N''EMPTY_EXIT'' AND @kind<>N''empty'') THROW 51004, ''Cannot cancel a completed physical movement.'', 1;
   IF @Mode=N''EMPTY_EXIT'' SET @Reason=N''Sortie sans prise de conteneur (ressorti a vide)'';
   UPDATE dbo.truck_visits SET canceled_at=@now,canceled_by=@ActorId,cancel_reason=@Reason,version=version+1 WHERE id=@VisitId;
   DECLARE @cancelDetails nvarchar(max)=(SELECT @Reason AS reason FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
   EXEC internal.record_gate_event @VisitId,N''ANNULATION'',@ActorId,@now,@cancelDetails,@before;
  END ELSE BEGIN
   IF @controlled=0 AND NOT EXISTS(SELECT 1 FROM internal.legacy_imported_visits WHERE visit_id=@VisitId) THROW 51004, ''Unregistered legacy visit; import provenance required.'', 1;
   IF @controlled=1 AND EXISTS(SELECT 1 FROM dbo.truck_visits v CROSS APPLY(VALUES(v.order_item_id,v.iso_code,v.armateur_id),(CASE WHEN v.is_twin=1 THEN v.order_item_id_2 END,v.iso_code_2,v.armateur_id_2)) x(item,iso,line)
    LEFT JOIN dbo.transport_order_items i ON i.id=x.item LEFT JOIN dbo.transport_orders o ON o.id=i.order_id
    WHERE v.id=@VisitId AND (x.item IS NOT NULL OR x.iso IS NOT NULL) AND
     (i.id IS NULL OR o.active=0 OR x.iso IS DISTINCT FROM i.iso_code OR x.line IS DISTINCT FROM i.armateur_id OR o.direction<>CASE WHEN @kind=N''loaded'' THEN N''RESTITUTION'' ELSE N''LIVRAISON'' END))
     THROW 51004, ''Reserved order, carrier or ISO changed.'', 1;
   DECLARE @key nvarchar(100),@value nvarchar(max);
   DECLARE detail_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT [key],value FROM OPENJSON(@Details);
   OPEN detail_cursor;FETCH NEXT FROM detail_cursor INTO @key,@value;
   WHILE @@FETCH_STATUS=0 BEGIN
    SET @merged=JSON_MODIFY(@merged,N''$.''+@key,@value);FETCH NEXT FROM detail_cursor INTO @key,@value;
   END;CLOSE detail_cursor;DEALLOCATE detail_cursor;
   UPDATE dbo.truck_visits SET operational_details=@merged WHERE id=@VisitId;
   DECLARE @slots table(slot int PRIMARY KEY,number nvarchar(64) COLLATE Latin1_General_100_BIN2,
    iso nvarchar(4) COLLATE Latin1_General_100_BIN2,line nvarchar(64) COLLATE Latin1_General_100_BIN2,position nvarchar(max),stock_id uniqueidentifier);
   INSERT @slots(slot,number,iso,line,position)
    SELECT 1,CASE WHEN @kind=N''empty'' AND @engin IS NULL THEN @Container ELSE container_number END,iso_code,armateur_id,@Position FROM dbo.truck_visits WHERE id=@VisitId;
   IF @twin=1 INSERT @slots(slot,number,iso,line,position)
    SELECT 2,CASE WHEN @kind=N''empty'' AND @engin IS NULL THEN @Container2 ELSE container_number_2 END,iso_code_2,armateur_id_2,@Position2 FROM dbo.truck_visits WHERE id=@VisitId;
   IF EXISTS(SELECT 1 FROM @slots WHERE internal.valid_container_number(number)=0 OR iso IS NULL OR line IS NULL)
    OR EXISTS(SELECT number FROM @slots GROUP BY number HAVING COUNT(*)>1) THROW 51004, ''Distinct valid container numbers required for every reserved slot.'', 1;
   IF @twin=1 AND EXISTS(SELECT 1 FROM @slots WHERE LEFT(iso,1)<>N''2'') THROW 51004, ''Twin requires two 20-foot containers.'', 1;
   -- Once loaded/picked up, callers cannot replace the archived identity at exit.
   IF (@kind=N''loaded'' OR @engin IS NOT NULL) AND
    ((@Container IS NOT NULL AND @Container<>(SELECT number FROM @slots WHERE slot=1)) OR (@Container2 IS NOT NULL AND @Container2<>(SELECT number FROM @slots WHERE slot=2))) THROW 51004, ''Container identity is immutable after movement.'', 1;
   IF @kind=N''empty'' AND EXISTS(SELECT 1 FROM @slots s JOIN dbo.container_blocks b ON b.container_number=s.number WHERE b.blocked=1) THROW 51004, ''Container blocked: delivery prohibited.'', 1;
   IF @engin IS NULL BEGIN
    IF @kind=N''loaded'' BEGIN
     IF EXISTS(SELECT 1 FROM @slots s JOIN dbo.container_stock_intervals c ON c.container_number=s.number WHERE c.departed_at IS NULL) THROW 51004, ''Container already in stock.'', 1;
     INSERT dbo.container_stock_intervals(container_number,client_id,armateur_id,iso_code,start_visit_id,arrived_at,position)
      SELECT s.number,v.client_id,s.line,s.iso,@VisitId,@now,s.position FROM @slots s CROSS JOIN dbo.truck_visits v WHERE v.id=@VisitId;
    END ELSE BEGIN
     UPDATE s SET stock_id=c.id FROM @slots s JOIN dbo.container_stock_intervals c WITH(UPDLOCK,HOLDLOCK)
      ON c.container_number=s.number AND c.departed_at IS NULL
      JOIN dbo.truck_visits received ON received.id=c.start_visit_id
      JOIN dbo.containers registered ON registered.number=c.container_number
      WHERE c.iso_code=s.iso AND c.armateur_id=s.line AND registered.iso_code=s.iso AND registered.armateur_id=s.line
       AND received.entry_kind=N''loaded'' AND received.canceled_at IS NULL AND @now>=DATEADD(hour,24,received.entered_at);
     IF EXISTS(SELECT 1 FROM @slots WHERE stock_id IS NULL) THROW 51004, ''Stock absent, ISO/carrier incompatible or less than 24 hours since truck entry.'', 1;
     UPDATE c SET departed_at=@now,end_visit_id=@VisitId FROM dbo.container_stock_intervals c JOIN @slots s ON s.stock_id=c.id;
     UPDATE dbo.truck_visits SET container_number=(SELECT number FROM @slots WHERE slot=1),container_number_2=(SELECT number FROM @slots WHERE slot=2) WHERE id=@VisitId;
    END;
    INSERT dbo.yard_operations(visit_id,kind,container_number,position,performed_at,performed_by)
     SELECT @VisitId,CASE WHEN @kind=N''loaded'' THEN N''depose'' ELSE N''prise'' END,number,position,@now,@ActorId FROM @slots WHERE slot=1;
    UPDATE dbo.truck_visits SET engin_at=@now,engin_by=@ActorId,version=version+1 WHERE id=@VisitId;
    DECLARE @action nvarchar(64)=CASE WHEN @kind=N''loaded'' THEN N''DEPOSE'' ELSE N''PRISE'' END;
    EXEC internal.record_gate_event @VisitId,@action,@ActorId,@now,N''{}'',@before;
   END ELSE IF @Mode=N''YARD'' THROW 51004, ''Yard operation already performed.'', 1;
   -- A receiving truck is closed only after both stock insertions succeed.
   IF @kind=N''loaded'' OR @Mode=N''EXIT'' BEGIN
    IF @kind=N''loaded'' AND EXISTS(SELECT 1 FROM @slots s WHERE NOT EXISTS(SELECT 1 FROM dbo.container_stock_intervals c WHERE c.container_number=s.number AND c.start_visit_id=@VisitId)) THROW 51004, ''Deposit incomplete.'', 1;
    SELECT @before=(SELECT v.* FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER) FROM dbo.truck_visits v WHERE id=@VisitId;
    UPDATE dbo.truck_visits SET exited_at=@now,exited_by=@ActorId,version=version+1 WHERE id=@VisitId;
    DECLARE @exitDetails nvarchar(max)=CASE WHEN @kind=N''loaded'' THEN N''{"automatic":true,"reason":"Cloture apres restitution","physical_exit_observed":false}'' ELSE N''{}'' END;
    EXEC internal.record_gate_event @VisitId,N''SORTIE'',@ActorId,@now,@exitDetails,@before;
   END;
  END;
  DECLARE @response nvarchar(max)=(SELECT id,version,engin_at,exited_at,canceled_at FROM dbo.truck_visits WHERE id=@VisitId FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER);
  COMMIT;SELECT @response;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK;THROW;END CATCH;
END;';
 SET @phase=N'015_idempotent_gate_entry.sql / lot1';
 EXEC sys.sp_executesql N'-- Generated from008. An identical entry retry replays its original result atomically.
CREATE OR ALTER PROCEDURE api.enter_visit_once @ActorId uniqueidentifier,@RequestId uniqueidentifier,@PayloadHash binary(32),@Plate nvarchar(max),@Cin nvarchar(max),
 @EntryKind nvarchar(8),@OrderItemId uniqueidentifier,@IsTwin bit=0,@OrderItemId2 uniqueidentifier=NULL,
 @Container nvarchar(64)=NULL,@Container2 nvarchar(64)=NULL,@Details nvarchar(max)=N''{}'' AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF api.can_do(@ActorId,N''entree'')=0 THROW 51003, ''Entry role required.'', 1;
 IF @RequestId IS NULL OR @RequestId=''00000000-0000-0000-0000-000000000000'' OR @PayloadHash IS NULL THROW 51004, ''Entry request ID/hash required.'', 1;
 EXEC internal.validate_operational_details @Details;
 SET @Plate=UPPER(TRIM(@Plate));SET @Cin=TRIM(@Cin);
 SET @Container=NULLIF(UPPER(TRIM(@Container)),N'''');SET @Container2=NULLIF(UPPER(TRIM(@Container2)),N'''');
 IF @Plate IS NULL OR LEN(@Plate)<2 OR DATALENGTH(@Plate)>200 OR @Cin IS NULL OR LEN(@Cin)<2 OR DATALENGTH(@Cin)>200
  OR @EntryKind IS NULL OR @EntryKind NOT IN(N''loaded'',N''empty'') OR @OrderItemId IS NULL OR @IsTwin IS NULL
  OR (@IsTwin=1 AND @OrderItemId2 IS NULL) OR (@IsTwin=0 AND (@OrderItemId2 IS NOT NULL OR @Container2 IS NOT NULL))
  THROW 51004, ''Invalid visit fields.'', 1;
 IF @EntryKind=N''loaded'' AND (internal.valid_container_number(@Container)=0 OR (@IsTwin=1 AND (internal.valid_container_number(@Container2)=0 OR @Container=@Container2))) THROW 51004, ''Invalid or duplicate ISO6346 container.'', 1;
 IF @EntryKind=N''empty'' AND (@Container IS NOT NULL OR @Container2 IS NOT NULL) THROW 51004, ''Select pickup containers at yard operation, not entry.'', 1;
 BEGIN TRY
  BEGIN TRANSACTION;EXEC internal.gate_lock @Item1=@OrderItemId,@Item2=@OrderItemId2;
  IF api.can_do(@ActorId,N''entree'')=0 THROW 51003, ''Entry role required.'', 1;
  DECLARE @cached nvarchar(max),@cachedHash binary(32);
  SELECT @cached=response_json,@cachedHash=payload_hash FROM internal.gate_entry_requests WITH(UPDLOCK,HOLDLOCK) WHERE actor_id=@ActorId AND request_id=@RequestId;
  IF @cached IS NOT NULL BEGIN
   IF @cachedHash<>@PayloadHash THROW 51009, ''Request ID reused with different entry data.'', 1;
   COMMIT;SELECT @cached;RETURN;
  END;
  DECLARE @slots table(slot int PRIMARY KEY,item_id uniqueidentifier,number nvarchar(64) COLLATE Latin1_General_100_BIN2,
   iso nvarchar(4) COLLATE Latin1_General_100_BIN2,line nvarchar(64) COLLATE Latin1_General_100_BIN2,
   order_id uniqueidentifier,reference nvarchar(150) COLLATE Latin1_General_100_BIN2,client_id uniqueidentifier,
   client_reference nvarchar(150) COLLATE Latin1_General_100_BIN2,quantity int);
  INSERT @slots(slot,item_id,number) VALUES(1,@OrderItemId,@Container);
  IF @IsTwin=1 INSERT @slots(slot,item_id,number) VALUES(2,@OrderItemId2,@Container2);
  UPDATE s SET iso=i.iso_code,line=i.armateur_id,order_id=o.id,reference=o.reference,client_id=o.client_id,client_reference=o.client_order_reference,quantity=i.quantity
   FROM @slots s JOIN dbo.transport_order_items i ON i.id=s.item_id JOIN dbo.transport_orders o ON o.id=i.order_id
   WHERE o.active=1 AND o.direction=CASE WHEN @EntryKind=N''loaded'' THEN N''RESTITUTION'' ELSE N''LIVRAISON'' END;
  IF EXISTS(SELECT 1 FROM @slots WHERE order_id IS NULL OR (@IsTwin=1 AND LEFT(iso,1)<>N''2'')) THROW 51004, ''Order item inactive, wrong direction or invalid twin size.'', 1;
  IF EXISTS(SELECT 1 FROM @slots a JOIN @slots b ON a.slot=1 AND b.slot=2 WHERE a.client_id IS DISTINCT FROM b.client_id OR a.client_reference IS DISTINCT FROM b.client_reference) THROW 51004, ''Twin items require the same business client/order.'', 1;
  IF EXISTS(SELECT 1 FROM @slots s CROSS APPLY(SELECT COUNT_BIG(*) AS used FROM
    (SELECT id FROM dbo.truck_visits WHERE order_item_id=s.item_id AND canceled_at IS NULL UNION ALL
     SELECT id FROM dbo.truck_visits WHERE order_item_id_2=s.item_id AND canceled_at IS NULL) a) allocations
    WHERE allocations.used+(SELECT COUNT(*) FROM @slots x WHERE x.item_id=s.item_id)>s.quantity) THROW 51004, ''Order quantity exhausted.'', 1;
  IF @EntryKind=N''loaded'' AND (EXISTS(SELECT 1 FROM dbo.container_stock_intervals s JOIN @slots x ON x.number=s.container_number WHERE departed_at IS NULL)
   OR EXISTS(SELECT 1 FROM dbo.truck_visits v JOIN @slots x ON x.number=v.container_number OR x.number=v.container_number_2
     WHERE v.canceled_at IS NULL AND v.exited_at IS NULL AND ((v.entry_kind=N''loaded'' AND v.engin_at IS NULL) OR (v.entry_kind=N''empty'' AND v.engin_at IS NOT NULL)))) THROW 51004, ''Container already in stock or on an active truck.'', 1;
  DECLARE @number nvarchar(64),@iso nvarchar(4),@line nvarchar(64),@booking uniqueidentifier=NULL,@id uniqueidentifier=NEWID(),@now datetimeoffset(6)=TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00'');
  IF @EntryKind=N''loaded'' BEGIN
   DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT number,iso,line FROM @slots ORDER BY number;
   OPEN c;FETCH NEXT FROM c INTO @number,@iso,@line;
   WHILE @@FETCH_STATUS=0 BEGIN
    UPDATE dbo.containers SET iso_code=@iso,armateur_id=@line WHERE number=@number;
    IF @@ROWCOUNT=0 INSERT dbo.containers(number,iso_code,armateur_id,source) VALUES(@number,@iso,@line,N''operator'');
    FETCH NEXT FROM c INTO @number,@iso,@line;
   END;CLOSE c;DEALLOCATE c;
  END ELSE BEGIN
   SET @booking=NEWID();INSERT dbo.bookings(id,reference,armateur_id,iso_code) SELECT @booking,reference,line,iso FROM @slots WHERE slot=1;
  END;
  INSERT dbo.truck_visits(id,plate,driver_cin,entry_kind,container_number,booking_id,iso_code,armateur_id,client_id,entered_at,entered_by,is_twin,
   container_number_2,iso_code_2,armateur_id_2,booking_reference_2,client_order_reference,carrier_booking_reference,carrier_booking_armateur_id,carrier_booking_armateur_id_2,order_item_id,order_item_id_2,order_controlled,operational_details)
   SELECT @id,@Plate,@Cin,@EntryKind,a.number,@booking,a.iso,a.line,a.client_id,@now,@ActorId,@IsTwin,
    b.number,b.iso,b.line,b.reference,a.client_reference,a.reference,a.line,b.line,a.item_id,b.item_id,1,@Details
   FROM @slots a LEFT JOIN @slots b ON b.slot=2 WHERE a.slot=1;
  EXEC internal.record_gate_event @id,N''ENTREE'',@ActorId,@now;
  DECLARE @response nvarchar(max)=(SELECT @id AS id,1 AS version FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
  INSERT internal.gate_entry_requests(actor_id,request_id,payload_hash,visit_id,response_json) VALUES(@ActorId,@RequestId,@PayloadHash,@id,@response);
  COMMIT;SELECT @response;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK;THROW;END CATCH;
END;';
 SET @phase=N'013_forced_pickup_api.sql / lot1';
 EXEC sys.sp_executesql N'-- Complete the application API upgrade in the same transaction as 012.
SET NOCOUNT ON;
IF @@TRANCOUNT=0 THROW 51000, ''Use the transactional application upgrade wrapper.'', 1;';
 SET @phase=N'013_forced_pickup_api.sql / lot2';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.force_pickup @ActorId uniqueidentifier,@VisitId uniqueidentifier,@ExpectedVersion int,@Container nvarchar(64),@Reason nvarchar(max) AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 SET @Container=UPPER(TRIM(@Container));SET @Reason=TRIM(@Reason);
 IF api.can_do(@ActorId,N''admin'')=0 THROW 51003, ''Admin required.'', 1;
 IF internal.valid_container_number(@Container)=0 OR @Reason IS NULL OR LEN(@Reason)<10 OR DATALENGTH(@Reason)>2000 OR @ExpectedVersion IS NULL OR @ExpectedVersion<1 THROW 51004, ''Valid number, detailed reason and version required.'', 1;
 BEGIN TRY
  BEGIN TRANSACTION;EXEC internal.gate_lock @VisitId=@VisitId;
  IF api.can_do(@ActorId,N''admin'')=0 THROW 51003, ''Admin required.'', 1;
  DECLARE @version int,@iso nvarchar(4),@line nvarchar(64),@before nvarchar(max),@now datetimeoffset(6)=TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00''),@id uniqueidentifier=NEWID();
  SELECT @version=version,@iso=iso_code,@line=armateur_id,@before=(SELECT v.* FOR JSON PATH,WITHOUT_ARRAY_WRAPPER)
   FROM dbo.truck_visits v WITH(UPDLOCK,HOLDLOCK) WHERE id=@VisitId AND entry_kind=N''empty'' AND is_twin=0 AND order_controlled=1 AND engin_at IS NULL AND exited_at IS NULL AND canceled_at IS NULL;
  IF @version IS NULL THROW 51004, ''A pending single-container, order-controlled delivery is required.'', 1;
  IF @version<>@ExpectedVersion THROW 51009, ''Visit changed. Refresh.'', 1;
  IF NOT EXISTS(SELECT 1 FROM dbo.truck_visits v JOIN dbo.transport_order_items i ON i.id=v.order_item_id JOIN dbo.transport_orders o ON o.id=i.order_id
   WHERE v.id=@VisitId AND o.active=1 AND o.direction=N''LIVRAISON'' AND i.iso_code=@iso AND i.armateur_id=@line) THROW 51004, ''Reserved order no longer matches.'', 1;
  IF EXISTS(SELECT 1 FROM dbo.container_stock_intervals WHERE container_number=@Container AND departed_at IS NULL) THROW 51004, ''Container is in stock: use normal pickup.'', 1;
  IF EXISTS(SELECT 1 FROM dbo.container_blocks WHERE container_number=@Container AND blocked=1) THROW 51004, ''Container is blocked.'', 1;
  IF EXISTS(SELECT 1 FROM dbo.truck_visits WHERE entry_kind=N''loaded'' AND canceled_at IS NULL AND (container_number=@Container OR container_number_2=@Container) AND @now<DATEADD(hour,24,entered_at)) THROW 51004, ''24-hour receiving delay still applies.'', 1;
  IF EXISTS(SELECT 1 FROM dbo.truck_visits WHERE id<>@VisitId AND canceled_at IS NULL AND exited_at IS NULL AND (container_number=@Container OR container_number_2=@Container)) THROW 51009, ''Container active on another visit.'', 1;
  IF EXISTS(SELECT 1 FROM dbo.containers WHERE number=@Container AND (iso_code<>@iso OR armateur_id<>@line)) THROW 51004, ''Container ISO/carrier mismatch.'', 1;
  IF NOT EXISTS(SELECT 1 FROM dbo.containers WHERE number=@Container) INSERT dbo.containers(number,iso_code,armateur_id,source) VALUES(@Container,@iso,@line,N''manual'');
  INSERT dbo.yard_operations(visit_id,kind,container_number,performed_by,performed_at) VALUES(@VisitId,N''prise'',@Container,@ActorId,@now);
  UPDATE dbo.truck_visits SET container_number=@Container,engin_at=@now,engin_by=@ActorId,version=version+1 WHERE id=@VisitId;
  INSERT dbo.forced_container_actions(id,visit_id,container_number,action,reason,actor_id,occurred_at) VALUES(@id,@VisitId,@Container,N''PRISE_SANS_STOCK'',@Reason,@ActorId,@now);
  DECLARE @details nvarchar(max)=(SELECT @Container container,CONVERT(bit,1) forced,@Reason reason FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
  EXEC internal.record_gate_event @VisitId,N''PRISE'',@ActorId,@now,@details,@before;
  DECLARE @result nvarchar(max)=(SELECT @id id,@version+1 version FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
  COMMIT;SELECT @result;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK;THROW;END CATCH;
END;';
 SET @phase=N'013_forced_pickup_api.sql / lot3';
 EXEC sys.sp_executesql N'INSERT internal.schema_versions(version) VALUES(6);';
 IF @@TRANCOUNT<>1 THROW 51100, 'Transaction de deploiement inattendue.', 1;
 COMMIT;
 SELECT N'API APPLICATION VERSION6 INSTALLEE - IMPORT ET BASCULE RESTENT A FAIRE' resultat;
END TRY BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 DECLARE @error nvarchar(2048)=CONCAT(@phase,N' ; SQL ',ERROR_NUMBER(),N' ; ligne ',ERROR_LINE(),N' ; ',ERROR_MESSAGE());THROW 51101,@error,1;
END CATCH;
