begin;
create or replace function public.whisper_guard_message_contact_insert() returns trigger language plpgsql security definer set search_path='' as $$
begin
 -- Apply the same rule to user-to-user rows, including SECURITY DEFINER/service deliveries.
 -- Self-addressed/system rows are not a first contact between two members.
 if new.from_user_id is not null and new.to_user_id is not null and new.from_user_id<>new.to_user_id
    and not coalesce(public.whisper_can_contact(new.from_user_id,new.to_user_id),false) then
   raise exception using errcode='42501',message='Contact permission, block, or restriction prevents delivery';
 end if;
 return new;
end $$;
revoke all on function public.whisper_guard_message_contact_insert() from public,anon,authenticated;
do $$ begin
 if not exists(select 1 from pg_trigger where tgrelid='public.whisper_messages'::regclass and tgname='whisper_message_contact_insert_v2') then
   create trigger whisper_message_contact_insert_v2 before insert on public.whisper_messages for each row execute function public.whisper_guard_message_contact_insert();
 end if;
end $$;
commit;
