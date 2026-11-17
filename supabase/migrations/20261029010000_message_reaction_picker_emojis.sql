begin;
-- Keep the accepted catalog aligned with the six quick reactions and every '+' picker choice.
create or replace function public.whisper_valid_message_reaction(p_emoji text)
returns boolean language sql immutable set search_path='' as $$
 select p_emoji is not null and p_emoji = any(array['❤️','😂','😮','😢','😡','👍','🔥','🙌','💯','🎉','😍','🤔','👀','🙏','😭','🥹','💀','👏','🫶','😤','🤝','✨']::text[])
$$;
revoke all on function public.whisper_valid_message_reaction(text) from public,anon,authenticated;
-- Inspect the deployed constraint; abort rather than replace an unrelated check.
do $$
declare c record; n integer:=0;
begin
 for c in select conname,pg_get_constraintdef(oid) as definition from pg_constraint
 where conrelid='public.whisper_message_reactions'::regclass and contype='c'
 loop
  if c.definition like '%emoji%' and c.definition like '%❤️%' and c.definition like '%👍%' then
   execute format('alter table public.whisper_message_reactions drop constraint %I',c.conname);
   n:=n+1;
  end if;
 end loop;
 if n<>1 then raise exception 'Expected one legacy reaction catalog constraint; no changes applied'; end if;
end $$;
alter table public.whisper_message_reactions add constraint whisper_message_reactions_picker_emoji_check
 check(emoji is null or public.whisper_valid_message_reaction(emoji));
-- Replace only the legacy catalog predicates in the live functions. Preserve their complete
-- authorization, locking, idempotency, membership, block and notification implementations.
do $$
declare signature text; definition text; old_predicate text; new_predicate text;
begin
 foreach signature in array array['public.whisper_set_message_reaction(uuid,text,uuid)','public.whisper_toggle_message_reaction(uuid,text,uuid)'] loop
  definition:=pg_get_functiondef(signature::regprocedure);
  old_predicate:='p_emoji not in (''❤️'',''😂'',''😮'',''😢'',''😡'',''👍'')';
  new_predicate:='not public.whisper_valid_message_reaction(p_emoji)';
  if position(old_predicate in definition)=0 then raise exception 'Unexpected live reaction validation: %; no changes applied',signature; end if;
  execute replace(definition,old_predicate,new_predicate);
 end loop;
end $$;
commit;
