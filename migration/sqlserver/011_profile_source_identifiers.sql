-- Additive upgrade from installed Gate schema 4. Execute in one deployment transaction.
-- Source metadata was verified on 2026-11-21. No source password is copied.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF @@TRANCOUNT=0 THROW 51000, 'Use the transactional identifiers upgrade wrapper.', 1;
IF (SELECT COUNT(*) FROM internal.schema_versions WHERE version IN(1,2,3,4))<>4
 OR (SELECT MAX(version) FROM internal.schema_versions)<>4
 THROW 51000, 'Exactly installed schema versions 1/2/3/4 required; do not replay.', 1;
IF COL_LENGTH(N'dbo.profiles',N'username') IS NOT NULL
 THROW 51000, 'Unexpected existing profiles.username column; investigate before upgrade.', 1;
-- Historical metadata only. Normal authentication continues to use internal.local_accounts.
-- Nullable for profiles subsequently created by the existing Admin API; no login is activated.
ALTER TABLE dbo.profiles ADD username nvarchar(max) COLLATE Latin1_General_100_BIN2 NULL;
INSERT internal.schema_versions(version) VALUES(5);
