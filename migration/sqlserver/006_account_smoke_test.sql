-- Run ONLY on an empty _Test database after 001/002/005, using sqlcmd -b.
-- All fixtures are synthetic, password strings are NOT deployable hashes, and every block rolls back.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() NOT LIKE N'%[_]Test' THROW 51000, 'Use a dedicated _Test database.', 1;
IF NOT EXISTS(SELECT 1 FROM internal.schema_versions WHERE version=3) THROW 51000, 'Apply account version 3 first.', 1;
IF EXISTS(SELECT 1 FROM dbo.profiles) OR EXISTS(SELECT 1 FROM internal.local_accounts)
  THROW 51000, 'Run account tests before importing data or bootstrapping accounts.', 1;
GO
-- Backend database identity can execute the API, but cannot bootstrap an Admin or read credential tables.
BEGIN TRY
  BEGIN TRANSACTION;
  CREATE USER qa_pointage_account_api WITHOUT LOGIN;
  ALTER ROLE pointage_api ADD MEMBER qa_pointage_account_api;
  DECLARE @bootstrap int,@credentials int,@api int;
  EXECUTE AS USER=N'qa_pointage_account_api';
  SELECT @bootstrap=COALESCE(HAS_PERMS_BY_NAME(N'internal.bootstrap_admin',N'OBJECT',N'EXECUTE'),0),
    @credentials=COALESCE(HAS_PERMS_BY_NAME(N'internal.local_accounts',N'OBJECT',N'SELECT'),0),
    @api=COALESCE(HAS_PERMS_BY_NAME(N'api.account_create',N'OBJECT',N'EXECUTE'),0);
  REVERT;
  IF @bootstrap<>0 OR @credentials<>0 OR @api<>1 THROW 51099, 'Backend database permissions are incorrect.', 1;
  ROLLBACK;
  PRINT 'PASS: API execution allowed; direct credential reads and Admin bootstrap denied.';
END TRY BEGIN CATCH
  IF USER_NAME()=N'qa_pointage_account_api' REVERT;
  IF @@TRANCOUNT>0 ROLLBACK;
  THROW;
END CATCH;
GO
-- First Admin, historical identity mapping and password change revoke every session.
BEGIN TRY
  BEGIN TRANSACTION;
  DECLARE @response table(payload nvarchar(max)),@admin uniqueidentifier,@existing uniqueidentifier=NEWID(),
    @hash nvarchar(512)=REPLICATE(N'x',40),@nextHash nvarchar(512)=REPLICATE(N'y',40),
    @token varbinary(32)=HASHBYTES('SHA2_256',N'synthetic-session-1'),@token2 varbinary(32)=HASHBYTES('SHA2_256',N'synthetic-session-2');
  DECLARE @ids table(id uniqueidentifier);
  INSERT @ids EXEC internal.bootstrap_admin N'admin01',N'QA Admin',@hash;
  SELECT @admin=id FROM @ids;
  IF @admin IS NULL OR api.can_do(@admin,N'admin')<>1 THROW 51099, 'First Admin missing.', 1;
  INSERT dbo.profiles(id,display_name) VALUES(@existing,N'Preserved historical agent');
  INSERT @response EXEC api.account_create @admin,N'agent01',N'New name ignored for existing profile',@hash,N'["entree"]',@existing;
  IF JSON_VALUE((SELECT TOP(1) payload FROM @response),'$.id')<>CONVERT(nvarchar(36),@existing) THROW 51099, 'Profile UUID changed.', 1;
  IF (SELECT display_name FROM dbo.profiles WHERE id=@existing)<>N'Preserved historical agent' THROW 51099, 'Historical identity overwritten.', 1;
  DELETE @response;
  INSERT @response EXEC api.account_login @existing,1,@hash,1,NULL,@token,8;
  IF NOT EXISTS(SELECT 1 FROM internal.application_sessions WHERE token_hash=@token AND user_id=@existing) THROW 51099, 'Login session missing.', 1;
  IF JSON_VALUE((SELECT payload FROM @response),'$.must_change_password')<>N'true' THROW 51099, 'Initial password change not required.', 1;
  INSERT internal.application_sessions(token_hash,user_id,expires_at) VALUES(@token2,@existing,DATEADD(hour,1,SYSDATETIMEOFFSET()));
  DECLARE @changed table(value int);
  INSERT @changed EXEC api.account_change_password @existing,1,@nextHash,@token;
  IF NOT EXISTS(SELECT 1 FROM @changed WHERE value=1) THROW 51099, 'Password change refused.', 1;
  IF EXISTS(SELECT 1 FROM internal.application_sessions WHERE user_id=@existing) THROW 51099, 'Password change retained sessions.', 1;
  IF NOT EXISTS(SELECT 1 FROM internal.local_accounts WHERE user_id=@existing AND version=2 AND must_change_password=0) THROW 51099, 'Password state not updated.', 1;
  ROLLBACK;
  PRINT 'PASS: offline first Admin, preserved profile, normal username, mandatory password change and all-session revocation.';
