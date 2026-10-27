-- Local application accounts. Apply after 001/002, using the DBA deployment identity.
-- No AD, Entra, professional email or source password is required/imported.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF NOT EXISTS(SELECT 1 FROM internal.schema_versions WHERE version=2) THROW 51000, 'Schema version 2 is required.', 1;
IF EXISTS(SELECT 1 FROM internal.schema_versions WHERE version=3) THROW 51000, 'Version 3 is already installed.', 1;
BEGIN TRANSACTION;
CREATE TABLE internal.local_accounts (
  user_id uniqueidentifier NOT NULL PRIMARY KEY REFERENCES dbo.profiles(id),
  username nvarchar(100) COLLATE Latin1_General_100_BIN2 NOT NULL,
  normalized_username AS UPPER(username) PERSISTED,
  password_hash nvarchar(512) NOT NULL,
  must_change_password bit NOT NULL DEFAULT 1,
  version int NOT NULL DEFAULT 1 CHECK(version>0),
  failed_attempts int NOT NULL DEFAULT 0 CHECK(failed_attempts BETWEEN 0 AND 5),
  locked_until datetimeoffset(6) NULL,
  created_at datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00'),
  CHECK (DATALENGTH(username) BETWEEN 6 AND 200 AND username NOT LIKE N'%[^A-Za-z0-9@._+-]%'),
  CHECK (LEN(password_hash) BETWEEN 40 AND 512)
);
CREATE UNIQUE INDEX local_accounts_username_key ON internal.local_accounts(normalized_username);
CREATE TABLE internal.application_sessions (
  token_hash binary(32) NOT NULL PRIMARY KEY,
  user_id uniqueidentifier NOT NULL REFERENCES internal.local_accounts(user_id),
  expires_at datetimeoffset(6) NOT NULL,
  created_at datetimeoffset(6) NOT NULL DEFAULT TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00')
);
CREATE INDEX application_sessions_user_idx ON internal.application_sessions(user_id);
CREATE INDEX application_sessions_expiry_idx ON internal.application_sessions(expires_at);
GO
CREATE OR ALTER PROCEDURE internal.account_admin_lock AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @lock int;
  EXEC @lock=sys.sp_getapplock @Resource=N'pointage-admin-accounts',@LockMode=N'Exclusive',@LockOwner=N'Transaction',@LockTimeout=10000;
  IF @lock<0 THROW 51009, 'Account management busy; retry after refresh.', 1;
