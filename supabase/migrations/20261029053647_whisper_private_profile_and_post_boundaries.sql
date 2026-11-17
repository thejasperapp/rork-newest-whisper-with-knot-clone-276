begin;
create policy whisper_private_profile_boundary_v2 on public.profiles as restrictive for select to public using(auth.uid()=id or public.is_coach_of(id));
create trigger whisper_identity_flags_v2 before insert or update on public.usernames for each row execute function public.whisper_guard_identity_flags();
create or replace function public.whisper_guard_follow_request() returns trigger language plpgsql security definer set search_path='' as $$ begin
 if auth.role()='service_role' or auth.uid() is null then return new; end if;
 if tg_op='INSERT' then
   if new.requester_id<>auth.uid() or new.status<>'pending' then raise exception 'Only pending follow requests may be created'; end if;
 else
   if new.requester_id is distinct from old.requester_id or new.target_id is distinct from old.target_id then raise exception 'Follow request participants are immutable'; end if;
   if new.status is distinct from old.status and not ((auth.uid()=old.target_id and new.status in ('approved','denied')) or (auth.uid()=old.requester_id and new.status='cancelled')) then raise exception 'Only the recipient can approve a follow request'; end if;
 end if;
 return new; end $$;
create trigger whisper_follow_request_guard_v2 before insert or update on public.whisper_follow_requests for each row execute function public.whisper_guard_follow_request();
create or replace function public.whisper_can_view_post_author(p_author uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid()=p_author or (
 not exists(select 1 from public.whisper_profiles where user_id=p_author and is_private is true)
 or exists(select 1 from public.whisper_follow_requests where target_id=p_author and requester_id=auth.uid() and status='approved')
 ); $$;
create policy whisper_post_private_boundary_v2 on public.whisper_posts as restrictive for select to public using(public.whisper_can_view_post_author(user_id));
commit;
