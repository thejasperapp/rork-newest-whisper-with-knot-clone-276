-- ============================================================================
-- Security hardening — closes the overly-broad RLS policies found in the
-- August 2026 audit. Run once in the Supabase SQL editor. Safe to re-run.
--
-- 1) Applicant questionnaire — responses carried applicant PII (name, email,
--    answers) that was world-readable AND world-editable; questions were
--    world-editable.
-- 2) Live speaker requests — anyone could approve/deny any request.
-- 3) Live room speakers — anyone could add/remove any speaker row.
-- ============================================================================

-- Helper: true when the caller is on the Whisper team (admins table or
-- profile flags). SECURITY DEFINER so policies can consult both tables.
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

-- 1) Applicant questionnaire -------------------------------------------------

-- Questions stay publicly readable (the signup form is public), but only
-- Whisper team members can create/edit/delete them.
drop policy if exists applicant_questions_insert on public.whisper_applicant_questions;
drop policy if exists applicant_questions_update on public.whisper_applicant_questions;
drop policy if exists applicant_questions_delete on public.whisper_applicant_questions;
create policy applicant_questions_insert on public.whisper_applicant_questions
  for insert with check (public.whisper_is_admin(auth.uid()));
create policy applicant_questions_update on public.whisper_applicant_questions
  for update using (public.whisper_is_admin(auth.uid()));
create policy applicant_questions_delete on public.whisper_applicant_questions
  for delete using (public.whisper_is_admin(auth.uid()));

-- Responses: reads limited to the owning recruiter, the applicant, and the
-- team. Submitting stays open (leads may not have accounts yet — the table
-- becomes a write-only mailbox for them); edits recruiter/team only;
-- deletes team only.
drop policy if exists applicant_responses_select on public.whisper_applicant_responses;
drop policy if exists applicant_responses_update on public.whisper_applicant_responses;
drop policy if exists applicant_responses_delete on public.whisper_applicant_responses;
create policy applicant_responses_select on public.whisper_applicant_responses
  for select using (
    recruiter_id = auth.uid()
    or applicant_user_id = auth.uid()
    or public.whisper_is_admin(auth.uid())
  );
create policy applicant_responses_update on public.whisper_applicant_responses
  for update using (
    recruiter_id = auth.uid()
    or public.whisper_is_admin(auth.uid())
  );
create policy applicant_responses_delete on public.whisper_applicant_responses
  for delete using (public.whisper_is_admin(auth.uid()));

-- 2) Live speaker requests ----------------------------------------------------

-- Only the room host (or the team) can accept/deny. Requesters withdraw via
-- their existing DELETE policy, so they keep no UPDATE path (previously
-- anyone could flip any request to accepted).
drop policy if exists live_speaker_requests_update on public.whisper_live_speaker_requests;
drop policy if exists wlsr_update on public.whisper_live_speaker_requests;
create policy live_speaker_requests_update on public.whisper_live_speaker_requests
  for update using (
    auth.uid() in (
      select host_id from whisper_live_rooms r
      where r.id = whisper_live_speaker_requests.room_id
    )
    or public.whisper_is_admin(auth.uid())
  );

-- 3) Live room speakers --------------------------------------------------------

-- Speaker rows can be added/removed only by the person themself or the room
-- host (hosts promote/demote), plus the team. Previously (true) for both.
drop policy if exists wlrs_insert on public.whisper_live_room_speakers;
drop policy if exists wlrs_delete on public.whisper_live_room_speakers;
create policy wlrs_insert on public.whisper_live_room_speakers
  for insert with check (
    auth.uid() = user_id
    or auth.uid() in (
      select host_id from whisper_live_rooms r
      where r.id = whisper_live_room_speakers.room_id
    )
    or public.whisper_is_admin(auth.uid())
  );
create policy wlrs_delete on public.whisper_live_room_speakers
  for delete using (
    auth.uid() = user_id
    or auth.uid() in (
      select host_id from whisper_live_rooms r
      where r.id = whisper_live_room_speakers.room_id
    )
    or public.whisper_is_admin(auth.uid())
  );
