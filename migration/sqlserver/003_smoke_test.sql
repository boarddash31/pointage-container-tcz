-- DBA integration checks, ONLY on a fresh test database whose name ends in _Test.
-- Execute with sqlcmd -b. Every fixture is rolled back, including on failure.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() NOT LIKE N'%[_]Test' THROW 51000, 'Use a dedicated _Test database.', 1;
IF NOT EXISTS(SELECT 1 FROM internal.schema_versions WHERE version=2) THROW 51000, 'Apply versions 1 and 2 first.', 1;
IF EXISTS(SELECT 1 FROM dbo.profiles) THROW 51000, 'Run smoke checks on an empty test database before importing data.', 1;
GO
-- First happy path: stable IDs, ERO/EDO direction, two carriers, increment and versioned edit.
BEGIN TRY
  BEGIN TRANSACTION;
  DECLARE @actor uniqueidentifier=NEWID(),@carrier nvarchar(64)=N'QA-'+CONVERT(nvarchar(36),NEWID()),
    @second nvarchar(64)=N'QA-'+CONVERT(nvarchar(36),NEWID()),@reference nvarchar(150)=N'QA-'+CONVERT(nvarchar(36),NEWID());
  INSERT dbo.profiles(id,display_name) VALUES(@actor,N'Migration test clerk');
  INSERT dbo.user_roles VALUES(@actor,N'entree');
  INSERT dbo.armateurs(id,name) VALUES(@carrier,N'Test carrier 1'),(@second,N'Test carrier 2');
  DECLARE @items nvarchar(max)=(SELECT iso_code,armateur_id,quantity FROM
    (SELECT N'22G1' iso_code,@carrier armateur_id,2 quantity UNION ALL SELECT N'22G1',@second,3) entries FOR JSON PATH);
  DECLARE @response table(payload nvarchar(max));
  INSERT @response EXEC api.create_order @actor,N'ERO',@reference,@items;
  DECLARE @order uniqueidentifier=CONVERT(uniqueidentifier,(SELECT JSON_VALUE(payload,'$.id') FROM @response));
  IF NOT EXISTS(SELECT 1 FROM dbo.transport_orders WHERE id=@order AND kind=N'ERO' AND direction=N'RESTITUTION') THROW 51099, 'ERO direction failed.', 1;
  DECLARE @item uniqueidentifier=(SELECT id FROM dbo.transport_order_items WHERE order_id=@order AND armateur_id=@carrier);
  DELETE @response;
  INSERT @response EXEC api.increase_order_quantity @actor,@item,5;
  IF (SELECT quantity FROM dbo.transport_order_items WHERE id=@item)<>7 THROW 51099, 'Increment failed.', 1;
  DECLARE @version int=(SELECT version FROM dbo.transport_orders WHERE id=@order);
  SET @items=(SELECT id,iso_code,armateur_id,quantity FROM dbo.transport_order_items WHERE order_id=@order FOR JSON PATH);
  DELETE @response;
  INSERT @response EXEC api.update_order @actor,@order,@version,@items;
  IF (SELECT version FROM dbo.transport_orders WHERE id=@order)<>@version+1 THROW 51099, 'Edit version failed.', 1;
  IF NOT EXISTS(SELECT 1 FROM dbo.transport_order_items WHERE id=@item AND order_id=@order) THROW 51099, 'Item identity changed.', 1;
  IF (SELECT COUNT(*) FROM dbo.audit_logs WHERE entity_id=CONVERT(nvarchar(36),@order))<>3 THROW 51099, 'Audit count failed.', 1;
  DELETE @response;
  SET @reference=@reference+N'-EDO';
  SET @items=(SELECT N'22G1' iso_code,@carrier armateur_id,1 quantity FOR JSON PATH);
  INSERT @response EXEC api.create_order @actor,N'EDO',@reference,@items;
  IF NOT EXISTS(SELECT 1 FROM dbo.transport_orders WHERE reference=@reference AND direction=N'LIVRAISON') THROW 51099, 'EDO direction failed.', 1;
  ROLLBACK;
  PRINT 'PASS: order directions, multi-carrier items, increments, stable IDs, versions and audit; fixtures rolled back.';
