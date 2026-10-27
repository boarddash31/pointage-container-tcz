-- First API slice. Apply after 001_schema.sql using the DBA deployment identity.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF NOT EXISTS(SELECT 1 FROM internal.schema_versions WHERE version=1) THROW 51000, 'Schema version 1 is required.', 1;
IF EXISTS(SELECT 1 FROM internal.schema_versions WHERE version=2) THROW 51000, 'Version 2 is already installed.', 1;
GO
CREATE OR ALTER FUNCTION api.can_do(@actor uniqueidentifier,@permission nvarchar(16)) RETURNS bit AS
BEGIN
  RETURN CASE WHEN EXISTS(SELECT 1 FROM dbo.profiles p JOIN dbo.user_roles r ON r.user_id=p.id
    WHERE p.id=@actor AND p.active=1 AND (r.role=N'admin' OR r.role=@permission OR @permission=N'read')) THEN 1 ELSE 0 END;
END;
GO
CREATE OR ALTER FUNCTION api.parse_items(@items nvarchar(max)) RETURNS TABLE AS RETURN
  SELECT id,UPPER(TRIM(iso_code)) iso_code,armateur_id,quantity
  FROM OPENJSON(@items) WITH(id uniqueidentifier '$.id',iso_code nvarchar(max) '$.iso_code',
    armateur_id nvarchar(max) '$.armateur_id',quantity int '$.quantity');
GO
CREATE OR ALTER PROCEDURE api.resolve_actor @Issuer nvarchar(256),@Subject nvarchar(256) AS
BEGIN
  SET NOCOUNT ON;
  SELECT a.user_id FROM internal.identity_accounts a JOIN dbo.profiles p ON p.id=a.user_id
    WHERE a.issuer=@Issuer AND a.subject=@Subject AND a.active=1 AND p.active=1;
