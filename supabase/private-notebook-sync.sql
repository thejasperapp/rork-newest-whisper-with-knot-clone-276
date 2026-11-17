-- Private Notebook only. No changes to meetings, identities, recordings or shared recaps.
create table if not exists public.whisper_private_notebooks (
  owner_id uuid not null references auth.users(id) on delete cascade,
  id uuid not null,
  revision bigint not null check (revision > 0),
  operation_id uuid not null,
  document jsonb,
  deleted boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (owner_id, id),
  check ((deleted and document is null) or (not deleted and jsonb_typeof(document) = 'object' and octet_length(document::text) <= 2000000))
);
alter table public.whisper_private_notebooks enable row level security;
revoke all on public.whisper_private_notebooks from anon, authenticated;
grant select on public.whisper_private_notebooks to authenticated;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='whisper_private_notebooks' and policyname='private_notebook_owner_read') then
    create policy private_notebook_owner_read on public.whisper_private_notebooks for select to authenticated using (owner_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='whisper_private_notebooks' and policyname='private_notebook_owner_guard') then
    create policy private_notebook_owner_guard on public.whisper_private_notebooks as restrictive for all to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
  end if;
end $$;

-- Row-locked compare-and-swap; retrying the same operation is idempotent.
create or replace function public.save_private_notebook(p_id uuid, p_revision bigint, p_operation uuid, p_document jsonb, p_deleted boolean default false)
returns public.whisper_private_notebooks language plpgsql security definer set search_path = '' as $$
declare v_owner uuid := auth.uid(); v_row public.whisper_private_notebooks;
begin
  if v_owner is null then raise exception 'not_authenticated' using errcode='42501'; end if;
  if p_id is null or p_revision is null or p_revision < 0 or p_operation is null or p_deleted is null then raise exception 'invalid_note'; end if;
  if jsonb_typeof(p_document) is distinct from 'object' or p_document->>'ownerId' is distinct from v_owner::text
    or p_document->>'id' is distinct from p_id::text then raise exception 'notebook_account_changed' using errcode='42501'; end if;
  if not p_deleted and (p_document is null or jsonb_typeof(p_document) <> 'object'
    or p_document->>'id' is distinct from p_id::text or p_document->>'ownerId' is distinct from v_owner::text
    or p_document->>'version' is distinct from '1' or octet_length(p_document::text) > 2000000
    or jsonb_typeof(p_document->'notes') is distinct from 'string' or length(p_document->>'notes') > 60000
    or jsonb_typeof(p_document->'transcript') is distinct from 'string' or length(p_document->>'transcript') > 60000) then raise exception 'invalid_note'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_owner::text, 8461));
  select * into v_row from public.whisper_private_notebooks where owner_id=v_owner and id=p_id for update;
  if found then
    if v_row.operation_id=p_operation then return v_row; end if;
    if v_row.revision<>p_revision or v_row.deleted then raise exception 'note_conflict' using errcode='40001'; end if;
    update public.whisper_private_notebooks set revision=revision+1, operation_id=p_operation,
      document=case when p_deleted then null else p_document end, deleted=p_deleted, updated_at=now()
      where owner_id=v_owner and id=p_id returning * into v_row;
  else
    if p_revision<>0 then raise exception 'note_conflict' using errcode='40001'; end if;
    if not p_deleted and (select count(*) from public.whisper_private_notebooks where owner_id=v_owner and not deleted)>=200 then raise exception 'notebook_limit'; end if;
    insert into public.whisper_private_notebooks(owner_id,id,revision,operation_id,document,deleted)
      values(v_owner,p_id,1,p_operation,case when p_deleted then null else p_document end,p_deleted) returning * into v_row;
  end if;
  return v_row;
end $$;
revoke all on function public.save_private_notebook(uuid,bigint,uuid,jsonb,boolean) from public, anon;
grant execute on function public.save_private_notebook(uuid,bigint,uuid,jsonb,boolean) to authenticated;