END;
GO
CREATE OR ALTER PROCEDURE api.account_credentials @Username nvarchar(100) AS
BEGIN
  SET NOCOUNT ON;
  SELECT (SELECT a.user_id,a.password_hash,a.version FROM internal.local_accounts a
    WHERE a.normalized_username=@Username FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
END;
GO
CREATE OR ALTER PROCEDURE api.account_own_credentials @ActorId uniqueidentifier AS
BEGIN
  SET NOCOUNT ON;
  SELECT (SELECT a.password_hash,a.version FROM internal.local_accounts a JOIN dbo.profiles p ON p.id=a.user_id
    WHERE a.user_id=@ActorId AND p.active=1 FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
END;
GO
CREATE OR ALTER PROCEDURE api.account_login @UserId uniqueidentifier,@ExpectedVersion int,@ExpectedHash nvarchar(512),
  @Verified bit,@ReplacementHash nvarchar(512)=NULL,@TokenHash varbinary(32),@SessionHours int AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  IF @SessionHours NOT BETWEEN 1 AND 12 OR DATALENGTH(@TokenHash)<>32 OR @TokenHash IS NULL
    THROW 51004, 'Invalid session settings.', 1;
  DECLARE @now datetimeoffset(6)=TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00'),@failed int,@locked datetimeoffset(6),@change bit;
  BEGIN TRY
    BEGIN TRANSACTION;
    SELECT @failed=a.failed_attempts,@locked=a.locked_until,@change=a.must_change_password
      FROM internal.local_accounts a WITH(UPDLOCK,HOLDLOCK) JOIN dbo.profiles p ON p.id=a.user_id
      WHERE a.user_id=@UserId AND a.version=@ExpectedVersion AND p.active=1
        AND a.password_hash COLLATE Latin1_General_100_BIN2=@ExpectedHash COLLATE Latin1_General_100_BIN2;
    IF @failed IS NULL OR @locked>@now BEGIN COMMIT; RETURN; END;
    IF @Verified<>1 OR @Verified IS NULL
    BEGIN
      SET @failed=CASE WHEN @locked IS NOT NULL AND @locked<=@now THEN 1 WHEN @failed<5 THEN @failed+1 ELSE 5 END;
      UPDATE internal.local_accounts SET failed_attempts=@failed,locked_until=CASE WHEN @failed>=5 THEN DATEADD(minute,15,@now) ELSE NULL END WHERE user_id=@UserId;
      COMMIT; RETURN;
    END;
    UPDATE internal.local_accounts SET failed_attempts=0,locked_until=NULL,password_hash=COALESCE(@ReplacementHash,password_hash) WHERE user_id=@UserId;
    DECLARE @expires datetimeoffset(6)=DATEADD(hour,@SessionHours,@now);
    DELETE internal.application_sessions WHERE user_id=@UserId AND expires_at<=@now;
    INSERT internal.application_sessions(token_hash,user_id,expires_at) VALUES(@TokenHash,@UserId,@expires);
    INSERT dbo.audit_logs(entity,entity_id,action,actor_id) VALUES(N'account',CONVERT(nvarchar(36),@UserId),N'LOGIN',@UserId);
    COMMIT;
    SELECT (SELECT @expires expires_at,@change must_change_password FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
  END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE api.account_session @TokenHash varbinary(32) AS
BEGIN
  SET NOCOUNT ON;
  SELECT (SELECT a.user_id,a.must_change_password FROM internal.application_sessions s
    JOIN internal.local_accounts a ON a.user_id=s.user_id JOIN dbo.profiles p ON p.id=a.user_id
    WHERE s.token_hash=@TokenHash AND s.expires_at>TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00') AND p.active=1
    FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
END;
GO
CREATE OR ALTER PROCEDURE api.account_logout @TokenHash varbinary(32) AS
BEGIN
  SET NOCOUNT ON;
  DELETE internal.application_sessions WHERE token_hash=@TokenHash;
END;
GO
CREATE OR ALTER PROCEDURE api.account_change_password @ActorId uniqueidentifier,@ExpectedVersion int,
  @PasswordHash nvarchar(512),@TokenHash varbinary(32) AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE a WITH(UPDLOCK) SET password_hash=@PasswordHash,must_change_password=0,version=version+1,failed_attempts=0,locked_until=NULL
      FROM internal.local_accounts a JOIN dbo.profiles p ON p.id=a.user_id
      WHERE a.user_id=@ActorId AND a.version=@ExpectedVersion AND p.active=1
        AND EXISTS(SELECT 1 FROM internal.application_sessions s WHERE s.user_id=@ActorId AND s.token_hash=@TokenHash
          AND s.expires_at>TODATETIMEOFFSET(SYSUTCDATETIME(),'+00:00'));
    IF @@ROWCOUNT<>1 BEGIN COMMIT; SELECT 0; RETURN; END;
    DELETE internal.application_sessions WHERE user_id=@ActorId;
    INSERT dbo.audit_logs(entity,entity_id,action,actor_id) VALUES(N'account',CONVERT(nvarchar(36),@ActorId),N'PASSWORD_CHANGED',@ActorId);
    COMMIT; SELECT 1;
  END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE internal.validate_account @Username nvarchar(100),@PasswordHash nvarchar(512),@Roles nvarchar(max) AS
BEGIN
  SET NOCOUNT ON;
  IF @Username IS NULL OR DATALENGTH(@Username) NOT BETWEEN 6 AND 200 OR @Username COLLATE Latin1_General_100_BIN2 LIKE N'%[^A-Za-z0-9@._+-]%'
    OR @PasswordHash IS NULL OR LEN(@PasswordHash) NOT BETWEEN 40 AND 512 THROW 51004, 'Invalid account.', 1;
  IF ISJSON(@Roles,ARRAY)<>1 OR @Roles IS NULL THROW 51004, 'Roles must be an array.', 1;
  IF (SELECT COUNT(*) FROM OPENJSON(@Roles)) NOT BETWEEN 1 AND 5
    OR EXISTS(SELECT 1 FROM OPENJSON(@Roles) WHERE type<>1 OR value COLLATE Latin1_General_100_BIN2 NOT IN(N'admin',N'entree',N'engin',N'sortie',N'viewer'))
    OR EXISTS(SELECT 1 FROM OPENJSON(@Roles) GROUP BY value COLLATE Latin1_General_100_BIN2 HAVING COUNT(*)>1)
    THROW 51004, 'Invalid roles.', 1;
END;
GO
CREATE OR ALTER PROCEDURE api.account_create @ActorId uniqueidentifier,@Username nvarchar(100),@DisplayName nvarchar(200),
  @PasswordHash nvarchar(512),@Roles nvarchar(max),@ExistingProfileId uniqueidentifier=NULL AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  IF api.can_do(@ActorId,N'admin')=0 THROW 51003, 'Only Admin creates accounts.', 1;
  EXEC internal.validate_account @Username,@PasswordHash,@Roles;
  IF @DisplayName IS NULL OR LEN(TRIM(@DisplayName))=0 THROW 51004, 'Display name required.', 1;
  BEGIN TRY
    BEGIN TRANSACTION;
    EXEC internal.account_admin_lock;
    IF api.can_do(@ActorId,N'admin')=0 THROW 51003, 'Only Admin creates accounts.', 1;
    DECLARE @user uniqueidentifier=COALESCE(@ExistingProfileId,NEWID());
    IF @ExistingProfileId IS NULL INSERT dbo.profiles(id,display_name) VALUES(@user,TRIM(@DisplayName));
    ELSE IF NOT EXISTS(SELECT 1 FROM dbo.profiles WHERE id=@user) THROW 51002, 'Historical profile not found.', 1;
    ELSE IF EXISTS(SELECT 1 FROM internal.local_accounts WHERE user_id=@user) THROW 51009, 'Profile already has an account.', 1;
    -- Existing profile UUID/identity are retained; roles are an explicit Admin decision.
    INSERT internal.local_accounts(user_id,username,password_hash) VALUES(@user,@Username,@PasswordHash);
    DELETE dbo.user_roles WHERE user_id=@user;
    INSERT dbo.user_roles(user_id,role) SELECT @user,value FROM OPENJSON(@Roles);
    INSERT dbo.audit_logs(entity,entity_id,action,actor_id,after_data) VALUES(N'account',CONVERT(nvarchar(36),@user),N'CREATION',@ActorId,
      (SELECT @Username username,JSON_QUERY(@Roles) roles FOR JSON PATH,WITHOUT_ARRAY_WRAPPER));
    COMMIT;
    SELECT (SELECT @user id,1 version,CAST(1 AS bit) must_change_password FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
  END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE api.account_list @ActorId uniqueidentifier AS
BEGIN
  SET NOCOUNT ON;
  IF api.can_do(@ActorId,N'admin')=0 THROW 51003, 'Only Admin lists accounts.', 1;
  SELECT (SELECT p.id,p.display_name,p.active,a.username,a.version,a.must_change_password,
    JSON_QUERY((SELECT role FROM dbo.user_roles WHERE user_id=p.id FOR JSON PATH)) roles
    FROM internal.local_accounts a JOIN dbo.profiles p ON p.id=a.user_id ORDER BY a.username FOR JSON PATH);
END;
GO
CREATE OR ALTER PROCEDURE api.account_update @ActorId uniqueidentifier,@UserId uniqueidentifier,@ExpectedVersion int,@Active bit,@Roles nvarchar(max) AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  IF api.can_do(@ActorId,N'admin')=0 THROW 51003, 'Only Admin manages accounts.', 1;
  -- Reuse role validation with valid non-credential placeholder values; no password changes here.
  DECLARE @placeholder nvarchar(512)=REPLICATE(N'x',40);
  EXEC internal.validate_account N'validation',@placeholder,@Roles;
  IF @Active IS NULL THROW 51004, 'Active flag required.', 1;
  BEGIN TRY
    BEGIN TRANSACTION;
    EXEC internal.account_admin_lock;
    IF api.can_do(@ActorId,N'admin')=0 THROW 51003, 'Only Admin manages accounts.', 1;
    IF NOT EXISTS(SELECT 1 FROM internal.local_accounts WITH(UPDLOCK,HOLDLOCK) WHERE user_id=@UserId AND version=@ExpectedVersion)
      THROW 51009, 'Account changed; refresh required.', 1;
    UPDATE dbo.profiles SET active=@Active WHERE id=@UserId;
    DELETE dbo.user_roles WHERE user_id=@UserId;
    INSERT dbo.user_roles(user_id,role) SELECT @UserId,value FROM OPENJSON(@Roles);
    IF NOT EXISTS(SELECT 1 FROM internal.local_accounts a JOIN dbo.profiles p ON p.id=a.user_id
      JOIN dbo.user_roles r ON r.user_id=p.id WHERE p.active=1 AND r.role=N'admin') THROW 51004, 'Keep at least one active Admin account.', 1;
    UPDATE internal.local_accounts SET version=version+1 WHERE user_id=@UserId;
    DELETE internal.application_sessions WHERE user_id=@UserId;
    INSERT dbo.audit_logs(entity,entity_id,action,actor_id,after_data) VALUES(N'account',CONVERT(nvarchar(36),@UserId),N'MODIFICATION',@ActorId,
      (SELECT @Active active,JSON_QUERY(@Roles) roles FOR JSON PATH,WITHOUT_ARRAY_WRAPPER));
    COMMIT;
    SELECT (SELECT @UserId id,@ExpectedVersion+1 version FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
  END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE api.account_reset_password @ActorId uniqueidentifier,@UserId uniqueidentifier,@ExpectedVersion int,@PasswordHash nvarchar(512) AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  IF api.can_do(@ActorId,N'admin')=0 THROW 51003, 'Only Admin resets passwords.', 1;
  IF @ActorId=@UserId THROW 51004, 'Use authenticated password change for your own account.', 1;
  BEGIN TRY
    BEGIN TRANSACTION;
    EXEC internal.account_admin_lock;
    IF api.can_do(@ActorId,N'admin')=0 THROW 51003, 'Only Admin resets passwords.', 1;
    UPDATE internal.local_accounts SET password_hash=@PasswordHash,must_change_password=1,version=version+1,failed_attempts=0,locked_until=NULL
      WHERE user_id=@UserId AND version=@ExpectedVersion;
    IF @@ROWCOUNT<>1 THROW 51009, 'Account changed; refresh required.', 1;
    DELETE internal.application_sessions WHERE user_id=@UserId;
    INSERT dbo.audit_logs(entity,entity_id,action,actor_id) VALUES(N'account',CONVERT(nvarchar(36),@UserId),N'PASSWORD_RESET',@ActorId);
    COMMIT;
    SELECT (SELECT @UserId id,@ExpectedVersion+1 version,CAST(1 AS bit) must_change_password FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
  END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE internal.bootstrap_admin @Username nvarchar(100),@DisplayName nvarchar(200),@PasswordHash nvarchar(512),@ExistingProfileId uniqueidentifier=NULL AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  EXEC internal.validate_account @Username,@PasswordHash,N'["admin"]';
  IF @DisplayName IS NULL OR LEN(TRIM(@DisplayName))=0 THROW 51004, 'Display name required.', 1;
  BEGIN TRY
    BEGIN TRANSACTION;
    EXEC internal.account_admin_lock;
    IF EXISTS(SELECT 1 FROM internal.local_accounts) THROW 51004, 'Bootstrap only permits the first account.', 1;
    DECLARE @user uniqueidentifier=COALESCE(@ExistingProfileId,NEWID());
    IF @ExistingProfileId IS NULL INSERT dbo.profiles(id,display_name) VALUES(@user,TRIM(@DisplayName));
    ELSE IF NOT EXISTS(SELECT 1 FROM dbo.profiles WHERE id=@user) THROW 51002, 'Historical profile not found.', 1;
    INSERT internal.local_accounts(user_id,username,password_hash) VALUES(@user,@Username,@PasswordHash);
    IF NOT EXISTS(SELECT 1 FROM dbo.user_roles WHERE user_id=@user AND role=N'admin') INSERT dbo.user_roles(user_id,role) VALUES(@user,N'admin');
    UPDATE dbo.profiles SET active=1 WHERE id=@user;
    INSERT dbo.audit_logs(entity,entity_id,action,actor_id) VALUES(N'account',CONVERT(nvarchar(36),@user),N'BOOTSTRAP',@user);
    COMMIT; SELECT @user;
  END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
END;
GO
-- pointage_api has EXECUTE on api from 002; internal.bootstrap_admin remains DBA-only.
INSERT internal.schema_versions(version) VALUES(3);
COMMIT TRANSACTION;
GO
