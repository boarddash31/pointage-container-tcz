-- Supabase ZENATA ONLY. Reopen source ONLY before any new SQL business write.
-- After SQL has received new operations, reconcile the SQL delta before any rollback.
BEGIN;
SET LOCAL lock_timeout='30s';
SELECT pg_catalog.pg_advisory_xact_lock(628921411964637::bigint);
UPDATE migration_control.freeze_state SET frozen=false,freeze_id=gen_random_uuid(),changed_at=now() WHERE singleton;
COMMIT;
SELECT frozen,freeze_id,changed_at FROM migration_control.freeze_state WHERE singleton;
