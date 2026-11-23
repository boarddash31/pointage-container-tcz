-- Generated from008. An identical entry retry replays its original result atomically.
CREATE OR ALTER PROCEDURE api.enter_visit_once @ActorId uniqueidentifier,@RequestId uniqueidentifier,@PayloadHash binary(32),@Plate nvarchar(max),@Cin nvarchar(max),
 @EntryKind nvarchar(8),@OrderItemId uniqueidentifier,@IsTwin bit=0,@OrderItemId2 uniqueidentifier=NULL,
 @Container nvarchar(64)=NULL,@Container2 nvarchar(64)=NULL,@Details nvarchar(max)=N'{}' AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF api.can_do(@ActorId,N'entree')=0 THROW 51003, 'Entry role required.', 1;
 IF @RequestId IS NULL OR @RequestId='00000000-0000-0000-0000-000000000000' OR @PayloadHash IS NULL THROW 51004, 'Entry request ID/hash required.', 1;
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
  DECLARE @cached nvarchar(max),@cachedHash binary(32);
  SELECT @cached=response_json,@cachedHash=payload_hash FROM internal.gate_entry_requests WITH(UPDLOCK,HOLDLOCK) WHERE actor_id=@ActorId AND request_id=@RequestId;
  IF @cached IS NOT NULL BEGIN
   IF @cachedHash<>@PayloadHash THROW 51009, 'Request ID reused with different entry data.', 1;
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
  DECLARE @response nvarchar(max)=(SELECT @id AS id,1 AS version FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
  INSERT internal.gate_entry_requests(actor_id,request_id,payload_hash,visit_id,response_json) VALUES(@ActorId,@RequestId,@PayloadHash,@id,@response);
  COMMIT;SELECT @response;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK;THROW;END CATCH;
END;
GO
