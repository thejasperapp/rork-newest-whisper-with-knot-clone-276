begin;
create or replace function public.whisper_guard_report() returns trigger language plpgsql security definer set search_path='' as $$
declare p public.whisper_posts;
begin
 if auth.role()='service_role' then return new; end if;
 if tg_op='UPDATE' then
 if not public.whisper_is_reviewer() then raise exception 'Reviewer permission required'; end if;
 if (to_jsonb(new)-array['status','reviewed_by','reviewed_at','review_note']) is distinct from (to_jsonb(old)-array['status','reviewed_by','reviewed_at','review_note']) then raise exception 'Report evidence and participants are immutable'; end if;
 new.reviewed_by:=auth.uid(); new.reviewed_at:=now(); return new;
 end if;
 if auth.uid() is null or new.reporter_id is distinct from auth.uid() then raise exception 'Sign in to report'; end if;
 new.status:='open'; new.reviewed_by:=null; new.reviewed_at:=null; new.review_note:=null; new.post_snapshot:=null;
 select username into new.reporter_username from public.whisper_profiles where user_id=auth.uid();
 if new.target_kind in ('post','reel') then
 select * into p from public.whisper_posts where id::text=new.target_id and public.whisper_can_view_post_author(user_id) and (not coalesce(is_ghost,false) or user_id=auth.uid());
 if p.id is null then raise exception 'Post not available'; end if;
 new.target_user_id:=p.user_id;
 select username into new.target_username from public.whisper_profiles where user_id=p.user_id;
 new.post_snapshot:=jsonb_build_object('post_id',p.id,'author_id',p.user_id,'caption',p.caption,'media_urls',p.media_urls,'created_at',p.created_at,'captured_at',now());
 end if;
 return new;
end $$;
alter table public.whisper_liar_appeals add column if not exists author_id uuid references auth.users(id);
-- Historical username-only ownership cannot safely be inferred after renames.
-- Preserve every record for staff review; only account-bound records are member-readable.
create policy whisper_legacy_appeal_bound_owner_v3 on public.whisper_liar_appeals as restrictive for select to public using(public.whisper_is_reviewer() or author_id=auth.uid());
create or replace function public.whisper_bind_legacy_appeal() returns trigger language plpgsql security definer set search_path='' as $$ begin
 if auth.role()='service_role' or auth.uid() is null then return new; end if;
 if tg_op='INSERT' then new.author_id:=auth.uid();
 elsif new.id is distinct from old.id or new.author_id is distinct from old.author_id or new.username is distinct from old.username or new.body is distinct from old.body or new.created_at is distinct from old.created_at then raise exception 'Historical appeal evidence is immutable'; end if;
 return new; end $$;
create trigger whisper_legacy_appeal_bind_v3 before insert or update on public.whisper_liar_appeals for each row execute function public.whisper_bind_legacy_appeal();
create policy whisper_legacy_labels_no_delete_v3 on public.whisper_liar_badges as restrictive for delete to public using(false);
create policy whisper_legacy_strikes_no_update_v3 on public.whisper_liar_strikes as restrictive for update to public using(false) with check(false);
create policy whisper_legacy_strikes_no_delete_v3 on public.whisper_liar_strikes as restrictive for delete to public using(false);
create policy whisper_ai_strikes_no_update_v3 on public.whisper_safety_strikes as restrictive for update to public using(false) with check(false);
create policy whisper_ai_strikes_no_delete_v3 on public.whisper_safety_strikes as restrictive for delete to public using(false);
create policy whisper_ai_flags_no_delete_v3 on public.whisper_safety_flags as restrictive for delete to public using(false);
commit;
