# Whisper chat → Meet scheduling and RSVP handoff

Document URL: https://www.mydailywhisper.com/whisper-chat-meet-handoff-20260925.md

This is the integration document hosted on the main Whisper website. Actual meeting links continue to use `https://meet.mydailywhisper.com/meet/<original identity>`; the documentation address does not replace the Meet app's room links.

## Status
Whisper iOS now has Meet in direct, dating and group chat plus menus, using the actual light/dark Meet favicon from the canonical Meet site. It has a scheduling form, an invitation card and confirmed Going/Not going controls. The protected RPC contract below is wired in the client but IS NOT implemented or deployed by this pass. Until activated, scheduling shows a service-update error and never invents a meeting or local attendance. No live database inspection, production schema change or Meet app deployment was performed.

## Relay this to the Meet app team
Use the existing Supabase project `uryyyegnbtlmyhqlgndy` and the existing authenticated user UUIDs. Add private, chat-scoped scheduled meetings to Meet's Upcoming list for every invited user, including those who have not responded. Display Going, Not going and Awaiting response in meeting details, and keep actual call attendance separate. Going must not join the room, request media, or set `joined_at`.

Implement the following authenticated PostgREST RPCs (same names and parameter keys). They return a single JSON object, not an array. Native code uses the existing Supabase session; no tokens are placed in links.

### `whisper_chat_meet_schedule`
Parameters:
```json
{
  "operation_id": "client-generated UUID",
  "conversation_kind": "direct | dating | group",
  "peer_id": "peer UUID for direct/dating, omitted for group",
  "group_id": "group UUID for group, omitted for direct/dating",
  "title": "Meeting title, 1–120 trimmed characters",
  "starts_at": "ISO-8601 UTC instant",
  "ends_at": "ISO-8601 UTC instant",
  "timezone": "IANA timezone identifier"
}
```

Server responsibilities:
- Resolve organizer from `auth.uid()`; never trust a caller-supplied organizer or username.
- Verify current membership in `whisper_group_threads` (include owner) or the exact direct/dating context. Check bilateral blocks, DM restrictions and account eligibility. Fail closed when verification is unavailable.
- Snapshot all current chat members, including the organizer, as invitees; do not silently add later group members. Bound roster size and scheduling rate. Do not allow arbitrary recipient arrays.
- Validate future start and 15–120 minute duration. Preserve UTC instants and timezone for display; do not reinterpret local timestamps as UTC.
- Atomically create/reconcile one scheduled `whisper_meetings` room, one canonical calendar invitation and its invitee list. Never call a join/participant-registration RPC during creation or card display.
- Reuse `(organizer UUID, operation_id)` for retries. Identical requests must return the original IDs and resume only unfinished delivery. Different request content under the same key must fail. The native form freezes fields after submission and reuses its request until dismissed.
- Deliver a calendar envelope in the ORIGINAL conversation, using the existing direct/dating thread identity or `::wg-v1::<group UUID>::<group name>::<body>` for groups. Use stable per-recipient message IDs, durable delivery receipts/outbox and existing push preferences. Do not send separate ordinary DMs for a group or dating invitation. Include the organizer's sent history normally.
- Return `deliveryComplete: true` only once every authorized recipient has a durable message, not merely a queued attempt or an attempted push. Push delivery itself is not proof of message persistence.
- Keep pending/failed delivery visible and recoverable in Meet so closing/relaunching Whisper cannot require creating a duplicate. Uncertain native requests are not cancelled by dismissing their form.

### `whisper_chat_meet_get`
Parameters: `{ "event_id": "canonical calendar event UUID" }`.
Authorize current user against the invitation and current group/block policy; return fresh meeting/cancellation/RSVP state. Do not join a room. Deleted or unauthorized records must return an authorization/not-found error with no restricted metadata.

### `whisper_chat_meet_respond`
Parameters: `{ "event_id": "canonical calendar event UUID", "response_status": "going | declined" }`.
Resolve user from auth, verify invitation/current access, reject cancelled meetings, upsert only this user's response, then return the authoritative snapshot. Do not create a participant attendance record. `declined` is labeled **Not going** in Whisper. Missing RSVP means Awaiting response, never an inferred yes/no.