END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
GO
-- A gate clerk cannot create accounts even if they request an Admin role.
BEGIN TRY
  BEGIN TRANSACTION;
  DECLARE @clerk uniqueidentifier=NEWID(),@hash nvarchar(512)=REPLICATE(N'x',40);
  INSERT dbo.profiles(id,display_name) VALUES(@clerk,N'QA Clerk');
  INSERT dbo.user_roles(user_id,role) VALUES(@clerk,N'entree');
  EXEC api.account_create @clerk,N'forged-admin',N'Forbidden',@hash,N'["admin"]',NULL;
  THROW 51099, 'Clerk created an account.', 1;
END TRY BEGIN CATCH
  DECLARE @error int=ERROR_NUMBER(); IF @@TRANCOUNT>0 ROLLBACK;
  IF @error<>51003 THROW;
  PRINT 'PASS: clerk account creation denied.';
END CATCH;
GO
-- Serialized role changes cannot remove the final active Admin.
BEGIN TRY
  BEGIN TRANSACTION;
  DECLARE @admin uniqueidentifier=NEWID(),@hash nvarchar(512)=REPLICATE(N'x',40);
  INSERT dbo.profiles(id,display_name) VALUES(@admin,N'QA Admin');
  INSERT dbo.user_roles(user_id,role) VALUES(@admin,N'admin');
  INSERT internal.local_accounts(user_id,username,password_hash) VALUES(@admin,N'admin01',@hash);
  EXEC api.account_update @admin,@admin,1,0,N'["viewer"]';
  THROW 51099, 'Last Admin disabled.', 1;
END TRY BEGIN CATCH
  DECLARE @error int=ERROR_NUMBER(); IF @@TRANCOUNT>0 ROLLBACK;
  IF @error<>51004 THROW;
  PRINT 'PASS: final active Admin preserved.';
