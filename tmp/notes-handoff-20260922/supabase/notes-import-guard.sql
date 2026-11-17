-- Validate newly imported/replaced packets only. Existing snapshots, writing and checkoffs remain editable.
begin;
create or replace function public.whisper_notes_import_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare p jsonb; a jsonb; t jsonb; r jsonb; k text; begin
 if new.deleted then return new; end if;
 p:=new.document->'meetingDocument';
 if p is null then return new; end if;
 if tg_op='UPDATE' and p is not distinct from old.document->'meetingDocument' then return new; end if;
 if jsonb_typeof(p) is distinct from 'object' or p->>'version' not in ('1','2') or p->>'version' is null then raise exception 'invalid_meet_import'; end if;
 if jsonb_typeof(p->'transcript') is distinct from 'array' then raise exception 'transcript_required'; end if;
 if jsonb_array_length(p->'transcript') not between 1 and 4000 or coalesce(p->>'transcriptStatus','') not in ('complete','partial') then raise exception 'transcript_required'; end if;
 for t in select value from jsonb_array_elements(p->'transcript') loop
  if jsonb_typeof(t->'text') is distinct from 'string' or btrim(t->>'text')='' then raise exception 'transcript_required'; end if;
 end loop;
 if p->>'version'='1' then
  if p ? 'screenshots' or p ? 'recordings' or exists(select 1 from jsonb_array_elements(p->'transcript') s where s ? 'timing') then raise exception 'media_requires_v2'; end if;
  return new;
 end if;
 if jsonb_typeof(p->'screenshots') is distinct from 'array' or jsonb_typeof(p->'recordings') is distinct from 'array' then raise exception 'invalid_media_references'; end if;
 if jsonb_array_length(p->'screenshots')>20 or jsonb_array_length(p->'recordings')>10 then raise exception 'media_limit'; end if;
 for a in select value from jsonb_array_elements(p->'screenshots') loop
  if jsonb_typeof(a) is distinct from 'object' then raise exception 'invalid_asset_reference'; end if;
  for k in select jsonb_object_keys(a) loop if k not in ('version','assetId','caption','alt','width','height','mimeType','byteCount','sha256','transcriptId') then raise exception 'invalid_asset_reference'; end if; end loop;
  if a->>'version' is distinct from '1' or not exists(select 1 from public.whisper_note_assets n where n.id=(a->>'assetId')::uuid and n.owner_id=new.owner_id and n.state='ready' and n.mime_type=a->>'mimeType' and n.byte_count=(a->>'byteCount')::bigint and n.width=(a->>'width')::int and n.height=(a->>'height')::int and n.sha256=a->>'sha256') then raise exception 'asset_access_denied' using errcode='42501'; end if;
 end loop;
 for a in select value from jsonb_array_elements(p->'recordings') loop
  if jsonb_typeof(a) is distinct from 'object' then raise exception 'invalid_recording_reference'; end if;
  for k in select jsonb_object_keys(a) loop if k not in ('version','assetId','recordingId','sourceRevision','title','durationSeconds','mediaKind') then raise exception 'invalid_recording_reference'; end if; end loop;
  if a->>'version' is distinct from '1' or not exists(select 1 from public.whisper_recording_archives n where n.id=(a->>'assetId')::uuid and n.owner_id=new.owner_id and n.state='ready' and n.recording_id=(a->>'recordingId')::uuid and n.source_revision=(a->>'sourceRevision')::bigint and n.snapshot->>'storageConsent'='true' and n.snapshot->>'meetingId'=p->>'sourceMeetingId') then raise exception 'recording_access_denied' using errcode='42501'; end if;
 end loop;
 for t in select value->'timing' from jsonb_array_elements(p->'transcript') where value ? 'timing' loop
  if jsonb_typeof(t) is distinct from 'object' then raise exception 'invalid_transcript_timing'; end if;
  for k in select jsonb_object_keys(t) loop if k not in ('version','basis','sessionId','recordingAssetId','startMs','endMs') then raise exception 'invalid_transcript_timing'; end if; end loop;
  if t->>'version' is distinct from '1' or coalesce(t->>'basis','') not in ('session','recording') or (t->>'sessionId')::uuid is null or (t->>'startMs')::bigint is null or (t->>'startMs')::bigint not between 0 and 604800000 or coalesce((t->>'endMs')::bigint,(t->>'startMs')::bigint) not between (t->>'startMs')::bigint and 604800000 then raise exception 'invalid_transcript_timing'; end if;
  if t->>'basis'='recording' then
   select value into r from jsonb_array_elements(p->'recordings') where value->>'assetId'=t->>'recordingAssetId';
   if r is null or coalesce((t->>'endMs')::bigint,(t->>'startMs')::bigint)>(r->>'durationSeconds')::bigint*1000 then raise exception 'invalid_transcript_timing'; end if;
  elsif t ? 'recordingAssetId' then raise exception 'invalid_transcript_timing'; end if;
 end loop;
 return new;
end $$;
revoke all on function public.whisper_notes_import_guard() from public,anon,authenticated;
create or replace trigger whisper_notes_import_guard before insert or update on public.whisper_private_notebooks for each row execute function public.whisper_notes_import_guard();
-- Publisher endpoint never updates an existing document: p_revision is always zero.
create or replace function public.import_whisper_meet_document(p_id uuid,p_operation uuid,p_document jsonb) returns public.whisper_private_notebooks language plpgsql security invoker set search_path='' as $$ begin
 if p_document->'meetingDocument' is null or p_document->>'notes' is distinct from '' or p_document->>'transcript' is distinct from '' or coalesce(p_document->'completedDocumentSteps','[]'::jsonb)<>'[]'::jsonb then raise exception 'invalid_meet_import'; end if;
 return public.save_private_notebook(p_id,0,p_operation,p_document,false);
end $$;
revoke all on function public.import_whisper_meet_document(uuid,uuid,jsonb) from public,anon;
grant execute on function public.import_whisper_meet_document(uuid,uuid,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
