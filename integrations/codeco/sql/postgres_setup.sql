-- DBA preparation ONLY. Not applied automatically and not exposed through the public Data API.
-- Create a separate LOGIN through IT's protected process and make it a member of codeco_reader.
BEGIN;
CREATE SCHEMA IF NOT EXISTS private;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='codeco_reader') THEN CREATE ROLE codeco_reader NOLOGIN; END IF; END $$;
CREATE TABLE IF NOT EXISTS private.codeco_movement_metadata (
  event_id bigint NOT NULL REFERENCES public.visit_events(id),
  slot smallint NOT NULL CHECK(slot IN(1,2)),
  booking_reference text CHECK(length(booking_reference) BETWEEN 1 AND 150),
  gross_weight numeric(12,3) CHECK(gross_weight>=0),
  tare_weight numeric(12,3) CHECK(tare_weight>=0),
  vgm_weight numeric(12,3) CHECK(vgm_weight>=0),
  ports jsonb CHECK(jsonb_typeof(ports)='array'),
  source_reference text NOT NULL CHECK(length(btrim(source_reference)) BETWEEN 1 AND 200),
  recorded_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(event_id,slot)
);
ALTER TABLE private.codeco_movement_metadata ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.codeco_movement_metadata FROM PUBLIC;
-- Deliberate private definer projection: the technical reader can execute only this bounded,
-- read-only function, without SELECT access to snapshots containing driver identity or other personal data.
CREATE OR REPLACE FUNCTION private.codeco_extract(p_from timestamptz,p_to timestamptz)
RETURNS TABLE(event_id text,action text,occurred_at timestamptz,snapshot jsonb,metadata jsonb)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF p_from IS NULL OR p_to IS NULL OR p_to<=p_from OR p_to-p_from>interval '31 days' THEN
    RAISE EXCEPTION 'invalid CODECO window' USING errcode='22023';
  END IF;
  RETURN QUERY SELECT e.id::text,e.action,e.occurred_at,
    jsonb_build_object('entry_kind',d.snapshot->'entry_kind','plate',d.snapshot->'plate','is_twin',d.snapshot->'is_twin',
      'container_number',d.snapshot->'container_number','iso_code',d.snapshot->'iso_code','armateur_id',d.snapshot->'armateur_id',
      'container_number_2',d.snapshot->'container_number_2','iso_code_2',d.snapshot->'iso_code_2','armateur_id_2',d.snapshot->'armateur_id_2',
      'carrier_booking_reference',d.snapshot->'carrier_booking_reference','booking_reference_2',d.snapshot->'booking_reference_2'),
    COALESCE((SELECT jsonb_object_agg(m.slot::text,jsonb_build_object('bookingReference',m.booking_reference,
      'grossWeight',m.gross_weight::text,'tareWeight',m.tare_weight::text,'vgmWeight',m.vgm_weight::text,'ports',m.ports))
      FROM private.codeco_movement_metadata m WHERE m.event_id=e.id),'{}'::jsonb)
    FROM public.visit_events e JOIN public.generated_documents d ON d.event_id=e.id AND d.kind=e.action
    WHERE e.occurred_at>=p_from AND e.occurred_at<p_to
      AND ((e.action='ENTREE' AND d.snapshot->>'entry_kind'='loaded') OR (e.action='SORTIE' AND d.snapshot->>'entry_kind'='empty'))
      AND (d.snapshot->>'armateur_id'='MSC' OR (d.snapshot->>'is_twin'='true' AND d.snapshot->>'armateur_id_2'='MSC'))
    ORDER BY e.occurred_at,e.id,d.id LIMIT 10001;
END $$;
REVOKE ALL ON FUNCTION private.codeco_extract(timestamptz,timestamptz) FROM PUBLIC;
GRANT USAGE ON SCHEMA private TO codeco_reader;
GRANT EXECUTE ON FUNCTION private.codeco_extract(timestamptz,timestamptz) TO codeco_reader;
COMMIT;
