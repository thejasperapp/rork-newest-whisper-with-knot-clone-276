begin;
-- Owner is explicit as well as authenticated, so queued work cannot target a newly adopted account.
create or replace function public.whisper_update_push_preferences(p_owner uuid, p_patch jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare result jsonb;
begin
  if auth.uid() is null or p_owner is null or auth.uid() <> p_owner then raise exception 'not authorized' using errcode='42501'; end if;
  if jsonb_typeof(p_patch) <> 'object' or p_patch is null then raise exception 'invalid preferences'; end if;
  if exists (select 1 from jsonb_each(p_patch) e where jsonb_typeof(e.value) <> 'boolean' or not e.key = any(array[
    'master_enabled','quiet_mode','dms','mentions','likes','comments','follows','story_responses','missed_calls'])) then
    raise exception 'invalid preference field';
  end if;
  insert into public.whisper_notification_prefs(user_id) values (p_owner) on conflict (user_id) do nothing;
  update public.whisper_notification_prefs set
    master_enabled = coalesce((p_patch->>'master_enabled')::boolean, master_enabled),
    quiet_mode = coalesce((p_patch->>'quiet_mode')::boolean, quiet_mode),
    dms = coalesce((p_patch->>'dms')::boolean, dms),
    mentions = coalesce((p_patch->>'mentions')::boolean, mentions),
    likes = coalesce((p_patch->>'likes')::boolean, likes),
    comments = coalesce((p_patch->>'comments')::boolean, comments),
    follows = coalesce((p_patch->>'follows')::boolean, follows),
    story_responses = coalesce((p_patch->>'story_responses')::boolean, story_responses),
    missed_calls = coalesce((p_patch->>'missed_calls')::boolean, missed_calls), updated_at = now()
    where user_id = p_owner;
  select to_jsonb(p) - 'user_id' - 'updated_at' into result from public.whisper_notification_prefs p where user_id=p_owner;
  return result;
end;
$$;
revoke all on function public.whisper_update_push_preferences(uuid,jsonb) from public, anon;
grant execute on function public.whisper_update_push_preferences(uuid,jsonb) to authenticated;
commit;
