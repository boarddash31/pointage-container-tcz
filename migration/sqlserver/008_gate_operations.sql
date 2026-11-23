-- Upgrade from installed schema versions 1/2/3. Execute in one deployment transaction.
-- Do not replay 001 on the existing database. This file alone is not the full upgrade.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF (SELECT COUNT(*) FROM internal.schema_versions WHERE version IN(1,2,3))<>3
 THROW 51000, 'Foundation versions 1/2/3 required.', 1;
IF EXISTS(SELECT 1 FROM internal.schema_versions WHERE version=4)
 THROW 51000, 'Gate version 4 already installed.', 1;
IF @@TRANCOUNT=0 THROW 51000, 'Use the transactional gate upgrade wrapper.', 1;
ALTER TABLE dbo.truck_visits ADD operational_details nvarchar(max) NOT NULL
 CONSTRAINT truck_visits_operational_details_default DEFAULT N'{}'
 CONSTRAINT truck_visits_operational_details_object CHECK(ISJSON(operational_details,OBJECT)=1);
CREATE TABLE dbo.container_blocks(
 container_number nvarchar(11) COLLATE Latin1_General_100_BIN2 NOT NULL PRIMARY KEY REFERENCES dbo.containers(number),
 blocked bit NOT NULL, reason nvarchar(1000) NOT NULL CHECK(LEN(TRIM(reason)) BETWEEN 3 AND 1000),
 changed_by uniqueidentifier NOT NULL REFERENCES dbo.profiles(id),
 changed_at datetimeoffset(6) NOT NULL,version int NOT NULL CHECK(version>0)
);
GO
CREATE OR ALTER FUNCTION internal.valid_container_number(@number nvarchar(64)) RETURNS bit AS
BEGIN
 IF @number IS NULL OR DATALENGTH(@number)<>22 OR @number COLLATE Latin1_General_100_BIN2 NOT LIKE N'[A-Z][A-Z][A-Z][A-Z][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' RETURN 0;
 DECLARE @sum int=0,@index int=1,@code int,@value int,@weight int=1;
 WHILE @index<=10 BEGIN
  SET @code=UNICODE(SUBSTRING(@number,@index,1));
  SET @value=CASE WHEN @index>4 THEN @code-48 ELSE 10+@code-65+(10+@code-65-1)/10 END;
  SET @sum=@sum+@value*@weight;SET @weight=@weight*2;SET @index=@index+1;
 END;
 RETURN CASE WHEN (@sum%11)%10=UNICODE(RIGHT(@number,1))-48 THEN 1 ELSE 0 END;
END;
GO
CREATE OR ALTER PROCEDURE internal.validate_operational_details @Details nvarchar(max) AS
BEGIN
 SET NOCOUNT ON;
 IF ISJSON(@Details,OBJECT)<>1 OR @Details IS NULL THROW 51004, 'Operational details must be a JSON object.', 1;
 IF EXISTS(SELECT 1 FROM OPENJSON(@Details) WHERE type<>1 OR
  DATALENGTH(value)/2>CASE [key] COLLATE Latin1_General_100_BIN2
   WHEN N'haulier' THEN 100 WHEN N'lane' THEN 40 WHEN N'lane_2' THEN 40
   WHEN N'seal_number' THEN 60 WHEN N'seal_number_2' THEN 60
   WHEN N'damage_reservations' THEN 1000 WHEN N'damage_reservations_2' THEN 1000 ELSE -1 END)
  OR EXISTS(SELECT 1 FROM OPENJSON(@Details) GROUP BY [key] COLLATE Latin1_General_100_BIN2 HAVING COUNT(*)>1)
  THROW 51004, 'Unknown, duplicate or invalid operational field.', 1;
END;
GO
-- All lifecycle writers serialize under this transaction-owned lock. Parent orders
-- are then locked before items, matching the existing quantity/order editor.
CREATE OR ALTER PROCEDURE internal.gate_lock @VisitId uniqueidentifier=NULL,
 @Item1 uniqueidentifier=NULL,@Item2 uniqueidentifier=NULL AS
BEGIN
 SET NOCOUNT ON;
 IF @@TRANCOUNT=0 THROW 51004, 'Gate operation requires a transaction.', 1;
 DECLARE @result int,@id uniqueidentifier,@unused uniqueidentifier;
 EXEC @result=sys.sp_getapplock @Resource=N'zenata-gate-lifecycle',@LockMode=N'Exclusive',@LockOwner=N'Transaction',@LockTimeout=10000;
 IF @result<0 THROW 51009, 'Gate operation busy. Refresh and retry.', 1;
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
END;
GO
CREATE OR ALTER PROCEDURE internal.record_gate_event @VisitId uniqueidentifier,@Action nvarchar(64),
 @ActorId uniqueidentifier,@At datetimeoffset(6),@Details nvarchar(max)=N'{}',@Before nvarchar(max)=NULL AS
