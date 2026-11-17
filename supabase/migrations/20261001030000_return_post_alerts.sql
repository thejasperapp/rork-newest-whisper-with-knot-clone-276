-- Prepared, default-off. No historical replay and no inferred Story history.
begin;
alter table public.whisper_notification_prefs add column if not exists new_posts boolean not null default false,
  add column if not exists new_posts_synced boolean not null default false;
create schema if not exists whisper_return_posts_private;
revoke all on schema whisper_return_posts_private from public,anon,authenticated;
create table if not exists whisper_return_posts_private.activation(singleton boolean primary key default true check(singleton),enabled boolean not null default false);
insert into whisper_return_posts_private.activation(singleton) values(true) on conflict do nothing;
create table if not exists whisper_return_posts_private.deliveries(post_id uuid not null,author_id uuid not null,recipient_id uuid not null,created_at timestamptz not null default now(),primary key(post_id,recipient_id));
create index if not exists whisper_return_post_cooldown on whisper_return_posts_private.deliveries(recipient_id,created_at);
alter table whisper_return_posts_private.activation enable row level security;
alter table whisper_return_posts_private.deliveries enable row level security;
revoke all on all tables in schema whisper_return_posts_private from public,anon,authenticated;

create or replace function public.whisper_new_post_preference(p_owner uuid,p_enabled boolean default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare enabled boolean;
begin
  if auth.uid() is null or p_owner is null or auth.uid()<>p_owner then raise insufficient_privilege; end if;
  insert into public.whisper_notification_prefs(user_id) values(p_owner) on conflict do nothing;
  -- A passive refresh cannot undo another installation's explicit choice.
  update public.whisper_notification_prefs set new_posts=coalesce(p_enabled,new_posts),new_posts_synced=true where user_id=p_owner returning new_posts into enabled;
  return jsonb_build_object('new_posts',enabled,'rollout_enabled',coalesce((select a.enabled from whisper_return_posts_private.activation a where singleton),false));
end $$;
revoke all on function public.whisper_new_post_preference(uuid,boolean) from public,anon;
grant execute on function public.whisper_new_post_preference(uuid,boolean) to authenticated;

create or replace function public.whisper_return_post_candidates(p_post uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare post public.whisper_posts; previous timestamptz; target record; recipients jsonb; audience uuid[] := '{}';
begin
  if coalesce(auth.role(),'')<>'service_role' then raise insufficient_privilege; end if;
  if not coalesce((select enabled from whisper_return_posts_private.activation where singleton),false) then return '[]'::jsonb; end if;
  select * into post from public.whisper_posts where id=p_post;
  if not found or post.created_at<now()-interval '15 minutes' or post.created_at>now()+interval '1 minute'
    or coalesce(post.is_ghost,false) or coalesce(to_jsonb(post)->>'community_id','')<>'' then return '[]'::jsonb; end if;
  perform pg_advisory_xact_lock(hashtextextended('return-post-author:'||post.user_id::text,0));
  select max(created_at) into previous from public.whisper_posts where user_id=post.user_id and id<>p_post;
  -- A first post or unavailable history is not evidence of a return.
  if previous is null or previous>post.created_at-interval '14 days' then return '[]'::jsonb; end if;
  -- Intentionally bounded to 100 eligible close contacts, not a follower-wide blast.
  for target in select f.follower_id as id from public.whisper_follows f
    join public.whisper_notification_prefs prefs on prefs.user_id=f.follower_id
    where f.followee_id=post.user_id and prefs.new_posts_synced and prefs.new_posts
      and prefs.master_enabled and not prefs.quiet_mode
      and whisper_social_teams_private.pair_allowed(post.user_id,f.follower_id)
      and (
        (exists(select 1 from public.whisper_messages m where m.from_user_id=f.follower_id and m.to_user_id=post.user_id and m.created_at>now()-interval '90 days' and length(trim(m.body))>0 and m.body not like '::%')
        and exists(select 1 from public.whisper_messages m where m.from_user_id=post.user_id and m.to_user_id=f.follower_id and m.created_at>now()-interval '90 days' and length(trim(m.body))>0 and m.body not like '::%'))
        or (select count(*) from public.whisper_post_likes l join public.whisper_posts p on p.id=l.post_id where l.user_id=f.follower_id and p.user_id=post.user_id and l.created_at>now()-interval '90 days')>=3
      ) order by f.follower_id limit 100 loop
    perform pg_advisory_xact_lock(hashtextextended('return-post-recipient:'||target.id::text,0));
    if exists(select 1 from whisper_return_posts_private.deliveries where post_id=p_post and recipient_id=target.id and author_id=post.user_id) then
      audience := array_append(audience,target.id); continue;
    end if;
    if exists(select 1 from whisper_return_posts_private.deliveries where author_id=post.user_id and recipient_id=target.id and created_at>now()-interval '30 days') then continue; end if;
    if (select count(*) from whisper_return_posts_private.deliveries where recipient_id=target.id and created_at>now()-interval '7 days')>=3 then continue; end if;
    insert into whisper_return_posts_private.deliveries(post_id,author_id,recipient_id) values(p_post,post.user_id,target.id) on conflict do nothing;
    audience := array_append(audience,target.id);
  end loop;
  -- Retry only the durable recipients who still pass the complete admission above.
  select to_jsonb(audience) into recipients;
  return recipients;
end $$;
revoke all on function public.whisper_return_post_candidates(uuid) from public,anon,authenticated;
grant execute on function public.whisper_return_post_candidates(uuid) to service_role;
create or replace trigger whisper_return_post_push after insert on public.whisper_posts for each row execute function public.whisper_dispatch_social_push();
commit;