END;
GO
CREATE OR ALTER PROCEDURE api.user_context @ActorId uniqueidentifier AS
BEGIN
  SET NOCOUNT ON;
  IF api.can_do(@ActorId,N'read')=0 THROW 51003, 'Access denied.', 1;
  SELECT (SELECT p.id,p.display_name,p.first_name,p.last_name,p.phone,p.active,
    JSON_QUERY((SELECT role FROM dbo.user_roles WHERE user_id=p.id FOR JSON PATH)) roles
    FROM dbo.profiles p WHERE p.id=@ActorId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
END;
GO
CREATE OR ALTER PROCEDURE api.operators @ActorId uniqueidentifier AS
BEGIN
  SET NOCOUNT ON;
  IF api.can_do(@ActorId,N'read')=0 THROW 51003, 'Access denied.', 1;
  SELECT (SELECT id,name,bic FROM dbo.armateurs WHERE active=1 ORDER BY name FOR JSON PATH);
END;
GO
CREATE OR ALTER PROCEDURE api.order_items_status @ActorId uniqueidentifier,@Direction nvarchar(16)=NULL AS
BEGIN
  SET NOCOUNT ON;
  IF api.can_do(@ActorId,N'read')=0 THROW 51003, 'Access denied.', 1;
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
END;
GO
CREATE OR ALTER PROCEDURE api.validate_items @Items nvarchar(max) AS
BEGIN
  SET NOCOUNT ON;
  IF ISJSON(@Items)<>1 OR LEFT(TRIM(@Items),1)<>N'[' THROW 51004, 'Items must be a JSON array.', 1;
  IF (SELECT COUNT(*) FROM api.parse_items(@Items)) NOT BETWEEN 1 AND 50 THROW 51004, 'Provide 1 to 50 items.', 1;
  IF EXISTS(SELECT 1 FROM OPENJSON(@Items) i WHERE i.type<>5 OR NOT EXISTS(
    SELECT 1 FROM OPENJSON(i.value) p WHERE p.[key]=N'quantity' AND p.type=2 AND p.value NOT LIKE N'%[^0-9]%' COLLATE Latin1_General_100_BIN2))
    THROW 51004, 'Each item requires an integer quantity.', 1;
  IF EXISTS(SELECT 1 FROM api.parse_items(@Items) WHERE iso_code IS NULL OR LEN(iso_code)<>4
    OR iso_code COLLATE Latin1_General_100_BIN2 LIKE N'%[^0-9A-Z]%'
    OR quantity IS NULL OR quantity NOT BETWEEN 1 AND 1000000 OR armateur_id IS NULL OR LEN(armateur_id)>64
    OR DATALENGTH(armateur_id)<>DATALENGTH(TRIM(armateur_id)))
    THROW 51004, 'Invalid item ISO, carrier or quantity.', 1;
  IF EXISTS(SELECT 1 FROM api.parse_items(@Items) GROUP BY armateur_id,iso_code HAVING COUNT(*)>1)
    THROW 51004, 'An item already exists for this carrier and ISO.', 1;
END;
GO
CREATE OR ALTER PROCEDURE api.create_order @ActorId uniqueidentifier,@Kind nvarchar(32),@Reference nvarchar(max),@Items nvarchar(max) AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  IF api.can_do(@ActorId,N'entree')=0 THROW 51003, 'Order creation denied.', 1;
  IF @Kind NOT IN (N'EDO',N'ERO') OR @Kind IS NULL THROW 51004, 'Only EDO and ERO can be created.', 1;
  SET @Reference=UPPER(TRIM(@Reference));
  IF @Reference IS NULL OR LEN(@Reference) NOT BETWEEN 1 AND 150 THROW 51004, 'Reference is required, up to 150 characters.', 1;
  EXEC api.validate_items @Items;
  IF EXISTS(SELECT 1 FROM api.parse_items(@Items) i LEFT JOIN dbo.armateurs a ON a.id=i.armateur_id WHERE a.id IS NULL OR a.active=0)
    THROW 51004, 'Active carrier required.', 1;
  IF EXISTS(SELECT 1 FROM api.parse_items(@Items) WHERE id IS NOT NULL) THROW 51004, 'New items cannot supply existing IDs.', 1;
  BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @id uniqueidentifier=NEWID(),@carrier nvarchar(64)=(SELECT TOP(1) armateur_id FROM api.parse_items(@Items) ORDER BY armateur_id,iso_code);
    INSERT dbo.transport_orders(id,kind,direction,reference,armateur_id,created_by,updated_by)
      VALUES(@id,@Kind,CASE WHEN @Kind=N'EDO' THEN N'LIVRAISON' ELSE N'RESTITUTION' END,@Reference,@carrier,@ActorId,@ActorId);
    INSERT dbo.transport_order_items(order_id,armateur_id,iso_code,quantity)
      SELECT @id,armateur_id,iso_code,quantity FROM api.parse_items(@Items);
    INSERT dbo.audit_logs(entity,entity_id,action,actor_id,after_data)
      VALUES(N'transport_order',CONVERT(nvarchar(36),@id),N'CREATION',@ActorId,
        (SELECT @Reference reference,@Kind kind,JSON_QUERY(@Items) items FOR JSON PATH,WITHOUT_ARRAY_WRAPPER));
    COMMIT;
    SELECT (SELECT @id id,1 version FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
  END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
GO
CREATE OR ALTER TRIGGER dbo.protect_order_item_history ON dbo.transport_order_items AFTER UPDATE,DELETE AS
BEGIN
  SET NOCOUNT ON;
  IF EXISTS(SELECT 1 FROM deleted d LEFT JOIN inserted i ON i.id=d.id
    WHERE (i.id IS NULL OR i.order_id<>d.order_id OR i.armateur_id<>d.armateur_id OR i.iso_code<>d.iso_code)
      AND EXISTS(SELECT 1 FROM dbo.truck_visits WHERE order_item_id=d.id OR order_item_id_2=d.id))
    THROW 51004, 'Used items cannot be removed or change order, carrier or ISO.', 1;
  IF EXISTS(SELECT 1 FROM inserted i CROSS APPLY(SELECT COUNT_BIG(*) allocated FROM (
    SELECT id FROM dbo.truck_visits WHERE order_item_id=i.id AND canceled_at IS NULL
    UNION ALL SELECT id FROM dbo.truck_visits WHERE order_item_id_2=i.id AND canceled_at IS NULL) a) q WHERE i.quantity<q.allocated)
    THROW 51004, 'Quantity is below the reserved or completed total.', 1;
END;
GO
CREATE OR ALTER TRIGGER dbo.protect_delivery_age ON dbo.container_stock_intervals AFTER INSERT,UPDATE AS
BEGIN
  SET NOCOUNT ON;
  IF EXISTS(SELECT 1 FROM inserted i LEFT JOIN deleted d ON d.id=i.id JOIN dbo.truck_visits received ON received.id=i.start_visit_id
    WHERE i.departed_at IS NOT NULL AND (d.departed_at IS NULL OR i.departed_at<>d.departed_at)
      AND (received.entry_kind<>N'loaded' OR i.departed_at<DATEADD(hour,24,received.entered_at)))
    THROW 51004, 'Delivery requires 24 hours from the receiving truck entry.', 1;
END;
GO
CREATE OR ALTER PROCEDURE api.increase_order_quantity @ActorId uniqueidentifier,@ItemId uniqueidentifier,@Quantity int AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  IF api.can_do(@ActorId,N'entree')=0 THROW 51003, 'Order modification denied.', 1;
  IF @Quantity IS NULL OR @Quantity NOT BETWEEN 1 AND 1000000 THROW 51004, 'Positive quantity required.', 1;
  BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @parent uniqueidentifier,@before int,@total int,@version int;
    SELECT @parent=order_id FROM dbo.transport_order_items WHERE id=@ItemId;
    IF @parent IS NULL THROW 51002, 'Item not found.', 1;
    SELECT @version=version FROM dbo.transport_orders WITH(UPDLOCK,HOLDLOCK) WHERE id=@parent;
    SELECT @before=quantity FROM dbo.transport_order_items WITH(UPDLOCK,HOLDLOCK) WHERE id=@ItemId;
    IF @before IS NULL THROW 51009, 'Item was removed. Refresh the order.', 1;
    IF @before+@Quantity>1000000 THROW 51004, 'Maximum total is 1000000.', 1;
    SET @total=@before+@Quantity;
    UPDATE dbo.transport_order_items SET quantity=@total WHERE id=@ItemId;
    UPDATE dbo.transport_orders SET version=version+1,updated_at=TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00'),updated_by=@ActorId WHERE id=@parent;
    INSERT dbo.audit_logs(entity,entity_id,action,actor_id,before_data,after_data)
      VALUES(N'transport_order',CONVERT(nvarchar(36),@parent),N'AJOUT_QUANTITE',@ActorId,
        (SELECT @ItemId item_id,@before quantity FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
        (SELECT @ItemId item_id,@total quantity,@Quantity added FOR JSON PATH,WITHOUT_ARRAY_WRAPPER));
    COMMIT;
    SELECT (SELECT @total quantity,@version+1 version FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
  END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE api.update_order @ActorId uniqueidentifier,@OrderId uniqueidentifier,@ExpectedVersion int,@Items nvarchar(max) AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  IF api.can_do(@ActorId,N'entree')=0 THROW 51003, 'Order modification denied.', 1;
  EXEC api.validate_items @Items;
  BEGIN TRY
    BEGIN TRANSACTION;
    SET @OrderId=COALESCE((SELECT order_id FROM internal.transport_order_aliases WHERE alias_id=@OrderId),@OrderId);
    DECLARE @version int,@before nvarchar(max),@after nvarchar(max);
    SELECT @version=version FROM dbo.transport_orders WITH(UPDLOCK,HOLDLOCK) WHERE id=@OrderId;
    IF @version IS NULL THROW 51002, 'Order not found.', 1;
    IF @ExpectedVersion IS NULL OR @version<>@ExpectedVersion THROW 51009, 'Order changed. Refresh before saving.', 1;
    DECLARE @locked int;
    SELECT @locked=COUNT(*) FROM dbo.transport_order_items WITH(UPDLOCK,HOLDLOCK) WHERE order_id=@OrderId;
    IF EXISTS(SELECT 1 FROM api.parse_items(@Items) i LEFT JOIN dbo.transport_order_items d ON d.id=i.id AND d.order_id=@OrderId WHERE i.id IS NOT NULL AND d.id IS NULL)
      THROW 51004, 'Item does not belong to this order.', 1;
    IF EXISTS(SELECT id FROM api.parse_items(@Items) WHERE id IS NOT NULL GROUP BY id HAVING COUNT(*)>1)
      THROW 51004, 'Repeated item ID.', 1;
    IF EXISTS(SELECT 1 FROM api.parse_items(@Items) i LEFT JOIN dbo.transport_order_items d ON d.id=i.id
      LEFT JOIN dbo.armateurs a ON a.id=i.armateur_id WHERE a.id IS NULL OR (a.active=0 AND (d.id IS NULL OR d.armateur_id<>i.armateur_id)))
      THROW 51004, 'Active carrier required for new or changed items.', 1;
    SET @before=(SELECT o.*,JSON_QUERY((SELECT * FROM dbo.transport_order_items WHERE order_id=@OrderId FOR JSON PATH)) items FROM dbo.transport_orders o WHERE id=@OrderId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
    -- Remove unused omitted rows before changing keys; used rows are protected by the trigger.
    DELETE d FROM dbo.transport_order_items d WHERE d.order_id=@OrderId AND NOT EXISTS(SELECT 1 FROM api.parse_items(@Items) i WHERE i.id=d.id);
    UPDATE d SET iso_code=i.iso_code,armateur_id=i.armateur_id,quantity=i.quantity
      FROM dbo.transport_order_items d JOIN api.parse_items(@Items) i ON i.id=d.id WHERE d.order_id=@OrderId;
    INSERT dbo.transport_order_items(order_id,armateur_id,iso_code,quantity)
      SELECT @OrderId,armateur_id,iso_code,quantity FROM api.parse_items(@Items) WHERE id IS NULL;
    UPDATE dbo.transport_orders SET version=version+1,updated_at=TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00'),updated_by=@ActorId WHERE id=@OrderId;
    SET @after=(SELECT o.*,JSON_QUERY((SELECT * FROM dbo.transport_order_items WHERE order_id=@OrderId FOR JSON PATH)) items FROM dbo.transport_orders o WHERE id=@OrderId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
    INSERT dbo.audit_logs(entity,entity_id,action,actor_id,before_data,after_data) VALUES(N'transport_order',CONVERT(nvarchar(36),@OrderId),N'MODIFICATION',@ActorId,@before,@after);
    COMMIT;
    SELECT (SELECT @version+1 version FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
  END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
GO
-- The API identity receives procedure execution only, never direct access to business tables.
IF DATABASE_PRINCIPAL_ID(N'pointage_api') IS NULL CREATE ROLE pointage_api;
GRANT EXECUTE ON SCHEMA::api TO pointage_api;
DENY SELECT,INSERT,UPDATE,DELETE ON SCHEMA::dbo TO pointage_api;
DENY SELECT,INSERT,UPDATE,DELETE ON SCHEMA::internal TO pointage_api;
INSERT internal.schema_versions(version) VALUES(2);
GO
