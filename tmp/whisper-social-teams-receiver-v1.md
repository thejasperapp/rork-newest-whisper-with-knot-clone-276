# Whisper Social → Whisper Teams integration handoff — receiver v1

## Status and ownership

Implemented in Social source; NOT deployed or activated. The public receiver origin will be confirmed after the approved Cloudflare deployment. Do not substitute the Teams backend, a website preview, or a historical clone URL. Use `SOCIAL_BACKEND_ORIGIN` below as a deployment-time placeholder, not an existing endpoint.

Whisper Social is the parent app. Whisper Teams is the original canonical shared-team service. Teams owns invitations, recorded inviter authority, exact recipient identity, lifecycle state, verification at review, return links and explicit acceptance. Social owns inbox delivery, card presentation, blocks/privacy, push preferences and notification effects. There is no new roster, automatic acceptance, Teams action call or Meet change.

## Receiver

`POST ${SOCIAL_BACKEND_ORIGIN}/social/teams/v1/events`

- Server-to-server only; HTTPS; no query parameters; `Content-Type: application/json`.
- One full canonical invitation state per event. UTF-8 request body is at most 8192 bytes.
- All 12 fields below required; additional fields rejected. No URLs, bearer tokens, emails, roles, document data, notification copy, usernames or caller-chosen Social message IDs.
- UUIDs must be lowercase. Identity tuple `(invitationId, teamId, inviterId, recipientId)` is immutable. Inviter is the recorded inviter, NEVER inferred from team owner. Supabase user IDs come from the existing Whisper identity system.
- `invitationVersion` is a positive base-10 STRING, maximum signed Int64, not a JavaScript number. Versions strictly order one invitation. They need not be contiguous.
- Timestamps are positive integer Unix milliseconds. `occurredAt` is the canonical event time, not retry time; future skew over 60 seconds is rejected. Pending snapshots must expire after `occurredAt`.
- Status: `pending | accepted | declined | revoked | expired`. Terminal states cannot return to pending or a different terminal state. A legitimate reinvite requires a new canonical invitation ID; retrying does not.

```json
{
  "schemaVersion": 1,
  "source": "whisper-teams",
  "eventId": "11111111-1111-4111-8111-111111111111",
  "invitationId": "22222222-2222-4222-8222-222222222222",
  "invitationVersion": "1",
  "teamId": "33333333-3333-4333-8333-333333333333",
  "teamName": "Example team",
  "inviterId": "44444444-4444-4444-8444-444444444444",
  "recipientId": "55555555-5555-4555-8555-555555555555",
  "status": "pending",
  "occurredAt": 1790812800000,
  "expiresAt": 1791417600000
}
```

These UUIDs/timestamps are illustrative only, not accounts or invitations to test against production. `teamName` is nonempty, at most 120 UTF-16 code units, without control/format/line-separator characters or angle brackets. It stays in the private projection, never message bodies or pushes.

## Server authentication

Use an integration-specific random 256-bit HMAC key, shared only between Teams' canonical event publisher and Social's receiver. Do not send end-user JWTs, Rork identity headers, Supabase anon keys or service-role credentials as producer authorization. Social's Supabase service-role key stays inside Social; Teams never receives it.

Social private configuration:
- `WHISPER_TEAMS_SIGNING_KEYS`: JSON object mapping key ID to a 64-character lowercase hexadecimal secret (32 decoded bytes). Multiple key IDs permit rotation.
- `WHISPER_TEAMS_RECEIVER_ENABLED`: must be exactly `true` to enable ingestion; otherwise `503 receiver_not_ready`.
- Existing `SUPABASE_SERVICE_ROLE_KEY`: used only against the pinned `https://uryyyegnbtlmyhqlgndy.supabase.co` RPC. No replacement project or Auth model.

Headers:
```text
X-Whisper-Teams-Key-Id: <configured key ID>
X-Whisper-Teams-Timestamp: <current Unix seconds, 10 decimal digits>
X-Whisper-Teams-Signature: v1=<lowercase HMAC-SHA256 hex>
```

Signature input is UTF-8, with LF separators and NO trailing LF:
```text
whisper-social-teams-v1
POST
/social/teams/v1/events
<key ID>
<timestamp header>
<lowercase SHA256 hex of the exact UTF-8 request-body bytes>
```

Decode the hexadecimal secret into bytes before HMAC. The request timestamp must be within 300 seconds of Social's clock. On a retry, retain the same event data/event ID/version, update only transport timestamp/signature if necessary. Sign the bytes actually sent; do not sign one JSON serialization and transmit another. Refuse redirects. Keys must be exchanged out of band through server secret configuration, not chat/source/client bundles. Remove retired IDs after the producer switches; in a compromise, disable ingestion/remove the key immediately.

