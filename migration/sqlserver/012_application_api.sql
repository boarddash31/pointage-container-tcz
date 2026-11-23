-- Application reads, reference maintenance and integration reads. Upgrade 5 -> 6.
-- Run with 013 in a single deployment transaction. No business rows are imported here.
SET NOCOUNT ON;SET XACT_ABORT ON;
IF @@TRANCOUNT=0 OR (SELECT MAX(version) FROM internal.schema_versions)<>5
 OR (SELECT COUNT(*) FROM internal.schema_versions WHERE version IN(1,2,3,4,5))<>5
 THROW 51000, 'Transactional upgrade from exactly schema5 required.', 1;
-- Only the offline importer may register inherited, already-open visits. New entries always require order items.
CREATE TABLE internal.legacy_imported_visits(
 visit_id uniqueidentifier NOT NULL PRIMARY KEY REFERENCES dbo.truck_visits(id),
 source_snapshot_sha256 char(64) COLLATE Latin1_General_100_BIN2 NOT NULL,
 registered_at datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00')
);
CREATE TABLE internal.gate_entry_requests(
 actor_id uniqueidentifier NOT NULL REFERENCES dbo.profiles(id),request_id uniqueidentifier NOT NULL,
 payload_hash binary(32) NOT NULL,visit_id uniqueidentifier NOT NULL REFERENCES dbo.truck_visits(id),
 response_json nvarchar(max) NOT NULL CHECK(ISJSON(response_json,OBJECT)=1),
 created_at datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00'),
 PRIMARY KEY(actor_id,request_id)
);
GO
CREATE OR ALTER PROCEDURE api.readiness AS
BEGIN
 SET NOCOUNT ON;
 IF (SELECT MAX(version) FROM internal.schema_versions)<>6 THROW 51004, 'Application schema6 required.', 1;
 IF EXISTS(SELECT 1 FROM dbo.truck_visits v WHERE order_controlled=0 AND exited_at IS NULL AND canceled_at IS NULL
  AND NOT EXISTS(SELECT 1 FROM internal.legacy_imported_visits l WHERE l.visit_id=v.id)) THROW 51004, 'Unregistered inherited visits: verify the import provenance.', 1;
 IF NOT EXISTS(SELECT 1 FROM internal.local_accounts a JOIN dbo.profiles p ON p.id=a.user_id JOIN dbo.user_roles r ON r.user_id=p.id WHERE p.active=1 AND r.role=N'admin') THROW 51004, 'Provision the first local Admin after import.', 1;
 SELECT N'{"ready":true,"backend":"sqlserver","schema_version":6}';
END;
GO
CREATE OR ALTER PROCEDURE api.runtime_metadata AS
BEGIN
 SET NOCOUNT ON;
 SELECT DB_NAME(),CONVERT(nvarchar(128),SERVERPROPERTY('MachineName')),CONVERT(nvarchar(128),SERVERPROPERTY('InstanceName')),(SELECT MAX(version) FROM internal.schema_versions);
END;
GO
CREATE OR ALTER PROCEDURE api.runtime_integration_actor AS
BEGIN
 SET NOCOUNT ON;
 SELECT TOP(1) CONVERT(nvarchar(36),a.user_id) FROM internal.local_accounts a JOIN dbo.profiles p ON p.id=a.user_id
  JOIN dbo.user_roles r ON r.user_id=p.id WHERE p.active=1 AND r.role=N'admin' ORDER BY a.created_at,a.user_id;
END;
GO
CREATE OR ALTER PROCEDURE api.app_read @ActorId uniqueidentifier,@Operation nvarchar(40),@Id uniqueidentifier=NULL,
 @Text nvarchar(150)=NULL,@Day date=NULL,@Limit int=500,@AnyTime bit=0,@From datetimeoffset(6)=NULL,@To datetimeoffset(6)=NULL AS
