-- Social projection/delivery only. No Teams roster, acceptance, Meet or existing message policies changed.
-- Prepared migration: deploy only against the existing native-Auth Whisper database after schema review.
begin;
create schema if not exists whisper_social_teams_private;
revoke all on schema whisper_social_teams_private from public, anon, authenticated;

create table if not exists whisper_social_teams_private.invitations (
  invitation_id uuid primary key,
  team_id uuid not null,
  inviter_id uuid not null,
  recipient_id uuid not null,
  version bigint not null check (version > 0),
  snapshot jsonb not null,
  message_id uuid unique,
  suppressed boolean not null default false,
  received_at timestamptz not null default now(),
  check (inviter_id <> recipient_id)
);
create table if not exists whisper_social_teams_private.events (
  event_id uuid primary key,
  invitation_id uuid not null,
  version bigint not null,
  fingerprint text not null,
  result text not null,
  created_at timestamptz not null default now(),
  unique(invitation_id, version)
);
-- A restrictive device snapshot never overwrites another device's restrictions.
create table if not exists whisper_social_teams_private.privacy (
  user_id uuid not null references auth.users(id) on delete cascade,
  installation_id uuid not null,
  revision bigint not null,
  private_dm boolean not null,
  approved uuid[] not null,
  denied uuid[] not null,
  updated_at timestamptz not null default now(),
  primary key(user_id, installation_id)
);
alter table whisper_social_teams_private.invitations enable row level security;
alter table whisper_social_teams_private.events enable row level security;
alter table whisper_social_teams_private.privacy enable row level security;
revoke all on all tables in schema whisper_social_teams_private from public, anon, authenticated;

create or replace function public.whisper_social_teams_privacy(
  p_owner uuid, p_installation uuid, p_revision bigint, p_private boolean, p_approved uuid[], p_denied uuid[]
) returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or auth.uid() <> p_owner then raise insufficient_privilege; end if;
  if p_installation is null or p_revision is null or p_revision < 1 or p_private is null
    or p_approved is null or p_denied is null or cardinality(p_approved) > 2000 or cardinality(p_denied) > 2000
    or array_position(p_approved,null) is not null or array_position(p_denied,null) is not null then
    raise exception using errcode='22023', message='invalid_privacy';
  end if;
  insert into whisper_social_teams_private.privacy(user_id,installation_id,revision,private_dm,approved,denied)
    values(p_owner,p_installation,p_revision,p_private,p_approved,p_denied)
    on conflict(user_id,installation_id) do update set revision=excluded.revision,private_dm=excluded.private_dm,
      approved=excluded.approved,denied=excluded.denied,updated_at=now()
    where whisper_social_teams_private.privacy.revision < excluded.revision;
end $$;
revoke all on function public.whisper_social_teams_privacy(uuid,uuid,bigint,boolean,uuid[],uuid[]) from public,anon;
grant execute on function public.whisper_social_teams_privacy(uuid,uuid,bigint,boolean,uuid[],uuid[]) to authenticated;

