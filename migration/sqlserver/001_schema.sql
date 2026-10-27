-- SQL Server 2025. Generated from the metadata snapshot; no source rows are embedded.
-- Run against a NEW, empty database selected by your DBA, never master or an existing application database.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() IN (N'master',N'model',N'msdb',N'tempdb') THROW 51000, 'Select the dedicated Pointage database first.', 1;
IF CONVERT(int,SERVERPROPERTY('ProductMajorVersion'))<17 THROW 51000, 'SQL Server 2025 or newer is required.', 1;
IF OBJECT_ID(N'internal.schema_versions') IS NOT NULL THROW 51000, 'Migration already initialized; do not replay.', 1;
IF EXISTS(SELECT 1 FROM sys.tables WHERE is_ms_shipped=0) THROW 51000, 'Destination must be empty.', 1;
BEGIN TRANSACTION;
IF SCHEMA_ID(N'internal') IS NULL EXEC(N'CREATE SCHEMA internal AUTHORIZATION dbo');
IF SCHEMA_ID(N'api') IS NULL EXEC(N'CREATE SCHEMA api AUTHORIZATION dbo');
CREATE TABLE internal.schema_versions(version int NOT NULL PRIMARY KEY, applied_at datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00'));


CREATE TABLE [internal].[transport_order_aliases] (
  [alias_id] uniqueidentifier NOT NULL,
  [order_id] uniqueidentifier NOT NULL,
  [original_header] nvarchar(max) NOT NULL,
  CHECK ([original_header] IS NULL OR ISJSON([original_header],VALUE)=1),
  CONSTRAINT [transport_order_aliases_pkey] PRIMARY KEY ([alias_id])
);

CREATE TABLE [internal].[transport_order_controls] (
  [singleton] bit NOT NULL DEFAULT 1,
  [required] bit NOT NULL DEFAULT 0,
  CONSTRAINT [transport_order_controls_pkey] PRIMARY KEY ([singleton]),
  CHECK ([singleton]=1)
);

CREATE TABLE [dbo].[armateurs] (
  [id] nvarchar(64) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [name] nvarchar(max) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [bic] nvarchar(max) COLLATE Latin1_General_100_BIN2 NULL,
  [official_logo_path] nvarchar(max) COLLATE Latin1_General_100_BIN2 NULL,
  [official_logo_verified] bit NOT NULL DEFAULT 0,
  [active] bit NOT NULL DEFAULT 1,
  CONSTRAINT [armateurs_pkey] PRIMARY KEY ([id])
);

CREATE TABLE [dbo].[audit_logs] (
  [id] bigint IDENTITY(1,1) NOT NULL,
  [entity] nvarchar(64) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [entity_id] nvarchar(150) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [action] nvarchar(64) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [actor_id] uniqueidentifier NULL,
  [occurred_at] datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00'),
  [before_data] nvarchar(max) NULL,
  CHECK ([before_data] IS NULL OR ISJSON([before_data],VALUE)=1),
  [after_data] nvarchar(max) NULL,
  CHECK ([after_data] IS NULL OR ISJSON([after_data],VALUE)=1),
  [reason] nvarchar(max) COLLATE Latin1_General_100_BIN2 NULL,
  CONSTRAINT [audit_logs_pkey] PRIMARY KEY ([id])
);

CREATE TABLE [dbo].[bookings] (
  [id] uniqueidentifier NOT NULL DEFAULT NEWID(),
  [reference] nvarchar(150) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [client_id] uniqueidentifier NULL,
  [armateur_id] nvarchar(64) COLLATE Latin1_General_100_BIN2 NULL,
  [iso_code] nvarchar(4) COLLATE Latin1_General_100_BIN2 NULL,
  [created_at] datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00'),
  CONSTRAINT [bookings_pkey] PRIMARY KEY ([id]),
  CHECK (LEN(TRIM([reference])) BETWEEN 1 AND 150)
);

CREATE TABLE [dbo].[client_armateurs] (
  [client_id] uniqueidentifier NOT NULL,
  [armateur_id] nvarchar(64) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [valid_from] date NOT NULL,
  [valid_to] date NULL,
  CONSTRAINT [client_armateurs_pkey] PRIMARY KEY ([client_id],[armateur_id],[valid_from]),
  CHECK ([valid_to] IS NULL OR [valid_to]>=[valid_from])
);

CREATE TABLE [dbo].[clients] (
  [id] uniqueidentifier NOT NULL DEFAULT NEWID(),
  [code] nvarchar(150) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [name] nvarchar(max) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [active] bit NOT NULL DEFAULT 1,
  CONSTRAINT [clients_code_key] UNIQUE ([code]),
  CONSTRAINT [clients_pkey] PRIMARY KEY ([id])
);

CREATE TABLE [dbo].[container_stock_intervals] (
  [id] uniqueidentifier NOT NULL DEFAULT NEWID(),
  [container_number] nvarchar(11) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [client_id] uniqueidentifier NULL,
  [armateur_id] nvarchar(64) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [iso_code] nvarchar(4) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [start_visit_id] uniqueidentifier NOT NULL,
  [end_visit_id] uniqueidentifier NULL,
  [arrived_at] datetimeoffset(6) NOT NULL,
  [departed_at] datetimeoffset(6) NULL,
  [position] nvarchar(max) COLLATE Latin1_General_100_BIN2 NULL,
  CONSTRAINT [container_stock_intervals_pkey] PRIMARY KEY ([id]),
  CHECK ([departed_at] IS NULL OR [departed_at]>=[arrived_at])
);

CREATE TABLE [dbo].[containers] (
  [number] nvarchar(11) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [iso_code] nvarchar(4) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [armateur_id] nvarchar(64) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [source] nvarchar(16) COLLATE Latin1_General_100_BIN2 NOT NULL DEFAULT N'operator',
  [created_at] datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00'),
  CONSTRAINT [containers_pkey] PRIMARY KEY ([number]),
  CHECK (LEN([number])=11 AND LEFT([number],4) NOT LIKE N'%[^A-Z]%' AND RIGHT([number],7) NOT LIKE N'%[^0-9]%'),
  CHECK (LEN([iso_code])=4 AND [iso_code] NOT LIKE N'%[^0-9A-Z]%'),
  CHECK ([source] IN (N'operator',N'manual',N'import'))
);

CREATE TABLE [dbo].[document_actions] (
  [id] bigint IDENTITY(1,1) NOT NULL,
  [document_id] uniqueidentifier NOT NULL,
  [actor_id] uniqueidentifier NOT NULL,
  [action] nvarchar(64) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [occurred_at] datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00'),
  CONSTRAINT [document_actions_pkey] PRIMARY KEY ([id]),
  CHECK ([action] IN (N'PREVIEW_REQUESTED',N'SHARE_REQUESTED',N'PRINT_DIALOG_REQUESTED',N'DIRECT_PRINT_REQUESTED',N'BRIDGE_ARCHIVE_REQUESTED',N'BRIDGE_PRINT_REQUESTED'))
);

CREATE TABLE [dbo].[evp_rules] (
  [effective_from] date NOT NULL,
  [size_feet] int NOT NULL,
  [factor] decimal(38,18) NOT NULL,
  [source_note] nvarchar(max) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [created_by] uniqueidentifier NULL,
  [created_at] datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00'),
  CONSTRAINT [evp_rules_pkey] PRIMARY KEY ([effective_from],[size_feet]),
  CHECK ([factor]>0),
  CHECK ([size_feet] IN (20,40,45))
);

CREATE TABLE [dbo].[forced_container_actions] (
  [id] uniqueidentifier NOT NULL DEFAULT NEWID(),
  [visit_id] uniqueidentifier NOT NULL,
  [container_number] nvarchar(11) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [action] nvarchar(64) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [reason] nvarchar(max) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [actor_id] uniqueidentifier NOT NULL,
  [occurred_at] datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00'),
  [resolved_at] datetimeoffset(6) NULL,
  [resolved_by] uniqueidentifier NULL,
  [external_reference] nvarchar(max) COLLATE Latin1_General_100_BIN2 NULL,
  CONSTRAINT [forced_container_actions_pkey] PRIMARY KEY ([id]),
  CONSTRAINT [forced_container_actions_visit_id_key] UNIQUE ([visit_id]),
  CHECK ([action]=N'PRISE_SANS_STOCK'),
  CHECK (LEN(TRIM([reason]))>=10),
  CHECK (([resolved_at] IS NULL AND [resolved_by] IS NULL AND [external_reference] IS NULL) OR ([resolved_at] IS NOT NULL AND [resolved_by] IS NOT NULL AND LEN(TRIM([external_reference]))>=3))
);

CREATE TABLE [dbo].[generated_documents] (
  [id] uniqueidentifier NOT NULL DEFAULT NEWID(),
  [visit_id] uniqueidentifier NOT NULL,
  [event_id] bigint NOT NULL,
  [kind] nvarchar(32) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [storage_path] nvarchar(450) COLLATE Latin1_General_100_BIN2 NULL,
  [status] nvarchar(16) COLLATE Latin1_General_100_BIN2 NOT NULL DEFAULT N'pending',
  [snapshot] nvarchar(max) NOT NULL,
  CHECK ([snapshot] IS NULL OR ISJSON([snapshot],VALUE)=1),
  [created_by] uniqueidentifier NOT NULL,
  [created_at] datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00'),
  CONSTRAINT [generated_documents_event_id_key] UNIQUE ([event_id]),
  CONSTRAINT [generated_documents_pkey] PRIMARY KEY ([id]),
  CHECK ([kind] IN (N'ENTREE',N'DEPOSE',N'PRISE',N'SORTIE',N'ANNULATION')),
  CHECK ([status] IN (N'pending',N'uploaded',N'failed'))
);

CREATE TABLE [dbo].[iso_report_types] (
  [iso_code] nvarchar(4) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [effective_from] date NOT NULL,
  [category] nvarchar(max) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [size_feet] int NOT NULL,
  [source_note] nvarchar(max) COLLATE Latin1_General_100_BIN2 NOT NULL,
  CONSTRAINT [iso_report_types_pkey] PRIMARY KEY ([iso_code],[effective_from]),
  CHECK ([category] IN (N'20 DV',N'40 DV ST',N'40 DV HC',N'45 DV',N'FRIGO 20',N'FRIGO 40',N'OT&FL&HP&CT')),
  CHECK ([size_feet] IN (20,40,45))
);

CREATE TABLE [dbo].[printer_settings] (
  [user_id] uniqueidentifier NOT NULL,
  [device_id] nvarchar(200) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [printer_name] nvarchar(max) COLLATE Latin1_General_100_BIN2 NULL,
  [updated_at] datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00'),
  CONSTRAINT [printer_settings_pkey] PRIMARY KEY ([user_id],[device_id])
);

CREATE TABLE [dbo].[profiles] (
  [id] uniqueidentifier NOT NULL,
  [display_name] nvarchar(max) COLLATE Latin1_General_100_BIN2 NOT NULL DEFAULT N'',
  [active] bit NOT NULL DEFAULT 1,
  [created_at] datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00'),
  [phone] nvarchar(32) COLLATE Latin1_General_100_BIN2 NULL,
  [first_name] nvarchar(max) COLLATE Latin1_General_100_BIN2 NULL,
  [last_name] nvarchar(max) COLLATE Latin1_General_100_BIN2 NULL,
  [avatar_url] nvarchar(max) COLLATE Latin1_General_100_BIN2 NULL,
  CONSTRAINT [profiles_pkey] PRIMARY KEY ([id])
);

CREATE TABLE [dbo].[transport_order_items] (
  [id] uniqueidentifier NOT NULL DEFAULT NEWID(),
  [order_id] uniqueidentifier NOT NULL,
  [iso_code] nvarchar(4) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [quantity] int NOT NULL,
  [armateur_id] nvarchar(64) COLLATE Latin1_General_100_BIN2 NOT NULL,
  CONSTRAINT [transport_order_item_carrier_iso_key] UNIQUE ([order_id],[armateur_id],[iso_code]),
  CONSTRAINT [transport_order_items_pkey] PRIMARY KEY ([id]),
  CHECK (LEN([iso_code])=4 AND [iso_code] NOT LIKE N'%[^0-9A-Z]%'),
  CHECK ([quantity] BETWEEN 1 AND 1000000)
);

CREATE TABLE [dbo].[transport_orders] (
  [id] uniqueidentifier NOT NULL DEFAULT NEWID(),
  [kind] nvarchar(32) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [direction] nvarchar(16) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [reference] nvarchar(150) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [armateur_id] nvarchar(64) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [client_id] uniqueidentifier NULL,
  [client_order_reference] nvarchar(150) COLLATE Latin1_General_100_BIN2 NULL,
  [active] bit NOT NULL DEFAULT 1,
  [created_at] datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00'),
  [created_by] uniqueidentifier NULL,
  [version] int NOT NULL DEFAULT 1,
  [updated_at] datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00'),
  [updated_by] uniqueidentifier NULL,
  CONSTRAINT [transport_orders_pkey] PRIMARY KEY ([id]),
  CHECK (([kind]<>N'EDO' OR [direction]=N'LIVRAISON') AND ([kind]<>N'ERO' OR [direction]=N'RESTITUTION')),
  CHECK ([client_order_reference] IS NULL OR [client_id] IS NOT NULL),
  CHECK ([direction] IN (N'RESTITUTION',N'LIVRAISON')),
  CHECK ([kind] IN (N'BOOKING',N'EDO',N'ERO')),
  CHECK (LEN(TRIM([reference])) BETWEEN 1 AND 150)
);

CREATE TABLE [dbo].[truck_visits] (
  [id] uniqueidentifier NOT NULL DEFAULT NEWID(),
  [plate] nvarchar(max) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [driver_cin] nvarchar(max) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [entry_kind] nvarchar(8) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [container_number] nvarchar(11) COLLATE Latin1_General_100_BIN2 NULL,
  [booking_id] uniqueidentifier NULL,
  [iso_code] nvarchar(4) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [armateur_id] nvarchar(64) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [client_id] uniqueidentifier NULL,
  [entered_at] datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00'),
  [entered_by] uniqueidentifier NOT NULL,
  [engin_at] datetimeoffset(6) NULL,
  [engin_by] uniqueidentifier NULL,
  [exited_at] datetimeoffset(6) NULL,
  [exited_by] uniqueidentifier NULL,
  [canceled_at] datetimeoffset(6) NULL,
  [canceled_by] uniqueidentifier NULL,
  [cancel_reason] nvarchar(max) COLLATE Latin1_General_100_BIN2 NULL,
  [version] int NOT NULL DEFAULT 1,
  [is_twin] bit NOT NULL DEFAULT 0,
  [container_number_2] nvarchar(11) COLLATE Latin1_General_100_BIN2 NULL,
  [iso_code_2] nvarchar(4) COLLATE Latin1_General_100_BIN2 NULL,
  [armateur_id_2] nvarchar(64) COLLATE Latin1_General_100_BIN2 NULL,
  [booking_reference_2] nvarchar(150) COLLATE Latin1_General_100_BIN2 NULL,
  [client_order_reference] nvarchar(150) COLLATE Latin1_General_100_BIN2 NULL,
  [carrier_booking_reference] nvarchar(150) COLLATE Latin1_General_100_BIN2 NULL,
  [carrier_booking_armateur_id] nvarchar(64) COLLATE Latin1_General_100_BIN2 NULL,
  [carrier_booking_armateur_id_2] nvarchar(64) COLLATE Latin1_General_100_BIN2 NULL,
  [order_item_id] uniqueidentifier NULL,
  [order_item_id_2] uniqueidentifier NULL,
  [order_controlled] bit NOT NULL DEFAULT 0,
  CONSTRAINT [truck_visits_pkey] PRIMARY KEY ([id]),
  CHECK (([entry_kind]=N'loaded' AND [container_number] IS NOT NULL) OR ([entry_kind]=N'empty' AND [booking_id] IS NOT NULL)),
  CHECK ([carrier_booking_reference] IS NULL OR LEN(TRIM([carrier_booking_reference])) BETWEEN 1 AND 150),
  CHECK ([exited_at] IS NULL OR ([engin_at] IS NOT NULL AND [canceled_at] IS NULL)),
  CHECK ([canceled_at] IS NULL OR ([exited_at] IS NULL AND LEN(TRIM([cancel_reason]))>0)),
  CHECK ([client_order_reference] IS NULL OR LEN(TRIM([client_order_reference])) BETWEEN 1 AND 150),
  CHECK ([entry_kind] IN (N'loaded',N'empty'))
);

CREATE TABLE [dbo].[user_roles] (
  [user_id] uniqueidentifier NOT NULL,
  [role] nvarchar(16) COLLATE Latin1_General_100_BIN2 NOT NULL,
  CONSTRAINT [user_roles_pkey] PRIMARY KEY ([user_id],[role]),
  CHECK ([role] IN (N'admin',N'entree',N'engin',N'sortie',N'viewer'))
);

CREATE TABLE [dbo].[visit_events] (
  [id] bigint IDENTITY(1,1) NOT NULL,
  [visit_id] uniqueidentifier NOT NULL,
  [action] nvarchar(64) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [occurred_at] datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00'),
  [actor_id] uniqueidentifier NOT NULL,
  [details] nvarchar(max) NOT NULL DEFAULT N'{}',
  CHECK ([details] IS NULL OR ISJSON([details],VALUE)=1),
  CONSTRAINT [visit_events_pkey] PRIMARY KEY ([id]),
  CHECK ([action] IN (N'ENTREE',N'DEPOSE',N'PRISE',N'SORTIE',N'ANNULATION'))
);

CREATE TABLE [dbo].[yard_operations] (
  [id] uniqueidentifier NOT NULL DEFAULT NEWID(),
  [visit_id] uniqueidentifier NOT NULL,
  [kind] nvarchar(32) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [container_number] nvarchar(11) COLLATE Latin1_General_100_BIN2 NOT NULL,
  [position] nvarchar(max) COLLATE Latin1_General_100_BIN2 NULL,
  [performed_at] datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00'),
  [performed_by] uniqueidentifier NOT NULL,
  CONSTRAINT [yard_operations_pkey] PRIMARY KEY ([id]),
  CONSTRAINT [yard_operations_visit_id_key] UNIQUE ([visit_id]),
  CHECK ([kind] IN (N'depose',N'prise'))
);

ALTER TABLE [internal].[transport_order_aliases] WITH CHECK ADD CONSTRAINT [transport_order_aliases_order_id_fkey] FOREIGN KEY ([order_id]) REFERENCES [dbo].[transport_orders] ([id]);

ALTER TABLE [dbo].[audit_logs] WITH CHECK ADD CONSTRAINT [audit_logs_actor_id_fkey] FOREIGN KEY ([actor_id]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[bookings] WITH CHECK ADD CONSTRAINT [bookings_armateur_id_fkey] FOREIGN KEY ([armateur_id]) REFERENCES [dbo].[armateurs] ([id]);

ALTER TABLE [dbo].[bookings] WITH CHECK ADD CONSTRAINT [bookings_client_id_fkey] FOREIGN KEY ([client_id]) REFERENCES [dbo].[clients] ([id]);

ALTER TABLE [dbo].[client_armateurs] WITH CHECK ADD CONSTRAINT [client_armateurs_armateur_id_fkey] FOREIGN KEY ([armateur_id]) REFERENCES [dbo].[armateurs] ([id]);

ALTER TABLE [dbo].[client_armateurs] WITH CHECK ADD CONSTRAINT [client_armateurs_client_id_fkey] FOREIGN KEY ([client_id]) REFERENCES [dbo].[clients] ([id]);

ALTER TABLE [dbo].[container_stock_intervals] WITH CHECK ADD CONSTRAINT [container_stock_intervals_armateur_id_fkey] FOREIGN KEY ([armateur_id]) REFERENCES [dbo].[armateurs] ([id]);

ALTER TABLE [dbo].[container_stock_intervals] WITH CHECK ADD CONSTRAINT [container_stock_intervals_client_id_fkey] FOREIGN KEY ([client_id]) REFERENCES [dbo].[clients] ([id]);

ALTER TABLE [dbo].[container_stock_intervals] WITH CHECK ADD CONSTRAINT [container_stock_intervals_container_number_fkey] FOREIGN KEY ([container_number]) REFERENCES [dbo].[containers] ([number]);

ALTER TABLE [dbo].[container_stock_intervals] WITH CHECK ADD CONSTRAINT [container_stock_intervals_end_visit_id_fkey] FOREIGN KEY ([end_visit_id]) REFERENCES [dbo].[truck_visits] ([id]);

ALTER TABLE [dbo].[container_stock_intervals] WITH CHECK ADD CONSTRAINT [container_stock_intervals_start_visit_id_fkey] FOREIGN KEY ([start_visit_id]) REFERENCES [dbo].[truck_visits] ([id]);

ALTER TABLE [dbo].[containers] WITH CHECK ADD CONSTRAINT [containers_armateur_id_fkey] FOREIGN KEY ([armateur_id]) REFERENCES [dbo].[armateurs] ([id]);

ALTER TABLE [dbo].[document_actions] WITH CHECK ADD CONSTRAINT [document_actions_actor_id_fkey] FOREIGN KEY ([actor_id]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[document_actions] WITH CHECK ADD CONSTRAINT [document_actions_document_id_fkey] FOREIGN KEY ([document_id]) REFERENCES [dbo].[generated_documents] ([id]);

ALTER TABLE [dbo].[evp_rules] WITH CHECK ADD CONSTRAINT [evp_rules_created_by_fkey] FOREIGN KEY ([created_by]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[forced_container_actions] WITH CHECK ADD CONSTRAINT [forced_container_actions_actor_id_fkey] FOREIGN KEY ([actor_id]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[forced_container_actions] WITH CHECK ADD CONSTRAINT [forced_container_actions_container_number_fkey] FOREIGN KEY ([container_number]) REFERENCES [dbo].[containers] ([number]);

ALTER TABLE [dbo].[forced_container_actions] WITH CHECK ADD CONSTRAINT [forced_container_actions_resolved_by_fkey] FOREIGN KEY ([resolved_by]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[forced_container_actions] WITH CHECK ADD CONSTRAINT [forced_container_actions_visit_id_fkey] FOREIGN KEY ([visit_id]) REFERENCES [dbo].[truck_visits] ([id]);

ALTER TABLE [dbo].[generated_documents] WITH CHECK ADD CONSTRAINT [generated_documents_created_by_fkey] FOREIGN KEY ([created_by]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[generated_documents] WITH CHECK ADD CONSTRAINT [generated_documents_event_id_fkey] FOREIGN KEY ([event_id]) REFERENCES [dbo].[visit_events] ([id]);

ALTER TABLE [dbo].[generated_documents] WITH CHECK ADD CONSTRAINT [generated_documents_visit_id_fkey] FOREIGN KEY ([visit_id]) REFERENCES [dbo].[truck_visits] ([id]);

ALTER TABLE [dbo].[printer_settings] WITH CHECK ADD CONSTRAINT [printer_settings_user_id_fkey] FOREIGN KEY ([user_id]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[transport_order_items] WITH CHECK ADD CONSTRAINT [transport_order_items_armateur_id_fkey] FOREIGN KEY ([armateur_id]) REFERENCES [dbo].[armateurs] ([id]);

ALTER TABLE [dbo].[transport_order_items] WITH CHECK ADD CONSTRAINT [transport_order_items_order_id_fkey] FOREIGN KEY ([order_id]) REFERENCES [dbo].[transport_orders] ([id]);

ALTER TABLE [dbo].[transport_orders] WITH CHECK ADD CONSTRAINT [transport_orders_armateur_id_fkey] FOREIGN KEY ([armateur_id]) REFERENCES [dbo].[armateurs] ([id]);

ALTER TABLE [dbo].[transport_orders] WITH CHECK ADD CONSTRAINT [transport_orders_client_id_fkey] FOREIGN KEY ([client_id]) REFERENCES [dbo].[clients] ([id]);

ALTER TABLE [dbo].[transport_orders] WITH CHECK ADD CONSTRAINT [transport_orders_created_by_fkey] FOREIGN KEY ([created_by]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[transport_orders] WITH CHECK ADD CONSTRAINT [transport_orders_updated_by_fkey] FOREIGN KEY ([updated_by]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[truck_visits] WITH CHECK ADD CONSTRAINT [truck_visits_armateur_id_2_fkey] FOREIGN KEY ([armateur_id_2]) REFERENCES [dbo].[armateurs] ([id]);

ALTER TABLE [dbo].[truck_visits] WITH CHECK ADD CONSTRAINT [truck_visits_armateur_id_fkey] FOREIGN KEY ([armateur_id]) REFERENCES [dbo].[armateurs] ([id]);

ALTER TABLE [dbo].[truck_visits] WITH CHECK ADD CONSTRAINT [truck_visits_booking_id_fkey] FOREIGN KEY ([booking_id]) REFERENCES [dbo].[bookings] ([id]);

ALTER TABLE [dbo].[truck_visits] WITH CHECK ADD CONSTRAINT [truck_visits_canceled_by_fkey] FOREIGN KEY ([canceled_by]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[truck_visits] WITH CHECK ADD CONSTRAINT [truck_visits_carrier_booking_armateur_id_2_fkey] FOREIGN KEY ([carrier_booking_armateur_id_2]) REFERENCES [dbo].[armateurs] ([id]);

ALTER TABLE [dbo].[truck_visits] WITH CHECK ADD CONSTRAINT [truck_visits_carrier_booking_armateur_id_fkey] FOREIGN KEY ([carrier_booking_armateur_id]) REFERENCES [dbo].[armateurs] ([id]);

ALTER TABLE [dbo].[truck_visits] WITH CHECK ADD CONSTRAINT [truck_visits_client_id_fkey] FOREIGN KEY ([client_id]) REFERENCES [dbo].[clients] ([id]);

ALTER TABLE [dbo].[truck_visits] WITH CHECK ADD CONSTRAINT [truck_visits_container_number_2_fkey] FOREIGN KEY ([container_number_2]) REFERENCES [dbo].[containers] ([number]);

ALTER TABLE [dbo].[truck_visits] WITH CHECK ADD CONSTRAINT [truck_visits_container_number_fkey] FOREIGN KEY ([container_number]) REFERENCES [dbo].[containers] ([number]);

ALTER TABLE [dbo].[truck_visits] WITH CHECK ADD CONSTRAINT [truck_visits_engin_by_fkey] FOREIGN KEY ([engin_by]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[truck_visits] WITH CHECK ADD CONSTRAINT [truck_visits_entered_by_fkey] FOREIGN KEY ([entered_by]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[truck_visits] WITH CHECK ADD CONSTRAINT [truck_visits_exited_by_fkey] FOREIGN KEY ([exited_by]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[truck_visits] WITH CHECK ADD CONSTRAINT [truck_visits_order_item_id_2_fkey] FOREIGN KEY ([order_item_id_2]) REFERENCES [dbo].[transport_order_items] ([id]);

ALTER TABLE [dbo].[truck_visits] WITH CHECK ADD CONSTRAINT [truck_visits_order_item_id_fkey] FOREIGN KEY ([order_item_id]) REFERENCES [dbo].[transport_order_items] ([id]);

ALTER TABLE [dbo].[user_roles] WITH CHECK ADD CONSTRAINT [user_roles_user_id_fkey] FOREIGN KEY ([user_id]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[visit_events] WITH CHECK ADD CONSTRAINT [visit_events_actor_id_fkey] FOREIGN KEY ([actor_id]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[visit_events] WITH CHECK ADD CONSTRAINT [visit_events_visit_id_fkey] FOREIGN KEY ([visit_id]) REFERENCES [dbo].[truck_visits] ([id]);

ALTER TABLE [dbo].[yard_operations] WITH CHECK ADD CONSTRAINT [yard_operations_container_number_fkey] FOREIGN KEY ([container_number]) REFERENCES [dbo].[containers] ([number]);

ALTER TABLE [dbo].[yard_operations] WITH CHECK ADD CONSTRAINT [yard_operations_performed_by_fkey] FOREIGN KEY ([performed_by]) REFERENCES [dbo].[profiles] ([id]);

ALTER TABLE [dbo].[yard_operations] WITH CHECK ADD CONSTRAINT [yard_operations_visit_id_fkey] FOREIGN KEY ([visit_id]) REFERENCES [dbo].[truck_visits] ([id]);


ALTER TABLE dbo.transport_orders ADD normalized_reference AS UPPER(TRIM(reference)) PERSISTED;
CREATE UNIQUE INDEX transport_orders_reference_key ON dbo.transport_orders(normalized_reference);
CREATE UNIQUE INDEX generated_documents_path_key ON dbo.generated_documents(storage_path) WHERE storage_path IS NOT NULL;
CREATE UNIQUE INDEX one_open_stock_interval ON dbo.container_stock_intervals(container_number) WHERE departed_at IS NULL;
-- A computed SHA-256 key permits indexing arbitrary-length historical position strings.
ALTER TABLE dbo.container_stock_intervals ADD position_hash AS CONVERT(binary(32),HASHBYTES('SHA2_256',position)) PERSISTED;
CREATE UNIQUE INDEX one_open_yard_position ON dbo.container_stock_intervals(position_hash) WHERE departed_at IS NULL AND position IS NOT NULL;
CREATE UNIQUE INDEX idx_profiles_phone_unique ON dbo.profiles(phone) WHERE phone IS NOT NULL AND phone<>N'';
-- SQL Server filtered indexes cannot express the PostgreSQL OR predicate. Inactive rows
-- use their UUID as a distinct key, while active rows use the container number.
ALTER TABLE dbo.truck_visits ADD active_container_key AS
  CASE WHEN container_number IS NOT NULL AND canceled_at IS NULL AND exited_at IS NULL
    AND ((entry_kind=N'loaded' AND engin_at IS NULL) OR (entry_kind=N'empty' AND engin_at IS NOT NULL))
    THEN CONVERT(nvarchar(36),container_number) ELSE CONVERT(nvarchar(36),id) END PERSISTED;
ALTER TABLE dbo.truck_visits ADD active_container_2_key AS
  CASE WHEN container_number_2 IS NOT NULL AND canceled_at IS NULL AND exited_at IS NULL
    AND ((entry_kind=N'loaded' AND engin_at IS NULL) OR (entry_kind=N'empty' AND engin_at IS NOT NULL))
    THEN CONVERT(nvarchar(36),container_number_2) ELSE CONVERT(nvarchar(36),id) END PERSISTED;
CREATE UNIQUE INDEX one_active_container_on_truck ON dbo.truck_visits(active_container_key);
CREATE UNIQUE INDEX one_active_container_2_on_truck ON dbo.truck_visits(active_container_2_key);
CREATE INDEX visits_order_item_idx ON dbo.truck_visits(order_item_id) INCLUDE(canceled_at,engin_at,exited_at);
CREATE INDEX visits_order_item_2_idx ON dbo.truck_visits(order_item_id_2) INCLUDE(canceled_at,engin_at,exited_at);
CREATE INDEX visits_inside_idx ON dbo.truck_visits(entered_at,id) WHERE exited_at IS NULL AND canceled_at IS NULL;
CREATE INDEX audit_entity_idx ON dbo.audit_logs(entity,entity_id,occurred_at);
CREATE INDEX documents_visit_idx ON dbo.generated_documents(visit_id,created_at);
INSERT internal.schema_versions(version) VALUES(1);
COMMIT TRANSACTION;
GO
