-- VERSION4: mise a jour du socle existant, jamais reinitialisation ni import.
-- Cible unique : toszps. Nouvelle session, selectionner tout, Ctrl+Entree.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF @@TRANCOUNT<>0 THROW 51100, 'Session sans transaction requise.', 1;
DECLARE @stage nvarchar(200)=N'Controle de cible';
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
 IF (SELECT compatibility_level FROM sys.databases WHERE database_id=DB_ID())<>170 THROW 51100, 'Compatibilite170 requise.', 1;
 IF DATABASEPROPERTYEX(DB_NAME(),'Updateability')<>N'READ_WRITE' THROW 51100, 'Base modifiable requise.', 1;
 IF IS_ROLEMEMBER(N'db_owner')<>1 AND IS_SRVROLEMEMBER(N'sysadmin')<>1 THROW 51100, 'Compte de deploiement requis.', 1;
 BEGIN TRANSACTION;
 SET @stage=N'008_gate_operations.sql, lot 1';
 EXEC sys.sp_executesql N'-- Upgrade from installed schema versions 1/2/3. Execute in one deployment transaction.
-- Do not replay 001 on the existing database. This file alone is not the full upgrade.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF (SELECT COUNT(*) FROM internal.schema_versions WHERE version IN(1,2,3))<>3
 THROW 51000, ''Foundation versions 1/2/3 required.'', 1;
IF EXISTS(SELECT 1 FROM internal.schema_versions WHERE version=4)
 THROW 51000, ''Gate version 4 already installed.'', 1;
IF @@TRANCOUNT=0 THROW 51000, ''Use the transactional gate upgrade wrapper.'', 1;
ALTER TABLE dbo.truck_visits ADD operational_details nvarchar(max) NOT NULL
 CONSTRAINT truck_visits_operational_details_default DEFAULT N''{}''
 CONSTRAINT truck_visits_operational_details_object CHECK(ISJSON(operational_details,OBJECT)=1);
CREATE TABLE dbo.container_blocks(
 container_number nvarchar(11) COLLATE Latin1_General_100_BIN2 NOT NULL PRIMARY KEY REFERENCES dbo.containers(number),
 blocked bit NOT NULL, reason nvarchar(1000) NOT NULL CHECK(LEN(TRIM(reason)) BETWEEN 3 AND 1000),
 changed_by uniqueidentifier NOT NULL REFERENCES dbo.profiles(id),
 changed_at datetimeoffset(6) NOT NULL,version int NOT NULL CHECK(version>0)
);';
 SET @stage=N'008_gate_operations.sql, lot 2';
 EXEC sys.sp_executesql N'CREATE OR ALTER FUNCTION internal.valid_container_number(@number nvarchar(64)) RETURNS bit AS