create or replace function whisper_social_teams_private.pair_allowed(a uuid,b uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select a <> b
    and (select count(*)=2 from auth.users u where u.id in(a,b) and u.deleted_at is null
      and not coalesce(u.is_anonymous,false) and (u.banned_until is null or u.banned_until <= now()))
    and (select count(*)=2 from public.whisper_profiles p where p.user_id in(a,b)
      and not p.ghost_enabled and length(trim(p.username)) > 0)
    and not exists(select 1 from public.whisper_blocks where (blocker_id=a and blocked_user_id=b) or (blocker_id=b and blocked_user_id=a))
    and not exists(select 1 from public.whisper_dm_blocks where (blocked_sender_id=a and protected_user_id=b) or (blocked_sender_id=b and protected_user_id=a))
    and not exists(select 1 from whisper_social_teams_private.privacy where user_id=b and a=any(denied))
$$;

create or replace function whisper_social_teams_private.notify_allowed(a uuid,b uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select whisper_social_teams_private.pair_allowed(a,b)
    and exists(select 1 from whisper_social_teams_private.privacy where user_id=b)
    and not exists(select 1 from whisper_social_teams_private.privacy p where p.user_id=b and p.private_dm
      and not(a=any(p.approved)) and not exists(select 1 from public.whisper_follows f where
        (f.follower_id=a and f.followee_id=b) or (f.follower_id=b and f.followee_id=a)))
    and not exists(select 1 from public.whisper_notification_prefs p where p.user_id=b and
      (p.master_enabled=false or p.quiet_mode=true or p.dms=false))
$$;

create or replace function public.whisper_social_teams_receive(p_event jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  e uuid; i uuid; t uuid; a uuid; b uuid; v bigint; fp text; existing_fp text;
  state whisper_social_teams_private.invitations%rowtype;
  found_state boolean; outcome text; mid uuid; tid uuid; allowed boolean;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise insufficient_privilege; end if;
  if p_event is null or jsonb_typeof(p_event) <> 'object' or octet_length(p_event::text)>8192
    or p_event->>'source' is distinct from 'whisper-teams' or p_event->'schemaVersion' is distinct from '1'::jsonb
    or not(p_event ?& array['eventId','invitationId','invitationVersion','teamId','inviterId','recipientId','teamName','status','occurredAt','expiresAt'])
    or (select count(*) from jsonb_object_keys(p_event))<>12
    or p_event->>'status' not in('pending','accepted','declined','revoked','expired')
    or length(trim(p_event->>'teamName')) not between 1 and 120
    or p_event->>'teamName' ~ '[[:cntrl:]<>]'
    or jsonb_typeof(p_event->'invitationVersion')<>'string' or (p_event->>'invitationVersion') !~ '^[1-9][0-9]{0,18}$'
    or jsonb_typeof(p_event->'occurredAt')<>'number' or (p_event->>'occurredAt') !~ '^[0-9]{1,16}$'
    or jsonb_typeof(p_event->'expiresAt')<>'number' or (p_event->>'expiresAt') !~ '^[0-9]{1,16}$'
    or exists(select 1 from jsonb_each(p_event) x where x.value='null'::jsonb)
  then raise exception using errcode='22023',message='invalid_event'; end if;
  e:=(p_event->>'eventId')::uuid; i:=(p_event->>'invitationId')::uuid; t:=(p_event->>'teamId')::uuid;
  a:=(p_event->>'inviterId')::uuid; b:=(p_event->>'recipientId')::uuid; v:=(p_event->>'invitationVersion')::bigint;
  if a=b or v<1 or (p_event->>'occurredAt')::numeric>extract(epoch from now())*1000+60000
    or (p_event->>'expiresAt')::numeric<=0 or (p_event->>'occurredAt')::numeric<=0
    or (p_event->>'expiresAt')::numeric>=8640000000000000
    or (p_event->>'status'='pending' and (p_event->>'expiresAt')::numeric<=(p_event->>'occurredAt')::numeric)
    then raise exception using errcode='22023',message='invalid_event'; end if;
  fp:=encode(sha256(convert_to(p_event::text,'UTF8')),'hex');
  -- Lock event first, then invitation. Same event across different invitations cannot race.
  perform pg_advisory_xact_lock(hashtextextended('social-teams-event:'||e::text,0));
  select fingerprint into existing_fp from whisper_social_teams_private.events where event_id=e;
  if found then
    if existing_fp<>fp then raise exception using errcode='PT409',message='event_conflict'; end if;
    return jsonb_build_object('eventId',e,'result','duplicate');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('social-teams-invitation:'||i::text,0));
  select * into state from whisper_social_teams_private.invitations where invitation_id=i for update;
  found_state:=found;
  if found_state and (state.team_id<>t or state.inviter_id<>a or state.recipient_id<>b) then
    raise exception using errcode='PT409',message='identity_conflict';
  end if;
  if exists(select 1 from whisper_social_teams_private.events where invitation_id=i and version=v) then
    raise exception using errcode='PT409',message='version_conflict';
  end if;
  if found_state and v<state.version then
    insert into whisper_social_teams_private.events values(e,i,v,fp,'stale',now());
    return jsonb_build_object('eventId',e,'result','stale');
  end if;
  if found_state and state.snapshot->>'status'<>'pending' and p_event->>'status'<>state.snapshot->>'status' then
    raise exception using errcode='PT409',message='terminal_invitation';
  end if;
  allowed:=whisper_social_teams_private.pair_allowed(a,b);
  mid:=case when found_state then state.message_id else null end;
  outcome:=case when allowed and not coalesce(state.suppressed,false) then 'applied' else 'suppressed' end;
  -- Only the first observed live pending state may deliver; terminal-first events are tombstones.
  if not found_state and allowed and p_event->>'status'='pending'
      and (p_event->>'expiresAt')::numeric > extract(epoch from now())*1000 then
    mid:=gen_random_uuid();
  end if;
  insert into whisper_social_teams_private.invitations(invitation_id,team_id,inviter_id,recipient_id,version,snapshot,message_id,suppressed)
    values(i,t,a,b,v,p_event,mid,not allowed)
    on conflict(invitation_id) do update set version=v,snapshot=p_event,received_at=now(),
      suppressed=whisper_social_teams_private.invitations.suppressed or not allowed;
  insert into whisper_social_teams_private.events values(e,i,v,fp,outcome,now());
  if not found_state and mid is not null then
    tid:=substr(encode(sha256(convert_to(least(a::text,b::text)||'|'||greatest(a::text,b::text),'UTF8')),'hex'),1,32)::uuid;
    insert into public.whisper_messages(id,thread_id,from_user_id,to_user_id,from_username,to_username,body)
      select mid,tid,a,b,pa.username,pb.username,'::whisper-teams-v1::'||mid::text
      from public.whisper_profiles pa,public.whisper_profiles pb where pa.user_id=a and pb.user_id=b;
    if not found then raise exception 'profiles_changed'; end if;
  end if;
  return jsonb_build_object('eventId',e,'result',outcome);
end $$;
revoke all on function public.whisper_social_teams_receive(jsonb) from public,anon,authenticated;
grant execute on function public.whisper_social_teams_receive(jsonb) to service_role;

-- Only this resolver gives a card provenance. User-editable message bodies/embeds never do.
create or replace function public.whisper_social_teams_card(p_message_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s whisper_social_teams_private.invitations%rowtype; m public.whisper_messages%rowtype; st text;
begin
  if auth.uid() is null then raise insufficient_privilege; end if;
  select * into s from whisper_social_teams_private.invitations where message_id=p_message_id;
  if not found or auth.uid() not in(s.inviter_id,s.recipient_id) or s.suppressed
    or not whisper_social_teams_private.pair_allowed(s.inviter_id,s.recipient_id) then
    raise exception using errcode='42501',message='card_unavailable'; end if;
  select * into m from public.whisper_messages where id=p_message_id;
  if not found or m.from_user_id<>s.inviter_id or m.to_user_id is distinct from s.recipient_id
    or m.body is distinct from '::whisper-teams-v1::'||p_message_id::text then
    raise exception using errcode='42501',message='card_unavailable'; end if;
  st:=s.snapshot->>'status';
  if st='pending' and (s.snapshot->>'expiresAt')::numeric<=extract(epoch from now())*1000 then st:='expired'; end if;
  return jsonb_build_object('messageId',m.id,'invitationId',s.invitation_id,'teamId',s.team_id,
    'inviterId',s.inviter_id,'recipientId',s.recipient_id,'version',s.version::text,
    'teamName',s.snapshot->>'teamName','status',st,'expiresAt',s.snapshot->'expiresAt',
    'occurredAt',s.snapshot->'occurredAt','canOpen',st='pending' and auth.uid()=s.recipient_id);
end $$;
revoke all on function public.whisper_social_teams_card(uuid) from public,anon;
grant execute on function public.whisper_social_teams_card(uuid) to authenticated;

-- Fanout must check this at send time, not trust an INSERT webhook's cached body.
create or replace function public.whisper_social_teams_push_allowed(p_message_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare s whisper_social_teams_private.invitations%rowtype;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise insufficient_privilege; end if;
  select * into s from whisper_social_teams_private.invitations where message_id=p_message_id;
  return found and not s.suppressed and s.snapshot->>'status'='pending'
    and (s.snapshot->>'expiresAt')::numeric > extract(epoch from now())*1000
    and whisper_social_teams_private.notify_allowed(s.inviter_id,s.recipient_id)
    and exists(select 1 from public.whisper_messages m where m.id=p_message_id and m.read_at is null
      and m.from_user_id=s.inviter_id and m.to_user_id=s.recipient_id
      and m.body='::whisper-teams-v1::'||p_message_id::text);
end $$;
revoke all on function public.whisper_social_teams_push_allowed(uuid) from public,anon,authenticated;
grant execute on function public.whisper_social_teams_push_allowed(uuid) to service_role;
-- Permanent per-device claims: never automatically resend an ambiguous Teams APNs attempt.
create table if not exists public.whisper_social_teams_push_claims (
  event_key text primary key,
  created_at timestamptz not null default now()
);
alter table public.whisper_social_teams_push_claims enable row level security;
revoke all on public.whisper_social_teams_push_claims from public,anon,authenticated;
grant select,insert on public.whisper_social_teams_push_claims to service_role;

create or replace function whisper_social_teams_private.protect_message()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if TG_OP='DELETE' then
    update whisper_social_teams_private.invitations set suppressed=true where message_id=old.id;
    return old;
  end if;
  if TG_OP='UPDATE' and exists(select 1 from whisper_social_teams_private.invitations where message_id=old.id)
    and (to_jsonb(new)-'read_at') is distinct from (to_jsonb(old)-'read_at') then
    raise exception using errcode='42501',message='server_owned_card';
  end if;
  if TG_OP='INSERT' and (new.body like '::whisper-teams-%' or exists(select 1 from whisper_social_teams_private.invitations where message_id=new.id)) then
    if coalesce(auth.role(),'')<>'service_role' or not exists(select 1 from whisper_social_teams_private.invitations s
      where s.message_id=new.id and not s.suppressed and s.inviter_id=new.from_user_id and s.recipient_id=new.to_user_id
      and new.body='::whisper-teams-v1::'||new.id::text) then
      raise exception using errcode='42501',message='server_owned_card';
    end if;
  end if;
  return new;
end $$;
create or replace trigger whisper_social_teams_message_guard before insert or update or delete on public.whisper_messages
  for each row execute function whisper_social_teams_private.protect_message();
revoke all on all functions in schema whisper_social_teams_private from public,anon,authenticated;
commit;
