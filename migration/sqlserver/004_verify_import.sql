-- Synthetic import verification only; do not run as a production data comparison.
SET NOCOUNT ON;
IF DB_NAME() NOT LIKE N'%[_]Test' THROW 51000, 'Use the synthetic _Test database.', 1;
IF NOT EXISTS(SELECT 1 FROM dbo.visit_events WHERE id=9007199254740993 AND DATEPART(NANOSECOND,occurred_at)=123456000)
  THROW 51099, 'Bigint or timestamp precision changed.', 1;
IF NOT EXISTS(SELECT 1 FROM dbo.evp_rules WHERE factor=CAST(N'2.000000000000000001' AS decimal(38,18)))
  THROW 51099, 'Decimal precision changed.', 1;
IF NOT EXISTS(SELECT 1 FROM dbo.generated_documents WHERE JSON_VALUE(snapshot,'$.source_event')=N'9007199254740993')
  THROW 51099, 'JSON precision changed.', 1;
IF CONVERT(bigint,IDENT_CURRENT(N'dbo.visit_events'))<>9007199254740993
  THROW 51099, 'Event identity was not reseeded.', 1;
IF NOT EXISTS(SELECT 1 FROM dbo.transport_order_items WHERE id='33333333-3333-4333-8333-333333333333' AND quantity=5)
  THROW 51099, 'Order item ID or quantity changed.', 1;
PRINT 'PASS: imported UUIDs, bigint IDs, identity seed, datetime microseconds, exact decimals and JSON numbers.';
GO
