-- Additive rollout on the existing native-auth backend. No historical reactions are imported.
begin;
alter table public.whisper_messages add column if not exists logical_group_message_id uuid;
create table if not exists public.whisper_group_message_identity (
 id uuid primary key, group_id uuid not null references public.whisper_group_threads(id) on delete cascade,
 sender_id uuid not null references auth.users(id) on delete cascade, body text not null, created_at timestamptz not null default now()
);
alter table public.whisper_group_message_identity enable row level security;
revoke all on public.whisper_group_message_identity from public, anon, authenticated;
create index if not exists whisper_message_logical_identity on public.whisper_messages(logical_group_message_id) where logical_group_message_id is not null;

create or replace function public.whisper_guard_group_message_identity()
returns trigger language plpgsql security definer set search_path='' as $$
declare gid uuid; identity_row public.whisper_group_message_identity; g public.whisper_group_threads;
begin
 if TG_OP='UPDATE' then
  if new.from_user_id is distinct from old.from_user_id or new.to_user_id is distinct from old.to_user_id
     or new.thread_id is distinct from old.thread_id then raise exception 'Message participants are immutable' using errcode='42501'; end if;
  if new.logical_group_message_id is distinct from old.logical_group_message_id or
    (old.logical_group_message_id is not null and (new.body is distinct from old.body or new.from_user_id is distinct from old.from_user_id or new.to_user_id is distinct from old.to_user_id)) then
    raise exception 'Message identity is immutable' using errcode='42501';
  end if;
  return new;
 end if;
 if new.logical_group_message_id is null then return new; end if;
 if auth.uid() is distinct from new.from_user_id then raise exception 'Sender required' using errcode='42501'; end if;
 if new.body not like '::wg-v1::%' then raise exception 'Group message required'; end if;
 gid := split_part(substr(new.body,10),'::',1)::uuid;
 select * into g from public.whisper_group_threads where id=gid for share;
 if not found or (new.from_user_id=g.owner_id or new.from_user_id=any(g.member_ids)) is not true
   or (new.to_user_id=g.owner_id or new.to_user_id=any(g.member_ids)) is not true then raise exception 'Group unavailable' using errcode='42501'; end if;
 insert into public.whisper_group_message_identity(id,group_id,sender_id,body)
 values(new.logical_group_message_id,gid,new.from_user_id,new.body) on conflict(id) do nothing;
 select * into identity_row from public.whisper_group_message_identity where id=new.logical_group_message_id;
 if identity_row.group_id<>gid or identity_row.sender_id<>new.from_user_id or identity_row.body<>new.body then
  raise exception 'Group message identity conflict' using errcode='42501';
 end if;
 return new;
end $$;
revoke all on function public.whisper_guard_group_message_identity() from public,anon,authenticated;
create or replace trigger whisper_group_message_identity_guard before insert or update on public.whisper_messages
 for each row execute function public.whisper_guard_group_message_identity();

create table if not exists public.whisper_message_reactions (
 target_id text not null, actor_id uuid not null references auth.users(id) on delete cascade, emoji text,
 operation_id uuid not null, updated_at timestamptz not null default now(),
 primary key(target_id,actor_id), check(emoji is null or emoji in ('❤️','😂','😮','😢','😡','👍'))
);
alter table public.whisper_message_reactions enable row level security;
revoke all on public.whisper_message_reactions from public,anon,authenticated;
create table if not exists public.whisper_message_reaction_events (
 id uuid primary key default gen_random_uuid(), target_id text not null, message_id uuid not null,
 actor_id uuid not null references auth.users(id) on delete cascade,
 recipient_id uuid not null references auth.users(id) on delete cascade,
 group_id uuid references public.whisper_group_threads(id) on delete cascade, emoji text not null,
 operation_id uuid not null, created_at timestamptz not null default now()
);
alter table public.whisper_message_reaction_events enable row level security;
revoke all on public.whisper_message_reaction_events from public,anon,authenticated;
grant select on public.whisper_message_reaction_events, public.whisper_message_reactions, public.whisper_group_message_identity to service_role;
create index if not exists whisper_reaction_event_throttle on public.whisper_message_reaction_events(target_id,actor_id,created_at desc);

