-- Generated from009. Only explicitly registered inherited IDs bypass NEW order allocation.
-- All stock/ISO/hold/24h/role/version checks remain in the same lifecycle transaction.
CREATE OR ALTER PROCEDURE api.move_visit @ActorId uniqueidentifier,@VisitId uniqueidentifier,@ExpectedVersion int,
 @Mode nvarchar(16),@Container nvarchar(64)=NULL,@Container2 nvarchar(64)=NULL,
 @Position nvarchar(max)=NULL,@Position2 nvarchar(max)=NULL,@Reason nvarchar(max)=NULL,@Details nvarchar(max)=N'{}' AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF @Mode IS NULL OR @Mode NOT IN(N'YARD',N'EXIT',N'EMPTY_EXIT',N'CANCEL') OR @ExpectedVersion IS NULL OR @ExpectedVersion<1 THROW 51004, 'Invalid lifecycle request.', 1;
 IF (@Mode=N'CANCEL' AND api.can_do(@ActorId,N'admin')=0)
  OR (@Mode IN(N'EXIT',N'EMPTY_EXIT') AND api.can_do(@ActorId,N'sortie')=0)
  OR (@Mode=N'YARD' AND api.can_do(@ActorId,N'engin')=0 AND api.can_do(@ActorId,N'sortie')=0) THROW 51003, 'Lifecycle permission denied.', 1;
 EXEC internal.validate_operational_details @Details;
 SET @Container=NULLIF(UPPER(TRIM(@Container)),N'');SET @Container2=NULLIF(UPPER(TRIM(@Container2)),N'');
 SET @Position=NULLIF(TRIM(@Position),N'');SET @Position2=NULLIF(TRIM(@Position2),N'');SET @Reason=TRIM(@Reason);
 IF DATALENGTH(@Position)>2000 OR DATALENGTH(@Position2)>2000 THROW 51004, 'Position too long.', 1;
 IF @Mode=N'CANCEL' AND (@Reason IS NULL OR LEN(@Reason)<3 OR DATALENGTH(@Reason)>2000) THROW 51004, 'Cancellation reason required.', 1;
 BEGIN TRY
  BEGIN TRANSACTION;EXEC internal.gate_lock @VisitId=@VisitId;
  IF (@Mode=N'CANCEL' AND api.can_do(@ActorId,N'admin')=0)
   OR (@Mode IN(N'EXIT',N'EMPTY_EXIT') AND api.can_do(@ActorId,N'sortie')=0)
   OR (@Mode=N'YARD' AND api.can_do(@ActorId,N'engin')=0 AND api.can_do(@ActorId,N'sortie')=0) THROW 51003, 'Lifecycle permission denied.', 1;
  DECLARE @kind nvarchar(8),@version int,@twin bit,@engin datetimeoffset(6),@closed datetimeoffset(6),@canceled datetimeoffset(6),@controlled bit,
   @before nvarchar(max),@merged nvarchar(max),@now datetimeoffset(6)=TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00');
  SELECT @kind=entry_kind,@version=version,@twin=is_twin,@engin=engin_at,@closed=exited_at,@canceled=canceled_at,@controlled=order_controlled,@merged=operational_details,
    @before=(SELECT v.* FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER)
    FROM dbo.truck_visits v WITH(UPDLOCK,HOLDLOCK) WHERE id=@VisitId;
  IF @version IS NULL THROW 51002, 'Visit not found.', 1;
  IF @version<>@ExpectedVersion THROW 51009, 'Visit changed. Refresh.', 1;
  IF @closed IS NOT NULL OR @canceled IS NOT NULL THROW 51004, 'Visit already closed.', 1;
  IF @twin=0 AND (@Container2 IS NOT NULL OR @Position2 IS NOT NULL) THROW 51004, 'Second slot was not reserved.', 1;
  IF @Mode IN(N'CANCEL',N'EMPTY_EXIT') BEGIN
   IF @engin IS NOT NULL OR (@Mode=N'EMPTY_EXIT' AND @kind<>N'empty') THROW 51004, 'Cannot cancel a completed physical movement.', 1;
   IF @Mode=N'EMPTY_EXIT' SET @Reason=N'Sortie sans prise de conteneur (ressorti a vide)';
   UPDATE dbo.truck_visits SET canceled_at=@now,canceled_by=@ActorId,cancel_reason=@Reason,version=version+1 WHERE id=@VisitId;
   DECLARE @cancelDetails nvarchar(max)=(SELECT @Reason AS reason FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
   EXEC internal.record_gate_event @VisitId,N'ANNULATION',@ActorId,@now,@cancelDetails,@before;
  END ELSE BEGIN
   IF @controlled=0 AND NOT EXISTS(SELECT 1 FROM internal.legacy_imported_visits WHERE visit_id=@VisitId) THROW 51004, 'Unregistered legacy visit; import provenance required.', 1;
   IF @controlled=1 AND EXISTS(SELECT 1 FROM dbo.truck_visits v CROSS APPLY(VALUES(v.order_item_id,v.iso_code,v.armateur_id),(CASE WHEN v.is_twin=1 THEN v.order_item_id_2 END,v.iso_code_2,v.armateur_id_2)) x(item,iso,line)
    LEFT JOIN dbo.transport_order_items i ON i.id=x.item LEFT JOIN dbo.transport_orders o ON o.id=i.order_id
    WHERE v.id=@VisitId AND (x.item IS NOT NULL OR x.iso IS NOT NULL) AND
     (i.id IS NULL OR o.active=0 OR x.iso IS DISTINCT FROM i.iso_code OR x.line IS DISTINCT FROM i.armateur_id OR o.direction<>CASE WHEN @kind=N'loaded' THEN N'RESTITUTION' ELSE N'LIVRAISON' END))
     THROW 51004, 'Reserved order, carrier or ISO changed.', 1;
   DECLARE @key nvarchar(100),@value nvarchar(max);
   DECLARE detail_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT [key],value FROM OPENJSON(@Details);
   OPEN detail_cursor;FETCH NEXT FROM detail_cursor INTO @key,@value;
   WHILE @@FETCH_STATUS=0 BEGIN
    SET @merged=JSON_MODIFY(@merged,N'$.'+@key,@value);FETCH NEXT FROM detail_cursor INTO @key,@value;
   END;CLOSE detail_cursor;DEALLOCATE detail_cursor;
   UPDATE dbo.truck_visits SET operational_details=@merged WHERE id=@VisitId;
   DECLARE @slots table(slot int PRIMARY KEY,number nvarchar(64) COLLATE Latin1_General_100_BIN2,
    iso nvarchar(4) COLLATE Latin1_General_100_BIN2,line nvarchar(64) COLLATE Latin1_General_100_BIN2,position nvarchar(max),stock_id uniqueidentifier);
   INSERT @slots(slot,number,iso,line,position)
    SELECT 1,CASE WHEN @kind=N'empty' AND @engin IS NULL THEN @Container ELSE container_number END,iso_code,armateur_id,@Position FROM dbo.truck_visits WHERE id=@VisitId;
   IF @twin=1 INSERT @slots(slot,number,iso,line,position)
    SELECT 2,CASE WHEN @kind=N'empty' AND @engin IS NULL THEN @Container2 ELSE container_number_2 END,iso_code_2,armateur_id_2,@Position2 FROM dbo.truck_visits WHERE id=@VisitId;
   IF EXISTS(SELECT 1 FROM @slots WHERE internal.valid_container_number(number)=0 OR iso IS NULL OR line IS NULL)
    OR EXISTS(SELECT number FROM @slots GROUP BY number HAVING COUNT(*)>1) THROW 51004, 'Distinct valid container numbers required for every reserved slot.', 1;
   IF @twin=1 AND EXISTS(SELECT 1 FROM @slots WHERE LEFT(iso,1)<>N'2') THROW 51004, 'Twin requires two 20-foot containers.', 1;
   -- Once loaded/picked up, callers cannot replace the archived identity at exit.
   IF (@kind=N'loaded' OR @engin IS NOT NULL) AND
    ((@Container IS NOT NULL AND @Container<>(SELECT number FROM @slots WHERE slot=1)) OR (@Container2 IS NOT NULL AND @Container2<>(SELECT number FROM @slots WHERE slot=2))) THROW 51004, 'Container identity is immutable after movement.', 1;
   IF @kind=N'empty' AND EXISTS(SELECT 1 FROM @slots s JOIN dbo.container_blocks b ON b.container_number=s.number WHERE b.blocked=1) THROW 51004, 'Container blocked: delivery prohibited.', 1;
   IF @engin IS NULL BEGIN
    IF @kind=N'loaded' BEGIN
     IF EXISTS(SELECT 1 FROM @slots s JOIN dbo.container_stock_intervals c ON c.container_number=s.number WHERE c.departed_at IS NULL) THROW 51004, 'Container already in stock.', 1;
     INSERT dbo.container_stock_intervals(container_number,client_id,armateur_id,iso_code,start_visit_id,arrived_at,position)
      SELECT s.number,v.client_id,s.line,s.iso,@VisitId,@now,s.position FROM @slots s CROSS JOIN dbo.truck_visits v WHERE v.id=@VisitId;
    END ELSE BEGIN
     UPDATE s SET stock_id=c.id FROM @slots s JOIN dbo.container_stock_intervals c WITH(UPDLOCK,HOLDLOCK)
      ON c.container_number=s.number AND c.departed_at IS NULL
      JOIN dbo.truck_visits received ON received.id=c.start_visit_id
      JOIN dbo.containers registered ON registered.number=c.container_number
      WHERE c.iso_code=s.iso AND c.armateur_id=s.line AND registered.iso_code=s.iso AND registered.armateur_id=s.line
       AND received.entry_kind=N'loaded' AND received.canceled_at IS NULL AND @now>=DATEADD(hour,24,received.entered_at);
     IF EXISTS(SELECT 1 FROM @slots WHERE stock_id IS NULL) THROW 51004, 'Stock absent, ISO/carrier incompatible or less than 24 hours since truck entry.', 1;
     UPDATE c SET departed_at=@now,end_visit_id=@VisitId FROM dbo.container_stock_intervals c JOIN @slots s ON s.stock_id=c.id;
     UPDATE dbo.truck_visits SET container_number=(SELECT number FROM @slots WHERE slot=1),container_number_2=(SELECT number FROM @slots WHERE slot=2) WHERE id=@VisitId;
    END;
    INSERT dbo.yard_operations(visit_id,kind,container_number,position,performed_at,performed_by)
     SELECT @VisitId,CASE WHEN @kind=N'loaded' THEN N'depose' ELSE N'prise' END,number,position,@now,@ActorId FROM @slots WHERE slot=1;
    UPDATE dbo.truck_visits SET engin_at=@now,engin_by=@ActorId,version=version+1 WHERE id=@VisitId;
    DECLARE @action nvarchar(64)=CASE WHEN @kind=N'loaded' THEN N'DEPOSE' ELSE N'PRISE' END;
    EXEC internal.record_gate_event @VisitId,@action,@ActorId,@now,N'{}',@before;
   END ELSE IF @Mode=N'YARD' THROW 51004, 'Yard operation already performed.', 1;
   -- A receiving truck is closed only after both stock insertions succeed.
   IF @kind=N'loaded' OR @Mode=N'EXIT' BEGIN
    IF @kind=N'loaded' AND EXISTS(SELECT 1 FROM @slots s WHERE NOT EXISTS(SELECT 1 FROM dbo.container_stock_intervals c WHERE c.container_number=s.number AND c.start_visit_id=@VisitId)) THROW 51004, 'Deposit incomplete.', 1;
    SELECT @before=(SELECT v.* FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER) FROM dbo.truck_visits v WHERE id=@VisitId;
    UPDATE dbo.truck_visits SET exited_at=@now,exited_by=@ActorId,version=version+1 WHERE id=@VisitId;
    DECLARE @exitDetails nvarchar(max)=CASE WHEN @kind=N'loaded' THEN N'{"automatic":true,"reason":"Cloture apres restitution","physical_exit_observed":false}' ELSE N'{}' END;
    EXEC internal.record_gate_event @VisitId,N'SORTIE',@ActorId,@now,@exitDetails,@before;
   END;
  END;
  DECLARE @response nvarchar(max)=(SELECT id,version,engin_at,exited_at,canceled_at FROM dbo.truck_visits WHERE id=@VisitId FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER);
  COMMIT;SELECT @response;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK;THROW;END CATCH;
END;
GO