### Shared response shape (all three RPCs)
```json
{
  "eventID": "canonical calendar UUID",
  "meetingID": "original meeting UUID or wsp-xxxx-xxxx code",
  "title": "Design check-in",
  "startTime": "2026-09-28T15:00:00Z",
  "endTime": "2026-09-28T15:30:00Z",
  "cancelled": false,
  "invitees": [
    { "userID": "auth UUID", "username": "display handle", "status": "going" },
    { "userID": "auth UUID", "username": "display handle", "status": null }
  ],
  "deliveryComplete": true
}
```
All invitee UUIDs must be unique. RSVP reads and responses include the current authenticated user in this authorized roster. A meeting can exist while `deliveryComplete` is false; retry must not create another.

## Authorization clarification from the original Whisper app — September 25 follow-up

This section answers the Meet agent's request for direct/dating authorization. It describes checked-in source evidence and the required server contract, NOT deployed authorization. The supplied Meet-agent screenshot reports its own live audit; this Whisper pass did not independently inspect the live database or deploy changes. Keep Chat-to-Meet inactive until the missing permission and delivery work is implemented and verified.

### Conversation identity is routing, not permission

For distinct valid authenticated user UUIDs, normalize to lowercase canonical UUID text and sort the two strings as `a`, `b`:

- Direct hash input: `a + "|" + b`.
- Dating hash input: `"dating-v1:" + a + "|dating-v1:" + b`.
- SHA-256 the UTF-8 input, take the first 32 lowercase hexadecimal characters, then format as `8-4-4-4-12`. Do NOT change version/variant bits: this is not UUIDv5.
- Derive this identity on the server from `auth.uid()`, validated `peer_id` and exact `conversation_kind`. Reject self, missing/unknown kinds, invalid peers and conflicting peer/group fields. Never accept an arbitrary thread ID, username or recipient list as authority.
- Native local cache keys (`peer UUID` or `dating:<peer UUID>`) are NOT stored message thread IDs. Native legacy fallback classifies unknown/nonmatching thread IDs as direct for display; do not copy that permissive fallback into authorization. Do not migrate or reclassify old direct messages into dating.

Source: `WhisperConversationKind.swift` and `WhisperBackendService.deterministicThreadID`. Deliver into the derived original context even when the same two people also have the other context.

### Direct: a real persisted consent prerequisite is still missing

`WhisperDMPrivacyService` stores private-inbox, approved and denied choices only in device `UserDefaults` (`whisper.dm.private.v1`, `whisper.dm.approved.v1`, `whisper.dm.denied.v1`). Its approve/deny methods do not write server records. These local preferences cannot authorize another user or be uploaded as trusted historical consent. No general server-persisted direct-DM acceptance relation was identified in the inspected source; that is a gap, not evidence of universal permission.

Required activation rule: scheduling from a direct chat requires recipient-controlled, server-persisted permission for this exact organizer/recipient and direct context, plus current eligibility and block checks. The Meet/server team must first implement the consent/request acceptance relation and authenticated accept/revoke path, or identify and verify an equivalent authoritative existing mechanism. Record who accepted, the pair/context, permission scope and current revocation state; prevent one participant from granting the other's consent. Pending, denied, revoked, missing or unreadable permission fails closed. Do not backfill consent from message history, follows, mutual message counts, a deterministic hash, local approvals, a public profile or absence of blocks. If product policy chooses broader invitation eligibility later, it needs explicit agreement and a documented server rule before activation.

The existing native Meet menu is an entry point, not an assertion that a direct conversation has passed this check. Missing server consent must return an honest authorization/unavailable error; it must not fall back to a public calendar or another chat kind.

### Dating: two current `again` decisions for the same original date

Checked-in `supabase/blind-dating.sql` defines:

- `whisper_blind_dates(id, room_code, host_id, guest_id, ...)` with unique `room_code`.
- `whisper_blind_date_decisions(room_code, user_id, decision, created_at)` with key `(room_code, user_id)`.
- Decisions are `again`, `friends` or `pass`; the existing decide/history functions define mutual as BOTH `again`. `friends` is not mutual dating consent.

Required activation rule: the server must find an existing date whose distinct host/guest are exactly the organizer and peer, then join BOTH current decisions to that SAME `room_code` and each corresponding user UUID. Both must be `again`. Bind that verified date identity to the invitation authorization record, and recheck those same decisions for unfinished delivery, reads, RSVP and Meet admission; never substitute another historical date when the bound evidence is revoked. With the existing peer-only schedule request, select the latest date for that pair deterministically (`started_at`, then `id`) and fail closed if it does not qualify; do not cherry-pick an older mutual result over a later pass/missing decision. If the product needs a particular older-date context, version the contract to carry and verify that date explicitly instead of guessing.

A room code, `revealed`, date-row existence, `::whisper-matchreq-v1::` / `::whisper-matched-v1::` message marker, ordinary DM approval or client `mutual` Boolean is insufficient. Do not call `whisper_blind_date_open`, `decide`, `finish` or any join RPC while verifying: those can create/claim date state. Decision SELECT is self-only, so use a narrowly scoped authenticated server check that reads both records without exposing private decisions. Verify effective write policies/grants and decision provenance before trusting this evidence; the legacy date-open path by itself does not prove queue pairing or attendance. This eligibility permits an invitation, never automatic Going, joining or media access.

### Groups: current registry, frozen invitees, original group delivery

Use the persisted `whisper_group_threads` row by `group_id`; the authoritative roster is the deduplicated union of `owner_id` and `member_ids`. Require the actor in that roster and derive recipient UUIDs there. Do not use `member_usernames`, the envelope's group name, a client recipient list, cached/local-only groups or the native legacy local-owner fallback. Source: `supabase/business-plus.sql` and `WhisperGroupChatService.swift`.

Freeze the authorized roster at scheduling; new members do not inherit earlier invitations. Recheck current membership and block restrictions before each unfinished delivery and every protected read/response/admission. Removed members lose chat-private access; restoring membership must not automatically resurrect a revoked invitation. A blocked intended recipient must not be silently dropped while reporting everyone invited: reject a new schedule, or mark an existing delivery as revoked/incomplete without a success claim. Preserve an organizer-visible, privacy-safe recovery state and the original operation/event IDs.

Groups use one durable `whisper_messages` row per recipient with `::wg-v1::<group UUID>::<current registry name>::<calendar body>`. The wrapper establishes display/routing only; re-read membership server-side. Organizer sent-history aggregation should use these real sent rows, not a fabricated self-delivery. Existing push checks are notification filtering, NOT a substitute for message-insert or Meet authorization. Group membership does not imply acceptance of a particular meeting.

### Blocks, protected operations and delivery

- Platform blocks: check `whisper_blocks(blocker_id, blocked_user_id)` in BOTH orientations. Checked-in `whisper_dating_blocked_between(a,b)` covers this table only. An empty client-visible SELECT is not proof that no reverse block exists; use authoritative server reads and reject invalid/null identities or query failures.
- DM restrictions: separately check `whisper_dm_blocks(blocked_sender_id, protected_user_id)`. This is a negative directional restriction, not positive consent. For this private Meet contract, reject either restricted orientation for the organizer/recipient pair. The platform-block helper does not include this table.
- For every RPC, use verified auth identity, current account eligibility, invitation membership AND current conversation policy. A forwarded event UUID or meeting code grants nothing. Do not expose a roster/title/RSVP/notes before admission. Never let caller-supplied organizer/status/user IDs mutate someone else's response.
- Enforce the same policy for Meet Upcoming, room metadata, notes and explicit Join; private calendar RLS alone is insufficient if linked meeting metadata remains public. No invitation action writes attendance or requests camera/microphone.
- Store stable per-recipient message IDs and durable delivery receipts with the operation. Keep a pending/revoked/error state on partial failures. `deliveryComplete` requires durable authorized conversation messages for the frozen intended recipient set, not push acceptance or an outbox enqueue. Do not replay already-confirmed deliveries or create a replacement meeting on retry.
- Revalidate authorization in the mutation/delivery transaction (with suitable concurrency control), not just in an earlier client check. Retries must recheck revocation while retaining original IDs. Revocation prevents future protected reads/joins/delivery; it cannot erase metadata already received by older clients or external copies.

