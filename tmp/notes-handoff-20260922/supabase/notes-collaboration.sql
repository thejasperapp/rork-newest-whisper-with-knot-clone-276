-- Additive, invitation-only shared editions. Existing private notebooks and Meet policies are untouched.
begin;
create table if not exists public.whisper_shared_documents (
 id uuid primary key, owner_id uuid not null references auth.users(id), title text not null check(length(title) between 1 and 160),
 seed jsonb not null check(jsonb_typeof(seed)='object' and octet_length(seed::text)<=1500000),
 seq bigint not null default 0, bytes bigint not null default 0, deleted boolean not null default false,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.whisper_document_members (
 id uuid primary key, document_id uuid not null references public.whisper_shared_documents(id),
 invited_by uuid not null references auth.users(id), user_id uuid references auth.users(id), email text,
 role text not null check(role in ('viewer','commenter','editor')), status text not null default 'pending' check(status in ('pending','active','revoked','declined')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), last_email_at timestamptz,
 check((user_id is not null) <> (email is not null))
);
create index if not exists notes_members_document on public.whisper_document_members(document_id);
create index if not exists notes_members_user on public.whisper_document_members(user_id,status);
create index if not exists notes_members_email on public.whisper_document_members(lower(email),status);
create table if not exists public.whisper_document_updates (
 document_id uuid not null references public.whisper_shared_documents(id), seq bigint not null,
 operation_id uuid not null, author_id uuid not null references auth.users(id), update_data text not null check(length(update_data) between 1 and 1500000),
 created_at timestamptz not null default now(), primary key(document_id,seq), unique(document_id,operation_id)
);
create table if not exists public.whisper_document_comments (
 id uuid primary key, document_id uuid not null references public.whisper_shared_documents(id), author_id uuid not null references auth.users(id),
 parent_id uuid, quote text not null default '', anchor jsonb, body text not null check(length(body) between 1 and 4000),
 resolved boolean not null default false, created_at timestamptz not null default now()
);
create index if not exists notes_comments_document on public.whisper_document_comments(document_id,created_at);
create table if not exists public.whisper_document_versions (
 id uuid primary key, document_id uuid not null references public.whisper_shared_documents(id), author_id uuid not null references auth.users(id),
 label text not null check(length(label) between 1 and 120), seq bigint not null, content jsonb not null,
 created_at timestamptz not null default now(), check(jsonb_typeof(content)='object' and octet_length(content::text)<=1500000)
);
create index if not exists notes_versions_document on public.whisper_document_versions(document_id,created_at);
create table if not exists public.whisper_document_presence (
 document_id uuid not null references public.whisper_shared_documents(id), user_id uuid not null references auth.users(id), session_id uuid not null,
 selection jsonb, updated_at timestamptz not null default now(), primary key(document_id,user_id,session_id), check(octet_length(selection::text)<=4000)
);
alter table public.whisper_shared_documents enable row level security;
alter table public.whisper_document_members enable row level security;
alter table public.whisper_document_updates enable row level security;
alter table public.whisper_document_comments enable row level security;
alter table public.whisper_document_versions enable row level security;
alter table public.whisper_document_presence enable row level security;
-- No direct client policies: all reads and writes pass through permission-checked functions below.
revoke all on public.whisper_shared_documents, public.whisper_document_members, public.whisper_document_updates, public.whisper_document_comments, public.whisper_document_versions, public.whisper_document_presence from public, anon, authenticated;

create or replace function public.whisper_notes_role(p_doc uuid) returns text
language sql stable security definer set search_path='' as $$
 select case when d.owner_id=auth.uid() then 'owner' else (
  select m.role from public.whisper_document_members m where m.document_id=d.id and m.status='active'
   and not exists(select 1 from public.whisper_blocks b where (b.blocker_id=d.owner_id and b.blocked_user_id=auth.uid()) or (b.blocker_id=auth.uid() and b.blocked_user_id=d.owner_id))
   and (m.user_id=auth.uid() or (m.email is not null and exists(select 1 from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null and lower(u.email)=m.email)))
  order by case m.role when 'editor' then 3 when 'commenter' then 2 else 1 end desc limit 1
 ) end from public.whisper_shared_documents d where d.id=p_doc and not d.deleted;
$$;
revoke all on function public.whisper_notes_role(uuid) from public, anon, authenticated;

create or replace function public.whisper_notes_library() returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid := auth.uid(); mail text; result jsonb;
begin
 if uid is null then raise exception 'sign_in_required' using errcode='42501'; end if;
 select lower(email) into mail from auth.users where id=uid and email_confirmed_at is not null;
 select jsonb_build_object('documents',coalesce((select jsonb_agg(x) from (
  select d.id,d.title,d.owner_id,d.updated_at,public.whisper_notes_role(d.id) as role
  from public.whisper_shared_documents d where not d.deleted and public.whisper_notes_role(d.id) is not null order by d.updated_at desc limit 200
 ) x),'[]'::jsonb),'invitations',coalesce((select jsonb_agg(x) from (
  select m.id,m.document_id,m.role,d.title,m.created_at from public.whisper_document_members m join public.whisper_shared_documents d on d.id=m.document_id
  where not d.deleted and m.status='pending' and (m.user_id=uid or m.email=mail) order by m.created_at desc limit 200
 ) x),'[]'::jsonb)) into result;
 return result;
end; $$;
revoke all on function public.whisper_notes_library() from public,anon;
grant execute on function public.whisper_notes_library() to authenticated;

create or replace function public.whisper_notes_action(p_doc uuid,p_action text,p_payload jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare uid uuid:=auth.uid(); d public.whisper_shared_documents; m public.whisper_document_members; v public.whisper_document_versions;
 r text; mail text; target uuid; op uuid; cursor_seq bigint; data text; content jsonb; item uuid; parent uuid; output jsonb;
begin
 if uid is null then raise exception 'sign_in_required' using errcode='42501'; end if;
 if p_doc is null or p_action is null or jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>2200000 then raise exception 'invalid_document'; end if;
 select lower(email) into mail from auth.users where id=uid and email_confirmed_at is not null;
 if p_action='create' then
  perform pg_advisory_xact_lock(hashtextextended(uid::text,93211));
  select * into d from public.whisper_shared_documents where id=p_doc;
  if found then if d.owner_id<>uid or d.deleted then raise exception 'document_access_denied' using errcode='42501'; end if; return jsonb_build_object('id',d.id); end if;
  if (select count(*) from public.whisper_shared_documents where owner_id=uid and not deleted)>=200 then raise exception 'document_limit'; end if;
  if length(btrim(p_payload->>'title')) not between 1 and 160 or p_payload->>'title' is null or jsonb_typeof(p_payload->'content') is distinct from 'object' or octet_length((p_payload->'content')::text)>1500000 then raise exception 'invalid_document'; end if;
  insert into public.whisper_shared_documents(id,owner_id,title,seed) values(p_doc,uid,btrim(p_payload->>'title'),p_payload->'content');
  return jsonb_build_object('id',p_doc);
 end if;
 -- The document lock serializes permission changes with writes and update sequence assignment.
 select * into d from public.whisper_shared_documents where id=p_doc for update;
 if not found or d.deleted then raise exception 'document_access_denied' using errcode='42501'; end if;
 if p_action in ('accept','decline') then
  if exists(select 1 from public.whisper_blocks where (blocker_id=uid and blocked_user_id=d.owner_id) or (blocker_id=d.owner_id and blocked_user_id=uid)) then raise exception 'document_access_denied' using errcode='42501'; end if;
  select * into m from public.whisper_document_members where id=(p_payload->>'id')::uuid and document_id=p_doc for update;
  if not found or m.status not in ('pending','active') or not coalesce(m.user_id=uid or m.email=mail,false) then raise exception 'document_access_denied' using errcode='42501'; end if;
  update public.whisper_document_members set status=case when p_action='accept' then 'active' else 'declined' end,updated_at=now() where id=m.id;
  return jsonb_build_object('ok',true);
 end if;
 r:=public.whisper_notes_role(p_doc);
 if r is null then raise exception 'document_access_denied' using errcode='42501'; end if;
 if p_action='read' then
  cursor_seq:=coalesce((p_payload->>'after')::bigint,0);
  if cursor_seq<0 or cursor_seq>d.seq then raise exception 'invalid_cursor'; end if;
  select jsonb_build_object('id',d.id,'title',d.title,'owner_id',d.owner_id,'role',r,'seq',d.seq,
   'seed',case when d.seq=0 then d.seed else null end,
   'updates',coalesce((select jsonb_agg(x order by x.seq) from (select seq,operation_id,author_id,update_data from public.whisper_document_updates where document_id=p_doc and seq>cursor_seq order by seq limit 128) x),'[]'::jsonb),
   'people',coalesce((select jsonb_agg(x) from (select p.user_id,p.session_id,p.selection,coalesce(w.username,'Collaborator') as name from public.whisper_document_presence p left join public.whisper_profiles w on w.user_id=p.user_id where p.document_id=p_doc and p.updated_at>now()-interval '20 seconds' and (p.user_id=d.owner_id or exists(select 1 from public.whisper_document_members mm left join auth.users u on u.id=p.user_id where mm.document_id=p_doc and mm.status='active' and (mm.user_id=p.user_id or (mm.email=lower(u.email) and u.email_confirmed_at is not null)))) limit 50) x),'[]'::jsonb)) into output;
  return output;
 elsif p_action in ('update','initialize','restore') then
  if r not in ('owner','editor') then raise exception 'document_access_denied' using errcode='42501'; end if;
  op:=(p_payload->>'operation')::uuid; data:=p_payload->>'update';
  if op is null or data is null or length(data) not between 1 and 1500000 or data !~ '^[A-Za-z0-9+/]*={0,2}$' then raise exception 'invalid_update'; end if;
  select seq into cursor_seq from public.whisper_document_updates where document_id=p_doc and operation_id=op;
  if found then return jsonb_build_object('seq',cursor_seq,'operation',op); end if;
  if p_action='initialize' and d.seq>0 then return jsonb_build_object('seq',d.seq,'alreadyInitialized',true); end if;
  if p_action='restore' and coalesce((p_payload->>'expected')::bigint,-1)<>d.seq then raise exception 'document_changed' using errcode='40001'; end if;
  if d.seq>=20000 or d.bytes+length(data)>30000000 then raise exception 'document_limit'; end if;
  if p_action='restore' then
   if (select count(*) from public.whisper_document_versions where document_id=p_doc)>=100 then raise exception 'document_limit'; end if;
   if jsonb_typeof(p_payload->'before') is distinct from 'object' or octet_length((p_payload->'before')::text)>1500000 then raise exception 'invalid_document'; end if;
   insert into public.whisper_document_versions(id,document_id,author_id,label,seq,content) values(op,p_doc,uid,'Before restore',d.seq,p_payload->'before');
  end if;
  insert into public.whisper_document_updates(document_id,seq,operation_id,author_id,update_data) values(p_doc,d.seq+1,op,uid,data);
  update public.whisper_shared_documents set seq=seq+1,bytes=bytes+length(data),updated_at=now() where id=p_doc;
  return jsonb_build_object('seq',d.seq+1,'operation',op);
 elsif p_action='presence' then
  item:=(p_payload->>'session')::uuid;
  if item is null or octet_length(coalesce((p_payload->'selection')::text,''))>4000 then raise exception 'invalid_document'; end if;
  if (select count(*) from public.whisper_document_presence where document_id=p_doc and user_id=uid and updated_at>now()-interval '20 seconds')>=5 and not exists(select 1 from public.whisper_document_presence where document_id=p_doc and user_id=uid and session_id=item) then raise exception 'document_limit'; end if;
  delete from public.whisper_document_presence where document_id=p_doc and updated_at<now()-interval '1 minute';
  insert into public.whisper_document_presence(document_id,user_id,session_id,selection) values(p_doc,uid,item,p_payload->'selection') on conflict(document_id,user_id,session_id) do update set selection=excluded.selection,updated_at=now();
  return jsonb_build_object('ok',true);
 elsif p_action='invite' then
  if r<>'owner' then raise exception 'document_access_denied' using errcode='42501'; end if;
  item:=(p_payload->>'id')::uuid;
  if item is null or (p_payload->>'role') not in ('viewer','commenter','editor') or p_payload->>'role' is null then raise exception 'invalid_invitation'; end if;
  select * into m from public.whisper_document_members where id=item;
  if found then if m.document_id<>p_doc then raise exception 'invalid_invitation'; end if; return jsonb_build_object('id',m.id,'status',m.status); end if;
  if (select count(*) from public.whisper_document_members where document_id=p_doc)>=100 or (select count(*) from public.whisper_document_members where invited_by=uid and created_at>now()-interval '1 day')>=30 then raise exception 'invitation_limit'; end if;
  if p_payload->>'username' is not null then
   if p_payload->>'username' !~ '^[A-Za-z0-9_.]{1,40}$' then raise exception 'invalid_invitation'; end if;
   select user_id into target from public.whisper_profiles where lower(username)=lower(p_payload->>'username');
   if target is null or target=uid or exists(select 1 from public.whisper_blocks where (blocker_id=uid and blocked_user_id=target) or (blocker_id=target and blocked_user_id=uid)) then raise exception 'person_unavailable'; end if;
   mail:=null;
  else
   mail:=lower(btrim(p_payload->>'email'));
   if mail is null or length(mail)>254 or mail !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'invalid_invitation'; end if;
  end if;
  if exists(select 1 from public.whisper_document_members where document_id=p_doc and status in ('active','pending') and (user_id=target or email=mail)) then raise exception 'already_invited'; end if;
  insert into public.whisper_document_members(id,document_id,invited_by,user_id,email,role) values(item,p_doc,uid,target,mail,p_payload->>'role');
  return jsonb_build_object('id',item,'status','pending');
 elsif p_action='members' then
  if r<>'owner' then raise exception 'document_access_denied' using errcode='42501'; end if;
  return coalesce((select jsonb_agg(x) from (select m.id,m.user_id,m.email,m.role,m.status,m.created_at,m.last_email_at,w.username from public.whisper_document_members m left join public.whisper_profiles w on w.user_id=m.user_id where m.document_id=p_doc order by m.created_at) x),'[]'::jsonb);
 elsif p_action='permission' then
  if r<>'owner' or p_payload->>'role' is null or p_payload->>'role' not in ('viewer','commenter','editor','revoked') then raise exception 'document_access_denied' using errcode='42501'; end if;
  update public.whisper_document_members set role=case when p_payload->>'role'='revoked' then role else p_payload->>'role' end,status=case when p_payload->>'role'='revoked' then 'revoked' else status end,updated_at=now() where document_id=p_doc and id=(p_payload->>'id')::uuid;
  return jsonb_build_object('ok',true);
 elsif p_action='email_claim' then
  if r<>'owner' then raise exception 'document_access_denied' using errcode='42501'; end if;
  select * into m from public.whisper_document_members where document_id=p_doc and id=(p_payload->>'id')::uuid for update;
  if not found or m.email is null or m.status<>'pending' or m.last_email_at>now()-interval '10 minutes' then raise exception 'invitation_unavailable'; end if;
  if (select count(*) from public.whisper_document_members where invited_by=uid and last_email_at>now()-interval '1 hour')>=15 then raise exception 'invitation_limit'; end if;
  update public.whisper_document_members set last_email_at=now() where id=m.id;
  return jsonb_build_object('email',m.email,'title',d.title,'id',m.id,'document_id',d.id);
 elsif p_action='comment' then
  if r not in ('owner','editor','commenter') then raise exception 'document_access_denied' using errcode='42501'; end if;
  item:=(p_payload->>'id')::uuid; parent:=(p_payload->>'parent')::uuid;
  if item is null or length(btrim(p_payload->>'body')) not between 1 and 4000 or p_payload->>'body' is null or length(coalesce(p_payload->>'quote',''))>2000 or octet_length(coalesce((p_payload->'anchor')::text,''))>4000 then raise exception 'invalid_comment'; end if;
  if exists(select 1 from public.whisper_document_comments where id=item and (document_id<>p_doc or author_id<>uid)) then raise exception 'invalid_comment'; end if;
  if parent is not null and not exists(select 1 from public.whisper_document_comments where id=parent and document_id=p_doc and parent_id is null) then raise exception 'invalid_comment'; end if;
  if (select count(*) from public.whisper_document_comments where document_id=p_doc)>=1000 then raise exception 'document_limit'; end if;
  insert into public.whisper_document_comments(id,document_id,author_id,parent_id,quote,anchor,body) values(item,p_doc,uid,parent,coalesce(p_payload->>'quote',''),p_payload->'anchor',btrim(p_payload->>'body')) on conflict(id) do nothing;
  return jsonb_build_object('ok',true);
 elsif p_action='resolve' then
  if r not in ('owner','editor','commenter') then raise exception 'document_access_denied' using errcode='42501'; end if;
  update public.whisper_document_comments set resolved=coalesce((p_payload->>'resolved')::boolean,false) where id=(p_payload->>'id')::uuid and document_id=p_doc and parent_id is null and (r in ('owner','editor') or author_id=uid);
  return jsonb_build_object('ok',true);
 elsif p_action='comments' then
  return coalesce((select jsonb_agg(x) from (select c.*,coalesce(w.username,'Collaborator') as name from public.whisper_document_comments c left join public.whisper_profiles w on w.user_id=c.author_id where c.document_id=p_doc order by c.created_at limit 1000) x),'[]'::jsonb);
 elsif p_action='version' then
  if r not in ('owner','editor') then raise exception 'document_access_denied' using errcode='42501'; end if;
  item:=(p_payload->>'id')::uuid; content:=p_payload->'content';
  if item is null or jsonb_typeof(content) is distinct from 'object' or octet_length(content::text)>1500000 or length(btrim(p_payload->>'label')) not between 1 and 120 or p_payload->>'label' is null then raise exception 'invalid_document'; end if;
  if coalesce((p_payload->>'expected')::bigint,-1)<>d.seq then raise exception 'document_changed' using errcode='40001'; end if;
  if (select count(*) from public.whisper_document_versions where document_id=p_doc)>=100 then raise exception 'document_limit'; end if;
  insert into public.whisper_document_versions(id,document_id,author_id,label,seq,content) values(item,p_doc,uid,btrim(p_payload->>'label'),d.seq,content) on conflict(id) do nothing;
  return jsonb_build_object('ok',true);
 elsif p_action='versions' then
  return coalesce((select jsonb_agg(x) from (select v.id,v.label,v.seq,v.created_at,coalesce(w.username,'Collaborator') as name from public.whisper_document_versions v left join public.whisper_profiles w on w.user_id=v.author_id where v.document_id=p_doc order by v.created_at desc limit 100) x),'[]'::jsonb);
 elsif p_action='version_read' then
  select * into v from public.whisper_document_versions where id=(p_payload->>'id')::uuid and document_id=p_doc;
  if not found then raise exception 'document_access_denied' using errcode='42501'; end if;
  return jsonb_build_object('content',v.content,'label',v.label);
 elsif p_action='rename' then
  if r not in ('owner','editor') then raise exception 'document_access_denied' using errcode='42501'; end if;
  if length(btrim(p_payload->>'title')) not between 1 and 160 or p_payload->>'title' is null then raise exception 'invalid_document'; end if;
  update public.whisper_shared_documents set title=btrim(p_payload->>'title'),updated_at=now() where id=p_doc;
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'invalid_action';
end; $$;
revoke all on function public.whisper_notes_action(uuid,text,jsonb) from public,anon;
grant execute on function public.whisper_notes_action(uuid,text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