BEGIN
 SET NOCOUNT ON;
 IF @@TRANCOUNT=0 THROW 51004, 'Event requires transaction.', 1;
 DECLARE @event bigint,@snapshot nvarchar(max),@agent nvarchar(max);
 SELECT @agent=COALESCE(NULLIF(TRIM(CONCAT(first_name,N' ',last_name)),N''),NULLIF(display_name,N''),CONVERT(nvarchar(36),id)) FROM dbo.profiles WHERE id=@ActorId;
 SELECT @snapshot=(SELECT v.*,JSON_QUERY(@Details) AS [event],@agent AS agent_name FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER) FROM dbo.truck_visits v WHERE id=@VisitId;
 -- Read the object directly, avoiding JSON_VALUE's 4000-character scalar limit.
 SELECT @snapshot=JSON_MODIFY(@snapshot,N'$.operational_details',JSON_QUERY(operational_details)) FROM dbo.truck_visits WHERE id=@VisitId;
 INSERT dbo.visit_events(visit_id,action,occurred_at,actor_id,details) VALUES(@VisitId,@Action,@At,@ActorId,@Details);
 SET @event=CONVERT(bigint,SCOPE_IDENTITY());
 INSERT dbo.generated_documents(visit_id,event_id,kind,snapshot,created_by,created_at) VALUES(@VisitId,@event,@Action,@snapshot,@ActorId,@At);
 INSERT dbo.audit_logs(entity,entity_id,action,actor_id,occurred_at,before_data,after_data)
  VALUES(N'truck_visit',CONVERT(nvarchar(36),@VisitId),@Action,@ActorId,@At,@Before,@snapshot);
