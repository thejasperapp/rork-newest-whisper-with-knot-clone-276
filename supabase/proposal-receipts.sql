-- ============================================================================
-- whisper_proposal_receipts — accept/decline ledger for v2 coach proposals.
--
-- FOUND MISSING in the schema audit: both iOS (WhisperProposalReceiptService)
-- and web (respondToCoachProposal in lib/coach.ts) write to this table, but it
-- was never created — so coaches never see the "applied" indicator.
--
-- Run once in the Supabase SQL editor — safe to re-run.
-- ============================================================================

create table if not exists public.whisper_proposal_receipts (
  proposal_id uuid not null,
  client_user_id uuid not null,
  status text not null check (status in ('accepted','declined')),
  responded_at timestamptz not null default now(),
  message_id uuid,
  primary key (proposal_id, client_user_id)
);

alter table public.whisper_proposal_receipts enable row level security;

drop policy if exists "client writes own receipts"
  on public.whisper_proposal_receipts;
create policy "client writes own receipts"
  on public.whisper_proposal_receipts for insert to authenticated
  with check (client_user_id = auth.uid());

drop policy if exists "client updates own receipts"
  on public.whisper_proposal_receipts;
create policy "client updates own receipts"
  on public.whisper_proposal_receipts for update to authenticated
  using (client_user_id = auth.uid())
  with check (client_user_id = auth.uid());

drop policy if exists "client reads own receipts"
  on public.whisper_proposal_receipts;
create policy "client reads own receipts"
  on public.whisper_proposal_receipts for select to authenticated
  using (client_user_id = auth.uid());

drop policy if exists "coach reads receipts for accepted clients"
  on public.whisper_proposal_receipts;
create policy "coach reads receipts for accepted clients"
  on public.whisper_proposal_receipts for select to authenticated
  using (
    exists (
      select 1 from public.whisper_coach_requests r
      where r.coach_user_id  = auth.uid()
        and r.client_user_id = whisper_proposal_receipts.client_user_id
        and r.status = 'accepted'
    )
  );