-- Both read and write derive the viewer from native auth and validate a real delivery.
create or replace function public.whisper_reaction_target(p_message_id uuid)
returns text language plpgsql stable security definer set search_path='' as $$
declare m public.whisper_messages; actor uuid := auth.uid(); gid uuid;
begin
 if actor is null then return null; end if;
 select * into m from public.whisper_messages where id=p_message_id;
 if not found or (actor=m.from_user_id or actor=m.to_user_id) is not true
 or not public.whisper_chat_meet_message_access(m.id) then return null; end if;
 if exists(select 1 from public.whisper_blocks where (blocker_id=actor and blocked_user_id in(m.from_user_id,m.to_user_id)) or (blocked_user_id=actor and blocker_id in(m.from_user_id,m.to_user_id)))
 or exists(select 1 from public.whisper_dm_blocks where (protected_user_id=actor and blocked_sender_id in(m.from_user_id,m.to_user_id)) or (blocked_sender_id=actor and protected_user_id in(m.from_user_id,m.to_user_id))) then return null; end if;
 if m.body like '::wg-v1::%' then
  if m.logical_group_message_id is null then return null; end if;
  select group_id into gid from public.whisper_group_message_identity where id=m.logical_group_message_id and sender_id=m.from_user_id;
  if gid is null or not exists(select 1 from public.whisper_group_threads g where g.id=gid and (actor=g.owner_id or actor=any(g.member_ids))) then return null; end if;
  return 'group:'||m.logical_group_message_id::text;
 end if;
 if m.body like '::whisper-call-%' then return null; end if;
 return 'dm:'||m.id::text;
end $$;
revoke all on function public.whisper_reaction_target(uuid) from public,anon,authenticated;

create or replace function public.whisper_get_message_reactions(p_message_ids uuid[])
returns table(message_id uuid, emoji text, reaction_count bigint, mine boolean)
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or coalesce(cardinality(p_message_ids),0)>200 then raise exception 'Invalid request' using errcode='42501'; end if;
 return query select ids.id,r.emoji,count(*),bool_or(r.actor_id=auth.uid())
 from (select distinct unnest(p_message_ids) as id) ids
 join public.whisper_message_reactions r on r.target_id=public.whisper_reaction_target(ids.id)
 where r.emoji is not null and not exists(select 1 from public.whisper_blocks b where
 (b.blocker_id=auth.uid() and b.blocked_user_id=r.actor_id) or (b.blocked_user_id=auth.uid() and b.blocker_id=r.actor_id))
 and not exists(select 1 from public.whisper_dm_blocks b where
 (b.protected_user_id=auth.uid() and b.blocked_sender_id=r.actor_id) or (b.blocked_sender_id=auth.uid() and b.protected_user_id=r.actor_id))
 group by ids.id,r.emoji;
end $$;
revoke all on function public.whisper_get_message_reactions(uuid[]) from public,anon;
grant execute on function public.whisper_get_message_reactions(uuid[]) to authenticated;

create or replace function public.whisper_set_message_reaction(p_message_id uuid,p_emoji text,p_operation_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare target text; actor uuid:=auth.uid(); previous public.whisper_message_reactions; m public.whisper_messages; gid uuid;
begin
 if p_operation_id is null or (p_emoji is not null and p_emoji not in ('❤️','😂','😮','😢','😡','👍')) then raise exception 'Invalid reaction'; end if;
 target:=public.whisper_reaction_target(p_message_id);
 if target is null then raise exception 'Message unavailable, or older group message has no shared identity' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(target::text||actor::text,0));
 select * into previous from public.whisper_message_reactions where target_id=target and actor_id=actor;
 if found and (previous.operation_id=p_operation_id or previous.emoji is not distinct from p_emoji) then return; end if;
 insert into public.whisper_message_reactions(target_id,actor_id,emoji,operation_id) values(target,actor,p_emoji,p_operation_id)
 on conflict(target_id,actor_id) do update set emoji=excluded.emoji,operation_id=excluded.operation_id,updated_at=now();
 select * into m from public.whisper_messages where id=p_message_id;
 select group_id into gid from public.whisper_group_message_identity where id=m.logical_group_message_id;
 if p_emoji is not null and actor<>m.from_user_id and not exists(select 1 from public.whisper_message_reaction_events e where e.target_id=target and e.actor_id=actor and e.created_at>now()-interval '30 seconds') then
  insert into public.whisper_message_reaction_events(target_id,message_id,actor_id,recipient_id,group_id,emoji,operation_id)
  values(target,m.id,actor,m.from_user_id,gid,p_emoji,p_operation_id);
 end if;
end $$;
revoke all on function public.whisper_set_message_reaction(uuid,text,uuid) from public,anon;
grant execute on function public.whisper_set_message_reaction(uuid,text,uuid) to authenticated;
commit;
