-- SQL engine regression checks. Dedicated EMPTY _Test database only, after gate version4.
-- Never run on toszps or after any real data/account import. All fixtures roll back.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() NOT LIKE N'%[_]Test' THROW 51000, 'Dedicated _Test database required.', 1;
IF NOT EXISTS(SELECT 1 FROM internal.schema_versions WHERE version=4) THROW 51000, 'Gate version4 required.', 1;
IF EXISTS(SELECT 1 FROM dbo.profiles) OR EXISTS(SELECT 1 FROM dbo.truck_visits) OR EXISTS(SELECT 1 FROM dbo.armateurs) OR EXISTS(SELECT 1 FROM internal.local_accounts)
 THROW 51000, 'Only an empty synthetic test database is allowed.', 1;
GO
-- twin restitution auto closes only after both stock rows
BEGIN TRY
 BEGIN TRANSACTION;

 DECLARE @actor uniqueidentifier=NEWID(),@viewer uniqueidentifier=NEWID(),@ero uniqueidentifier=NEWID(),@edo uniqueidentifier=NEWID(),
  @receive uniqueidentifier=NEWID(),@deliver uniqueidentifier=NEWID(),@wrongSize uniqueidentifier=NEWID(),@visit uniqueidentifier,@pickup uniqueidentifier,@as_backend bit=0;
 INSERT dbo.profiles(id,display_name) VALUES(@actor,N'QA Gate Admin'),(@viewer,N'QA Viewer');
 INSERT dbo.user_roles VALUES(@actor,N'admin'),(@viewer,N'viewer');
 INSERT dbo.armateurs(id,name) VALUES(N'QA_GATE',N'Fictitious gate carrier');
 INSERT dbo.transport_orders(id,kind,direction,reference,armateur_id) VALUES
  (@ero,N'ERO',N'RESTITUTION',N'QA_GATE_ERO',N'QA_GATE'),(@edo,N'EDO',N'LIVRAISON',N'QA_GATE_EDO',N'QA_GATE');
 INSERT dbo.transport_order_items(id,order_id,armateur_id,iso_code,quantity) VALUES
  (@receive,@ero,N'QA_GATE',N'22G1',2),(@deliver,@edo,N'QA_GATE',N'22G1',2),(@wrongSize,@edo,N'QA_GATE',N'42G1',1);

EXEC api.enter_visit @ActorId=@actor,@Plate=N'QA-TRUCK',@Cin=N'QA-DRIVER',@EntryKind=N'loaded',@OrderItemId=@receive,@IsTwin=1,@OrderItemId2=@receive,
 @Container=N'CSQU3054383',@Container2=N'MSCU6639870',@Details=N'{"haulier":"Fictitious haulier","seal_number":"S1","seal_number_2":"S2"}';
 SELECT @visit=id FROM dbo.truck_visits WHERE entry_kind=N'loaded' AND entered_by=@actor;
 CREATE USER qa_gate_backend WITHOUT LOGIN;
 ALTER ROLE pointage_api ADD MEMBER qa_gate_backend;
 SET @as_backend=1;
 EXECUTE AS USER=N'qa_gate_backend';
 EXEC api.move_visit @ActorId=@actor,@VisitId=@visit,@ExpectedVersion=1,@Mode=N'YARD';
 REVERT;
 SET @as_backend=0;
 IF (SELECT COUNT(*) FROM dbo.container_stock_intervals WHERE start_visit_id=@visit AND departed_at IS NULL)<>2 THROW 51099, 'Twin stock incomplete.', 1;
 IF NOT EXISTS(SELECT 1 FROM dbo.truck_visits WHERE id=@visit AND engin_at IS NOT NULL AND exited_at=engin_at AND version=3) THROW 51099, 'Automatic closure incorrect.', 1;
 IF (SELECT COUNT(*) FROM dbo.generated_documents WHERE visit_id=@visit)<>3 THROW 51099, 'Entry/deposit/exit snapshots missing.', 1;
 IF NOT EXISTS(SELECT 1 FROM dbo.generated_documents WHERE visit_id=@visit AND kind=N'SORTIE' AND JSON_VALUE(snapshot,'$.event.automatic')=N'true'
  AND JSON_VALUE(snapshot,'$.operational_details.seal_number_2')=N'S2') THROW 51099, 'Frozen twin seals or closure reason missing.', 1;
 ROLLBACK TRANSACTION;
 PRINT 'PASS: twin restitution auto closes only after both stock rows; fixtures rolled back.';
