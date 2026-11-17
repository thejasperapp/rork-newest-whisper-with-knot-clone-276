-- Additive owner-only recording snapshots. Never writes legacy meeting/recap rows.
BEGIN;
CREATE TABLE IF NOT EXISTS public.whisper_recording_archives (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES auth.users(id),
  recording_id uuid NOT NULL,
  source_revision bigint NOT NULL CHECK (source_revision >= 0),
  snapshot jsonb NOT NULL,
  media_bytes bigint NOT NULL CHECK (media_bytes BETWEEN 1 AND 471859200),
  audio_bytes bigint NOT NULL CHECK (audio_bytes BETWEEN 44 AND 471859200),
  state text NOT NULL DEFAULT 'uploading' CHECK (state IN ('uploading', 'ready', 'deleting')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(owner_id, recording_id, source_revision),
  CHECK (octet_length(snapshot::text) <= 3000000),
  CHECK (COALESCE(snapshot->>'ownerId' = owner_id::text AND snapshot->>'id' = recording_id::text
    AND snapshot->>'storageConsent' = 'true' AND snapshot->>'version' = '1'
    AND (snapshot->>'revision')::bigint = source_revision
    AND snapshot->>'status' IN ('ready','interrupted'), false))
);
ALTER TABLE public.whisper_recording_archives ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.whisper_recording_archives FORCE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS whisper_recording_archives_owner_date ON public.whisper_recording_archives(owner_id, created_at DESC);
REVOKE ALL ON public.whisper_recording_archives FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.whisper_recording_archives TO anon, authenticated;
GRANT INSERT, DELETE ON public.whisper_recording_archives TO authenticated;
GRANT UPDATE(state) ON public.whisper_recording_archives TO authenticated;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='whisper_recording_archives' AND policyname='recording_archive_owner') THEN
    CREATE POLICY recording_archive_owner ON public.whisper_recording_archives FOR ALL TO authenticated
      USING (owner_id = (SELECT auth.uid())) WITH CHECK (owner_id = (SELECT auth.uid()));
  END IF;
END $$;
INSERT INTO storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
VALUES ('whisper-private-recordings', 'whisper-private-recordings', false, 471859200, ARRAY['audio/mp4','audio/webm','video/mp4','video/webm','audio/wav'])
ON CONFLICT (id) DO NOTHING;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id='whisper-private-recordings' AND public=false AND file_size_limit=471859200 AND allowed_mime_types @> ARRAY['audio/mp4','audio/webm','video/mp4','video/webm','audio/wav'] AND allowed_mime_types <@ ARRAY['audio/mp4','audio/webm','video/mp4','video/webm','audio/wav']) THEN
    RAISE EXCEPTION 'Private recording bucket configuration does not match; refusing setup';
  END IF;
END $$;

