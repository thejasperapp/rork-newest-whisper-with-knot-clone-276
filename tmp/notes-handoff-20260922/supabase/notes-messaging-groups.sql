-- Narrow explicit Notes messaging and opt-in registry-backed group discovery.
begin;
create table if not exists public.whisper_notes_message_receipts (
 id uuid primary key, sender_id uuid not null references auth.users(id), document_id uuid not null references public.whisper_shared_documents(id),
 recipient_id uuid not null references auth.users(id), fingerprint text not null, created_at timestamptz not null default now()
);
alter table public.whisper_notes_message_receipts enable row level security;
revoke all on public.whisper_notes_message_receipts from public,anon,authenticated;

create or replace function public.whisper_notes_message(p_doc uuid,p_id uuid,p_recipient uuid,p_body text,p_quote text default '') returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); d public.whisper_shared_documents; receipt public.whisper_notes_message_receipts; sender text; recipient text; content text; fingerprint text; thread uuid;
begin
 if uid is null or p_id is null or p_recipient is null or p_recipient=uid then raise exception 'person_unavailable' using errcode='42501'; end if;
 if coalesce(length(btrim(p_body)),0) not between 1 and 1500 or coalesce(length(p_quote),0)>2000 then raise exception 'invalid_message'; end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text,90883));
 select * into d from public.whisper_shared_documents where id=p_doc and not deleted for update;
 if not found or public.whisper_notes_role(p_doc) is null then raise exception 'document_access_denied' using errcode='42501'; end if;
 -- A snippet cannot bypass document access: recipient must already be an active reader.
 if p_recipient<>d.owner_id and not exists(select 1 from public.whisper_document_members m join auth.users u on u.id=p_recipient where m.document_id=p_doc and m.status='active' and (m.user_id=p_recipient or (m.email=lower(u.email) and u.email_confirmed_at is not null))) then raise exception 'recipient_access_required' using errcode='42501'; end if;
 if exists(select 1 from public.whisper_blocks b where (b.blocker_id=uid and b.blocked_user_id=p_recipient) or (b.blocker_id=p_recipient and b.blocked_user_id in (uid,d.owner_id)) or (b.blocker_id=d.owner_id and b.blocked_user_id=p_recipient))
 or exists(select 1 from public.whisper_dm_blocks b where b.blocked_sender_id=uid and b.protected_user_id=p_recipient) then raise exception 'person_unavailable' using errcode='42501'; end if;
 fingerprint:=encode(sha256(convert_to(jsonb_build_array(p_doc,p_recipient,btrim(p_body),coalesce(p_quote,''))::text,'UTF8')),'hex');
 select * into receipt from public.whisper_notes_message_receipts where id=p_id;
 if found then
  if receipt.sender_id<>uid or receipt.fingerprint<>fingerprint then raise exception 'message_conflict'; end if;
  return jsonb_build_object('id',p_id,'sent',true);
 end if;
 if (select count(*) from public.whisper_notes_message_receipts where sender_id=uid and created_at>now()-interval '1 hour')>=60 then raise exception 'message_limit'; end if;
 select username into sender from public.whisper_profiles where user_id=uid;select username into recipient from public.whisper_profiles where user_id=p_recipient;
 if sender is null or recipient is null then raise exception 'person_unavailable'; end if;
 content:=btrim(p_body)||E'\n\n'||d.title||case when coalesce(p_quote,'')<>'' then E'\n“'||p_quote||'”' else '' end||E'\nhttps://notes.mydailywhisper.com/shared/'||p_doc::text;
 if length(content)>4000 then raise exception 'invalid_message'; end if;
 thread:=substr(encode(sha256(convert_to(least(uid::text,p_recipient::text)||'|'||greatest(uid::text,p_recipient::text),'UTF8')),'hex'),1,32)::uuid;
 insert into public.whisper_notes_message_receipts(id,sender_id,document_id,recipient_id,fingerprint) values(p_id,uid,p_doc,p_recipient,fingerprint);
 insert into public.whisper_messages(id,thread_id,from_user_id,to_user_id,from_username,to_username,body) values(p_id,thread,uid,p_recipient,sender,recipient,content);
 return jsonb_build_object('id',p_id,'sent',true);
end;$$;
revoke all on function public.whisper_notes_message(uuid,uuid,uuid,text,text) from public,anon;
grant execute on function public.whisper_notes_message(uuid,uuid,uuid,text,text) to authenticated;

-- Groups are candidate sets, not continuously inherited grants. The owner reviews and invites individuals.
create or replace function public.whisper_notes_groups(p_group uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); g public.whisper_group_threads; ids uuid[];
begin
 if uid is null then raise exception 'sign_in_required' using errcode='42501'; end if;
 if p_group is null then
  return coalesce((select jsonb_agg(x) from(select id,name,cardinality(member_ids) as member_count from public.whisper_group_threads where owner_id=uid or uid=any(member_ids) order by name limit 100)x),'[]');
 end if;
 select * into g from public.whisper_group_threads where id=p_group and (owner_id=uid or uid=any(member_ids));
 if not found then raise exception 'group_unavailable' using errcode='42501'; end if;
 ids:=array_append(g.member_ids,g.owner_id);
 if cardinality(ids)>200 then raise exception 'group_limit'; end if;
 return public.whisper_notes_people('',ids);
end;$$;
revoke all on function public.whisper_notes_groups(uuid) from public,anon;
grant execute on function public.whisper_notes_groups(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
