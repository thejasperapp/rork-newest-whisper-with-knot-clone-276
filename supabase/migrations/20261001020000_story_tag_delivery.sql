-- Prepared only. Requires the preceding Social privacy migration. No historic replay.
begin;
create schema if not exists whisper_story_social_private;
revoke all on schema whisper_story_social_private from public,anon,authenticated;
create table if not exists whisper_story_social_private.activation(singleton boolean primary key default true check(singleton),enabled boolean not null default false);
insert into whisper_story_social_private.activation(singleton) values(true) on conflict do nothing;
create table if not exists whisper_story_social_private.tags(
  story_id uuid not null, recipient_id uuid not null, author_id uuid not null,
  message_id uuid not null unique default gen_random_uuid(), suppressed boolean not null default false, created_at timestamptz not null default now(),
  primary key(story_id,recipient_id)
);
create index if not exists whisper_story_tag_rate on whisper_story_social_private.tags(author_id,recipient_id,created_at);
alter table whisper_story_social_private.activation enable row level security;
alter table whisper_story_social_private.tags enable row level security;
revoke all on all tables in schema whisper_story_social_private from public,anon,authenticated;

create or replace function whisper_story_social_private.visible(p_story uuid,p_viewer uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select p_viewer is not null and exists(
    select 1 from public.whisper_stories s join public.whisper_profiles p on p.user_id=s.user_id
    where s.id=p_story and s.expires_at>now() and coalesce(to_jsonb(s)->>'is_ghost','false')<>'true' and not coalesce(p.ghost_enabled,false)
    and (p_viewer=s.user_id or (whisper_social_teams_private.pair_allowed(s.user_id,p_viewer)
      and (not coalesce(p.is_private,true) or exists(select 1 from public.whisper_follows f where f.follower_id=p_viewer and f.followee_id=s.user_id))))
  )
$$;

create or replace function whisper_story_social_private.deliver_tags()
returns trigger language plpgsql security definer set search_path='' as $$
declare meta jsonb; item jsonb; handles text[] := '{}'; handle text; recipient record; receipt uuid; actor_name text; thread uuid;
begin
  if not coalesce((select enabled from whisper_story_social_private.activation where singleton),false) then return new; end if;
  if new.expires_at<=now() or new.created_at>now()+interval '1 minute' or new.created_at<now()-interval '5 minutes' then return new; end if;
  if auth.uid() is distinct from new.user_id and coalesce(auth.role(),'')<>'service_role' then return new; end if;
  if octet_length(coalesce(new.metadata,''))>131072 then return new; end if;
  begin meta:=coalesce(new.metadata,'{}')::jsonb; exception when invalid_text_representation then return new; end;
  if jsonb_typeof(meta->'stickers')<>'array' then return new; end if;
  for item in select value from jsonb_array_elements(meta->'stickers') limit 100 loop
    if item->>'kind'='mention' then
      handle:=lower(trim(leading '@' from trim(item->>'label')));
      if handle ~ '^[a-z0-9_.]{1,64}$' and not handle=any(handles) then handles:=array_append(handles,handle); end if;
    end if;
    exit when cardinality(handles)>=20;
  end loop;
  select username into actor_name from public.whisper_profiles where user_id=new.user_id;
  for recipient in select p.user_id,p.username from public.whisper_profiles p where lower(p.username)=any(handles) and p.user_id<>new.user_id loop
    if not whisper_story_social_private.visible(new.id,recipient.user_id) then continue; end if;
    perform pg_advisory_xact_lock(hashtextextended('story-tag:'||new.user_id::text||':'||recipient.user_id::text,0));
    if (select count(*) from whisper_story_social_private.tags where author_id=new.user_id and recipient_id=recipient.user_id and created_at>now()-interval '24 hours')>=5 then continue; end if;
    receipt:=null;
    insert into whisper_story_social_private.tags(story_id,recipient_id,author_id) values(new.id,recipient.user_id,new.user_id)
      on conflict do nothing returning message_id into receipt;
    if receipt is null then continue; end if;
    thread:=substr(encode(sha256(convert_to(least(new.user_id::text,recipient.user_id::text)||'|'||greatest(new.user_id::text,recipient.user_id::text),'UTF8')),'hex'),1,32)::uuid;
    insert into public.whisper_messages(id,thread_id,from_user_id,to_user_id,from_username,to_username,body)
      values(receipt,thread,new.user_id,recipient.user_id,actor_name,recipient.username,'::whisper-storytag-v1::'||new.id::text);
  end loop;
  return new;
end $$;
create or replace trigger whisper_story_tag_delivery after insert on public.whisper_stories
  for each row execute function whisper_story_social_private.deliver_tags();

create or replace function whisper_story_social_private.protect_message()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if TG_OP='DELETE' then
    update whisper_story_social_private.tags set suppressed=true where message_id=old.id;
    return old;
  end if;
  if TG_OP='INSERT' then
    if new.body like '::whisper-storytag-%' and not exists(select 1 from whisper_story_social_private.tags t
      where t.message_id=new.id and not t.suppressed and t.author_id=new.from_user_id and t.recipient_id=new.to_user_id
        and new.body='::whisper-storytag-v1::'||t.story_id::text) then
      raise exception using errcode='42501',message='server_owned_story_tag';
    end if;
    return new;
  end if;
  if new.body like '::whisper-storytag-%' and not exists(select 1 from whisper_story_social_private.tags where message_id=old.id) then
    raise exception using errcode='42501',message='server_owned_story_tag';
  end if;
  if exists(select 1 from whisper_story_social_private.tags where message_id=old.id)
    and (to_jsonb(new)-'read_at') is distinct from (to_jsonb(old)-'read_at') then
    raise exception using errcode='42501',message='server_owned_story_tag';
  end if;
  return new;
end $$;
create or replace trigger whisper_story_tag_message_guard before insert or update or delete on public.whisper_messages
  for each row execute function whisper_story_social_private.protect_message();

create or replace function public.whisper_story_tag_push(p_message_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare tag whisper_story_social_private.tags; m public.whisper_messages; allowed boolean;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise insufficient_privilege; end if;
  select * into tag from whisper_story_social_private.tags where message_id=p_message_id;
  if not found then return jsonb_build_object('tagged',false); end if;
  select * into m from public.whisper_messages where id=p_message_id;
  allowed:=coalesce((select enabled from whisper_story_social_private.activation where singleton),false) and not tag.suppressed and m.id is not null and m.from_user_id=tag.author_id and m.to_user_id=tag.recipient_id
    and m.body='::whisper-storytag-v1::'||tag.story_id::text and m.read_at is null
    and whisper_story_social_private.visible(tag.story_id,tag.recipient_id)
    and whisper_social_teams_private.notify_allowed(tag.author_id,tag.recipient_id);
  return jsonb_build_object('tagged',true,'allowed',coalesce(allowed,false));
end $$;
revoke all on function public.whisper_story_tag_push(uuid) from public,anon,authenticated;
grant execute on function public.whisper_story_tag_push(uuid) to service_role;

create or replace function public.whisper_story_card(p_story_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.whisper_stories;
begin
  if not whisper_story_social_private.visible(p_story_id,auth.uid()) then raise insufficient_privilege; end if;
  select * into s from public.whisper_stories where id=p_story_id;
  return jsonb_build_object('id',s.id,'user_id',s.user_id,'username',s.username,'image_url',s.image_url,'caption',s.caption,
    'created_at',s.created_at,'expires_at',s.expires_at,'metadata',s.metadata,'video_url',s.video_url,
    'music_url',s.music_url,'music_title',s.music_title,'music_artist',s.music_artist,'music_artwork',s.music_artwork);
end $$;
revoke all on function public.whisper_story_card(uuid) from public,anon;
grant execute on function public.whisper_story_card(uuid) to authenticated;
revoke all on all functions in schema whisper_story_social_private from public,anon,authenticated;
commit;
