-- ============================================================================
-- Whisper Collab Projects
-- Invite-only collaboration spaces for moderators and the people they invite.
-- Run once in the Supabase SQL editor — safe to re-run.
-- All app access is mediated by the backend with a signed user token; direct
-- client table access is intentionally denied by RLS.
-- ============================================================================

create table if not exists public.whisper_collab_projects (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 2 and 100),
  summary text not null default '' check (char_length(summary) <= 600),
  format text not null default 'content_sprint' check (format in (
    'content_sprint', 'community_challenge', 'feedback_swap', 'brand_campaign', 'scouting_room', 'custom'
  )),
  status text not null default 'active' check (status in ('draft', 'active', 'complete', 'archived')),
  created_by uuid not null references auth.users(id) on delete cascade,
  created_by_username text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.whisper_collab_members (
  project_id uuid not null references public.whisper_collab_projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  username text not null default '',
  invited_by uuid not null references auth.users(id) on delete cascade,
  role text not null default 'collaborator' check (role in ('lead', 'collaborator')),
  status text not null default 'active' check (status in ('active', 'removed')),
  created_at timestamptz not null default now(),
  primary key (project_id, user_id)
);

create table if not exists public.whisper_collab_activities (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.whisper_collab_projects(id) on delete cascade,
  title text not null check (char_length(title) between 2 and 160),
  detail text not null default '' check (char_length(detail) <= 1000),
  kind text not null default 'task' check (kind in ('task', 'post', 'review', 'meeting', 'challenge')),
  status text not null default 'open' check (status in ('open', 'doing', 'done')),
  due_on date,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_by_username text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists whisper_collab_projects_status_idx
  on public.whisper_collab_projects(status, updated_at desc);
create index if not exists whisper_collab_members_user_idx
  on public.whisper_collab_members(user_id, status, created_at desc);
create index if not exists whisper_collab_activities_project_idx
  on public.whisper_collab_activities(project_id, status, created_at asc);

-- Keep project recency meaningful when an activity changes.
create or replace function public.whisper_collab_touch_project() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.whisper_collab_projects set updated_at = now() where id = coalesce(new.project_id, old.project_id);
  return coalesce(new, old);
end;
$$;

drop trigger if exists whisper_collab_activity_touch_project on public.whisper_collab_activities;
create trigger whisper_collab_activity_touch_project
after insert or update or delete on public.whisper_collab_activities
for each row execute function public.whisper_collab_touch_project();

alter table public.whisper_collab_projects enable row level security;
alter table public.whisper_collab_members enable row level security;
alter table public.whisper_collab_activities enable row level security;

-- No direct client policies. The project backend checks the signed-in member
-- or moderator on every operation, so invites cannot be guessed or bypassed.