BEGIN
 SET NOCOUNT ON;
 IF api.can_do(@ActorId,N'read')=0 THROW 51003, 'Read denied.', 1;
 IF @Operation IN(N'profiles',N'audit',N'hourly',N'dashboard',N'forced',N'report-snapshot') AND api.can_do(@ActorId,N'admin')=0
  THROW 51003, 'Admin required.', 1;
 IF @Limit IS NULL OR @Limit NOT BETWEEN 1 AND 1000 THROW 51004, 'Invalid read limit.', 1;
 SET @Day=COALESCE(@Day,CONVERT(date,SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'Morocco Standard Time'));
 DECLARE @start datetimeoffset(6)=CONVERT(datetime2,@Day) AT TIME ZONE 'Morocco Standard Time',
  @finish datetimeoffset(6)=CONVERT(datetime2,DATEADD(day,1,@Day)) AT TIME ZONE 'Morocco Standard Time';
 IF @Operation=N'clients' BEGIN SELECT (SELECT id,code,name,active FROM dbo.clients ORDER BY name,id FOR JSON PATH);RETURN;END;
 IF @Operation=N'operators' BEGIN SELECT (SELECT id,name,active,bic FROM dbo.armateurs ORDER BY name,id FOR JSON PATH);RETURN;END;
 IF @Operation=N'container' BEGIN SELECT (SELECT number,iso_code,armateur_id FROM dbo.containers WHERE number=@Text FOR JSON PATH);RETURN;END;
 IF @Operation=N'profiles' BEGIN
  SELECT (SELECT p.id,p.display_name,p.first_name,p.last_name,p.active,p.avatar_url,p.created_at,
   COALESCE(a.username,p.username) username,CONVERT(bit,CASE WHEN a.user_id IS NOT NULL THEN 1 ELSE 0 END) account_linked,
   a.version,JSON_QUERY((SELECT role FROM dbo.user_roles r WHERE r.user_id=p.id FOR JSON PATH)) user_roles
   FROM dbo.profiles p LEFT JOIN internal.local_accounts a ON a.user_id=p.id ORDER BY p.created_at DESC,p.id FOR JSON PATH);RETURN;
 END;
 IF @Operation=N'audit' BEGIN SELECT (SELECT TOP(100) entity,entity_id,action,actor_id,occurred_at,reason FROM dbo.audit_logs ORDER BY occurred_at DESC,id DESC FOR JSON PATH);RETURN;END;
 IF @Operation=N'forced' BEGIN SELECT (SELECT TOP(1000) id,visit_id,container_number,action,reason,actor_id,occurred_at,resolved_at,external_reference FROM dbo.forced_container_actions WHERE resolved_at IS NULL ORDER BY occurred_at,id FOR JSON PATH);RETURN;END;
 IF @Operation=N'visits' BEGIN
  SELECT (SELECT TOP(@Limit) v.*,JSON_QUERY(v.operational_details) operational_fields,
   JSON_QUERY((SELECT COALESCE(v.carrier_booking_reference,b.reference) reference FOR JSON PATH,WITHOUT_ARRAY_WRAPPER)) bookings
   FROM dbo.truck_visits v LEFT JOIN dbo.bookings b ON b.id=v.booking_id
   WHERE (@Id IS NULL OR v.id=@Id) AND (@Text IS NULL OR v.plate=@Text) ORDER BY v.entered_at DESC,v.id DESC FOR JSON PATH);RETURN;
 END;
 IF @Operation=N'transactions' BEGIN
  SELECT (SELECT TOP(500) v.*,JSON_QUERY(v.operational_details) operational_fields,CONVERT(nvarchar(20),entry.id) transaction_number,c.name client_name,
   COALESCE(NULLIF(creator.display_name,N''),CONVERT(nvarchar(36),v.entered_by)) creator_name,
   COALESCE(NULLIF(changer.display_name,N''),CONVERT(nvarchar(36),COALESCE(last_change.actor_id,v.entered_by))) changer_name,
   COALESCE(last_change.occurred_at,v.entered_at) changed_at,
   JSON_QUERY((SELECT COALESCE(v.carrier_booking_reference,b.reference) reference FOR JSON PATH,WITHOUT_ARRAY_WRAPPER)) bookings
   FROM dbo.truck_visits v LEFT JOIN dbo.bookings b ON b.id=v.booking_id LEFT JOIN dbo.clients c ON c.id=v.client_id
   LEFT JOIN dbo.profiles creator ON creator.id=v.entered_by
   OUTER APPLY(SELECT TOP(1) id FROM dbo.visit_events e WHERE e.visit_id=v.id AND e.action=N'ENTREE' ORDER BY e.occurred_at,e.id) entry
   OUTER APPLY(SELECT TOP(1) actor_id,occurred_at FROM dbo.audit_logs a WHERE a.entity=N'truck_visit' AND a.entity_id=CONVERT(nvarchar(36),v.id) ORDER BY a.occurred_at DESC,a.id DESC) last_change
   LEFT JOIN dbo.profiles changer ON changer.id=COALESCE(last_change.actor_id,v.entered_by) ORDER BY v.entered_at DESC,v.id DESC FOR JSON PATH);RETURN;
 END;
 IF @Operation=N'documents' BEGIN
  SELECT (SELECT TOP(@Limit) id,visit_id,CONVERT(nvarchar(20),event_id) event_id,kind,status,storage_path,created_at,JSON_QUERY(snapshot) snapshot
   FROM dbo.generated_documents WHERE (@Id IS NULL OR visit_id=@Id) AND (@Text IS NULL OR kind=@Text) ORDER BY created_at DESC,event_id DESC,id DESC FOR JSON PATH);RETURN;
 END;
 IF @Operation=N'document-context' BEGIN
  IF @Id IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.generated_documents WHERE id=@Id) THROW 51002, 'Document not found.', 1;
  SELECT (SELECT COALESCE(JSON_VALUE(d.snapshot,'$.agent_name'),p.display_name,CONVERT(nvarchar(36),d.created_by)) agent_name,
   CONVERT(nvarchar(19),d.created_at AT TIME ZONE 'Morocco Standard Time',120) created_at_local,
   CONVERT(nvarchar(20),e.id) visit_number,CONVERT(nvarchar(20),d.event_id) authorization_number
   FROM dbo.generated_documents d LEFT JOIN dbo.profiles p ON p.id=d.created_by
   OUTER APPLY(SELECT TOP(1) id FROM dbo.visit_events e WHERE e.visit_id=d.visit_id AND e.action=N'ENTREE' ORDER BY occurred_at,id) e
   WHERE d.id=@Id FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);RETURN;
 END;
 IF @Operation=N'hourly' BEGIN
  ;WITH hours(h) AS(SELECT * FROM(VALUES(0),(1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12),(13),(14),(15),(16),(17),(18),(19),(20),(21),(22),(23))v(h)),
  stages(stage) AS(SELECT * FROM(VALUES(N'ENTREE'),(N'ENGIN'),(N'SORTIE'))v(stage)),
  counted AS(SELECT CASE WHEN action IN(N'DEPOSE',N'PRISE') THEN N'ENGIN' ELSE action END COLLATE Latin1_General_100_BIN2 stage,
   DATEPART(hour,occurred_at AT TIME ZONE 'Morocco Standard Time') h,COUNT(*) total FROM dbo.visit_events
   WHERE occurred_at>=@start AND occurred_at<@finish AND action IN(N'ENTREE',N'DEPOSE',N'PRISE',N'SORTIE')
   GROUP BY CASE WHEN action IN(N'DEPOSE',N'PRISE') THEN N'ENGIN' ELSE action END,DATEPART(hour,occurred_at AT TIME ZONE 'Morocco Standard Time'))
  SELECT (SELECT s.stage,h.h hour,COALESCE(c.total,0) total FROM stages s CROSS JOIN hours h LEFT JOIN counted c ON c.stage=s.stage COLLATE Latin1_General_100_BIN2 AND c.h=h.h ORDER BY s.stage,h.h FOR JSON PATH);RETURN;
 END;
 IF @Operation=N'dashboard' BEGIN
  SELECT (SELECT @Day day,
   (SELECT COUNT(*) FROM dbo.truck_visits WHERE entered_at>=@start AND entered_at<@finish) entries_today,
   (SELECT COUNT(*) FROM dbo.truck_visits WHERE exited_at>=@start AND exited_at<@finish AND canceled_at IS NULL) exits_today,
   (SELECT COUNT(*) FROM dbo.truck_visits WHERE exited_at IS NULL AND canceled_at IS NULL) trucks_in_yard,
   (SELECT COUNT(*) FROM dbo.container_stock_intervals WHERE departed_at IS NULL) containers_in_stock,
   (SELECT COUNT(*) FROM internal.local_accounts a JOIN dbo.profiles p ON p.id=a.user_id WHERE p.active=1) agents_count,
   JSON_QUERY((SELECT TOP(100) id,plate truck_plate,container_number,container_number_2,entered_at,exited_at,canceled_at,
    CASE WHEN canceled_at IS NOT NULL THEN N'ANNULE' WHEN exited_at IS NOT NULL THEN N'SORTI' ELSE N'AU_PARC' END status
    FROM dbo.truck_visits ORDER BY entered_at DESC,id DESC FOR JSON PATH)) recent_visits FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);RETURN;
 END;
 IF @Operation=N'freepool' BEGIN
  IF (SELECT COUNT_BIG(*) FROM dbo.container_stock_intervals WHERE arrived_at<@finish AND (departed_at IS NULL OR departed_at>=CASE WHEN @AnyTime=1 THEN @start ELSE @finish END) AND (@Id IS NULL OR client_id=@Id))>100000 THROW 51004, 'Report exceeds row limit.', 1;
  SELECT (SELECT s.container_number,s.client_id,s.armateur_id,s.iso_code,t.category,s.arrived_at,s.departed_at,s.position,r.factor evp
   FROM dbo.container_stock_intervals s
   OUTER APPLY(SELECT TOP(1) category,size_feet FROM dbo.iso_report_types t WHERE t.iso_code=s.iso_code AND effective_from<=@Day ORDER BY effective_from DESC)t
   OUTER APPLY(SELECT TOP(1) factor FROM dbo.evp_rules r WHERE r.size_feet=t.size_feet AND effective_from<=@Day ORDER BY effective_from DESC)r
   WHERE s.arrived_at<@finish AND (s.departed_at IS NULL OR CASE WHEN @AnyTime=1 AND s.departed_at>@start THEN 1 WHEN @AnyTime=0 AND s.departed_at>=@finish THEN 1 ELSE 0 END=1)
    AND (@Id IS NULL OR s.client_id=@Id) ORDER BY t.category,s.armateur_id,s.container_number FOR JSON PATH);RETURN;
 END;
 IF @Operation=N'report-snapshot' BEGIN
  IF @From IS NULL OR @To IS NULL OR @To<=@From OR @To>DATEADD(day,32,@From) THROW 51004, 'Invalid report window.', 1;
  IF (SELECT COUNT_BIG(*) FROM dbo.generated_documents WHERE kind IN(N'ENTREE',N'SORTIE') AND created_at>=@From AND created_at<@To)>100000
   OR (SELECT COUNT_BIG(*) FROM dbo.container_stock_intervals WHERE arrived_at<@To AND (departed_at IS NULL OR departed_at>=@To))>100000 THROW 51004, 'Report exceeds row limit.', 1;
  SELECT (SELECT JSON_QUERY((SELECT id,name,active FROM dbo.clients ORDER BY id FOR JSON PATH)) clients,
   JSON_QUERY((SELECT id,kind,created_at,JSON_QUERY(snapshot) snapshot FROM dbo.generated_documents WHERE kind IN(N'ENTREE',N'SORTIE') AND created_at>=@From AND created_at<@To ORDER BY id FOR JSON PATH)) documents,
   JSON_QUERY((SELECT id,container_number,client_id,armateur_id,iso_code,arrived_at,departed_at,position FROM dbo.container_stock_intervals WHERE arrived_at<@To AND (departed_at IS NULL OR departed_at>=@To) ORDER BY id FOR JSON PATH)) stock,
   JSON_QUERY((SELECT iso_code,effective_from,category,size_feet FROM dbo.iso_report_types ORDER BY iso_code,effective_from FOR JSON PATH)) isoRules,
   JSON_QUERY((SELECT size_feet,effective_from,factor FROM dbo.evp_rules ORDER BY size_feet,effective_from FOR JSON PATH)) evpRules FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);RETURN;
 END;
 IF @Operation=N'codeco' BEGIN
  IF @From IS NULL OR @To IS NULL OR @To<=@From OR @To>DATEADD(day,31,@From) THROW 51004, 'Invalid CODECO window.', 1;
  SELECT (SELECT TOP(10001) CONVERT(nvarchar(20),e.id) event_id,e.action,e.occurred_at,JSON_QUERY(d.snapshot) snapshot,JSON_QUERY(N'{}') metadata
   FROM dbo.visit_events e JOIN dbo.generated_documents d ON d.event_id=e.id AND d.kind=e.action
   WHERE e.occurred_at>=@From AND e.occurred_at<@To AND ((e.action=N'ENTREE' AND JSON_VALUE(d.snapshot,'$.entry_kind')=N'loaded') OR (e.action=N'SORTIE' AND JSON_VALUE(d.snapshot,'$.entry_kind')=N'empty'))
    AND (JSON_VALUE(d.snapshot,'$.armateur_id')=N'MSC' OR (JSON_VALUE(d.snapshot,'$.is_twin')=N'true' AND JSON_VALUE(d.snapshot,'$.armateur_id_2')=N'MSC'))
   ORDER BY e.occurred_at,e.id,d.id FOR JSON PATH);RETURN;
 END;
 THROW 51004, 'Unknown read operation.', 1;
