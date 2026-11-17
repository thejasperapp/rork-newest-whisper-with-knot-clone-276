begin;
create table if not exists public.whisper_corrections(id uuid primary key default gen_random_uuid(),report_id uuid not null unique references public.whisper_reports(id),post_id uuid not null,author_id uuid not null references auth.users(id),reviewed_snapshot jsonb not null,explanation text not null,sources text[] not null,state text not null default 'active' check(state in ('active','withdrawn')),reviewed_by uuid not null references auth.users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table if not exists public.whisper_correction_appeals(id uuid primary key default gen_random_uuid(),correction_id uuid not null unique references public.whisper_corrections(id),author_id uuid not null references auth.users(id),body text not null,status text not null default 'pending' check(status in ('pending','upheld','withdrawn','updated')),outcome text,reviewed_by uuid references auth.users(id),created_at timestamptz not null default now(),reviewed_at timestamptz);
create table if not exists public.whisper_correction_history(id uuid primary key default gen_random_uuid(),correction_id uuid not null references public.whisper_corrections(id),actor_id uuid not null references auth.users(id),action text not null,explanation text not null,sources text[] not null,created_at timestamptz not null default now());
alter table public.whisper_corrections enable row level security;
alter table public.whisper_correction_appeals enable row level security;
alter table public.whisper_correction_history enable row level security;
create or replace function public.whisper_public_post(p_id uuid) returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.whisper_posts p join public.whisper_profiles u on u.user_id=p.user_id where p.id=p_id and not coalesce(u.is_private,false) and not coalesce(p.is_ghost,false)); $$;
create policy whisper_correction_read on public.whisper_corrections for select to public using(author_id=auth.uid() or public.whisper_is_reviewer() or public.whisper_public_post(post_id));
create policy whisper_appeal_read on public.whisper_correction_appeals for select to authenticated using(author_id=auth.uid() or public.whisper_is_reviewer());
create policy whisper_correction_history_read on public.whisper_correction_history for select to authenticated using(public.whisper_is_reviewer() or exists(select 1 from public.whisper_corrections c where c.id=correction_id and c.author_id=auth.uid()));
grant select on public.whisper_corrections to anon,authenticated;
grant select on public.whisper_correction_appeals,public.whisper_correction_history to authenticated;
grant execute on function public.whisper_is_reviewer() to anon;

create or replace function public.whisper_review_correction(p_report_id uuid,p_explanation text,p_sources text[],p_state text default 'active') returns uuid language plpgsql security definer set search_path='' as $$
declare r public.whisper_reports; c public.whisper_corrections; cid uuid; source text;
begin
 if not public.whisper_is_reviewer() then raise exception 'Reviewer permission required'; end if;
 if length(trim(p_explanation))<20 or length(p_explanation)>4000 or p_state not in ('active','withdrawn') then raise exception 'Give a clear human review reason'; end if;
 if p_state='active' and coalesce(array_length(p_sources,1),0)<1 then raise exception 'Supporting sources required'; end if;
 foreach source in array coalesce(p_sources,array[]::text[]) loop if source !~ '^https://[^ /]+[^ ]*$' or length(source)>2000 then raise exception 'Use valid HTTPS source links'; end if; end loop;
 select * into r from public.whisper_reports where id=p_report_id for update;
 if r.id is null or r.post_snapshot is null or r.target_kind not in ('post','reel') then raise exception 'A reported public post version is required'; end if;
 if r.reporter_id=auth.uid() or r.target_user_id=auth.uid() then raise exception 'An independent reviewer is required'; end if;
 if p_state='active' and not public.whisper_public_post((r.post_snapshot->>'post_id')::uuid) then raise exception 'Only public posts may receive public corrections'; end if;
 select * into c from public.whisper_corrections where report_id=r.id for update;
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
create or replace function public.whisper_appeal_correction(p_correction_id uuid,p_body text) returns uuid language plpgsql security definer set search_path='' as $$
declare aid uuid;
begin
 if auth.uid() is null or not exists(select 1 from public.whisper_corrections where id=p_correction_id and author_id=auth.uid()) then raise exception 'Only the post author may appeal'; end if;
 if length(trim(p_body))<10 or length(p_body)>4000 then raise exception 'Explain your appeal in 10–4000 characters'; end if;
 insert into public.whisper_correction_appeals(correction_id,author_id,body) values(p_correction_id,auth.uid(),trim(p_body)) on conflict(correction_id) do nothing returning id into aid;
 if aid is null then select id into aid from public.whisper_correction_appeals where correction_id=p_correction_id; end if;
 return aid;
end $$;
create or replace function public.whisper_review_correction_appeal(p_appeal_id uuid,p_outcome text,p_explanation text,p_sources text[]) returns uuid language plpgsql security definer set search_path='' as $$
declare a public.whisper_correction_appeals; c public.whisper_corrections; cid uuid;
begin
 if not public.whisper_is_reviewer() or p_outcome not in ('upheld','withdrawn','updated') then raise exception 'Reviewer permission and outcome required'; end if;
 select * into a from public.whisper_correction_appeals where id=p_appeal_id for update;
 select * into c from public.whisper_corrections where id=a.correction_id;
 if a.id is null or a.status<>'pending' or c.reviewed_by=auth.uid() or a.author_id=auth.uid() then raise exception 'Pending appeal requires an independent reviewer'; end if;
 cid:=public.whisper_review_correction(c.report_id,p_explanation,p_sources,case when p_outcome='withdrawn' then 'withdrawn' else 'active' end);
 update public.whisper_correction_appeals set status=p_outcome,outcome=trim(p_explanation),reviewed_by=auth.uid(),reviewed_at=now() where id=a.id;
 return cid;
end $$;
revoke all on function public.whisper_review_correction(uuid,text,text[],text),public.whisper_appeal_correction(uuid,text),public.whisper_review_correction_appeal(uuid,text,text,text[]) from public;
grant execute on function public.whisper_review_correction(uuid,text,text[],text),public.whisper_appeal_correction(uuid,text),public.whisper_review_correction_appeal(uuid,text,text,text[]) to authenticated;
create or replace function public.whisper_post_identity_immutable() returns trigger language plpgsql set search_path='' as $$ begin if new.id is distinct from old.id or new.user_id is distinct from old.user_id then raise exception 'Post identity is immutable'; end if; return new; end $$;
create trigger whisper_post_identity_immutable_v2 before update on public.whisper_posts for each row execute function public.whisper_post_identity_immutable();
commit;
