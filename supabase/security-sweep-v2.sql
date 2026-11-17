-- ============================================================================
-- Security sweep v2 — closes the holes found in the August 2026 full audit
-- (round 50). Run once in the Supabase SQL editor. Safe to re-run.
--
--   1) Recruiter territories — INSERT/UPDATE/DELETE were wide open
--      (`with check (true)` / `using (true)`): any signed-in user could
--      claim, edit, or RELEASE any recruiter's territory. Reads stay public
--      (the team scout map needs them); writes now require ownership.
--
--   2) whisper_profiles UPDATE — the update surface is canonicalized to
--      exactly three cases: yourself, Whisper staff, and recruiters (who
--      legitimately flip is_coach / is_athlete / is_verified when signing
--      talent from both apps). Every pre-existing UPDATE policy on the
--      table is dropped deterministically first, so no forgotten
--      permissive policy can linger underneath.
--
-- Also re-creates the whisper_is_admin() helper if security-rls-fixes.sql
-- hasn't run yet, so this file works standalone.
-- ============================================================================

-- Helper: staff check (same definition as security-rls-fixes.sql).
create or replace function public.whisper_is_admin(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    exists (select 1 from whisper_admins a where a.user_id = uid)
    or exists (
      select 1 from profiles p
      where p.id = uid and (p.is_admin = true or p.is_owner = true)
    );
$$;

-- Helper: recruiter check — SECURITY DEFINER so whisper_profiles policies
-- can consult the table without recursing into their own RLS.
create or replace function public.whisper_is_recruiter(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from whisper_profiles wp
    where wp.user_id = uid and wp.is_recruiter = true
  );
$$;

-- ── 1) Recruiter territories: writes require ownership ─────────────────────

drop policy if exists "territories insert own" on public.whisper_recruiter_territories;
create policy "territories insert own"
  on public.whisper_recruiter_territories for insert
  to authenticated
  with check (recruiter_id = auth.uid());

drop policy if exists "territories update own" on public.whisper_recruiter_territories;
create policy "territories update own"
  on public.whisper_recruiter_territories for update
  to authenticated
  using (recruiter_id = auth.uid() or public.whisper_is_admin(auth.uid()));

drop policy if exists "territories delete own" on public.whisper_recruiter_territories;
create policy "territories delete own"
  on public.whisper_recruiter_territories for delete
  to authenticated
  using (recruiter_id = auth.uid() or public.whisper_is_admin(auth.uid()));

-- Reads stay as-is ("territories readable" using (true)) — the shared scout
-- map shows every recruiter's coverage by design.

-- ── 2) whisper_profiles UPDATE canonicalized ────────────────────────────────
-- Drop EVERY update policy currently on the table (names have drifted across
-- migrations), then install the single canonical one.

do $$
declare pol record;
begin
  for pol in
    select policyname from pg_policies
    where schemaname = 'public'
      and tablename = 'whisper_profiles'
      and cmd = 'UPDATE'
  loop
    execute format('drop policy %I on public.whisper_profiles', pol.policyname);
  end loop;
end $$;

create policy "wprof update self staff recruiter"
  on public.whisper_profiles for update
  to authenticated
  using (
    auth.uid() = user_id
    or public.whisper_is_admin(auth.uid())
    or public.whisper_is_recruiter(auth.uid())
  )
  with check (
    auth.uid() = user_id
    or public.whisper_is_admin(auth.uid())
    or public.whisper_is_recruiter(auth.uid())
  );
