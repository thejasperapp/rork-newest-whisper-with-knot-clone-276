create or replace function public.whisper_submit_report(p_kind text,p_reason text,p_details text default null,p_target_username text default null,p_target_id text default null,p_context jsonb default '{}'::jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); rid uuid; v_kind text; v_reason text;
begin
 if me is null then raise exception 'Sign in to report'; end if;
 v_kind:=case when p_kind in ('safety','profile','problem') then 'user' when p_kind='conversation' then 'dm' else p_kind end;
 if v_kind not in ('post','reel','story','dm','user','comment') or nullif(trim(p_target_id),'') is null then raise exception 'Report target required'; end if;
 v_reason:=coalesce(nullif(left(trim(p_reason),200),''),'other');
 perform pg_advisory_xact_lock(hashtextextended(me::text||v_kind||p_target_id||v_reason,0));
 select r.id into rid from public.whisper_reports r where r.reporter_id=me and r.target_kind=v_kind and r.target_id=p_target_id and r.reason=v_reason and r.created_at>now()-interval '24 hours' order by r.created_at desc limit 1;
 if rid is not null then return rid; end if;
 insert into public.whisper_reports(reporter_id,target_kind,target_id,target_username,reason,details,context) values(me,v_kind,left(p_target_id,200),nullif(left(p_target_username,100),''),v_reason,nullif(left(trim(p_details),4000),''),jsonb_build_object('surface',left(coalesce(p_context->>'surface','report'),80))) returning id into rid;
 return rid;
end $$;
