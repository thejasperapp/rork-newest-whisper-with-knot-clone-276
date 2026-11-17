-- Canonical, host-authorized meeting notes. Private notebooks and capture records remain untouched.
begin;
create table if not exists public.whisper_notes_meeting_documents (
 meeting_id uuid primary key references public.whisper_meetings(id),
 document_id uuid not null unique references public.whisper_shared_documents(id),
 source_owner uuid not null references auth.users(id), source_notebook uuid not null,
 created_at timestamptz not null default now()
);
create table if not exists public.whisper_notes_meeting_sharing (
 meeting_id uuid primary key references public.whisper_meetings(id),
 audience text not null check(audience in ('private','participants','selected')),
 recipients uuid[] not null default '{}', role text not null check(role in ('viewer','commenter','editor')),
 configured_by uuid not null references auth.users(id), operation_id uuid not null,
 published_at timestamptz, published_recipients uuid[] not null default '{}', updated_at timestamptz not null default now()
);
alter table public.whisper_notes_meeting_documents enable row level security;
alter table public.whisper_notes_meeting_sharing enable row level security;
revoke all on public.whisper_notes_meeting_documents,public.whisper_notes_meeting_sharing from public,anon,authenticated;

create or replace function public.whisper_notes_text_node(p_text text,p_level int default 0) returns jsonb
language sql immutable set search_path='' as $$
 select jsonb_build_object('type',case when p_level>0 then 'heading' else 'paragraph' end,'attrs',case when p_level>0 then jsonb_build_object('level',p_level) else '{}'::jsonb end,'content',case when coalesce(p_text,'')='' then '[]'::jsonb else jsonb_build_array(jsonb_build_object('type','text','text',p_text)) end);
$$;
revoke all on function public.whisper_notes_text_node(text,int) from public,anon,authenticated;