END CATCH;
GO
-- Five failed passwords lock the account, expired lock permits login, reset revokes its session.
BEGIN TRY
  BEGIN TRANSACTION;
  DECLARE @admin uniqueidentifier=NEWID(),@agent uniqueidentifier=NEWID(),@hash nvarchar(512)=REPLICATE(N'x',40),
    @nextHash nvarchar(512)=REPLICATE(N'y',40),@token varbinary(32)=HASHBYTES('SHA2_256',N'synthetic-lock-test');
  INSERT dbo.profiles(id,display_name) VALUES(@admin,N'QA Admin'),(@agent,N'QA Agent');
  INSERT dbo.user_roles(user_id,role) VALUES(@admin,N'admin'),(@agent,N'sortie');
  INSERT internal.local_accounts(user_id,username,password_hash,must_change_password) VALUES(@admin,N'admin01',@hash,0),(@agent,N'agent01',@hash,0);
  DECLARE @i int=0;
  WHILE @i<5 BEGIN EXEC api.account_login @agent,1,@hash,0,NULL,@token,8; SET @i+=1; END;
  EXEC api.account_login @agent,1,@hash,1,NULL,@token,8;
  IF EXISTS(SELECT 1 FROM internal.application_sessions WHERE user_id=@agent) THROW 51099, 'Locked account logged in.', 1;
  UPDATE internal.local_accounts SET locked_until=DATEADD(minute,-1,SYSDATETIMEOFFSET()) WHERE user_id=@agent;
  EXEC api.account_login @agent,1,@hash,1,NULL,@token,8;
  IF NOT EXISTS(SELECT 1 FROM internal.application_sessions WHERE user_id=@agent) THROW 51099, 'Expired lock did not permit login.', 1;
  EXEC api.account_reset_password @admin,@agent,1,@nextHash;
  IF EXISTS(SELECT 1 FROM internal.application_sessions WHERE user_id=@agent) THROW 51099, 'Reset retained sessions.', 1;
  IF NOT EXISTS(SELECT 1 FROM internal.local_accounts WHERE user_id=@agent AND version=2 AND must_change_password=1) THROW 51099, 'Reset state failed.', 1;
  IF EXISTS(SELECT 1 FROM dbo.audit_logs WHERE before_data LIKE N'%password%' OR after_data LIKE N'%password%' OR after_data LIKE N'%synthetic-lock-test%')
    THROW 51099, 'Credential material leaked into audit.', 1;
  EXEC api.account_login @agent,2,@nextHash,1,NULL,@token,8;
  UPDATE internal.application_sessions SET expires_at=DATEADD(second,-1,SYSDATETIMEOFFSET()) WHERE token_hash=@token;
  DECLARE @response table(payload nvarchar(max));
  INSERT @response EXEC api.account_session @token;
  IF EXISTS(SELECT 1 FROM @response WHERE JSON_VALUE(payload,'$.user_id') IS NOT NULL) THROW 51099, 'Expired session accepted.', 1;
  EXEC api.account_logout @token;
  IF EXISTS(SELECT 1 FROM internal.application_sessions WHERE token_hash=@token) THROW 51099, 'Logout retained session.', 1;
  EXEC api.account_login @agent,2,@nextHash,1,NULL,@token,8;
  EXEC api.account_update @admin,@agent,2,0,N'["sortie"]';
  IF EXISTS(SELECT 1 FROM internal.application_sessions WHERE user_id=@agent) THROW 51099, 'Disabled user retained sessions.', 1;
  EXEC api.account_login @agent,3,@nextHash,1,NULL,@token,8;
  IF EXISTS(SELECT 1 FROM internal.application_sessions WHERE user_id=@agent) THROW 51099, 'Disabled user logged in.', 1;
  ROLLBACK;
  PRINT 'PASS: lockout, expiry, reset, logout and disabled-user revocation; no credential material in audit.';
END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
GO
-- A stale update must not overwrite another Admin's change.
BEGIN TRY
  BEGIN TRANSACTION;
  DECLARE @admin uniqueidentifier=NEWID(),@hash nvarchar(512)=REPLICATE(N'x',40);
  INSERT dbo.profiles(id,display_name) VALUES(@admin,N'QA Admin');
  INSERT dbo.user_roles(user_id,role) VALUES(@admin,N'admin');
  INSERT internal.local_accounts(user_id,username,password_hash,version) VALUES(@admin,N'admin01',@hash,2);
  EXEC api.account_update @admin,@admin,1,1,N'["admin"]';
  THROW 51099, 'Stale account edit accepted.', 1;
END TRY BEGIN CATCH
  DECLARE @error int=ERROR_NUMBER(); IF @@TRANCOUNT>0 ROLLBACK;
  IF @error<>51009 THROW;
  PRINT 'PASS: stale account update rejected.';
END CATCH;
GO
-- Username uniqueness applies across case; no email-domain policy.
BEGIN TRY
  BEGIN TRANSACTION;
  DECLARE @admin uniqueidentifier=NEWID(),@hash nvarchar(512)=REPLICATE(N'x',40);
  INSERT dbo.profiles(id,display_name) VALUES(@admin,N'QA Admin');
  INSERT dbo.user_roles(user_id,role) VALUES(@admin,N'admin');
  INSERT internal.local_accounts(user_id,username,password_hash) VALUES(@admin,N'admin01',@hash);
  EXEC api.account_create @admin,N'AGENT01',N'QA 1',@hash,N'["entree"]',NULL;
  EXEC api.account_create @admin,N'agent01',N'QA 2',@hash,N'["sortie"]',NULL;
  THROW 51099, 'Duplicate username accepted.', 1;
END TRY BEGIN CATCH
  DECLARE @error int=ERROR_NUMBER(); IF @@TRANCOUNT>0 ROLLBACK;
  IF @error NOT IN(2601,2627) THROW;
  PRINT 'PASS: case-insensitive username uniqueness.';
END CATCH;
GO