END TRY BEGIN CATCH IF @as_backend=1 REVERT;IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;THROW;END CATCH;
GO
-- delivery after receiving-truck age removes both containers
BEGIN TRY
 BEGIN TRANSACTION;

 DECLARE @actor uniqueidentifier=NEWID(),@viewer uniqueidentifier=NEWID(),@ero uniqueidentifier=NEWID(),@edo uniqueidentifier=NEWID(),
  @receive uniqueidentifier=NEWID(),@deliver uniqueidentifier=NEWID(),@wrongSize uniqueidentifier=NEWID(),@visit uniqueidentifier,@pickup uniqueidentifier,@as_backend bit=0;
 INSERT dbo.profiles(id,display_name) VALUES(@actor,N'QA Gate Admin'),(@viewer,N'QA Viewer');
 INSERT dbo.user_roles VALUES(@actor,N'admin'),(@viewer,N'viewer');
 INSERT dbo.armateurs(id,name) VALUES(N'QA_GATE',N'Fictitious gate carrier');
 INSERT dbo.transport_orders(id,kind,direction,reference,armateur_id) VALUES
  (@ero,N'ERO',N'RESTITUTION',N'QA_GATE_ERO',N'QA_GATE'),(@edo,N'EDO',N'LIVRAISON',N'QA_GATE_EDO',N'QA_GATE');
 INSERT dbo.transport_order_items(id,order_id,armateur_id,iso_code,quantity) VALUES
  (@receive,@ero,N'QA_GATE',N'22G1',2),(@deliver,@edo,N'QA_GATE',N'22G1',2),(@wrongSize,@edo,N'QA_GATE',N'42G1',1);