Before activation, add negative cases for a valid hash without consent, direct/dating substitution, one-sided `again`, decisions from different rooms, `friends`/`pass`, later-date revocation, reverse platform blocks, both DM-restriction directions, group-owner omission, stale/local-only rosters, removed/re-added members, forged wrappers and arbitrary event IDs. Verify that denied requests create no room, roster or conversation message. These are server acceptance requirements, not tests run by this pass.

## Existing storage and privacy prerequisite
Prefer the existing `whisper_calendar_events` and `whisper_calendar_rsvps` concepts where compatible: canonical event ID, explicit meeting relation, organizer, invitation UUIDs, start/end, timezone and `going`/`declined` status. The checked-in legacy calendar SELECT policies are broadly readable. DO NOT store chat titles, roster UUIDs or RSVP information under those policies unchanged. First introduce and verify chat-private event visibility (including RSVP and notes policies) and protect the linked meeting metadata. Preserve unrelated public/team calendar behavior. Optional-column fallback that drops invitation/visibility fields is forbidden for these RPCs. If the separate Meet deployment uses a different store, provide a protected server bridge retaining canonical IDs rather than duplicate calendars.

Use a separate invitation membership relation if room participants require `joined_at`; invitations and actual attendance must not be conflated. A join still goes through Meet's existing explicit authenticated admission, microphone/camera and consent checks. Decide/document removed-member and block revocation behavior server-side; native checks cannot replace RLS.

## Backwards-compatible message body
Prefix: `::whisper-calendar-v1::`, immediately followed by JSON:
```json
{
  "id": "stable invitation message UUID",
  "eventID": "canonical calendar UUID",
  "title": "Design check-in",
  "eventType": "meet",
  "startTime": "2026-09-28T15:00:00Z",
  "location": null,
  "meetingLink": "https://meet.mydailywhisper.com/meet/<original identity>",
  "createdByUsername": "organizer handle",
  "taggedUsernames": ["invited handles"],
  "kind": "chat-meet"
}
```
Whisper recognizes `kind: chat-meet`, then fetches authorized current state using `eventID` before displaying details or RSVP. It does not trust embedded titles/rosters for access. Older readers retain their calendar-card fallback. Meet/web should implement the same card reader. Server cancellations/updates should preserve `kind: chat-meet`; fresh canonical state determines cancellation, not stale message metadata.

## Opening Meet
Preserve `whisperworkspace://meet/<original identity>` and HTTPS fallback `https://meet.mydailywhisper.com/meet/<original identity>`. Open the scheduled meeting detail/lobby, preserve the invitation across sign-in, and require explicit Join. No replacement room, embedded social call, session transfer or access token in URL.

The user-provided `www.meet.mydailywhisper.com` failed HTTPS verification because its certificate did not match that hostname (curl error 60), not because of a demonstrated DNS failure. The canonical `meet.mydailywhisper.com` served the current favicon declarations:
- `https://meet.mydailywhisper.com/meet-icon-light-20260925.png`
- `https://meet.mydailywhisper.com/meet-icon-dark-20260925.png`
These exact images are bundled in the native plus menu and meeting UI.

## Activation acceptance
Before enabling production: consenting direct/dating/group accounts; organizer and all invitees' Upcoming lists; no-response/going/declined; changed RSVP in Meet and native refresh; retry after lost response; partial delivery and relaunch; duplicate operation with changed content; removed members; bilateral blocks; unauthorized event IDs and RSVP spoofing; cancellation; timezone/DST; signed-out/installed/absent Meet app opening. Validate all policies against deployed definitions with approved management access. Native tests remain paused. A simulator build does not validate these server requirements.