END;
GO
CREATE OR ALTER PROCEDURE api.set_container_block @ActorId uniqueidentifier,@Container nvarchar(64),
 @Blocked bit,@Reason nvarchar(max),@ExpectedVersion int AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF api.can_do(@ActorId,N'admin')=0 THROW 51003, 'Admin required.', 1;
 SET @Container=UPPER(TRIM(@Container));SET @Reason=TRIM(@Reason);
 IF internal.valid_container_number(@Container)=0 OR @Blocked IS NULL OR @ExpectedVersion IS NULL OR @ExpectedVersion<0 OR @Reason IS NULL OR LEN(@Reason)<3 OR DATALENGTH(@Reason)>2000 THROW 51004, 'Invalid container hold.', 1;
 BEGIN TRY
  BEGIN TRANSACTION;EXEC internal.gate_lock;
  IF api.can_do(@ActorId,N'admin')=0 THROW 51003, 'Admin required.', 1;
  IF NOT EXISTS(SELECT 1 FROM dbo.containers WHERE number=@Container) THROW 51002, 'Container not found.', 1;
  DECLARE @version int,@before nvarchar(max),@after nvarchar(max),@now datetimeoffset(6)=TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00');
  SELECT @version=version,@before=(SELECT b.* FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) FROM dbo.container_blocks b WITH(UPDLOCK,HOLDLOCK) WHERE container_number=@Container;
  IF COALESCE(@version,0)<>@ExpectedVersion THROW 51009, 'Hold changed. Refresh.', 1;
  IF @version IS NULL INSERT dbo.container_blocks VALUES(@Container,@Blocked,@Reason,@ActorId,@now,1);
  ELSE UPDATE dbo.container_blocks SET blocked=@Blocked,reason=@Reason,changed_by=@ActorId,changed_at=@now,version=version+1 WHERE container_number=@Container;
  SET @after=(SELECT * FROM dbo.container_blocks WHERE container_number=@Container FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
  INSERT dbo.audit_logs(entity,entity_id,action,actor_id,before_data,after_data) VALUES(N'container_block',@Container,CASE WHEN @Blocked=1 THEN N'BLOCK' ELSE N'UNBLOCK' END,@ActorId,@before,@after);
  COMMIT;SELECT @after;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK;THROW;END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE api.enter_visit @ActorId uniqueidentifier,@Plate nvarchar(max),@Cin nvarchar(max),
 @EntryKind nvarchar(8),@OrderItemId uniqueidentifier,@IsTwin bit=0,@OrderItemId2 uniqueidentifier=NULL,
 @Container nvarchar(64)=NULL,@Container2 nvarchar(64)=NULL,@Details nvarchar(max)=N'{}' AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF api.can_do(@ActorId,N'entree')=0 THROW 51003, 'Entry role required.', 1;
 EXEC internal.validate_operational_details @Details;
 SET @Plate=UPPER(TRIM(@Plate));SET @Cin=TRIM(@Cin);
 SET @Container=NULLIF(UPPER(TRIM(@Container)),N'');SET @Container2=NULLIF(UPPER(TRIM(@Container2)),N'');
 IF @Plate IS NULL OR LEN(@Plate)<2 OR DATALENGTH(@Plate)>200 OR @Cin IS NULL OR LEN(@Cin)<2 OR DATALENGTH(@Cin)>200
  OR @EntryKind IS NULL OR @EntryKind NOT IN(N'loaded',N'empty') OR @OrderItemId IS NULL OR @IsTwin IS NULL
  OR (@IsTwin=1 AND @OrderItemId2 IS NULL) OR (@IsTwin=0 AND (@OrderItemId2 IS NOT NULL OR @Container2 IS NOT NULL))
  THROW 51004, 'Invalid visit fields.', 1;
 IF @EntryKind=N'loaded' AND (internal.valid_container_number(@Container)=0 OR (@IsTwin=1 AND (internal.valid_container_number(@Container2)=0 OR @Container=@Container2))) THROW 51004, 'Invalid or duplicate ISO6346 container.', 1;
 IF @EntryKind=N'empty' AND (@Container IS NOT NULL OR @Container2 IS NOT NULL) THROW 51004, 'Select pickup containers at yard operation, not entry.', 1;
 BEGIN TRY
  BEGIN TRANSACTION;EXEC internal.gate_lock @Item1=@OrderItemId,@Item2=@OrderItemId2;
  IF api.can_do(@ActorId,N'entree')=0 THROW 51003, 'Entry role required.', 1;
  DECLARE @slots table(slot int PRIMARY KEY,item_id uniqueidentifier,number nvarchar(64) COLLATE Latin1_General_100_BIN2,
   iso nvarchar(4) COLLATE Latin1_General_100_BIN2,line nvarchar(64) COLLATE Latin1_General_100_BIN2,
   order_id uniqueidentifier,reference nvarchar(150) COLLATE Latin1_General_100_BIN2,client_id uniqueidentifier,
   client_reference nvarchar(150) COLLATE Latin1_General_100_BIN2,quantity int);
  INSERT @slots(slot,item_id,number) VALUES(1,@OrderItemId,@Container);
  IF @IsTwin=1 INSERT @slots(slot,item_id,number) VALUES(2,@OrderItemId2,@Container2);
  UPDATE s SET iso=i.iso_code,line=i.armateur_id,order_id=o.id,reference=o.reference,client_id=o.client_id,client_reference=o.client_order_reference,quantity=i.quantity
   FROM @slots s JOIN dbo.transport_order_items i ON i.id=s.item_id JOIN dbo.transport_orders o ON o.id=i.order_id
   WHERE o.active=1 AND o.direction=CASE WHEN @EntryKind=N'loaded' THEN N'RESTITUTION' ELSE N'LIVRAISON' END;
  IF EXISTS(SELECT 1 FROM @slots WHERE order_id IS NULL OR (@IsTwin=1 AND LEFT(iso,1)<>N'2')) THROW 51004, 'Order item inactive, wrong direction or invalid twin size.', 1;
  IF EXISTS(SELECT 1 FROM @slots a JOIN @slots b ON a.slot=1 AND b.slot=2 WHERE a.client_id IS DISTINCT FROM b.client_id OR a.client_reference IS DISTINCT FROM b.client_reference) THROW 51004, 'Twin items require the same business client/order.', 1;
  IF EXISTS(SELECT 1 FROM @slots s CROSS APPLY(SELECT COUNT_BIG(*) AS used FROM
    (SELECT id FROM dbo.truck_visits WHERE order_item_id=s.item_id AND canceled_at IS NULL UNION ALL
     SELECT id FROM dbo.truck_visits WHERE order_item_id_2=s.item_id AND canceled_at IS NULL) a) allocations
    WHERE allocations.used+(SELECT COUNT(*) FROM @slots x WHERE x.item_id=s.item_id)>s.quantity) THROW 51004, 'Order quantity exhausted.', 1;
  IF @EntryKind=N'loaded' AND (EXISTS(SELECT 1 FROM dbo.container_stock_intervals s JOIN @slots x ON x.number=s.container_number WHERE departed_at IS NULL)
   OR EXISTS(SELECT 1 FROM dbo.truck_visits v JOIN @slots x ON x.number=v.container_number OR x.number=v.container_number_2
     WHERE v.canceled_at IS NULL AND v.exited_at IS NULL AND ((v.entry_kind=N'loaded' AND v.engin_at IS NULL) OR (v.entry_kind=N'empty' AND v.engin_at IS NOT NULL)))) THROW 51004, 'Container already in stock or on an active truck.', 1;
  DECLARE @number nvarchar(64),@iso nvarchar(4),@line nvarchar(64),@booking uniqueidentifier=NULL,@id uniqueidentifier=NEWID(),@now datetimeoffset(6)=TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00');
  IF @EntryKind=N'loaded' BEGIN
   DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT number,iso,line FROM @slots ORDER BY number;
   OPEN c;FETCH NEXT FROM c INTO @number,@iso,@line;
   WHILE @@FETCH_STATUS=0 BEGIN
    UPDATE dbo.containers SET iso_code=@iso,armateur_id=@line WHERE number=@number;
    IF @@ROWCOUNT=0 INSERT dbo.containers(number,iso_code,armateur_id,source) VALUES(@number,@iso,@line,N'operator');
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
  EXEC internal.record_gate_event @id,N'ENTREE',@ActorId,@now;
  COMMIT;SELECT (SELECT @id AS id,1 AS version FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK;THROW;END CATCH;
END;
GO