## Acknowledgment, retries and ordering

`200` after the database transaction has committed:
```json
{"eventId":"11111111-1111-4111-8111-111111111111","acknowledged":true,"result":"applied"}
```

Results:
- `applied`: the new state is persisted. It does NOT mean a push was delivered, opened, accepted, or even that a new message was appropriate (terminal-first snapshots are also applied).
- `duplicate`: exact previously recorded event (JSON value fingerprint); no repeated effects.
- `stale`: lower version than an already observed snapshot; event recorded, current state untouched.
- `suppressed`: state recorded but Social did not authorize delivery/access. Do not expose this as a block diagnosis or to the inviter; no reason, notification status or Social message/read IDs are returned.

`409 event_conflict`: event ID reused with changed data, another event ID at an existing invitation version, identity retargeting, or terminal-state resurrection. Stop; reconcile the publisher's durable records. Never mint a new event ID to bypass the conflict.

`401 invalid_server_signature`: fix key/signing/clock, do not retry with a user JWT.
`422 invalid_event`: fix the contract before resubmission. Invalid JSON also produces 422 after authentication.
`413 invalid_or_oversized_body`, `415 json_required`, `400 invalid_request`, `405 method_not_allowed`: terminal request errors.
`503 receiver_not_ready | receiver_unavailable`: not acknowledged. Honor `Retry-After: 60`, exponential backoff and jitter. Network timeout/lost successful response is ambiguous: replay the identical durable event, never a new command.

Teams MUST commit invitation mutation and immutable lifecycle/outbox event atomically, authorize the recorded inviter/recipient itself, deliver from that server outbox with at-least-once retries, and retain entries until the exact event ID is acknowledged. A Social 200 is consumer acknowledgment only. Teams' existing `/teams-v1/action` response and command `requestId` are unrelated to notification delivery. This HTTP publisher contract is the new extension Teams is being asked to implement; it is not an existing Teams API.

## Three separate duplicate boundaries

1. **Events:** durable `eventId` primary key and canonical JSON fingerprint; unique `(invitationId, invitationVersion)`. Transaction-scoped locks serialize conflicts and concurrent replays.
2. **Inbox:** private invitation projection owns one random Social message UUID, inserted atomically with the first eligible, unexpired pending state into existing `whisper_messages`. Direct-thread identity uses the existing sorted-user SHA256/first-32-hex UUID. Lifecycle events update the projection, not extra DMs or unread rows. Terminal-first, initially blocked/denied, missing/ineligible users and deleted messages never become a delayed/recreated card for that same invitation. A new canonical invitation is required after a genuine new invite action.
3. **Push:** ordinary message INSERT webhook and `WHISPER_DM` fanout, not a second sender. Teams uses a permanent per-message/recipient/device-token claim and stable collapse ID. A claimed ambiguous APNs attempt is NOT retried automatically, preventing a duplicate alert but potentially losing a push. This is at-most-once application send-attempt semantics, NOT guaranteed exactly-once notification delivery. Multiple devices each get their own claim; APNs/system behavior remains external. Inbox persistence does not depend on APNs success. No lifecycle/reminder pushes in v1.

Deletion tombstones remain to prevent resurrection. Do not prune event/version/message tombstones or Teams push claims independently; retention/erasure needs a coordinated operational policy. Private team titles are stored only in the latest Social projection; durable event receipts retain a fingerprint, not a second title/body archive.

## Privacy, blocking and notifications

Delivery and card access require named, non-ghost, existing non-anonymous/non-banned/non-deleted Whisper users, no platform block in either direction, no DM restriction in either direction and no synced recipient denial. These checks do not add a follow, approve a DM request, or create Team membership. Existing Social inbox/request sorting is retained.

Notification permission is checked separately at fanout: currently pending, unexpired, unread, still-authorized message; master on; quiet off; DM notifications on. Private unapproved message requests are silent. Follow/DM-approval evidence is only Social message admission, never Teams consent. Database lookup failures stop notification delivery.

Native formerly device-wide DM privacy is now account-scoped for new writes. Legacy restrictions remain conservative; unowned legacy approvals are not granted to another account. A Teams-only private per-installation snapshot is synced with the current authenticated account, bounded sets, increasing revisions, and account-generation guards. Any installation's denial/private-unapproved restriction suppresses the alert; another installation cannot silently overwrite it. Missing snapshot evidence suppresses Teams pushes, not ordinary inbox delivery. Web-only recipients without a native privacy snapshot receive inbox cards but no native push from this integration. Privacy sync failure is exposed on native Teams cards, with retry, and does not break the existing master/category preference sync. Offline changes cannot affect a server until synced; they remain local and are retried on the existing refresh path. Old clients do not sync this new snapshot.

