begin;
create or replace function public.whisper_is_reviewer() returns boolean language sql stable security definer set search_path='' as $$ select auth.uid() is not null and exists(select 1 from public.whisper_admins where user_id=auth.uid() and role::text in ('owner','admin','moderator')); $$;
revoke all on function public.whisper_is_reviewer() from public;
grant execute on function public.whisper_is_reviewer() to authenticated;

alter table public.whisper_reports add column if not exists context jsonb not null default '{}'::jsonb;
alter table public.whisper_reports add column if not exists post_snapshot jsonb;
create or replace function public.whisper_guard_report() returns trigger language plpgsql security definer set search_path='' as $$
declare p public.whisper_posts;
begin
 if auth.role()='service_role' then return new; end if;
 if tg_op='UPDATE' then
   if not public.whisper_is_reviewer() then raise exception 'Reviewer permission required'; end if;
   if new.reporter_id is distinct from old.reporter_id or new.target_id is distinct from old.target_id or new.post_snapshot is distinct from old.post_snapshot or new.context is distinct from old.context then raise exception 'Report context is immutable'; end if;
   new.reviewed_by:=auth.uid(); new.reviewed_at:=now(); return new;
 end if;
 if auth.uid() is null or new.reporter_id is distinct from auth.uid() then raise exception 'Sign in to report'; end if;
 new.status:='open'; new.reviewed_by:=null; new.reviewed_at:=null; new.review_note:=null;
 new.post_snapshot:=null;
 select username into new.reporter_username from public.whisper_profiles where user_id=auth.uid();
 if new.target_kind in ('post','reel') then
   select * into p from public.whisper_posts where id::text=new.target_id;
   if p.id is null then raise exception 'Post not available'; end if;
   new.target_user_id:=p.user_id;
   select username into new.target_username from public.whisper_profiles where user_id=p.user_id;
   new.post_snapshot:=jsonb_build_object('post_id',p.id,'author_id',p.user_id,'caption',p.caption,'media_urls',p.media_urls,'created_at',p.created_at,'captured_at',now());
 end if;
 return new;
end $$;
create trigger whisper_guard_report_v2 before insert or update on public.whisper_reports for each row execute function public.whisper_guard_report();
create policy whisper_report_insert_guard_v2 on public.whisper_reports as restrictive for insert to public with check(auth.uid()=reporter_id and status='open' and reviewed_by is null);
create policy whisper_report_confidential_v2 on public.whisper_reports as restrictive for select to public using(auth.uid()=reporter_id or public.whisper_is_reviewer());
create policy whisper_report_reviewer_read_v2 on public.whisper_reports for select to authenticated using(public.whisper_is_reviewer());
create policy whisper_report_reviewer_update_v2 on public.whisper_reports for update to authenticated using(public.whisper_is_reviewer()) with check(public.whisper_is_reviewer());
create policy whisper_report_reviewer_guard_v2 on public.whisper_reports as restrictive for update to public using(public.whisper_is_reviewer()) with check(public.whisper_is_reviewer());
create or replace function public.whisper_submit_report(p_kind text,p_reason text,p_details text default null,p_target_username text default null,p_target_id text default null,p_context jsonb default '{}'::jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); rid uuid; kind text; reason text;
begin
 if me is null then raise exception 'Sign in to report'; end if;
 kind:=case when p_kind in ('safety','profile','problem') then 'user' when p_kind='conversation' then 'dm' else p_kind end;
 if kind not in ('post','reel','story','dm','user','comment') or nullif(trim(p_target_id),'') is null then raise exception 'Report target required'; end if;
 reason:=coalesce(nullif(left(trim(p_reason),200),''),'other');
 perform pg_advisory_xact_lock(hashtextextended(me::text||kind||p_target_id||reason,0));
 select id into rid from public.whisper_reports where reporter_id=me and target_kind=kind and target_id=p_target_id and whisper_reports.reason=reason and created_at>now()-interval '24 hours' order by created_at desc limit 1;
 if rid is not null then return rid; end if;
 insert into public.whisper_reports(reporter_id,target_kind,target_id,target_username,reason,details,context) values(me,kind,left(p_target_id,200),nullif(left(p_target_username,100),''),reason,nullif(left(trim(p_details),4000),''),jsonb_build_object('surface',left(coalesce(p_context->>'surface','report'),80))) returning id into rid;
 return rid;
end $$;
revoke all on function public.whisper_submit_report(text,text,text,text,text,jsonb) from public;
grant execute on function public.whisper_submit_report(text,text,text,text,text,jsonb) to authenticated;

create or replace function public.whisper_guard_identity_flags() returns trigger language plpgsql security definer set search_path='' as $$
declare key text; prior jsonb; incoming jsonb:=to_jsonb(new);
begin
 if auth.role()='service_role' or auth.uid() is null then return new; end if;
 if tg_op='UPDATE' then prior:=to_jsonb(old); else prior:='{}'::jsonb; end if;
 foreach key in array array['is_owner','is_admin','is_moderator','is_verified','is_coach','is_athlete','is_recruiter','is_director','is_blogger','is_one','is_plus','is_pro_user','is_trusted_member','helpful_report_count','is_liar','liar_reason'] loop
   if incoming ? key and (incoming->key) is distinct from (prior->key) then
     if tg_op='INSERT' and (incoming->key='false'::jsonb or incoming->key='null'::jsonb or incoming->key='0'::jsonb) then continue; end if;
     raise exception 'Identity and entitlement fields are managed by Whisper';
   end if;
 end loop;
 return new;
end $$;
create trigger whisper_identity_flags_v2 before insert or update on public.profiles for each row execute function public.whisper_guard_identity_flags();
create trigger whisper_identity_flags_v2 before insert or update on public.whisper_profiles for each row execute function public.whisper_guard_identity_flags();

create policy whisper_legacy_labels_no_insert_v2 on public.whisper_liar_badges as restrictive for insert to public with check(false);
create policy whisper_legacy_labels_no_update_v2 on public.whisper_liar_badges as restrictive for update to public using(false) with check(false);
create policy whisper_legacy_labels_private_v2 on public.whisper_liar_badges as restrictive for select to public using(public.whisper_is_reviewer());
create policy whisper_legacy_strikes_no_insert_v2 on public.whisper_liar_strikes as restrictive for insert to public with check(false);
create policy whisper_legacy_strikes_private_v2 on public.whisper_liar_strikes as restrictive for select to public using(public.whisper_is_reviewer());
create policy whisper_ai_strikes_no_insert_v2 on public.whisper_safety_strikes as restrictive for insert to public with check(false);
create policy whisper_ai_strikes_private_v2 on public.whisper_safety_strikes as restrictive for select to public using(public.whisper_is_reviewer());
create policy whisper_ai_flags_no_insert_v2 on public.whisper_safety_flags as restrictive for insert to public with check(false);
create policy whisper_ai_flags_no_update_v2 on public.whisper_safety_flags as restrictive for update to public using(false) with check(false);
create policy whisper_ai_flags_private_v2 on public.whisper_safety_flags as restrictive for select to public using(public.whisper_is_reviewer());
commit;
