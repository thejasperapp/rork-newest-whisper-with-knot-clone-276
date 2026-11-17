-- Apply only after the reviewed sender is deployed. Reuses the existing trusted database credential.
-- Never embeds a service key in source or changes the original DM/follow/like webhooks.
begin;
create or replace function public.whisper_dispatch_social_push()
returns trigger language plpgsql security definer set search_path = '' as $$
declare args text[];
begin
  select string_to_array(encode(t.tgargs,'escape'), E'\\000') into args
    from pg_catalog.pg_trigger t where t.tgrelid='public.whisper_messages'::regclass and t.tgname='whisper-dm-push';
  if args is null or args[1] <> 'https://uryyyegnbtlmyhqlgndy.supabase.co/functions/v1/whisper-push-fanout'
     or args[2] <> 'POST' or coalesce((args[3]::jsonb)->>'Authorization','') = '' then
    raise warning 'Social push dispatcher configuration is unavailable';
    return new;
  end if;
  perform net.http_post(url := args[1], headers := args[3]::jsonb,
    body := jsonb_build_object('type','INSERT','schema',TG_TABLE_SCHEMA,'table',TG_TABLE_NAME,'record',to_jsonb(NEW)),
    timeout_milliseconds := 10000);
  return new;
exception when others then
  -- Notifications must not prevent the user's comment or response from being saved.
  raise warning 'Social push could not be queued';
  return new;
end;
$$;
revoke all on function public.whisper_dispatch_social_push() from public, anon, authenticated;

do $$ declare name text; begin
  foreach name in array array['whisper_post_comments','whisper_mentions','whisper_story_responses'] loop
    if not exists (select 1 from pg_trigger where tgrelid=('public.'||name)::regclass
      and not tgisinternal and (tgname='whisper-social-push' or tgfoid='public.whisper_dispatch_social_push()'::regprocedure)) then
      execute format('create trigger %I after insert on public.%I for each row execute function public.whisper_dispatch_social_push()', 'whisper-social-push', name);
    end if;
  end loop;
end $$;

-- Retain the original thought trigger but replace its anon credential with the trusted DM webhook headers.
create or replace function public.whisper_thought_replies_notify()
returns trigger language plpgsql security definer set search_path = '' as $$
declare args text[];
begin
  select string_to_array(encode(t.tgargs,'escape'), E'\\000') into args
    from pg_catalog.pg_trigger t where t.tgrelid='public.whisper_messages'::regclass and t.tgname='whisper-dm-push';
  if args is not null and args[1]='https://uryyyegnbtlmyhqlgndy.supabase.co/functions/v1/whisper-push-fanout' then
    perform net.http_post(url := args[1], headers := args[3]::jsonb,
      body := jsonb_build_object('type','INSERT','schema','public','table','whisper_thought_replies','record',to_jsonb(NEW)),
      timeout_milliseconds := 10000);
  end if;
  return new;
exception when others then
  raise warning 'Thought push could not be queued';
  return new;
end;
$$;
revoke all on function public.whisper_thought_replies_notify() from public, anon, authenticated;
commit;