END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
GO
-- Unique reference is global, including case and surrounding spaces.
BEGIN TRY
  BEGIN TRANSACTION;
  DECLARE @carrier nvarchar(64)=N'QA-'+CONVERT(nvarchar(36),NEWID()),@reference nvarchar(150)=N'QA-'+CONVERT(nvarchar(36),NEWID());
  INSERT dbo.armateurs(id,name) VALUES(@carrier,N'Test carrier');
  INSERT dbo.transport_orders(kind,direction,reference,armateur_id) VALUES(N'ERO',N'RESTITUTION',@reference,@carrier);
  INSERT dbo.transport_orders(kind,direction,reference,armateur_id) VALUES(N'EDO',N'LIVRAISON',N' '+LOWER(@reference)+N' ',@carrier);
  THROW 51099, 'Global uniqueness was not enforced.', 1;
END TRY BEGIN CATCH
  DECLARE @error int=ERROR_NUMBER(); IF @@TRANCOUNT>0 ROLLBACK;
  IF @error NOT IN (2601,2627) THROW;
  PRINT 'PASS: global normalized reference; fixtures rolled back.';
END CATCH;
GO
-- Permission denial must apply even if the caller supplies an existing profile ID.
BEGIN TRY
  BEGIN TRANSACTION;
  DECLARE @viewer uniqueidentifier=NEWID();
  INSERT dbo.profiles(id,display_name) VALUES(@viewer,N'Test viewer');
  INSERT dbo.user_roles VALUES(@viewer,N'viewer');
  EXEC api.create_order @viewer,N'ERO',N'QA-NOT-AUTHORIZED',N'[]';
  THROW 51099, 'Viewer created an order.', 1;
END TRY BEGIN CATCH
  DECLARE @error int=ERROR_NUMBER(); IF @@TRANCOUNT>0 ROLLBACK;
  IF @error<>51003 THROW;
  PRINT 'PASS: viewer denied; fixtures rolled back.';
END CATCH;
GO
-- The delivery guard starts from the receiving truck entry, regardless of stock arrival.
BEGIN TRY
  BEGIN TRANSACTION;
  DECLARE @actor uniqueidentifier=NEWID(),@visit uniqueidentifier=NEWID(),@carrier nvarchar(64)=N'QA-'+CONVERT(nvarchar(36),NEWID()),
    @entered datetimeoffset(6)=TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00'),@stock uniqueidentifier=NEWID();
  INSERT dbo.profiles(id,display_name) VALUES(@actor,N'Test stock actor');
  INSERT dbo.armateurs(id,name) VALUES(@carrier,N'Test carrier');
  INSERT dbo.containers(number,iso_code,armateur_id) VALUES(N'CSQU3054383',N'22G1',@carrier);
  INSERT dbo.truck_visits(id,plate,driver_cin,entry_kind,container_number,iso_code,armateur_id,entered_by,entered_at)
    VALUES(@visit,N'QA-TEST',N'QA-TEST',N'loaded',N'CSQU3054383',N'22G1',@carrier,@actor,@entered);
  INSERT dbo.container_stock_intervals(id,container_number,armateur_id,iso_code,start_visit_id,arrived_at)
    VALUES(@stock,N'CSQU3054383',@carrier,N'22G1',@visit,@entered);
  UPDATE dbo.container_stock_intervals SET departed_at=DATEADD(hour,24,@entered) WHERE id=@stock;
  -- Changing this accepted boundary to one second earlier must be rejected.
  UPDATE dbo.container_stock_intervals SET departed_at=DATEADD(second,86399,@entered) WHERE id=@stock;
  THROW 51099, 'Delivery before 24 hours was accepted.', 1;
END TRY BEGIN CATCH
  DECLARE @error int=ERROR_NUMBER(); IF @@TRANCOUNT>0 ROLLBACK;
  IF @error<>51004 THROW;
  PRINT 'PASS: exact 24-hour boundary accepted; earlier delivery rejected; fixtures rolled back.';
END CATCH;
GO