Push text is deliberately generic:
- Title: `Whisper`
- Body: `You have a team invitation. Open Whisper to review it.`
- Data: ordinary DM sender/recipient/thread/message IDs and `social_teams: v1` only; no team name, invitation ID, role, avatar, private excerpt or access token.
- Tap returns to the authorized existing Social DM. It does not open/accept Teams directly. Native notification extension skips avatar enrichment for this type. Foreground text-marker-only local notifications are disabled; only the authorized APNs path may alert.

## Card resolver and return flow

Social-owned RPC: `POST /rest/v1/rpc/whisper_social_teams_card` with current native Supabase session, body `{"p_message_id":"<Social message UUID>"}`. Only the exact inviter/recipient may read, after fresh Social eligibility/block checks. Response binds message/invitation/team/participants, version string, team name, status, millisecond expiry/event time and recipient-only `canOpen`. Unknown/forged/deleted/rebound/blocked rows fail generically. User-writable body/embed JSON is never provenance.

Clients display the last signed **Teams-reported state**, not an independently queried current Teams verification result. They recheck on foreground, every 30 seconds while active and before native review, clear on failure/account change, and never cache a membership grant. Teams must still implement verification at the actual review destination; event publication delay can make the projection stale. Social does not claim instant revocation of already displayed information or previously delivered OS alerts.

Native deliberate review uses the documented identity-only `whisperteams://invitations/<lowercase team UUID>`. Teams must resolve the current viewer's canonical invitation, handle signed-out/wrong-account recovery and require explicit acceptance. No token transfer, accept mutation, Teams scheme registration in Social or roster copy. If Teams is absent, Social reports that the approved browser link is unavailable. Web provides All teams review guidance, no fabricated link. Once Teams supplies/tests an approved HTTPS return-link contract, integrate it separately; `/teams/<UUID>` is not substituted.

## Runnable isolated examples and tests

From `web-whisperweb`:
```sh
bun run test -- worker-tests/teams-receiver.test.ts worker-tests/teams-delivery.test.ts src/lib/teamsInvitation.test.tsx
```

From project root:
```sh
deno check functions/teams-invitations.ts supabase/functions/whisper-push-fanout/index.ts
deno test --allow-env --allow-net=esm.sh,deno.land supabase/functions/whisper-push-fanout/delivery_test.ts
```

The receiver suite independently signs with Node `createHmac`/`createHash`; DB tests execute the actual migration in isolated PGlite with synthetic users; Deno tests exercise the actual push handler with intercepted database/APNs boundaries. They do not contact real accounts or send real pushes.

Required producer test examples:
- Deliver pending v1 twice (including a lost first response): one inbox row, replay acknowledged, at most one application send attempt per device token.
- Same event ID with a changed recipient/title: 409, no mutation.
- Different event ID at the same invitation version: 409.
- Receive revoked v3 before pending v1: no inbox card, v1 acknowledged stale; pending v4 under the same invitation ID rejected.
- Pending v1 then accepted v2: same card, reported accepted, no second unread message/alert, no Social roster writes.
- Bilateral platform/DM blocks, denial, ghost/ineligible users: no delivery; no private reasons returned.
- Master off, DM off, quiet on, unknown privacy snapshot or private unapproved request: inbox behavior retained as authorized, no push.
- Wrong-account/forged resolver, modified wire text, deleted card: no private title or review action.
- Invalid/stale signature, malformed body or disabled receiver: no DB write.

## Deployment prerequisites and acceptance boundary

No migration, Cloudflare receiver or modified push sender was deployed in this pass. Native simulator/web builds are separate from backend release; native automated tests remain paused. Current managed backend status does not expose the existing project connection; reconnect ONLY `uryyyegnbtlmyhqlgndy` before any live schema review/application, never provision another backend.

After explicit release approval: review the existing message schema/RLS/triggers and deployed push sender; apply `supabase/migrations/20261001010000_social_teams_invitations.sql`; deploy the compatible push sender and receiver default-off; configure server-only signing keys on both authorities; agree producer identity/version/terminal semantics; verify approved return links; then activate deliberately. Confirm the actual backend origin before giving Teams a live URL. No destructive SQL, historical invitation replay, real-user probe, hosting/domain change or store submission is authorized by this document.

Outstanding live acceptance: concurrent production transactions, two consenting accounts, installed/absent/signed-out/wrong-account Teams, background/terminated APNs and permission changes, small-phone/iPad/VoiceOver, signed-device/Release builds. Isolated tests and simulator compilation do not certify these.