END;
GO
CREATE OR ALTER PROCEDURE api.app_write @ActorId uniqueidentifier,@Operation nvarchar(40),@Payload nvarchar(max) AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF ISJSON(@Payload,OBJECT)<>1 THROW 51004, 'JSON object required.', 1;
 IF api.can_do(@ActorId,CASE WHEN @Operation=N'document-action' THEN N'read' ELSE N'admin' END)=0 THROW 51003, 'Operation denied.', 1;
 DECLARE @id uniqueidentifier=TRY_CONVERT(uniqueidentifier,JSON_VALUE(@Payload,'$.id')),
  @number nvarchar(64)=UPPER(TRIM(JSON_VALUE(@Payload,'$.number'))),@iso nvarchar(64)=UPPER(TRIM(JSON_VALUE(@Payload,'$.iso'))),
  @line nvarchar(64)=JSON_VALUE(@Payload,'$.armateur'),@code nvarchar(max)=TRIM(JSON_VALUE(@Payload,'$.code')),
  @name nvarchar(max)=TRIM(JSON_VALUE(@Payload,'$.name')),@before nvarchar(max),@after nvarchar(max),@now datetimeoffset(6)=TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00');
 BEGIN TRY
  BEGIN TRANSACTION;
  IF @Operation=N'document-action' BEGIN
   DECLARE @action nvarchar(64)=JSON_VALUE(@Payload,'$.action');
   IF @id IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.generated_documents WHERE id=@id) OR @action IS NULL OR @action NOT IN(N'PREVIEW_REQUESTED',N'SHARE_REQUESTED',N'PRINT_DIALOG_REQUESTED',N'DIRECT_PRINT_REQUESTED') THROW 51004, 'Invalid document action.', 1;
   INSERT dbo.document_actions(document_id,actor_id,action) VALUES(@id,@ActorId,@action);
  END ELSE BEGIN
   EXEC internal.account_admin_lock;
   IF api.can_do(@ActorId,N'admin')=0 THROW 51003, 'Admin required.', 1;
   IF @Operation=N'client' BEGIN
    IF @code IS NULL OR LEN(@code) NOT BETWEEN 1 AND 150 OR @name IS NULL OR LEN(@name) NOT BETWEEN 1 AND 200 THROW 51004, 'Client code and name required.', 1;
    SET @id=NEWID();INSERT dbo.clients(id,code,name) VALUES(@id,@code,@name);
   END ELSE IF @Operation=N'assignment' BEGIN
    SET @id=TRY_CONVERT(uniqueidentifier,JSON_VALUE(@Payload,'$.client'));
    DECLARE @valid date=TRY_CONVERT(date,JSON_VALUE(@Payload,'$.from'),23);
    IF @id IS NULL OR @line IS NULL OR @valid IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.clients WHERE id=@id AND active=1) OR NOT EXISTS(SELECT 1 FROM dbo.armateurs WHERE id=@line AND active=1) THROW 51004, 'Active client/carrier and valid start date required.', 1;
    IF EXISTS(SELECT 1 FROM dbo.client_armateurs WITH(UPDLOCK,HOLDLOCK) WHERE armateur_id=@line AND (valid_to IS NULL OR valid_to>=@valid)) THROW 51009, 'Overlapping carrier allocation; reconcile the existing assignment.', 1;
    INSERT dbo.client_armateurs(client_id,armateur_id,valid_from) VALUES(@id,@line,@valid);
   END ELSE IF @Operation=N'container' BEGIN
    IF internal.valid_container_number(@number)=0 OR DATALENGTH(@iso)<>8 OR @iso COLLATE Latin1_General_100_BIN2 LIKE N'%[^A-Z0-9]%' OR @line IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.armateurs WHERE id=@line AND active=1) THROW 51004, 'Valid container/ISO/carrier required.', 1;
    IF EXISTS(SELECT 1 FROM dbo.containers WITH(UPDLOCK,HOLDLOCK) WHERE number=@number) THROW 51009, 'Container already exists.', 1;
    INSERT dbo.containers(number,iso_code,armateur_id,source) VALUES(@number,@iso,@line,N'manual');
   END ELSE IF @Operation=N'profile' BEGIN
    DECLARE @first nvarchar(max)=TRIM(JSON_VALUE(@Payload,'$.first_name')),@last nvarchar(max)=TRIM(JSON_VALUE(@Payload,'$.last_name')),
     @expected int=TRY_CONVERT(int,JSON_VALUE(@Payload,'$.expected_version'));
    IF @id IS NULL OR @first IS NULL OR @last IS NULL OR LEN(@first) NOT BETWEEN 1 AND 100 OR LEN(@last) NOT BETWEEN 1 AND 100 OR @expected IS NULL OR @expected<1 THROW 51004, 'Profile names/version required.', 1;
    IF NOT EXISTS(SELECT 1 FROM internal.local_accounts WITH(UPDLOCK,HOLDLOCK) WHERE user_id=@id AND version=@expected) THROW 51009, 'Account changed. Refresh.', 1;
    SET @before=(SELECT id,display_name,first_name,last_name FROM dbo.profiles WHERE id=@id FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
    UPDATE dbo.profiles SET first_name=@first,last_name=@last,display_name=CONCAT(@first,N' ',@last) WHERE id=@id;
    IF EXISTS(SELECT 1 FROM OPENJSON(@Payload) WHERE [key]=N'avatar_url') UPDATE dbo.profiles SET avatar_url=NULLIF(JSON_VALUE(@Payload,'$.avatar_url'),N'') WHERE id=@id;
    UPDATE internal.local_accounts SET version=version+1 WHERE user_id=@id;
    DELETE internal.application_sessions WHERE user_id=@id;
   END ELSE IF @Operation=N'reconcile' BEGIN
    DECLARE @reference nvarchar(max)=TRIM(JSON_VALUE(@Payload,'$.external_reference'));
    IF @id IS NULL OR @reference IS NULL OR LEN(@reference) NOT BETWEEN 3 AND 150 THROW 51004, 'Reconciliation reference required.', 1;
    IF NOT EXISTS(SELECT 1 FROM dbo.forced_container_actions WITH(UPDLOCK,HOLDLOCK) WHERE id=@id AND resolved_at IS NULL) THROW 51009, 'Unresolved action not found.', 1;
    UPDATE dbo.forced_container_actions SET resolved_at=@now,resolved_by=@ActorId,external_reference=@reference WHERE id=@id;
   END ELSE THROW 51004, 'Unknown maintenance operation.', 1;
   INSERT dbo.audit_logs(entity,entity_id,action,actor_id,occurred_at,before_data)
    VALUES(N'application',COALESCE(CONVERT(nvarchar(36),@id),@number),UPPER(@Operation),@ActorId,@now,@before);
  END;
  COMMIT;SELECT N'{"ok":true}';
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK;THROW;END CATCH;
END;
GO