BEGIN
 IF @number IS NULL OR DATALENGTH(@number)<>22 OR @number COLLATE Latin1_General_100_BIN2 NOT LIKE N''[A-Z][A-Z][A-Z][A-Z][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'' RETURN 0;
 DECLARE @sum int=0,@index int=1,@code int,@value int,@weight int=1;
 WHILE @index<=10 BEGIN
  SET @code=UNICODE(SUBSTRING(@number,@index,1));
  SET @value=CASE WHEN @index>4 THEN @code-48 ELSE 10+@code-65+(10+@code-65-1)/10 END;
  SET @sum=@sum+@value*@weight;SET @weight=@weight*2;SET @index=@index+1;
 END;
 RETURN CASE WHEN (@sum%11)%10=UNICODE(RIGHT(@number,1))-48 THEN 1 ELSE 0 END;
END;';
 SET @stage=N'008_gate_operations.sql, lot 3';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE internal.validate_operational_details @Details nvarchar(max) AS
BEGIN
 SET NOCOUNT ON;
 IF ISJSON(@Details,OBJECT)<>1 OR @Details IS NULL THROW 51004, ''Operational details must be a JSON object.'', 1;
 IF EXISTS(SELECT 1 FROM OPENJSON(@Details) WHERE type<>1 OR
  DATALENGTH(value)/2>CASE [key] COLLATE Latin1_General_100_BIN2
   WHEN N''haulier'' THEN 100 WHEN N''lane'' THEN 40 WHEN N''lane_2'' THEN 40
   WHEN N''seal_number'' THEN 60 WHEN N''seal_number_2'' THEN 60
   WHEN N''damage_reservations'' THEN 1000 WHEN N''damage_reservations_2'' THEN 1000 ELSE -1 END)
  OR EXISTS(SELECT 1 FROM OPENJSON(@Details) GROUP BY [key] COLLATE Latin1_General_100_BIN2 HAVING COUNT(*)>1)
  THROW 51004, ''Unknown, duplicate or invalid operational field.'', 1;
END;';
 SET @stage=N'008_gate_operations.sql, lot 4';
 EXEC sys.sp_executesql N'-- All lifecycle writers serialize under this transaction-owned lock. Parent orders
-- are then locked before items, matching the existing quantity/order editor.
CREATE OR ALTER PROCEDURE internal.gate_lock @VisitId uniqueidentifier=NULL,
 @Item1 uniqueidentifier=NULL,@Item2 uniqueidentifier=NULL AS
BEGIN
 SET NOCOUNT ON;
 IF @@TRANCOUNT=0 THROW 51004, ''Gate operation requires a transaction.'', 1;
 DECLARE @result int,@id uniqueidentifier,@unused uniqueidentifier;
 EXEC @result=sys.sp_getapplock @Resource=N''zenata-gate-lifecycle'',@LockMode=N''Exclusive'',@LockOwner=N''Transaction'',@LockTimeout=10000;
 IF @result<0 THROW 51009, ''Gate operation busy. Refresh and retry.'', 1;
 IF @VisitId IS NOT NULL SELECT @Item1=order_item_id,@Item2=order_item_id_2 FROM dbo.truck_visits WHERE id=@VisitId;
 DECLARE parent_cursor CURSOR LOCAL FAST_FORWARD FOR
  SELECT DISTINCT order_id FROM dbo.transport_order_items WHERE id IN(@Item1,@Item2) ORDER BY order_id;
 OPEN parent_cursor;FETCH NEXT FROM parent_cursor INTO @id;
 WHILE @@FETCH_STATUS=0 BEGIN
  SELECT @unused=id FROM dbo.transport_orders WITH(UPDLOCK,HOLDLOCK) WHERE id=@id;
  FETCH NEXT FROM parent_cursor INTO @id;
 END;CLOSE parent_cursor;DEALLOCATE parent_cursor;
 DECLARE item_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT id FROM dbo.transport_order_items WHERE id IN(@Item1,@Item2) ORDER BY id;
 OPEN item_cursor;FETCH NEXT FROM item_cursor INTO @id;
 WHILE @@FETCH_STATUS=0 BEGIN
  SELECT @unused=id FROM dbo.transport_order_items WITH(UPDLOCK,HOLDLOCK) WHERE id=@id;
  FETCH NEXT FROM item_cursor INTO @id;
 END;CLOSE item_cursor;DEALLOCATE item_cursor;
END;';
 SET @stage=N'008_gate_operations.sql, lot 5';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE internal.record_gate_event @VisitId uniqueidentifier,@Action nvarchar(64),
 @ActorId uniqueidentifier,@At datetimeoffset(6),@Details nvarchar(max)=N''{}'',@Before nvarchar(max)=NULL AS
BEGIN
 SET NOCOUNT ON;
 IF @@TRANCOUNT=0 THROW 51004, ''Event requires transaction.'', 1;
 DECLARE @event bigint,@snapshot nvarchar(max),@agent nvarchar(max);
 SELECT @agent=COALESCE(NULLIF(TRIM(CONCAT(first_name,N'' '',last_name)),N''''),NULLIF(display_name,N''''),CONVERT(nvarchar(36),id)) FROM dbo.profiles WHERE id=@ActorId;
 SELECT @snapshot=(SELECT v.*,JSON_QUERY(@Details) AS [event],@agent AS agent_name FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER) FROM dbo.truck_visits v WHERE id=@VisitId;
 -- Read the object directly, avoiding JSON_VALUE''s 4000-character scalar limit.
 SELECT @snapshot=JSON_MODIFY(@snapshot,N''$.operational_details'',JSON_QUERY(operational_details)) FROM dbo.truck_visits WHERE id=@VisitId;
 INSERT dbo.visit_events(visit_id,action,occurred_at,actor_id,details) VALUES(@VisitId,@Action,@At,@ActorId,@Details);
 SET @event=CONVERT(bigint,SCOPE_IDENTITY());
 INSERT dbo.generated_documents(visit_id,event_id,kind,snapshot,created_by,created_at) VALUES(@VisitId,@event,@Action,@snapshot,@ActorId,@At);
 INSERT dbo.audit_logs(entity,entity_id,action,actor_id,occurred_at,before_data,after_data)
  VALUES(N''truck_visit'',CONVERT(nvarchar(36),@VisitId),@Action,@ActorId,@At,@Before,@snapshot);
END;';
 SET @stage=N'008_gate_operations.sql, lot 6';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.set_container_block @ActorId uniqueidentifier,@Container nvarchar(64),
 @Blocked bit,@Reason nvarchar(max),@ExpectedVersion int AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF api.can_do(@ActorId,N''admin'')=0 THROW 51003, ''Admin required.'', 1;
 SET @Container=UPPER(TRIM(@Container));SET @Reason=TRIM(@Reason);
 IF internal.valid_container_number(@Container)=0 OR @Blocked IS NULL OR @ExpectedVersion IS NULL OR @ExpectedVersion<0 OR @Reason IS NULL OR LEN(@Reason)<3 OR DATALENGTH(@Reason)>2000 THROW 51004, ''Invalid container hold.'', 1;
 BEGIN TRY
  BEGIN TRANSACTION;EXEC internal.gate_lock;
  IF api.can_do(@ActorId,N''admin'')=0 THROW 51003, ''Admin required.'', 1;
  IF NOT EXISTS(SELECT 1 FROM dbo.containers WHERE number=@Container) THROW 51002, ''Container not found.'', 1;
  DECLARE @version int,@before nvarchar(max),@after nvarchar(max),@now datetimeoffset(6)=TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00'');
  SELECT @version=version,@before=(SELECT b.* FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) FROM dbo.container_blocks b WITH(UPDLOCK,HOLDLOCK) WHERE container_number=@Container;
  IF COALESCE(@version,0)<>@ExpectedVersion THROW 51009, ''Hold changed. Refresh.'', 1;
  IF @version IS NULL INSERT dbo.container_blocks VALUES(@Container,@Blocked,@Reason,@ActorId,@now,1);
  ELSE UPDATE dbo.container_blocks SET blocked=@Blocked,reason=@Reason,changed_by=@ActorId,changed_at=@now,version=version+1 WHERE container_number=@Container;
  SET @after=(SELECT * FROM dbo.container_blocks WHERE container_number=@Container FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
  INSERT dbo.audit_logs(entity,entity_id,action,actor_id,before_data,after_data) VALUES(N''container_block'',@Container,CASE WHEN @Blocked=1 THEN N''BLOCK'' ELSE N''UNBLOCK'' END,@ActorId,@before,@after);
  COMMIT;SELECT @after;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK;THROW;END CATCH;
END;';
 SET @stage=N'008_gate_operations.sql, lot 7';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.enter_visit @ActorId uniqueidentifier,@Plate nvarchar(max),@Cin nvarchar(max),
 @EntryKind nvarchar(8),@OrderItemId uniqueidentifier,@IsTwin bit=0,@OrderItemId2 uniqueidentifier=NULL,
 @Container nvarchar(64)=NULL,@Container2 nvarchar(64)=NULL,@Details nvarchar(max)=N''{}'' AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF api.can_do(@ActorId,N''entree'')=0 THROW 51003, ''Entry role required.'', 1;
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
  COMMIT;SELECT (SELECT @id AS id,1 AS version FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK;THROW;END CATCH;
END;';
 SET @stage=N'009_gate_lifecycle.sql, lot 1';
 EXEC sys.sp_executesql N'-- Second half of version 4. Execute after 008, in the same deployment transaction.
SET NOCOUNT ON;
IF @@TRANCOUNT=0 THROW 51000, ''Use the transactional gate upgrade wrapper.'', 1;';
 SET @stage=N'009_gate_lifecycle.sql, lot 2';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.move_visit @ActorId uniqueidentifier,@VisitId uniqueidentifier,@ExpectedVersion int,
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
   IF @controlled=0 THROW 51004, ''Legacy visit requires order reconciliation before migration cutover.'', 1;
   IF EXISTS(SELECT 1 FROM dbo.truck_visits v CROSS APPLY(VALUES(v.order_item_id,v.iso_code,v.armateur_id),(CASE WHEN v.is_twin=1 THEN v.order_item_id_2 END,v.iso_code_2,v.armateur_id_2)) x(item,iso,line)
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
 SET @stage=N'009_gate_lifecycle.sql, lot 3';
 EXEC sys.sp_executesql N'CREATE OR ALTER TRIGGER dbo.protect_stock_block ON dbo.container_stock_intervals AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM inserted i LEFT JOIN deleted d ON d.id=i.id JOIN dbo.container_blocks b ON b.container_number=i.container_number
  WHERE i.departed_at IS NOT NULL AND d.departed_at IS NULL AND b.blocked=1) THROW 51004, ''Container blocked: delivery prohibited.'', 1;
END;';
 SET @stage=N'009_gate_lifecycle.sql, lot 4';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.gate_visits @ActorId uniqueidentifier,@AfterId uniqueidentifier=NULL,@PageSize int=200,@InsideOnly bit=1 AS
BEGIN
 SET NOCOUNT ON;
 IF api.can_do(@ActorId,N''read'')=0 THROW 51003, ''Read denied.'', 1;
 IF @PageSize IS NULL OR @PageSize NOT BETWEEN 1 AND 1000 OR @InsideOnly IS NULL THROW 51004, ''Invalid page.'', 1;
 SELECT (SELECT TOP(@PageSize) v.id,v.plate,v.driver_cin,v.entry_kind,v.container_number,v.container_number_2,v.iso_code,v.iso_code_2,v.armateur_id,v.armateur_id_2,
  v.client_id,v.entered_at,v.engin_at,v.exited_at,v.canceled_at,v.cancel_reason,v.is_twin,v.version,v.carrier_booking_reference,v.booking_reference_2,
  v.order_item_id,v.order_item_id_2,v.order_controlled,JSON_QUERY(v.operational_details) AS operational_details
  FROM dbo.truck_visits v WHERE (@AfterId IS NULL OR v.id>@AfterId) AND (@InsideOnly=0 OR (v.exited_at IS NULL AND v.canceled_at IS NULL)) ORDER BY v.id FOR JSON PATH);
END;';
 SET @stage=N'009_gate_lifecycle.sql, lot 5';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.gate_stock @ActorId uniqueidentifier,@AfterId uniqueidentifier=NULL,@PageSize int=200,@Iso nvarchar(4)=NULL,@Line nvarchar(64)=NULL AS
BEGIN
 SET NOCOUNT ON;
 IF api.can_do(@ActorId,N''read'')=0 THROW 51003, ''Read denied.'', 1;
 IF @PageSize IS NULL OR @PageSize NOT BETWEEN 1 AND 1000 THROW 51004, ''Invalid page.'', 1;
 SELECT (SELECT TOP(@PageSize) s.id,s.container_number,s.client_id,s.iso_code,s.armateur_id,s.arrived_at,s.position,r.entered_at AS receiving_truck_entered_at,
  CONVERT(bit,COALESCE(b.blocked,0)) AS blocked,
  CONVERT(bit,CASE WHEN COALESCE(b.blocked,0)=0 AND r.entry_kind=N''loaded'' AND r.canceled_at IS NULL AND TODATETIMEOFFSET(SYSUTCDATETIME(),''+00:00'')>=DATEADD(hour,24,r.entered_at) THEN 1 ELSE 0 END) AS delivery_ready
  FROM dbo.container_stock_intervals s JOIN dbo.truck_visits r ON r.id=s.start_visit_id LEFT JOIN dbo.container_blocks b ON b.container_number=s.container_number
  WHERE s.departed_at IS NULL AND (@AfterId IS NULL OR s.id>@AfterId) AND (@Iso IS NULL OR s.iso_code=@Iso) AND (@Line IS NULL OR s.armateur_id=@Line) ORDER BY s.id FOR JSON PATH);
END;';
 SET @stage=N'009_gate_lifecycle.sql, lot 6';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.gate_events @ActorId uniqueidentifier,@VisitId uniqueidentifier,@AfterId bigint=0,@PageSize int=200 AS
BEGIN
 SET NOCOUNT ON;
 IF api.can_do(@ActorId,N''read'')=0 THROW 51003, ''Read denied.'', 1;
 IF @PageSize IS NULL OR @PageSize NOT BETWEEN 1 AND 1000 OR @AfterId IS NULL OR @AfterId<0 THROW 51004, ''Invalid page.'', 1;
 SELECT (SELECT TOP(@PageSize) CONVERT(nvarchar(20),id) AS id,action,occurred_at,actor_id,JSON_QUERY(details) AS details FROM dbo.visit_events WHERE visit_id=@VisitId AND id>@AfterId ORDER BY id FOR JSON PATH);
END;';
 SET @stage=N'009_gate_lifecycle.sql, lot 7';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE api.container_blocks @ActorId uniqueidentifier,@After nvarchar(11)=NULL,@PageSize int=200 AS
BEGIN
 SET NOCOUNT ON;
 IF api.can_do(@ActorId,N''admin'')=0 THROW 51003, ''Admin required.'', 1;
 IF @PageSize IS NULL OR @PageSize NOT BETWEEN 1 AND 1000 THROW 51004, ''Invalid page.'', 1;
 SELECT (SELECT TOP(@PageSize) * FROM dbo.container_blocks WHERE @After IS NULL OR container_number>@After ORDER BY container_number FOR JSON PATH);
END;';
 SET @stage=N'009_gate_lifecycle.sql, lot 8';
 EXEC sys.sp_executesql N'INSERT internal.schema_versions(version) VALUES(4);';
 IF @@TRANCOUNT<>1 THROW 51100, 'Transaction de deploiement inattendue.', 1;
 COMMIT TRANSACTION;
 SELECT N'GATE VERSION4 INSTALLEE - application non basculee' AS resultat;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 DECLARE @message nvarchar(2048)=CONCAT(@stage,N' ; SQL ',ERROR_NUMBER(),N' ; ',COALESCE(ERROR_PROCEDURE(),N'lot'),N' ; ligne ',ERROR_LINE(),N' ; ',ERROR_MESSAGE());
 THROW 51101,@message,1;
END CATCH;
