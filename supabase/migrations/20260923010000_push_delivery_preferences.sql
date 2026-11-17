-- Additive notification settings and private delivery claims. No product rows are rewritten.
begin;
alter table public.whisper_notification_prefs
  add column if not exists master_enabled boolean not null default true,
  add column if not exists quiet_mode boolean not null default false,
  add column if not exists missed_calls boolean not null default true;

create table if not exists public.whisper_push_receipts (
  event_key text primary key check (length(event_key) = 64),
  created_at timestamptz not null default now()
);
alter table public.whisper_push_receipts enable row level security;
revoke all on public.whisper_push_receipts from anon, authenticated;
grant select, insert, delete on public.whisper_push_receipts to service_role;
create index if not exists whisper_push_receipts_age on public.whisper_push_receipts(created_at);

create or replace function public.whisper_push_receipts_gc()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  delete from public.whisper_push_receipts where event_key in
    (select event_key from public.whisper_push_receipts where created_at < now() - interval '2 days' limit 200);
  return new;
end;
$$;
revoke all on function public.whisper_push_receipts_gc() from public, anon, authenticated;
do $$ begin
  if not exists (select 1 from pg_trigger where tgname='whisper_push_receipts_gc' and tgrelid='public.whisper_push_receipts'::regclass) then
    create trigger whisper_push_receipts_gc after insert on public.whisper_push_receipts
      for each statement execute function public.whisper_push_receipts_gc();
  end if;
end $$;

create table if not exists public.whisper_push_group_mutes (
  user_id uuid not null references auth.users(id) on delete cascade,
  group_id uuid not null references public.whisper_group_threads(id) on delete cascade,
  muted boolean not null default true,
  primary key (user_id, group_id)
);
alter table public.whisper_push_group_mutes enable row level security;
revoke all on public.whisper_push_group_mutes from anon;
grant select, insert, update, delete on public.whisper_push_group_mutes to authenticated, service_role;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='whisper_push_group_mutes' and policyname='push_mute_owner') then
    create policy push_mute_owner on public.whisper_push_group_mutes for all to authenticated
      using (user_id = auth.uid()) with check (user_id = auth.uid());
  end if;
end $$;
commit;
