begin;
create table if not exists public.whisper_document_suggestions (
 id uuid primary key, document_id uuid not null references public.whisper_shared_documents(id), author_id uuid not null references auth.users(id),
 quote text not null check(length(quote) between 1 and 2000), replacement text not null check(length(replacement)<=4000),anchor jsonb not null check(octet_length(anchor::text)<=4000),
 status text not null default 'pending' check(status in ('pending','accepted','rejected')),decided_by uuid references auth.users(id),operation_id uuid,
 created_at timestamptz not null default now(),decided_at timestamptz
);
create index if not exists notes_suggestions_document on public.whisper_document_suggestions(document_id,created_at);
alter table public.whisper_document_suggestions enable row level security;
revoke all on public.whisper_document_suggestions from public,anon,authenticated;
create or replace function public.whisper_notes_suggestions(p_doc uuid,p_action text,p_payload jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare uid uuid:=auth.uid();r text;d public.whisper_shared_documents;s public.whisper_document_suggestions;item uuid;op uuid;data text;
begin
 if uid is null then raise exception 'sign_in_required' using errcode='42501';end if;
 if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>2200000 then raise exception 'invalid_document';end if;
 select * into d from public.whisper_shared_documents where id=p_doc for update;
 r:=public.whisper_notes_role(p_doc);if r is null then raise exception 'document_access_denied' using errcode='42501';end if;
 if p_action='list' then return coalesce((select jsonb_agg(x) from (select s.*,coalesce(w.username,'Collaborator') as name from public.whisper_document_suggestions s left join public.whisper_profiles w on w.user_id=s.author_id where s.document_id=p_doc order by s.created_at limit 500)x),'[]'::jsonb);end if;
 item:=(p_payload->>'id')::uuid;if item is null then raise exception 'invalid_document';end if;
 if p_action='create' then
  if r not in ('owner','editor','commenter') then raise exception 'document_access_denied' using errcode='42501';end if;
  if length(p_payload->>'quote') not between 1 and 2000 or p_payload->>'quote' is null or p_payload->>'replacement' is null or length(p_payload->>'replacement')>4000 or jsonb_typeof(p_payload->'anchor') is distinct from 'object' or octet_length((p_payload->'anchor')::text)>4000 then raise exception 'invalid_document';end if;
  if exists(select 1 from public.whisper_document_suggestions where id=item and (document_id<>p_doc or author_id<>uid)) then raise exception 'document_access_denied' using errcode='42501';end if;
  if (select count(*) from public.whisper_document_suggestions where document_id=p_doc)>=500 then raise exception 'document_limit';end if;
  insert into public.whisper_document_suggestions(id,document_id,author_id,quote,replacement,anchor) values(item,p_doc,uid,p_payload->>'quote',p_payload->>'replacement',p_payload->'anchor') on conflict(id) do nothing;
  return jsonb_build_object('ok',true);
 end if;
 if r not in ('owner','editor') then raise exception 'document_access_denied' using errcode='42501';end if;
 select * into s from public.whisper_document_suggestions where id=item and document_id=p_doc for update;
 if not found then raise exception 'document_access_denied' using errcode='42501';end if;
 op:=(p_payload->>'operation')::uuid;
 if s.status<>'pending' then
  if s.operation_id=op and s.decided_by=uid then return jsonb_build_object('ok',true);end if;
  raise exception 'document_changed' using errcode='40001';
 end if;
 if p_action='accept' then
  if op is null or coalesce((p_payload->>'expected')::bigint,-1)<>d.seq then raise exception 'document_changed' using errcode='40001';end if;
  data:=p_payload->>'update';if data is null or length(data) not between 1 and 1500000 or data !~ '^[A-Za-z0-9+/]*={0,2}$' then raise exception 'invalid_update';end if;
  if d.seq>=20000 or d.bytes+length(data)>30000000 then raise exception 'document_limit';end if;
  insert into public.whisper_document_updates(document_id,seq,operation_id,author_id,update_data) values(p_doc,d.seq+1,op,uid,data);
  update public.whisper_shared_documents set seq=seq+1,bytes=bytes+length(data),updated_at=now() where id=p_doc;
 elsif p_action<>'reject' then raise exception 'invalid_action';end if;
 update public.whisper_document_suggestions set status=case when p_action='accept' then 'accepted' else 'rejected' end,decided_by=uid,decided_at=now(),operation_id=op where id=item;
 return jsonb_build_object('ok',true);
end;$$;
revoke all on function public.whisper_notes_suggestions(uuid,text,jsonb) from public,anon;
grant execute on function public.whisper_notes_suggestions(uuid,text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