EXEC api.enter_visit @ActorId=@actor,@Plate=N'QA-TRUCK',@Cin=N'QA-DRIVER',@EntryKind=N'loaded',@OrderItemId=@receive,@IsTwin=1,@OrderItemId2=@receive,
 @Container=N'CSQU3054383',@Container2=N'MSCU6639870',@Details=N'{"haulier":"Fictitious haulier","seal_number":"S1","seal_number_2":"S2"}';
 SELECT @visit=id FROM dbo.truck_visits WHERE entry_kind=N'loaded' AND entered_by=@actor;
 EXEC api.move_visit @ActorId=@actor,@VisitId=@visit,@ExpectedVersion=1,@Mode=N'YARD';
 UPDATE dbo.truck_visits SET entered_at=DATEADD(hour,-25,TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00')) WHERE id=@visit;
 EXEC api.enter_visit @ActorId=@actor,@Plate=N'QA-PICKUP',@Cin=N'QA-DRIVER',@EntryKind=N'empty',@OrderItemId=@deliver,@IsTwin=1,@OrderItemId2=@deliver;
 SELECT @pickup=id FROM dbo.truck_visits WHERE entry_kind=N'empty' AND entered_by=@actor;
 EXEC api.move_visit @ActorId=@actor,@VisitId=@pickup,@ExpectedVersion=1,@Mode=N'EXIT',@Container=N'CSQU3054383',@Container2=N'MSCU6639870';
 IF (SELECT COUNT(*) FROM dbo.container_stock_intervals WHERE end_visit_id=@pickup AND departed_at IS NOT NULL)<>2 THROW 51099, 'Twin departure incomplete.', 1;
 IF NOT EXISTS(SELECT 1 FROM dbo.truck_visits WHERE id=@pickup AND exited_at IS NOT NULL AND version=3) THROW 51099, 'Delivery exit missing.', 1;
 ROLLBACK TRANSACTION;
 PRINT 'PASS: delivery after receiving-truck age removes both containers; fixtures rolled back.';
END TRY BEGIN CATCH IF @as_backend=1 REVERT;IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;THROW;END CATCH;
GO
-- quantity exhaustion
BEGIN TRY
 BEGIN TRANSACTION;

 DECLARE @actor uniqueidentifier=NEWID(),@viewer uniqueidentifier=NEWID(),@ero uniqueidentifier=NEWID(),@edo uniqueidentifier=NEWID(),
  @receive uniqueidentifier=NEWID(),@deliver uniqueidentifier=NEWID(),@wrongSize uniqueidentifier=NEWID(),@visit uniqueidentifier,@pickup uniqueidentifier,@as_backend bit=0;
 INSERT dbo.profiles(id,display_name) VALUES(@actor,N'QA Gate Admin'),(@viewer,N'QA Viewer');
 INSERT dbo.user_roles VALUES(@actor,N'admin'),(@viewer,N'viewer');
 INSERT dbo.armateurs(id,name) VALUES(N'QA_GATE',N'Fictitious gate carrier');
 INSERT dbo.transport_orders(id,kind,direction,reference,armateur_id) VALUES
  (@ero,N'ERO',N'RESTITUTION',N'QA_GATE_ERO',N'QA_GATE'),(@edo,N'EDO',N'LIVRAISON',N'QA_GATE_EDO',N'QA_GATE');
 INSERT dbo.transport_order_items(id,order_id,armateur_id,iso_code,quantity) VALUES
  (@receive,@ero,N'QA_GATE',N'22G1',2),(@deliver,@edo,N'QA_GATE',N'22G1',2),(@wrongSize,@edo,N'QA_GATE',N'42G1',1);

EXEC api.enter_visit @ActorId=@actor,@Plate=N'QA-TRUCK',@Cin=N'QA-DRIVER',@EntryKind=N'loaded',@OrderItemId=@receive,@IsTwin=1,@OrderItemId2=@receive,
 @Container=N'CSQU3054383',@Container2=N'MSCU6639870',@Details=N'{"haulier":"Fictitious haulier","seal_number":"S1","seal_number_2":"S2"}';
 SELECT @visit=id FROM dbo.truck_visits WHERE entry_kind=N'loaded' AND entered_by=@actor;
 DECLARE @rejected bit=0;
 BEGIN TRY
EXEC api.enter_visit @ActorId=@actor,@Plate=N'QA-EXTRA',@Cin=N'QA-DRIVER',@EntryKind=N'loaded',@OrderItemId=@receive,@Container=N'TCLU1234568';
 END TRY BEGIN CATCH
  IF ERROR_NUMBER()<>51004 THROW;
  SET @rejected=1;
 END CATCH;
 IF @rejected=0 THROW 51099, 'Expected gate rejection did not occur.', 1;
 IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
 IF EXISTS(SELECT 1 FROM dbo.profiles WHERE id=@actor) THROW 51099, 'Fixture transaction was not rolled back.', 1;
 PRINT 'PASS: quantity exhaustion; rejection and rollback checked.';
END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;THROW;END CATCH;
GO
-- delivery before24 hours
BEGIN TRY
 BEGIN TRANSACTION;

 DECLARE @actor uniqueidentifier=NEWID(),@viewer uniqueidentifier=NEWID(),@ero uniqueidentifier=NEWID(),@edo uniqueidentifier=NEWID(),
  @receive uniqueidentifier=NEWID(),@deliver uniqueidentifier=NEWID(),@wrongSize uniqueidentifier=NEWID(),@visit uniqueidentifier,@pickup uniqueidentifier,@as_backend bit=0;
 INSERT dbo.profiles(id,display_name) VALUES(@actor,N'QA Gate Admin'),(@viewer,N'QA Viewer');
 INSERT dbo.user_roles VALUES(@actor,N'admin'),(@viewer,N'viewer');
 INSERT dbo.armateurs(id,name) VALUES(N'QA_GATE',N'Fictitious gate carrier');
 INSERT dbo.transport_orders(id,kind,direction,reference,armateur_id) VALUES
  (@ero,N'ERO',N'RESTITUTION',N'QA_GATE_ERO',N'QA_GATE'),(@edo,N'EDO',N'LIVRAISON',N'QA_GATE_EDO',N'QA_GATE');
 INSERT dbo.transport_order_items(id,order_id,armateur_id,iso_code,quantity) VALUES
  (@receive,@ero,N'QA_GATE',N'22G1',2),(@deliver,@edo,N'QA_GATE',N'22G1',2),(@wrongSize,@edo,N'QA_GATE',N'42G1',1);

EXEC api.enter_visit @ActorId=@actor,@Plate=N'QA-TRUCK',@Cin=N'QA-DRIVER',@EntryKind=N'loaded',@OrderItemId=@receive,@IsTwin=1,@OrderItemId2=@receive,
 @Container=N'CSQU3054383',@Container2=N'MSCU6639870',@Details=N'{"haulier":"Fictitious haulier","seal_number":"S1","seal_number_2":"S2"}';
 SELECT @visit=id FROM dbo.truck_visits WHERE entry_kind=N'loaded' AND entered_by=@actor;
 EXEC api.move_visit @ActorId=@actor,@VisitId=@visit,@ExpectedVersion=1,@Mode=N'YARD';
EXEC api.enter_visit @ActorId=@actor,@Plate=N'QA-PICKUP',@Cin=N'QA-DRIVER',@EntryKind=N'empty',@OrderItemId=@deliver,@IsTwin=1,@OrderItemId2=@deliver;
 SELECT @pickup=id FROM dbo.truck_visits WHERE entry_kind=N'empty' AND entered_by=@actor;
 DECLARE @rejected bit=0;
 BEGIN TRY
EXEC api.move_visit @ActorId=@actor,@VisitId=@pickup,@ExpectedVersion=1,@Mode=N'EXIT',@Container=N'CSQU3054383',@Container2=N'MSCU6639870';
 END TRY BEGIN CATCH
  IF ERROR_NUMBER()<>51004 THROW;
  SET @rejected=1;
 END CATCH;
 IF @rejected=0 THROW 51099, 'Expected gate rejection did not occur.', 1;
 IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
 IF EXISTS(SELECT 1 FROM dbo.profiles WHERE id=@actor) THROW 51099, 'Fixture transaction was not rolled back.', 1;
 PRINT 'PASS: delivery before24 hours; rejection and rollback checked.';
END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;THROW;END CATCH;
GO
-- blocked second container rejects whole twin pickup
BEGIN TRY
 BEGIN TRANSACTION;

 DECLARE @actor uniqueidentifier=NEWID(),@viewer uniqueidentifier=NEWID(),@ero uniqueidentifier=NEWID(),@edo uniqueidentifier=NEWID(),
  @receive uniqueidentifier=NEWID(),@deliver uniqueidentifier=NEWID(),@wrongSize uniqueidentifier=NEWID(),@visit uniqueidentifier,@pickup uniqueidentifier,@as_backend bit=0;
 INSERT dbo.profiles(id,display_name) VALUES(@actor,N'QA Gate Admin'),(@viewer,N'QA Viewer');
 INSERT dbo.user_roles VALUES(@actor,N'admin'),(@viewer,N'viewer');
 INSERT dbo.armateurs(id,name) VALUES(N'QA_GATE',N'Fictitious gate carrier');
 INSERT dbo.transport_orders(id,kind,direction,reference,armateur_id) VALUES
  (@ero,N'ERO',N'RESTITUTION',N'QA_GATE_ERO',N'QA_GATE'),(@edo,N'EDO',N'LIVRAISON',N'QA_GATE_EDO',N'QA_GATE');
 INSERT dbo.transport_order_items(id,order_id,armateur_id,iso_code,quantity) VALUES
  (@receive,@ero,N'QA_GATE',N'22G1',2),(@deliver,@edo,N'QA_GATE',N'22G1',2),(@wrongSize,@edo,N'QA_GATE',N'42G1',1);

EXEC api.enter_visit @ActorId=@actor,@Plate=N'QA-TRUCK',@Cin=N'QA-DRIVER',@EntryKind=N'loaded',@OrderItemId=@receive,@IsTwin=1,@OrderItemId2=@receive,
 @Container=N'CSQU3054383',@Container2=N'MSCU6639870',@Details=N'{"haulier":"Fictitious haulier","seal_number":"S1","seal_number_2":"S2"}';
 SELECT @visit=id FROM dbo.truck_visits WHERE entry_kind=N'loaded' AND entered_by=@actor;
 EXEC api.move_visit @ActorId=@actor,@VisitId=@visit,@ExpectedVersion=1,@Mode=N'YARD';
 UPDATE dbo.truck_visits SET entered_at=DATEADD(hour,-25,TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00')) WHERE id=@visit;
 EXEC api.set_container_block @ActorId=@actor,@Container=N'MSCU6639870',@Blocked=1,@Reason=N'QA second slot hold',@ExpectedVersion=0;
 EXEC api.enter_visit @ActorId=@actor,@Plate=N'QA-PICKUP',@Cin=N'QA-DRIVER',@EntryKind=N'empty',@OrderItemId=@deliver,@IsTwin=1,@OrderItemId2=@deliver;
 SELECT @pickup=id FROM dbo.truck_visits WHERE entry_kind=N'empty' AND entered_by=@actor;
 DECLARE @rejected bit=0;
 BEGIN TRY
EXEC api.move_visit @ActorId=@actor,@VisitId=@pickup,@ExpectedVersion=1,@Mode=N'EXIT',@Container=N'CSQU3054383',@Container2=N'MSCU6639870';
 END TRY BEGIN CATCH
  IF ERROR_NUMBER()<>51004 THROW;
  SET @rejected=1;
 END CATCH;
 IF @rejected=0 THROW 51099, 'Expected gate rejection did not occur.', 1;
 IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
 IF EXISTS(SELECT 1 FROM dbo.profiles WHERE id=@actor) THROW 51099, 'Fixture transaction was not rolled back.', 1;
 PRINT 'PASS: blocked second container rejects whole twin pickup; rejection and rollback checked.';
END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;THROW;END CATCH;
GO
-- 40-foot booking cannot deliver20-foot stock
BEGIN TRY
 BEGIN TRANSACTION;

 DECLARE @actor uniqueidentifier=NEWID(),@viewer uniqueidentifier=NEWID(),@ero uniqueidentifier=NEWID(),@edo uniqueidentifier=NEWID(),
  @receive uniqueidentifier=NEWID(),@deliver uniqueidentifier=NEWID(),@wrongSize uniqueidentifier=NEWID(),@visit uniqueidentifier,@pickup uniqueidentifier,@as_backend bit=0;
 INSERT dbo.profiles(id,display_name) VALUES(@actor,N'QA Gate Admin'),(@viewer,N'QA Viewer');
 INSERT dbo.user_roles VALUES(@actor,N'admin'),(@viewer,N'viewer');
 INSERT dbo.armateurs(id,name) VALUES(N'QA_GATE',N'Fictitious gate carrier');
 INSERT dbo.transport_orders(id,kind,direction,reference,armateur_id) VALUES
  (@ero,N'ERO',N'RESTITUTION',N'QA_GATE_ERO',N'QA_GATE'),(@edo,N'EDO',N'LIVRAISON',N'QA_GATE_EDO',N'QA_GATE');
 INSERT dbo.transport_order_items(id,order_id,armateur_id,iso_code,quantity) VALUES
  (@receive,@ero,N'QA_GATE',N'22G1',2),(@deliver,@edo,N'QA_GATE',N'22G1',2),(@wrongSize,@edo,N'QA_GATE',N'42G1',1);

EXEC api.enter_visit @ActorId=@actor,@Plate=N'QA-TRUCK',@Cin=N'QA-DRIVER',@EntryKind=N'loaded',@OrderItemId=@receive,@IsTwin=1,@OrderItemId2=@receive,
 @Container=N'CSQU3054383',@Container2=N'MSCU6639870',@Details=N'{"haulier":"Fictitious haulier","seal_number":"S1","seal_number_2":"S2"}';
 SELECT @visit=id FROM dbo.truck_visits WHERE entry_kind=N'loaded' AND entered_by=@actor;
 EXEC api.move_visit @ActorId=@actor,@VisitId=@visit,@ExpectedVersion=1,@Mode=N'YARD';
 UPDATE dbo.truck_visits SET entered_at=DATEADD(hour,-25,TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00')) WHERE id=@visit;
 EXEC api.enter_visit @ActorId=@actor,@Plate=N'QA-WRONG',@Cin=N'QA-DRIVER',@EntryKind=N'empty',@OrderItemId=@wrongSize;
 SELECT @pickup=id FROM dbo.truck_visits WHERE entry_kind=N'empty' AND entered_by=@actor;
 DECLARE @rejected bit=0;
 BEGIN TRY
EXEC api.move_visit @ActorId=@actor,@VisitId=@pickup,@ExpectedVersion=1,@Mode=N'EXIT',@Container=N'CSQU3054383';
 END TRY BEGIN CATCH
  IF ERROR_NUMBER()<>51004 THROW;
  SET @rejected=1;
 END CATCH;
 IF @rejected=0 THROW 51099, 'Expected gate rejection did not occur.', 1;
 IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
 IF EXISTS(SELECT 1 FROM dbo.profiles WHERE id=@actor) THROW 51099, 'Fixture transaction was not rolled back.', 1;
 PRINT 'PASS: 40-foot booking cannot deliver20-foot stock; rejection and rollback checked.';
END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;THROW;END CATCH;
GO
-- viewer cannot block containers
BEGIN TRY
 BEGIN TRANSACTION;

 DECLARE @actor uniqueidentifier=NEWID(),@viewer uniqueidentifier=NEWID(),@ero uniqueidentifier=NEWID(),@edo uniqueidentifier=NEWID(),
  @receive uniqueidentifier=NEWID(),@deliver uniqueidentifier=NEWID(),@wrongSize uniqueidentifier=NEWID(),@visit uniqueidentifier,@pickup uniqueidentifier,@as_backend bit=0;
 INSERT dbo.profiles(id,display_name) VALUES(@actor,N'QA Gate Admin'),(@viewer,N'QA Viewer');
 INSERT dbo.user_roles VALUES(@actor,N'admin'),(@viewer,N'viewer');
 INSERT dbo.armateurs(id,name) VALUES(N'QA_GATE',N'Fictitious gate carrier');
 INSERT dbo.transport_orders(id,kind,direction,reference,armateur_id) VALUES
  (@ero,N'ERO',N'RESTITUTION',N'QA_GATE_ERO',N'QA_GATE'),(@edo,N'EDO',N'LIVRAISON',N'QA_GATE_EDO',N'QA_GATE');
 INSERT dbo.transport_order_items(id,order_id,armateur_id,iso_code,quantity) VALUES
  (@receive,@ero,N'QA_GATE',N'22G1',2),(@deliver,@edo,N'QA_GATE',N'22G1',2),(@wrongSize,@edo,N'QA_GATE',N'42G1',1);

EXEC api.enter_visit @ActorId=@actor,@Plate=N'QA-TRUCK',@Cin=N'QA-DRIVER',@EntryKind=N'loaded',@OrderItemId=@receive,@IsTwin=1,@OrderItemId2=@receive,
 @Container=N'CSQU3054383',@Container2=N'MSCU6639870',@Details=N'{"haulier":"Fictitious haulier","seal_number":"S1","seal_number_2":"S2"}';
 SELECT @visit=id FROM dbo.truck_visits WHERE entry_kind=N'loaded' AND entered_by=@actor;
 EXEC api.move_visit @ActorId=@actor,@VisitId=@visit,@ExpectedVersion=1,@Mode=N'YARD';
 DECLARE @rejected bit=0;
 BEGIN TRY
EXEC api.set_container_block @ActorId=@viewer,@Container=N'CSQU3054383',@Blocked=1,@Reason=N'QA forbidden',@ExpectedVersion=0;
 END TRY BEGIN CATCH
  IF ERROR_NUMBER()<>51003 THROW;
  SET @rejected=1;
 END CATCH;
 IF @rejected=0 THROW 51099, 'Expected gate rejection did not occur.', 1;
 IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
 IF EXISTS(SELECT 1 FROM dbo.profiles WHERE id=@actor) THROW 51099, 'Fixture transaction was not rolled back.', 1;
 PRINT 'PASS: viewer cannot block containers; rejection and rollback checked.';
END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;THROW;END CATCH;
GO
-- stale visit version
BEGIN TRY
 BEGIN TRANSACTION;

 DECLARE @actor uniqueidentifier=NEWID(),@viewer uniqueidentifier=NEWID(),@ero uniqueidentifier=NEWID(),@edo uniqueidentifier=NEWID(),
  @receive uniqueidentifier=NEWID(),@deliver uniqueidentifier=NEWID(),@wrongSize uniqueidentifier=NEWID(),@visit uniqueidentifier,@pickup uniqueidentifier,@as_backend bit=0;
 INSERT dbo.profiles(id,display_name) VALUES(@actor,N'QA Gate Admin'),(@viewer,N'QA Viewer');
 INSERT dbo.user_roles VALUES(@actor,N'admin'),(@viewer,N'viewer');
 INSERT dbo.armateurs(id,name) VALUES(N'QA_GATE',N'Fictitious gate carrier');
 INSERT dbo.transport_orders(id,kind,direction,reference,armateur_id) VALUES
  (@ero,N'ERO',N'RESTITUTION',N'QA_GATE_ERO',N'QA_GATE'),(@edo,N'EDO',N'LIVRAISON',N'QA_GATE_EDO',N'QA_GATE');
 INSERT dbo.transport_order_items(id,order_id,armateur_id,iso_code,quantity) VALUES
  (@receive,@ero,N'QA_GATE',N'22G1',2),(@deliver,@edo,N'QA_GATE',N'22G1',2),(@wrongSize,@edo,N'QA_GATE',N'42G1',1);

EXEC api.enter_visit @ActorId=@actor,@Plate=N'QA-TRUCK',@Cin=N'QA-DRIVER',@EntryKind=N'loaded',@OrderItemId=@receive,@IsTwin=1,@OrderItemId2=@receive,
 @Container=N'CSQU3054383',@Container2=N'MSCU6639870',@Details=N'{"haulier":"Fictitious haulier","seal_number":"S1","seal_number_2":"S2"}';
 SELECT @visit=id FROM dbo.truck_visits WHERE entry_kind=N'loaded' AND entered_by=@actor;
 DECLARE @rejected bit=0;
 BEGIN TRY
EXEC api.move_visit @ActorId=@actor,@VisitId=@visit,@ExpectedVersion=99,@Mode=N'YARD';
 END TRY BEGIN CATCH
  IF ERROR_NUMBER()<>51009 THROW;
  SET @rejected=1;
 END CATCH;
 IF @rejected=0 THROW 51099, 'Expected gate rejection did not occur.', 1;
 IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
 IF EXISTS(SELECT 1 FROM dbo.profiles WHERE id=@actor) THROW 51099, 'Fixture transaction was not rolled back.', 1;
 PRINT 'PASS: stale visit version; rejection and rollback checked.';
END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;THROW;END CATCH;
GO
-- cancellation releases reserved quantity before movement
BEGIN TRY
 BEGIN TRANSACTION;

 DECLARE @actor uniqueidentifier=NEWID(),@viewer uniqueidentifier=NEWID(),@ero uniqueidentifier=NEWID(),@edo uniqueidentifier=NEWID(),
  @receive uniqueidentifier=NEWID(),@deliver uniqueidentifier=NEWID(),@wrongSize uniqueidentifier=NEWID(),@visit uniqueidentifier,@pickup uniqueidentifier,@as_backend bit=0;
 INSERT dbo.profiles(id,display_name) VALUES(@actor,N'QA Gate Admin'),(@viewer,N'QA Viewer');
 INSERT dbo.user_roles VALUES(@actor,N'admin'),(@viewer,N'viewer');
 INSERT dbo.armateurs(id,name) VALUES(N'QA_GATE',N'Fictitious gate carrier');
 INSERT dbo.transport_orders(id,kind,direction,reference,armateur_id) VALUES
  (@ero,N'ERO',N'RESTITUTION',N'QA_GATE_ERO',N'QA_GATE'),(@edo,N'EDO',N'LIVRAISON',N'QA_GATE_EDO',N'QA_GATE');
 INSERT dbo.transport_order_items(id,order_id,armateur_id,iso_code,quantity) VALUES
  (@receive,@ero,N'QA_GATE',N'22G1',2),(@deliver,@edo,N'QA_GATE',N'22G1',2),(@wrongSize,@edo,N'QA_GATE',N'42G1',1);

EXEC api.enter_visit @ActorId=@actor,@Plate=N'QA-TRUCK',@Cin=N'QA-DRIVER',@EntryKind=N'loaded',@OrderItemId=@receive,@IsTwin=1,@OrderItemId2=@receive,
 @Container=N'CSQU3054383',@Container2=N'MSCU6639870',@Details=N'{"haulier":"Fictitious haulier","seal_number":"S1","seal_number_2":"S2"}';
 SELECT @visit=id FROM dbo.truck_visits WHERE entry_kind=N'loaded' AND entered_by=@actor;
 EXEC api.move_visit @ActorId=@actor,@VisitId=@visit,@ExpectedVersion=1,@Mode=N'CANCEL',@Reason=N'QA release';
 EXEC api.enter_visit @ActorId=@actor,@Plate=N'QA-REUSE',@Cin=N'QA-DRIVER',@EntryKind=N'loaded',@OrderItemId=@receive,@IsTwin=1,@OrderItemId2=@receive,@Container=N'CSQU3054383',@Container2=N'MSCU6639870';
 IF (SELECT COUNT(*) FROM dbo.truck_visits WHERE entered_by=@actor AND canceled_at IS NULL)<>1 THROW 51099, 'Reservation not released.', 1;
 ROLLBACK TRANSACTION;
 PRINT 'PASS: cancellation releases reserved quantity before movement; fixtures rolled back.';
END TRY BEGIN CATCH IF @as_backend=1 REVERT;IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;THROW;END CATCH;
GO
