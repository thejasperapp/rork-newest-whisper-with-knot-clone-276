-- Apply after the reaction-aware sender has deployed. Reuse the trusted database webhook configuration.
begin;
do $$ declare args text[]; begin
 select string_to_array(encode(t.tgargs,'escape'), E'\\000') into args
 from pg_catalog.pg_trigger t where t.tgrelid='public.whisper_messages'::regclass and t.tgname='whisper-dm-push';
 if args is null or args[1] is distinct from 'https://uryyyegnbtlmyhqlgndy.supabase.co/functions/v1/whisper-push-fanout'
 or args[2] is distinct from 'POST' or coalesce((args[3]::jsonb)->>'Authorization','')='' then
  raise exception 'Existing trusted push configuration is unavailable';
 end if;
 if not exists(select 1 from pg_catalog.pg_trigger where tgrelid='public.whisper_message_reaction_events'::regclass and tgname='whisper-reaction-push') then
  create trigger "whisper-reaction-push" after insert on public.whisper_message_reaction_events
  for each row execute function public.whisper_dispatch_social_push();
 end if;
end $$;
commit;
