begin;
create or replace function public.whisper_review_correction(p_report_id uuid,p_explanation text,p_sources text[],p_state text default 'active') returns uuid language plpgsql security definer set search_path='' as $$
declare r public.whisper_reports; c public.whisper_corrections; cid uuid; source text;
begin
 if not public.whisper_is_reviewer() then raise exception 'Reviewer permission required'; end if;
 if p_explanation is null or length(trim(p_explanation))<20 or length(p_explanation)>4000 or p_state is null or p_state not in ('active','withdrawn') then raise exception 'Give a clear human review reason'; end if;
 if p_state='active' and coalesce(array_length(p_sources,1),0)<1 then raise exception 'Supporting sources required'; end if;
 foreach source in array coalesce(p_sources,array[]::text[]) loop if source is null or source !~ '^https://[^ /]+[^ ]*$' or length(source)>2000 then raise exception 'Use valid HTTPS source links'; end if; end loop;
 select * into r from public.whisper_reports where id=p_report_id;
 if r.id is null or r.post_snapshot is null or r.target_kind not in ('post','reel') then raise exception 'A reported public post version is required'; end if;
 perform pg_advisory_xact_lock(hashtextextended('correction:'||(r.post_snapshot-'captured_at')::text,0));
 select * into r from public.whisper_reports where id=p_report_id for update;
 if r.reporter_id=auth.uid() or r.target_user_id=auth.uid() then raise exception 'An independent reviewer is required'; end if;
 if p_state='active' and not public.whisper_public_post((r.post_snapshot->>'post_id')::uuid) then raise exception 'Only public posts may receive public corrections'; end if;
 select * into c from public.whisper_corrections where report_id=r.id or (post_id=(r.post_snapshot->>'post_id')::uuid and (reviewed_snapshot-'captured_at')=(r.post_snapshot-'captured_at')) order by (report_id=r.id) desc,created_at asc limit 1 for update;
 if c.id is null then
 if p_state<>'active' then raise exception 'No correction to withdraw'; end if;
 insert into public.whisper_corrections(report_id,post_id,author_id,reviewed_snapshot,explanation,sources,reviewed_by) values(r.id,(r.post_snapshot->>'post_id')::uuid,r.target_user_id,r.post_snapshot,trim(p_explanation),p_sources,auth.uid()) returning id into cid;
 else
 cid:=c.id;
 update public.whisper_corrections set explanation=trim(p_explanation),sources=coalesce(p_sources,array[]::text[]),state=p_state,reviewed_by=auth.uid(),updated_at=now() where id=cid;
 end if;
 insert into public.whisper_correction_history(correction_id,actor_id,action,explanation,sources) values(cid,auth.uid(),case when c.id is null then 'published' else p_state end,trim(p_explanation),coalesce(p_sources,array[]::text[]));
 update public.whisper_reports set status='actioned',review_note=trim(p_explanation) where id=r.id;
 return cid;
end $$;
create or replace function public.whisper_review_correction_appeal(p_appeal_id uuid,p_outcome text,p_explanation text,p_sources text[]) returns uuid language plpgsql security definer set search_path='' as $$
declare a public.whisper_correction_appeals; c public.whisper_corrections; cid uuid;
begin
 if not public.whisper_is_reviewer() or p_outcome is null or p_outcome not in ('upheld','withdrawn','updated') then raise exception 'Reviewer permission and outcome required'; end if;
 select * into a from public.whisper_correction_appeals where id=p_appeal_id for update;
 select * into c from public.whisper_corrections where id=a.correction_id;
 if a.id is null or c.id is null then raise exception 'Pending appeal required'; end if;
 perform pg_advisory_xact_lock(hashtextextended('correction:'||(c.reviewed_snapshot-'captured_at')::text,0));
 select * into c from public.whisper_corrections where id=a.correction_id for update;
 if a.status<>'pending' or c.reviewed_by=auth.uid() or a.author_id=auth.uid() or exists(select 1 from public.whisper_correction_history where correction_id=c.id and actor_id=auth.uid()) then raise exception 'Pending appeal requires an independent reviewer'; end if;
 cid:=public.whisper_review_correction(c.report_id,p_explanation,p_sources,case when p_outcome='withdrawn' then 'withdrawn' else 'active' end);
 update public.whisper_correction_appeals set status=p_outcome,outcome=trim(p_explanation),reviewed_by=auth.uid(),reviewed_at=now() where id=a.id;
 return cid;
end $$;
commit;
