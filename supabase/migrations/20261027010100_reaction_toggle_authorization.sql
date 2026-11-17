begin;
-- An author's representative fan-out copy must not inherit an unrelated recipient's block state.
create or replace function public.whisper_reaction_target(p_message_id uuid)
returns text language plpgsql stable security definer set search_path='' as $$
declare m public.whisper_messages; actor uuid:=auth.uid(); gid uuid;
begin
 if actor is null then return null; end if;
 select * into m from public.whisper_messages where id=p_message_id;
 if not found or (actor=m.from_user_id or actor=m.to_user_id) is not true
 or not public.whisper_chat_meet_message_access(m.id) then return null; end if;
 if (m.logical_group_message_id is null or actor<>m.from_user_id) and (
 exists(select 1 from public.whisper_blocks where (blocker_id=actor and blocked_user_id in(m.from_user_id,m.to_user_id)) or (blocked_user_id=actor and blocker_id in(m.from_user_id,m.to_user_id)))
 or exists(select 1 from public.whisper_dm_blocks where (protected_user_id=actor and blocked_sender_id in(m.from_user_id,m.to_user_id)) or (blocked_sender_id=actor and protected_user_id in(m.from_user_id,m.to_user_id)))) then return null; end if;
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

-- Toggle uses the user's current server selection, not a stale or not-yet-loaded client badge.
create or replace function public.whisper_toggle_message_reaction(p_message_id uuid,p_emoji text,p_operation_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare target text; previous public.whisper_message_reactions;
begin
 if p_operation_id is null or p_emoji is null or p_emoji not in ('❤️','😂','😮','😢','😡','👍') then raise exception 'Invalid reaction'; end if;
 target:=public.whisper_reaction_target(p_message_id);
 if target is null then raise exception 'Message unavailable, or older group message has no shared identity' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(target||auth.uid()::text,0));
 select * into previous from public.whisper_message_reactions where target_id=target and actor_id=auth.uid();
 if found and previous.operation_id=p_operation_id then return; end if;
 perform public.whisper_set_message_reaction(p_message_id,case when previous.emoji=p_emoji then null else p_emoji end,p_operation_id);
end $$;
revoke all on function public.whisper_toggle_message_reaction(uuid,text,uuid) from public,anon;
grant execute on function public.whisper_toggle_message_reaction(uuid,text,uuid) to authenticated;
commit;