-- Restrictive guards are ANDed with every existing permissive storage policy.
-- Unrelated buckets retain exactly their previous behavior.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='recording_objects_owner_allow') THEN
    CREATE POLICY recording_objects_owner_allow ON storage.objects FOR ALL TO authenticated
      USING (bucket_id='whisper-private-recordings' AND EXISTS (SELECT 1 FROM public.whisper_recording_archives r WHERE r.owner_id=auth.uid() AND name IN (r.owner_id::text||'/'||r.id::text||'/original', r.owner_id::text||'/'||r.id::text||'/audio.wav')))
      WITH CHECK (bucket_id='whisper-private-recordings' AND EXISTS (SELECT 1 FROM public.whisper_recording_archives r WHERE r.owner_id=auth.uid() AND r.state='uploading' AND name IN (r.owner_id::text||'/'||r.id::text||'/original', r.owner_id::text||'/'||r.id::text||'/audio.wav')));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='recording_objects_read_guard') THEN
    CREATE POLICY recording_objects_read_guard ON storage.objects AS RESTRICTIVE FOR SELECT TO public
      USING (bucket_id<>'whisper-private-recordings' OR EXISTS (SELECT 1 FROM public.whisper_recording_archives r WHERE r.owner_id=auth.uid() AND name IN (r.owner_id::text||'/'||r.id::text||'/original', r.owner_id::text||'/'||r.id::text||'/audio.wav')));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='recording_objects_insert_guard') THEN
    CREATE POLICY recording_objects_insert_guard ON storage.objects AS RESTRICTIVE FOR INSERT TO public
      WITH CHECK (bucket_id<>'whisper-private-recordings' OR EXISTS (SELECT 1 FROM public.whisper_recording_archives r WHERE r.owner_id=auth.uid() AND r.state='uploading' AND name IN (r.owner_id::text||'/'||r.id::text||'/original', r.owner_id::text||'/'||r.id::text||'/audio.wav')));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='recording_objects_update_guard') THEN
    CREATE POLICY recording_objects_update_guard ON storage.objects AS RESTRICTIVE FOR UPDATE TO public
      USING (bucket_id<>'whisper-private-recordings') WITH CHECK (bucket_id<>'whisper-private-recordings');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='recording_objects_delete_guard') THEN
    CREATE POLICY recording_objects_delete_guard ON storage.objects AS RESTRICTIVE FOR DELETE TO public
      USING (bucket_id<>'whisper-private-recordings' OR EXISTS (SELECT 1 FROM public.whisper_recording_archives r WHERE r.owner_id=auth.uid() AND r.state='deleting' AND name IN (r.owner_id::text||'/'||r.id::text||'/original', r.owner_id::text||'/'||r.id::text||'/audio.wav')));
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.whisper_recording_archive_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF TG_OP='INSERT' THEN
    IF NEW.state<>'uploading' THEN RAISE EXCEPTION 'Create an upload before finalizing'; END IF;
    RETURN NEW;
  END IF;
  IF TG_OP='DELETE' THEN
    IF OLD.state<>'deleting' OR EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id='whisper-private-recordings' AND name LIKE OLD.owner_id::text||'/'||OLD.id::text||'/%') THEN
      RAISE EXCEPTION 'Remove private media before removing the archive';
    END IF;
    RETURN OLD;
  END IF;
  IF (to_jsonb(NEW)-'state') IS DISTINCT FROM (to_jsonb(OLD)-'state') THEN RAISE EXCEPTION 'Archive snapshots are immutable'; END IF;
  IF OLD.state=NEW.state THEN RETURN NEW; END IF;
  IF NEW.state='deleting' THEN RETURN NEW; END IF;
  IF OLD.state<>'uploading' OR NEW.state<>'ready' THEN RAISE EXCEPTION 'Invalid archive state transition'; END IF;
  IF NOT EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id='whisper-private-recordings' AND name=NEW.owner_id::text||'/'||NEW.id::text||'/original' AND (metadata->>'size')::bigint=NEW.media_bytes)
    OR NOT EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id='whisper-private-recordings' AND name=NEW.owner_id::text||'/'||NEW.id::text||'/audio.wav' AND (metadata->>'size')::bigint=NEW.audio_bytes) THEN
    RAISE EXCEPTION 'Upload both complete media objects before finalizing';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.whisper_recording_archive_guard() FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE TRIGGER whisper_recording_archive_guard BEFORE INSERT OR UPDATE OR DELETE ON public.whisper_recording_archives FOR EACH ROW EXECUTE FUNCTION public.whisper_recording_archive_guard();

-- Serialize completion of a TUS upload with deletion/finalization of its archive.
CREATE OR REPLACE FUNCTION public.whisper_recording_upload_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE parent_state text;
BEGIN
  IF NEW.bucket_id<>'whisper-private-recordings' THEN RETURN NEW; END IF;
  IF NEW.name !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/(original|audio[.]wav)$' THEN RAISE EXCEPTION 'Invalid recording object path'; END IF;
  SELECT state INTO parent_state FROM public.whisper_recording_archives
    WHERE owner_id=split_part(NEW.name,'/',1)::uuid AND id=split_part(NEW.name,'/',2)::uuid FOR SHARE;
  IF parent_state IS DISTINCT FROM 'uploading' THEN RAISE EXCEPTION 'Recording archive is no longer accepting uploads'; END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.whisper_recording_upload_guard() FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE TRIGGER whisper_recording_upload_guard BEFORE INSERT ON storage.objects FOR EACH ROW EXECUTE FUNCTION public.whisper_recording_upload_guard();
COMMIT;
