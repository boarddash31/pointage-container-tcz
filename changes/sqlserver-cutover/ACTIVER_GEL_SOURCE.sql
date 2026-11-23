-- Supabase ZENATA ONLY. Final cutover window: stop business entry on ALL old sites, including Netlify.
-- Run only after the SQL runtime is compiled, certificate and SQL runtime login are ready.
BEGIN;
SET LOCAL lock_timeout='30s';
SELECT pg_catalog.pg_advisory_xact_lock(628921411964637::bigint);
UPDATE migration_control.freeze_state SET frozen=true,freeze_id=gen_random_uuid(),changed_at=now() WHERE singleton;
COMMIT;
SELECT frozen,freeze_id,changed_at FROM migration_control.freeze_state WHERE singleton;