-- Deterministic structured conversion, never HTML or a lossy plain-text export. No personal fields or private media.
create or replace function public.whisper_notes_packet_seed(p jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$
declare nodes jsonb:='[]'; q jsonb; item jsonb; bullets jsonb; stamp text; seconds bigint;
begin
 if p->>'version' not in ('1','2') or jsonb_typeof(p->'transcript') is distinct from 'array' or octet_length(p::text)>1500000 then raise exception 'invalid_document'; end if;
 nodes:=nodes||jsonb_build_array(public.whisper_notes_text_node('Summary',2),public.whisper_notes_text_node(p->>'summary'));
 nodes:=nodes||jsonb_build_array(public.whisper_notes_text_node('Next steps',2));
 bullets:='[]';
 for item in select value from jsonb_array_elements(coalesce(p->'nextSteps','[]')) loop
  bullets:=bullets||jsonb_build_array(jsonb_build_object('type','taskItem','attrs',jsonb_build_object('checked',false),'content',jsonb_build_array(public.whisper_notes_text_node(case when coalesce(item->>'owner','')<>'' then (item->>'owner')||': ' else '' end||coalesce(item->>'text','')))));
 end loop;
 if jsonb_array_length(bullets)>0 then nodes:=nodes||jsonb_build_array(jsonb_build_object('type','taskList','content',bullets)); end if;
 nodes:=nodes||jsonb_build_array(public.whisper_notes_text_node('Details',2));
 for item in select value from jsonb_array_elements(coalesce(p->'details','[]')) loop
  nodes:=nodes||jsonb_build_array(public.whisper_notes_text_node(item->>'title',3),public.whisper_notes_text_node(item->>'text'));
 end loop;
 nodes:=nodes||'[{"type":"pageBreak"}]'::jsonb||jsonb_build_array(public.whisper_notes_text_node('Quick notes',1));
 for q in select value from jsonb_array_elements(coalesce(p->'quickNotes','[]')) loop
  nodes:=nodes||jsonb_build_array(public.whisper_notes_text_node(q->>'title',2));bullets:='[]';
  for item in select value from jsonb_array_elements(coalesce(q->'bullets','[]')) loop
   bullets:=bullets||jsonb_build_array(jsonb_build_object('type','listItem','content',jsonb_build_array(public.whisper_notes_text_node(item#>>'{}'))));
  end loop;
  if jsonb_array_length(bullets)>0 then nodes:=nodes||jsonb_build_array(jsonb_build_object('type','bulletList','content',bullets)); end if;
 end loop;
 nodes:=nodes||'[{"type":"pageBreak"}]'::jsonb||jsonb_build_array(public.whisper_notes_text_node('Transcript',1),public.whisper_notes_text_node('Capture coverage: '||coalesce(p->>'transcriptStatus','unavailable')||'. Edited text is not the original recording.'));
 for item in select value from jsonb_array_elements(p->'transcript') loop
  seconds:=coalesce((item->'timing'->>'startMs')::bigint/1000,(item->>'offsetSeconds')::bigint);
  stamp:=case when seconds is null then 'Time not supplied' else lpad((seconds/3600)::text,2,'0')||':'||lpad(((seconds%3600)/60)::text,2,'0')||':'||lpad((seconds%60)::text,2,'0') end;
  nodes:=nodes||jsonb_build_array(public.whisper_notes_text_node(coalesce(item->>'speaker','Speaker')||' · '||stamp,3),public.whisper_notes_text_node(item->>'text'));
 end loop;
 return jsonb_build_object('type','doc','content',nodes);
end;$$;
revoke all on function public.whisper_notes_packet_seed(jsonb) from public,anon,authenticated;

-- Resolves an owner's saved capture. A participant never becomes the host by owning a private export.
create or replace function public.whisper_notes_open_meeting(p_notebook uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); n public.whisper_private_notebooks; meeting public.whisper_meetings; link public.whisper_notes_meeting_documents; new_id uuid; seed jsonb;
begin
 if uid is null then raise exception 'sign_in_required' using errcode='42501'; end if;
 select * into n from public.whisper_private_notebooks where owner_id=uid and id=p_notebook and not deleted;
 if not found or jsonb_typeof(n.document->'meetingDocument') is distinct from 'object' then return jsonb_build_object('id',null,'reason','source_unavailable'); end if;
 select * into meeting from public.whisper_meetings where id=(n.document->'meetingDocument'->>'sourceMeetingId')::uuid;
 if not found then return jsonb_build_object('id',null,'reason','host_unverified'); end if;
 perform pg_advisory_xact_lock(hashtextextended(meeting.id::text,92883));
 select * into link from public.whisper_notes_meeting_documents where meeting_id=meeting.id;
 if found then
  if public.whisper_notes_role(link.document_id) is null then return jsonb_build_object('id',null,'reason','access_required'); end if;
  return jsonb_build_object('id',link.document_id);
 end if;
 if meeting.host_id<>uid then return jsonb_build_object('id',null,'reason','access_required'); end if;
 seed:=public.whisper_notes_packet_seed(n.document->'meetingDocument');new_id:=gen_random_uuid();
 perform public.whisper_notes_action(new_id,'create',jsonb_build_object('title',coalesce(nullif(n.document->>'title',''),'Meeting notes'),'content',seed));
 insert into public.whisper_notes_meeting_documents(meeting_id,document_id,source_owner,source_notebook) values(meeting.id,new_id,uid,n.id);
 return jsonb_build_object('id',new_id);
end;$$;
revoke all on function public.whisper_notes_open_meeting(uuid) from public,anon;
grant execute on function public.whisper_notes_open_meeting(uuid) to authenticated;

-- Meet saves this choice before capture. Publishing applies it once, after rich initialization.
-- Existing revoked/declined memberships are never revived by a publisher retry.
create or replace function public.whisper_notes_meeting_share(p_meeting uuid,p_action text,p_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); m public.whisper_meetings; settings public.whisper_notes_meeting_sharing; link public.whisper_notes_meeting_documents; target uuid; recipient_ids uuid[]; shared_count int:=0;
begin
 if uid is null then raise exception 'sign_in_required' using errcode='42501'; end if;
 select * into m from public.whisper_meetings where id=p_meeting for update;
 if not found or m.host_id<>uid then raise exception 'document_access_denied' using errcode='42501'; end if;
 if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>20000 then raise exception 'invalid_document'; end if;
 if p_action='configure' then
  if p_payload->>'operation' is null then raise exception 'invalid_invitation'; end if;
  select * into settings from public.whisper_notes_meeting_sharing where meeting_id=p_meeting;
  if settings.operation_id=(p_payload->>'operation')::uuid then return jsonb_build_object('ok',true); end if;
  if coalesce(p_payload->>'audience','') not in ('private','participants','selected') or coalesce(p_payload->>'role','') not in ('viewer','commenter','editor') then raise exception 'invalid_invitation'; end if;
  select coalesce(array_agg(distinct value::uuid),'{}'::uuid[]) into recipient_ids from jsonb_array_elements_text(coalesce(p_payload->'recipients','[]'));
  if cardinality(recipient_ids)>100 then raise exception 'invitation_limit'; end if;
  insert into public.whisper_notes_meeting_sharing(meeting_id,audience,recipients,role,configured_by,operation_id) values(p_meeting,p_payload->>'audience',recipient_ids,p_payload->>'role',uid,(p_payload->>'operation')::uuid)
  on conflict(meeting_id) do update set audience=excluded.audience,recipients=excluded.recipients,role=excluded.role,configured_by=uid,operation_id=excluded.operation_id,published_at=null,published_recipients='{}',updated_at=now();
  return jsonb_build_object('ok',true);
 end if;
 select * into settings from public.whisper_notes_meeting_sharing where meeting_id=p_meeting;
 if p_action='settings' then return jsonb_build_object('audience',coalesce(settings.audience,'private'),'role',coalesce(settings.role,'viewer'),'recipients',coalesce(settings.recipients,'{}'::uuid[])); end if;
 if p_action<>'publish' then raise exception 'invalid_action'; end if;
 select * into link from public.whisper_notes_meeting_documents where meeting_id=p_meeting;
 if not found or not exists(select 1 from public.whisper_shared_documents where id=link.document_id and owner_id=uid and not deleted and seq>0) then raise exception 'document_not_ready'; end if;
 if settings.audience is null or settings.audience='private' or settings.published_at is not null then return jsonb_build_object('id',link.document_id,'shared',0); end if;
 perform 1 from public.whisper_shared_documents where id=link.document_id for update;
 select coalesce(array_agg(distinct p.user_id),'{}'::uuid[]) into recipient_ids from public.whisper_meeting_participants p
 where p.meeting_id=p_meeting and p.user_id<>uid and (m.ended_at is null or p.joined_at<=m.ended_at) and (settings.audience='participants' or p.user_id=any(settings.recipients))
 and not exists(select 1 from public.whisper_blocks b where (b.blocker_id=uid and b.blocked_user_id=p.user_id) or (b.blocker_id=p.user_id and b.blocked_user_id=uid));
 foreach target in array recipient_ids loop
  if not exists(select 1 from public.whisper_document_members mm join auth.users u on u.id=target where mm.document_id=link.document_id and (mm.user_id=target or (mm.email=lower(u.email) and u.email_confirmed_at is not null))) then
   if (select count(*) from public.whisper_document_members where document_id=link.document_id)>=100 then raise exception 'invitation_limit'; end if;
   insert into public.whisper_document_members(id,document_id,invited_by,user_id,role,status) values(gen_random_uuid(),link.document_id,uid,target,settings.role,'active');shared_count:=shared_count+1;
  end if;
 end loop;
 update public.whisper_notes_meeting_sharing set published_at=now(),published_recipients=recipient_ids where meeting_id=p_meeting;
 return jsonb_build_object('id',link.document_id,'shared',shared_count);
end;$$;
revoke all on function public.whisper_notes_meeting_share(uuid,text,jsonb) from public,anon;
grant execute on function public.whisper_notes_meeting_share(uuid,text,jsonb) to authenticated;

-- Minimal document roster, never emails or the underlying private notebook. Only accessible-document readers.
create or replace function public.whisper_notes_context(p_doc uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); d public.whisper_shared_documents; link public.whisper_notes_meeting_documents; meeting jsonb; people jsonb;
begin
 if uid is null or public.whisper_notes_role(p_doc) is null then raise exception 'document_access_denied' using errcode='42501'; end if;
 select * into d from public.whisper_shared_documents where id=p_doc;
 select * into link from public.whisper_notes_meeting_documents where document_id=p_doc;
 if found then select jsonb_build_object('id',m.id,'title',m.title,'started_at',m.started_at,'ended_at',m.ended_at,'duration_seconds',case when m.started_at is not null and m.ended_at>=m.started_at then floor(extract(epoch from(m.ended_at-m.started_at))) else null end) into meeting from public.whisper_meetings m where id=link.meeting_id; end if;
 select coalesce(jsonb_agg(x),'[]') into people from (
  select w.user_id,w.username,coalesce(nullif(w.display_name,''),w.username) as name,w.profile_image_url as photo,
   case when w.user_id=d.owner_id then 'owner' else coalesce((select mm.role from public.whisper_document_members mm where mm.document_id=p_doc and (mm.user_id=w.user_id or exists(select 1 from auth.users u where u.id=w.user_id and u.email_confirmed_at is not null and lower(u.email)=mm.email)) and mm.status='active' order by case mm.role when 'editor' then 3 when 'commenter' then 2 else 1 end desc limit 1),'invited') end as role
  from public.whisper_profiles w where (w.user_id=d.owner_id or exists(select 1 from public.whisper_document_members mm where mm.document_id=p_doc and (mm.user_id=w.user_id or exists(select 1 from auth.users u where u.id=w.user_id and u.email_confirmed_at is not null and lower(u.email)=mm.email)) and mm.status in ('active','pending')))
   and not exists(select 1 from public.whisper_blocks b where (b.blocker_id=uid and b.blocked_user_id=w.user_id) or (b.blocker_id=w.user_id and b.blocked_user_id=uid))
  order by (w.user_id=d.owner_id) desc,w.username limit 101
 ) x;
 return jsonb_build_object('meeting',meeting,'people',people,'created_at',d.created_at);
end;$$;
revoke all on function public.whisper_notes_context(uuid) from public,anon;
grant execute on function public.whisper_notes_context(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
