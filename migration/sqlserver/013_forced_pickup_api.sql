-- Complete the application API upgrade in the same transaction as 012.
SET NOCOUNT ON;
IF @@TRANCOUNT=0 THROW 51000, 'Use the transactional application upgrade wrapper.', 1;
GO
CREATE OR ALTER PROCEDURE api.force_pickup @ActorId uniqueidentifier,@VisitId uniqueidentifier,@ExpectedVersion int,@Container nvarchar(64),@Reason nvarchar(max) AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 SET @Container=UPPER(TRIM(@Container));SET @Reason=TRIM(@Reason);
 IF api.can_do(@ActorId,N'admin')=0 THROW 51003, 'Admin required.', 1;
 IF internal.valid_container_number(@Container)=0 OR @Reason IS NULL OR LEN(@Reason)<10 OR DATALENGTH(@Reason)>2000 OR @ExpectedVersion IS NULL OR @ExpectedVersion<1 THROW 51004, 'Valid number, detailed reason and version required.', 1;
 BEGIN TRY
  BEGIN TRANSACTION;EXEC internal.gate_lock @VisitId=@VisitId;
  IF api.can_do(@ActorId,N'admin')=0 THROW 51003, 'Admin required.', 1;
  DECLARE @version int,@iso nvarchar(4),@line nvarchar(64),@before nvarchar(max),@now datetimeoffset(6)=TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00'),@id uniqueidentifier=NEWID();
  SELECT @version=version,@iso=iso_code,@line=armateur_id,@before=(SELECT v.* FOR JSON PATH,WITHOUT_ARRAY_WRAPPER)
   FROM dbo.truck_visits v WITH(UPDLOCK,HOLDLOCK) WHERE id=@VisitId AND entry_kind=N'empty' AND is_twin=0 AND order_controlled=1 AND engin_at IS NULL AND exited_at IS NULL AND canceled_at IS NULL;
  IF @version IS NULL THROW 51004, 'A pending single-container, order-controlled delivery is required.', 1;
  IF @version<>@ExpectedVersion THROW 51009, 'Visit changed. Refresh.', 1;
  IF NOT EXISTS(SELECT 1 FROM dbo.truck_visits v JOIN dbo.transport_order_items i ON i.id=v.order_item_id JOIN dbo.transport_orders o ON o.id=i.order_id
   WHERE v.id=@VisitId AND o.active=1 AND o.direction=N'LIVRAISON' AND i.iso_code=@iso AND i.armateur_id=@line) THROW 51004, 'Reserved order no longer matches.', 1;
  IF EXISTS(SELECT 1 FROM dbo.container_stock_intervals WHERE container_number=@Container AND departed_at IS NULL) THROW 51004, 'Container is in stock: use normal pickup.', 1;
  IF EXISTS(SELECT 1 FROM dbo.container_blocks WHERE container_number=@Container AND blocked=1) THROW 51004, 'Container is blocked.', 1;
  IF EXISTS(SELECT 1 FROM dbo.truck_visits WHERE entry_kind=N'loaded' AND canceled_at IS NULL AND (container_number=@Container OR container_number_2=@Container) AND @now<DATEADD(hour,24,entered_at)) THROW 51004, '24-hour receiving delay still applies.', 1;
  IF EXISTS(SELECT 1 FROM dbo.truck_visits WHERE id<>@VisitId AND canceled_at IS NULL AND exited_at IS NULL AND (container_number=@Container OR container_number_2=@Container)) THROW 51009, 'Container active on another visit.', 1;
  IF EXISTS(SELECT 1 FROM dbo.containers WHERE number=@Container AND (iso_code<>@iso OR armateur_id<>@line)) THROW 51004, 'Container ISO/carrier mismatch.', 1;
  IF NOT EXISTS(SELECT 1 FROM dbo.containers WHERE number=@Container) INSERT dbo.containers(number,iso_code,armateur_id,source) VALUES(@Container,@iso,@line,N'manual');
  INSERT dbo.yard_operations(visit_id,kind,container_number,performed_by,performed_at) VALUES(@VisitId,N'prise',@Container,@ActorId,@now);
  UPDATE dbo.truck_visits SET container_number=@Container,engin_at=@now,engin_by=@ActorId,version=version+1 WHERE id=@VisitId;
  INSERT dbo.forced_container_actions(id,visit_id,container_number,action,reason,actor_id,occurred_at) VALUES(@id,@VisitId,@Container,N'PRISE_SANS_STOCK',@Reason,@ActorId,@now);
  DECLARE @details nvarchar(max)=(SELECT @Container container,CONVERT(bit,1) forced,@Reason reason FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
  EXEC internal.record_gate_event @VisitId,N'PRISE',@ActorId,@now,@details,@before;
  DECLARE @result nvarchar(max)=(SELECT @id id,@version+1 version FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
  COMMIT;SELECT @result;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK;THROW;END CATCH;
END;
GO
INSERT internal.schema_versions(version) VALUES(6);
GO
