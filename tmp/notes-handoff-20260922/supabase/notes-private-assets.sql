-- Additive screenshot storage. Existing notebook/recording rows and policies are unchanged.
begin;
create table if not exists public.whisper_note_assets (
 id uuid primary key, owner_id uuid not null references auth.users(id), version integer not null default 1 check(version=1),
 mime_type text not null check(mime_type in ('image/png','image/jpeg','image/webp')),
 byte_count bigint not null check(byte_count between 1 and 5242880), width integer not null check(width between 1 and 8192), height integer not null check(height between 1 and 8192),
 sha256 text not null check(sha256 ~ '^[a-f0-9]{64}$'), consent_version text not null check(consent_version='notes-private-media-v1'), consent_at timestamptz not null,
 state text not null default 'uploading' check(state in ('uploading','ready','deleting')), created_at timestamptz not null default now()
);
alter table public.whisper_note_assets enable row level security;
alter table public.whisper_note_assets force row level security;
revoke all on public.whisper_note_assets from public,anon,authenticated;
grant select,insert,delete on public.whisper_note_assets to authenticated;
grant update(state) on public.whisper_note_assets to authenticated;
do $$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='whisper_note_assets' and policyname='notes_asset_owner') then
  create policy notes_asset_owner on public.whisper_note_assets for all to authenticated using(owner_id=auth.uid()) with check(owner_id=auth.uid());
 end if;
end $$;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('whisper-private-note-assets','whisper-private-note-assets',false,5242880,array['image/png','image/jpeg','image/webp']) on conflict(id) do nothing;
do $$ begin
 if not exists(select 1 from storage.buckets where id='whisper-private-note-assets' and public=false and file_size_limit=5242880 and allowed_mime_types @> array['image/png','image/jpeg','image/webp'] and allowed_mime_types <@ array['image/png','image/jpeg','image/webp']) then raise exception 'notes_bucket_configuration_mismatch'; end if;
 if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='notes_asset_objects_allow') then
  create policy notes_asset_objects_allow on storage.objects for all to authenticated using(bucket_id='whisper-private-note-assets' and exists(select 1 from public.whisper_note_assets a where a.owner_id=auth.uid() and name=a.owner_id::text||'/'||a.id::text||'/image')) with check(bucket_id='whisper-private-note-assets' and exists(select 1 from public.whisper_note_assets a where a.owner_id=auth.uid() and a.state='uploading' and name=a.owner_id::text||'/'||a.id::text||'/image'));
  create policy notes_asset_objects_read_guard on storage.objects as restrictive for select to public using(bucket_id<>'whisper-private-note-assets' or exists(select 1 from public.whisper_note_assets a where a.owner_id=auth.uid() and a.state='ready' and name=a.owner_id::text||'/'||a.id::text||'/image'));
  create policy notes_asset_objects_insert_guard on storage.objects as restrictive for insert to public with check(bucket_id<>'whisper-private-note-assets' or exists(select 1 from public.whisper_note_assets a where a.owner_id=auth.uid() and a.state='uploading' and name=a.owner_id::text||'/'||a.id::text||'/image'));
  create policy notes_asset_objects_update_guard on storage.objects as restrictive for update to public using(bucket_id<>'whisper-private-note-assets') with check(bucket_id<>'whisper-private-note-assets');
  create policy notes_asset_objects_delete_guard on storage.objects as restrictive for delete to public using(bucket_id<>'whisper-private-note-assets' or exists(select 1 from public.whisper_note_assets a where a.owner_id=auth.uid() and a.state='deleting' and name=a.owner_id::text||'/'||a.id::text||'/image'));
 end if;
end $$;
create or replace function public.whisper_note_asset_guard() returns trigger language plpgsql security definer set search_path='' as $$ begin
 if tg_op='INSERT' then
  perform pg_advisory_xact_lock(hashtextextended(new.owner_id::text,8462));
  if new.state<>'uploading' or (select count(*) from public.whisper_note_assets where owner_id=new.owner_id)>=500 then raise exception 'notes_asset_limit'; end if; return new;
 elsif tg_op='DELETE' then
  if old.state<>'deleting' or exists(select 1 from storage.objects where bucket_id='whisper-private-note-assets' and name=old.owner_id::text||'/'||old.id::text||'/image') then raise exception 'remove_asset_object_first'; end if; return old;
 end if;
 if (to_jsonb(new)-'state') is distinct from (to_jsonb(old)-'state') then raise exception 'asset_is_immutable'; end if;
 if new.state=old.state or new.state='deleting' then return new; end if;
 if old.state<>'uploading' or new.state<>'ready' then raise exception 'invalid_asset_transition'; end if;
 if not exists(select 1 from storage.objects where bucket_id='whisper-private-note-assets' and name=new.owner_id::text||'/'||new.id::text||'/image' and (metadata->>'size')::bigint=new.byte_count and metadata->>'mimetype'=new.mime_type) then raise exception 'asset_upload_incomplete'; end if;
 return new;
end $$;
revoke all on function public.whisper_note_asset_guard() from public,anon,authenticated;
create or replace trigger whisper_note_asset_guard before insert or update or delete on public.whisper_note_assets for each row execute function public.whisper_note_asset_guard();
create or replace function public.whisper_note_asset_upload_guard() returns trigger language plpgsql security definer set search_path='' as $$ declare s text; begin
 if new.bucket_id<>'whisper-private-note-assets' then return new; end if;
 if new.name !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/image$' then raise exception 'invalid_asset_path'; end if;
 select state into s from public.whisper_note_assets where owner_id=split_part(new.name,'/',1)::uuid and id=split_part(new.name,'/',2)::uuid for share;
 if s is distinct from 'uploading' then raise exception 'asset_not_uploading'; end if; return new;
end $$;
revoke all on function public.whisper_note_asset_upload_guard() from public,anon,authenticated;
create or replace trigger whisper_note_asset_upload_guard before insert on storage.objects for each row execute function public.whisper_note_asset_upload_guard();
notify pgrst,'reload schema';
commit;
