# Whisper Meet → Whisper Notes integration

## Current Notes app identity

- **iOS bundle ID: `app.rork.whisper-notes`** (confirmed in the workspace and Xcode target configuration).
- Current app-group entitlement: `group.app.rork.whisper-notes`.
- Apple association app ID: `<VERIFIED_APPLE_TEAM_ID>.app.rork.whisper-notes` for both `applinks.details[].appIDs` and `webcredentials.apps`.
- Website: `https://notes.mydailywhisper.com`; preferred native document scheme: `whispernotes`.
- `app.rork.whisper-workspace` is the old installation identity, **not** the Notes bundle to use in new signing, provisioning, or Apple association configuration.
- Changing bundle/app-group identity creates a separate app sandbox. Existing account-synced documents can be retrieved after sign-in, but old device-only notes, recovery files, and saved credentials do not automatically migrate. Keep the old installation and export or confirm sync before removing it. No local-data migration is claimed.

## September 22 canonical publisher package

The requested credential-free handoff ZIP contains the exact rich schema sources, SQL seed builder and RPC definitions, contract tests, and two self-contained converter bundles. It contains no app configuration, credentials, logs, real accounts, or user documents. SQL is reference material for the existing deployed service, **not a request to redeploy or replace it**.

- `converter/meet-seed.mjs`: import `seedToUpdate(seed)` in Node 20+/Bun, no package installation or DOM needed.
- `converter/meet-seed.js`: trusted bundled browser/WKWebView converter exposing `WhisperMeetSeed.seedToUpdate(seed)`. Supply only the authorized server-returned seed; keep all bearer tokens and RPC networking outside the converter. No remote scripts or network access are required by conversion.
- `web-whisperweb/src/lib/meetSeed.ts` wraps the supplied `sharedNotesDocument.ts`, `sharedNotesExtensions.ts`, `notesEditorExtensions.ts`, and `documentStyle.ts`. The SQL builder is `whisper_notes_packet_seed` in `supabase/notes-meeting-documents.sql`.
- The archive's purpose-built `web-whisperweb/package.json` pins the converter/test dependencies; from that folder run `bun install` and `bun test:contracts`. Contract tests use synthetic accounts and isolated PGlite databases. No production credentials are required.
- `MANIFEST.json` lists SHA-256 hashes of included files; `contract-examples.json` contains synthetic read/initialize/publish response shapes, not live account responses.

### Current validation (September 22)

- 138 web/database checks across 26 files passed, including the production `default`-fragment converter round trip and all active Jasper reading roles plus denied pending/revoked/blocked accounts.
- 12 browser scenarios passed, including a view-only collaborator's explicit Jasper request, service-error retry, unchanged document sequence, and disappearance of the answer after revocation. AI responses in these browser tests are synthetic.
- `WhisperTests/WhisperNotesTests`: 22 passed. The service-error classification regression first failed on the old behavior, then passed after correction. Native cases cover six workflows, request/result bridging, bounded source transport, denied-before-generation and revoked-after-generation behavior.
- The native editor bundle was refreshed and the iOS simulator build passed. A real Toolkit `openai/gpt-4.1-mini` synthetic connection probe returned HTTP 200, without any document data. This does not reproduce the reported device/account request; its final end-to-end acceptance remains open.
- The distributed browser IIFE and Node ESM converter both pass independent no-application smoke checks. The ZIP checksums and explicit export allowlist are checked before packaging. Source contract tests were run in the existing workspace; a clean installation of the archive's source-test dependencies is not claimed.

### Critical publisher retry rules

1. Use the shared service's returned `seed` only while canonical `seq === 0`. `checkedSharedJSON` verifies schema structure; it is not an arbitrary HTML/URL sanitizer. Do not substitute untrusted peer input or manually flatten a capture.
2. Persist the converter's exact base64 bytes plus one stable initialization operation UUID before sending. New Yjs documents have new CRDT identities, so do not regenerate bytes on uncertain retries.
3. Send **initialize**, never ordinary update, for this first seed. If another initializer won, replay the canonical updates; do not apply the losing seed to the canonical document.
4. A read returns at most 128 updates. Read from `after:0`, apply each contiguous sequence in order, and advance `after` only to the last applied sequence until reaching the reported head. Verify the updates decode and reconstruct a supported nonempty document, not only that `seq` is positive. At a positive sequence the server's seed is null.
5. Publish the reviewed audience only after initialized readback. `{shared:0}` can mean private, no eligible new recipients, or already published. It does not prove inbox delivery. Sharing settings do not reinstate revoked/declined memberships; changing to private does not revoke existing grants.
6. Preserve source notebook versus canonical IDs, private fields, original media, and edited canonical content. Everyone receives the same restricted `/shared/<canonical UUID>` link.

### Jasper access clarification

All active reading roles (owner, editor, commenter, viewer) may use Jasper on the open document or selected passage. Edit permission is not required. Pending, revoked, blocked, deleted, and uninvited access remains denied. Answers remain private; asking never changes the document or shares it further. Native verification retains the pinned account, refreshes that same account's session before each check, and checks access before and after generation. Service/credit/network failures are no longer described as a wrong-account problem. The actual reported device failure had no available runtime trace; a synthetic live AI connectivity check succeeded, but that does not verify a particular user's document request.

## September 22 direct editing and participant sharing — current integration

This section supersedes the older private-snapshot-only opening flow below. The capture envelope remains supported and unchanged, but verified meeting hosts and granted editors now open the captured notes directly in one canonical rich document. Everyone granted access reads the **same document ID and formatted content**, not separate flattened copies. Original captures, personal writing/checkoffs, and private recording/screenshot permissions are retained separately.

Deployed additive updates: `notes-meeting-documents-v1` (`supabase/notes-meeting-documents.sql`) and `notes-messaging-groups-v1` (`supabase/notes-messaging-groups.sql`). No existing notebook or meeting policies were loosened. These deployment results do not establish real-account delivery or device behavior.

### What the Meet agent needs to implement

1. **Before starting, show “Share notes with…”**: Only me, Everyone who joins, or Selected participants. Display Viewer/Commenter/Editor, defaulting to Viewer unless the host deliberately grants edit access. Show that the notes and transcript will be shared; do not imply this shares private audio/video or screenshots. Store the choice using the existing host's authenticated account after the meeting row exists. Do not derive participants from names or email strings.
2. Save the host-owned structured capture through `import_whisper_meet_document` exactly as specified below, retaining the original and stable export intent. Confirm `whisper_meetings.host_id === auth.uid()`, actual participant UUIDs, and correct `started_at`, `ended_at`, and `joined_at`. Notes computes the attachment's duration only from valid supplied meeting times, never guesses it from a summary.
3. Call `whisper_notes_open_meeting(p_notebook: <host's private capture UUID>)`. The server checks its saved source and actual meeting host, converts structured headings/lists/tasks/transcript, and atomically returns `{id:<canonical UUID>}`. Repeated calls return the existing document; they never overwrite participant edits. A participant's own private export does not make that participant the host. A null ID plus `source_unavailable`, `host_unverified`, or `access_required` is **not** a successful editable publish.
4. **Initialize before announcing sharing.** Read the canonical document with `whisper_notes_action(..., "read", {after:0})`. If `seq===0`, use the Notes rich schema and `seedSharedDocument(checkedSharedJSON(seed))` from `web-whisperweb/src/lib/sharedNotesDocument.ts`, then `Y.encodeStateAsUpdate` / `encodeSharedBytes`, and send `whisper_notes_action(...,"initialize",{operation:<stable UUID>,update:<base64 Yjs update>})`. A native Meet publisher should reuse this converter in a trusted publisher/bundled path, not manufacture a different attributed-text document. Read back a positive sequence. Opening it in Notes also performs initialization, but do not require that manual open for a completed automatic Meet export.
5. Call `whisper_notes_meeting_share(p_meeting:<meeting UUID>,p_action:"publish",p_payload:{})`. It grants the stored audience access only after initialization. Successful publication freezes the recipient snapshot; reopening/retries cannot add later link joiners or reinstate removed/declined access, including email-bound memberships. Existing roles are preserved, not silently upgraded. Joining after a supplied `ended_at` does not qualify. Changing to private does not revoke previously issued access: use Notes' access controls.
6. Read back the canonical document and publication response, then give **every authorized participant the same** `https://notes.mydailywhisper.com/shared/<canonical UUID>` (native `whispernotes://shared/<UUID>`). The host sees it in Your documents; others see it in Shared with me. Do not send the old owner-bound `/d` URL to collaborators, create one rich document per participant, or flatten the note into a DM. Keep source-notebook and canonical-document IDs distinct in your mapping.
7. New exports/retries must never replace an existing canonical body. A regenerated recap needs explicit user review before creating a separately named new document. Private screenshots/recordings remain owner-only; document access alone cannot authorize downloading them.

### Exact pre-meeting sharing call

`POST /rest/v1/rpc/whisper_notes_meeting_share`, with the same Supabase user bearer and public API key:

```json
{
  "p_meeting": "<meeting UUID>",
  "p_action": "configure",
  "p_payload": {
    "operation": "<stable UUID for this reviewed setting change>",
    "audience": "participants",
    "role": "viewer",
    "recipients": []
  }
}
```

- Audience is `private | participants | selected`; role is `viewer | commenter | editor`. For selected, supply at most 100 account UUIDs. Only selected accounts in the meeting's actual participant roster qualify for automatic publication. Guests without Whisper accounts and invitees who never joined require the existing explicit email/account invitation flow; never fabricate memberships.
- Retain the same operation and frozen choice across uncertain retries. A new reviewed setting change gets a new operation. `p_action:"settings"` reads the host's current choice. No saved choice means private; previously private captures are **not** retroactively shared merely by opening them.
- Host can also deliberately use Share → Share with meeting participants inside Notes. This applies the same policy. Group selection in Notes is opt-in discovery and individual invitation review, **not** automatic grants to present/future group members.
- Do not use service-role credentials in either app or client-supplied ownership as authority. Notes checks host/access again on the server.

### People, messaging, selection, and Jasper

- `whisper_notes_context(p_doc)` returns minimal account-backed people chips plus meeting title/date/duration. These sit outside editable content. Tapping a person shows name, username, photo when supported, role, and an explicit Whisper DM composer. No names are guessed into accounts from the transcript.
- Selected-passage DMs use `whisper_notes_message(p_doc,p_id,p_recipient,p_body,p_quote)`: message ≤1,500 characters, quote ≤2,000, final message ≤4,000. It checks active document access for both sender and recipient, both-direction user blocks and protected DM restrictions, and reconciles a stable receipt UUID. The body contains only the reviewed message, snippet, title, and restricted link; it never attaches personal writing. Success means saved to the Whisper message table, not read or push-delivered.
- `whisper_notes_groups(p_group?:UUID)` reads only groups the authenticated user currently belongs to. UI calls it only after “Include my Whisper groups” is enabled. No chat history is fetched. Choosing a group shows account-validated members to invite individually; future joins/leaves do not change separately granted document access.
- iOS adds Add comment, Message about selection, and Suggest change to the real system edit menu. Web uses the selected-passage arrow. Anchors are captured before opening a focused comment composer; existing discussions remain tappable. Physical-device system menu placement still needs acceptance testing.
- Jasper no longer requires a separate approval checkbox in Notes. Pressing Send supplies the open note/selection to cloud AI with the existing Cloud Credits disclosure and bounds. Opening the pill alone sends no content. No unrelated account history, silent document changes, or automatic messages are enabled. Oversize notes require a narrower passage; sources and Stop remain available.
- Formatting/insert controls are hidden while reading. On touch devices they appear directly above the keyboard; desktop users see them while the document/format controls are focused. Private-writing saves additionally guard against stale incoming props overwriting a same-frame local edit.

### Validation of the current changes

- 130 web/database tests across 24 files pass, including nine new SQL scenarios for canonical ownership, structural formatting, private-source retention, participant sharing, stable message receipts, both-direction blocks, protected DMs, group membership, email revocation, and publisher retries.
- Ten browser scenarios pass. The new captured-meeting scenario exercises direct opening/editing, formatted guest access, metadata chips, selected-passage comments, explicit snippet DMs, and optional group discovery. The private-formatting regression also passed three consecutive runs after the stale-prop guard fix.
- `WhisperTests/WhisperNotesTests`: 17 passed after refreshing the native editor bundle. Final iOS simulator `runChecks` passed. Both web TypeScript configurations, changed-source lint, and direct `bun run build` passed.
- Managed web `runChecks` encountered a platform build-job completion-record error, rather than a compile error; its unchanged retry was rejected. Independent verification confirmed the live preview root loads `/assets/index-BqLm2blR.js`, matching the final local production build, and the asset returns HTTP 200 with JavaScript content type. Do not confuse that status-record issue with a source compilation failure or claim the managed check itself passed.
- Reviewed sampled frames of the latest 57.7-second recording and phone screenshots for the person sheet and editable meeting document. No physical-device system-selection-menu or production-recipient-delivery claim is made.

### Remaining live acceptance

Meet's separate pre-meeting UI/publisher must still adopt this flow. Verify actual host publication and guest opening/editing across the two apps, real DM inbox receipt, native text-selection arrows, floating/hardware keyboards, VoiceOver, and participant-photo loading on consenting devices. Automated local database/browser scenarios are not production account tests.

## September 22 media contract — still authoritative for capture envelopes

**Envelope remains version 1.** Readers accept packet v1 and v2. New exports must include at least one nonblank, actual transcript passage and `transcriptStatus: "partial" | "complete"`. Do not synthesize speech from a summary. Legacy transcript-free v1 snapshots remain readable and personal writing/checkoff updates remain valid when the imported packet is unchanged.

Packet v2 adds `screenshots` (required array, maximum 20), `recordings` (required array, maximum 10), and optional per-speech `timing`. Empty media arrays are valid. All existing packet limits below continue to apply. Stable UUIDs identify assets; **never put signed playback URLs, storage paths, base64, or bearer tokens into these objects, a document, an export, logs, or recovery state**. Unknown media-reference properties are rejected by the web schema and import guard. Native models encode only the defined fields.

### Screenshot reference v1 — exact JSON shape

```json
{
  "version": 1,
  "assetId": "40000000-0000-4000-8000-000000000001",
  "caption": "Reviewed launch slide",
  "alt": "The launch milestones on a slide",
  "width": 1200,
  "height": 800,
  "mimeType": "image/png",
  "byteCount": 180000,
  "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "transcriptId": "t1"
}
```

- `transcriptId` is optional; every other property is required. The example digest is synthetic: use the actual lowercase SHA-256 of the uploaded bytes.
- PNG, JPEG, or WebP only; no SVG/GIF/remote URL. 1…5,242,880 bytes; width and height 1…8192 pixels each. Caption ≤1000 UTF-16 units; alt text 1…500. Strip unnecessary EXIF/location data before hashing/uploading.
- `assetId` is `whisper_note_assets.id`. Generate once and retain it through uncertain retries. Bytes and metadata are immutable; edited pixels require a new ID. A supplied transcript ID must exist in this packet.

### Duration confirmation for Meet — September 22

Notes confirms **round DOWN**, never nearest or up: `durationSeconds = Math.floor(snapshot.duration)` for finite, nonnegative recording durations. Examples: `59.999 → 59`, `60.001 → 60`, `3599.999 → 3599`. Send this as a JSON integer, not a numeric string or fractional number. Both Notes readers now compare the reference against the floored archive duration before opening playback.

- Keep original archive `snapshot.duration` and speech/seek offsets fractional. This is a display/reference conversion, not destructive media trimming.
- Meeting attachment duration independently uses `floor(ended_at - started_at)` with timezone-aware timestamps. It is not interchangeable with recording duration.
- Millisecond transcript labels floor only for display. Existing v2 recording-relative bounds are still `endMs <= durationSeconds * 1000`; a final fractional second cannot be represented by that integer reference bound. Do not silently discard speech or move its time: use the actual session-relative basis when available, or retain the precise passage in the recording archive until an exact-duration reference revision is agreed. Never fabricate a session offset.
- These checks validate the Notes contract; they do not certify the separate Meet publisher's current payload or live delivery.

### Recording reference v1 — exact JSON shape

```json
{
  "version": 1,
  "assetId": "50000000-0000-4000-8000-000000000001",
  "recordingId": "60000000-0000-4000-8000-000000000001",
  "sourceRevision": 2,
  "title": "Launch review recording",
  "durationSeconds": 1800,
  "mediaKind": "audio"
}
```

- All properties required; `mediaKind` is `audio | video`, title ≤160 units, revision a nonnegative integer, duration an integer 0…604800. This reference's range does not raise the existing recording capture/archive limits (current native archive decoder accepts up to 7231 seconds).
- `assetId` is the existing **archive** UUID, not the recording UUID. Match `whisper_recording_archives.id`, `.recording_id`, `.source_revision`, owner, ready state, storage consent, and snapshot meeting ID before accepting/opening it.
- Never use the host's private archive for another participant. Each viewer must own the referenced archive or omit the reference. A document invite grants no archive access.

### Transcript timing v1 — exact JSON shape

```json
{
  "id": "t1",
  "speaker": "Alex",
  "text": "Actual captured speech.",
  "timing": {
    "version": 1,
    "basis": "recording",
    "sessionId": "70000000-0000-4000-8000-000000000001",
    "recordingAssetId": "50000000-0000-4000-8000-000000000001",
    "startMs": 318250,
    "endMs": 321000
  }
}
```

- `timing` is optional. Within it, `endMs` is optional; `recordingAssetId` is required **only** for `basis: "recording"` and prohibited for `basis: "session"`. Other timing properties are required.
- `sessionId` is a stable capture-session UUID generated by Meet, not the meeting ID reused across reconnects. Offsets are actual integer elapsed milliseconds from that session or that exact recording's media timeline, not wall-clock timestamps, row positions, or AI guesses.
- Start 0…604800000; end ≥start and ≤604800000. Recording-relative intervals must fit within the referenced duration. No implicit cross-session stitching. Do not supply both legacy `offsetSeconds` and `timing` on one passage.
- Unknown timing: omit both timing and offset; reader says “Time not supplied.” Existing v1 `offsetSeconds` remains supported. Milliseconds are retained; visible labels floor to whole HH:MM:SS.

### Private APIs and lifecycle

Deployment: `notes-private-assets-v1` and `notes-meet-import-guard-v2` were applied successfully on September 22, 2026. Sources are `supabase/notes-private-assets.sql` and `supabase/notes-import-guard.sql`. This confirms schema deployment, not authenticated end-to-end file delivery.

All paths are relative to `https://uryyyegnbtlmyhqlgndy.supabase.co`. Use the same native Supabase user's bearer and public `apikey`, never a service role. Pin account identity/generation through each request. The Notes API does not establish source-meeting authorization: Meet must verify its own capture/export permission first.

**Publish a new document:** `POST /rest/v1/rpc/import_whisper_meet_document` with `{ "p_id": "<stable document UUID>", "p_operation": "<stable operation UUID>", "p_document": <complete envelope> }`. It calls the existing CAS save with revision zero: an uncertain same-operation retry is idempotent; an already-edited/deleted/conflicting document is not overwritten. New envelope `notes` and legacy `transcript` are empty and `completedDocumentSteps` is empty. Use `whisperDocumentImportSchema` plus `notebookDocumentSchema` before sending. Validate `meetingId === meetingDocument.sourceMeetingId`. Read back the exact owner/id row before displaying success. The ordinary save RPC remains for Notes' own edits.

**Read document:** `GET /rest/v1/whisper_private_notebooks?owner_id=eq.<owner>&id=eq.<document>&select=*`. Existing restrictive owner RLS still applies. No direct notebook INSERT/UPDATE/upsert.

**Screenshot upload:**
1. Explicitly review the screenshot and approve private cloud storage. Retain `{version:"notes-private-media-v1", approved:true, at:"<ISO timestamp>"}` only for this approved upload action; consent is not inherited from meeting membership or an older recording.
2. `POST /rest/v1/whisper_note_assets` with `id, owner_id, version:1, mime_type, byte_count, width, height, sha256, consent_version:"notes-private-media-v1", consent_at`. State defaults to `uploading`. Maximum 500 asset rows per owner, including incomplete/deleting uploads. Look up the same owner/id first on retry; do not replace a conflicting asset.
3. `POST /storage/v1/object/whisper-private-note-assets/<owner>/<assetId>/image`, raw bytes, correct `Content-Type`, `x-upsert:false`. Never make the bucket public or overwrite an object.
4. `PATCH /rest/v1/whisper_note_assets?id=eq.<assetId>&owner_id=eq.<owner>&state=eq.uploading` with `{state:"ready"}`, `Prefer:return=representation`. Finalization verifies stored byte size and MIME. Consumers also verify SHA-256 and decoded dimensions. Interrupted upload/finalization remains visible and retryable; do not claim success before ready readback.
5. Save the reference in the reviewed packet. The import guard checks owner, ready state, MIME, size, dimensions, and hash against metadata.

**Screenshot fetch:** re-read the owner/id ready metadata, then `GET /storage/v1/object/authenticated/whisper-private-note-assets/<owner>/<assetId>/image` with bearer auth. Verify bounds/hash/dimensions. Web creates an in-memory `blob:` URL and revokes it on close/account change; native uses an ephemeral no-cache session and in-memory image. No signed screenshot URL is needed.

**Screenshot delete:** explicitly confirm scope, PATCH metadata to `deleting`, then `DELETE /storage/v1/object/whisper-private-note-assets` with `{prefixes:["<owner>/<assetId>/image"]}`, then DELETE the owner/id metadata in deleting state. New reads are denied while deleting; incomplete cleanup is retryable. Deleting a document does not delete a separately retained asset/archive used by another saved document. Deleting an asset does not erase personal writing, checkoffs, transcript, or other meeting records; the reference shows unavailable. Downloaded copies cannot be recalled.

**Recording upload:** reuse `backupRecording` in `recordingCloud.ts` and existing `whisper_recording_archives`, not the image bucket. It requires storage consent and stopped capture; pending transcription blocks backup. Reserve stable archive metadata, upload both `<owner>/<archiveId>/original` and `audio.wav` to `whisper-private-recordings` through `/storage/v1/upload/resumable` (TUS, 6 MiB chunks, no overwrite), then finalize `state:"ready"`. Each file ≤471,859,200 bytes; metadata snapshot ≤3,000,000 server-serialized bytes (client safety bound 2,900,000). Supported types: audio/mp4, audio/webm, video/mp4, video/webm, audio/wav. Original recording snapshot v1 is defined by `meetingRecordingModel.ts`—do not substitute the document-reference shape for the archive snapshot.

**Recording fetch/playback:** GET ready owner/id archive, verify all reference fields and meeting ID, then `POST /storage/v1/object/sign/whisper-private-recordings/<owner>/<archiveId>/<original|audio.wav>` with `{expiresIn:300}`. The Notes reader holds the returned `signedURL` in transient player state only, stops/releases on close/account switch, and requires reopening after expiry. The older archive browser uses a separate 10800-second lifetime; new Notes references use 300 seconds. Signed URLs already issued can remain usable until expiry; removal/access changes do not retract downloaded bytes. Never serialize this URL into the snapshot, local storage, logs, exports, or retry journal.

**Recording deletion:** existing `deleteRecordingArchive`: mark deleting, remove both objects, then delete archive metadata. Never delete source recordings as a side effect of a document delete.

### Supported reader behavior (not a Google Docs parity claim)

- v1 remains supported. v2 renders text, transcript labels, compact document-tab list, personal checkoffs, screenshot attachment cards with captions/alt text, and explicitly opened private recording attachments.
- Full notes displays media cards; nothing downloads/plays automatically. Web uses browser audio/video controls for the original media (codec support varies); native offers continuous WAV audio. Deleted/unavailable media yields a retryable unavailable state without deleting the document.
- Detail links scroll to the exact transcript ID. Precise timing is displayed, but this release does **not** promise automatic transcript-to-player seeking, word-level synchronization, or cross-session playback stitching.
- Shared editions copy reviewed text/formatting only; private media references are not transferred. No screenshot OCR or media ingestion into Jasper is implied. PDF/Word/HTML text exports do not embed private binary attachments; complete JSON keeps stable references, not playback credentials or a media archive.
- Comments in shared editions highlight anchored passages, open their discussion on tap, offer threaded replies and resolve/reopen. @names are currently text, not notification/assignment semantics. Google Tasks integration and task assignee/date chips shown in the video are not implemented.

### Owner-access acceptance tests

Latest validation, September 22: 15 native Notes tests pass; 113 relevant web/SQL unit tests pass; eight browser scenarios pass, including comment anchoring/reply/resolve/reopen, compact tab switching, checkoff persistence, collaboration recovery, and access revocation. A focused rerun checks synthetic downward touch dismissal without changing formatted text. iOS simulator and web production builds pass; the bundled shared editor was rebuilt. These results do not establish physical-device keyboard behavior or authenticated live media delivery.

Automated tests are local/synthetic, not proof of live-account delivery. `notesPrivateAssets.sql.test.ts` exercises actual SQL using PGlite roles: cross-owner metadata/object denial despite an existing permissive storage policy, upload finalization, immutable objects, deleting-state denial, transcript-free import rejection, publisher conflict without personal-write/checkoff loss, legacy snapshot preservation, and wrong-owner notebook read/write denial. `whisperDocumentMedia.test.ts` exercises strict ID-only schemas, URL/path rejection, timing bounds/reference targets, attachment limits, and legacy-read/new-import distinctions. Live authenticated Storage upload/fetch and separate Meet publisher integration still require consenting-account acceptance.

## Earlier private-export message (superseded by the current integration above)

> Integrate with Whisper Notes iOS bundle **`app.rork.whisper-notes`**, not `app.rork.whisper-workspace`. Implement **Save to Whisper Notes** for an explicitly selected, authorized meeting. Use the same Supabase auth user and existing `whisper_private_notebooks` / `save_private_notebook` contract as Notes; do not create a second document database or change shared endpoints. Save a private Whisper Documents v2 snapshot for media/precise timing (v1 remains valid for transcript-bearing text-only exports) in the notebook envelope below. Preserve structured Quick notes, Summary, Next steps, Details, and speaker-labelled Transcript, with real elapsed timestamps only. Keep the meeting original unchanged. Confirm the saved owner/document/operation and read it back before returning `https://notes.mydailywhisper.com/d/<document UUID>?owner=<auth user UUID>&tab=full`. When the user clicks its note card, open this HTTPS URL using the operating system/browser instead of opening Meet's internal recap screen. IDs and URLs grant no access. Keep one stable document UUID and operation UUID for uncertain retries, refuse deleted/conflicting snapshots, and never overwrite personal writing or checkoffs in Notes. Validate using the shared packet and notebook schemas. Report live save/readback and cross-account denial tests before declaring the integration activated.

The Notes reader and route handlers are implemented in this workspace. **The separate Meet publisher, production domain, deployed private-notebook policies, and signed-device Universal Links have not been verified here.**

## Canonical contract

- Existing table: `public.whisper_private_notebooks`; primary key `(owner_id, id)`.
- Existing RPC: `public.save_private_notebook(p_id uuid, p_revision bigint, p_operation uuid, p_document jsonb, p_deleted boolean)`.
- SQL source: `supabase/private-notebook-sync.sql`; the live schema inspection confirms the table and owner policies. New imports use the deployed `import_whisper_meet_document` wrapper and guard described above. Never reapply older SQL over newer shared service changes without review.
- Owner is the current verified auth user UUID, never a meeting host, email address, participant, or arbitrary URL parameter. `auth.uid()` determines writes; owner-only RLS governs reads.
- The publisher must independently confirm this user may read the selected meeting and its transcript, respecting the meeting's access and capture policies. `sourceMeetingId` is provenance only, never a permission grant.
- One private snapshot per authorized owner/export, with its own stable document UUID. Store that mapping in Meet's existing account-bound state. Do not reuse a room code as the document UUID; avoid colliding with legacy private-copy IDs.
- Newly generated/revised content should be a new explicit export, not silent replacement of a snapshot the user has annotated in Notes.

### Complete minimal envelope (synthetic example)

Replace the example UUIDs and text. Generate and durably retain `p_operation` separately before the first send.

```json
{
  "version": 1,
  "id": "20000000-0000-4000-8000-000000000001",
  "ownerId": "10000000-0000-4000-8000-000000000001",
  "title": "Launch review",
  "folder": "",
  "people": "",
  "meetingId": "30000000-0000-4000-8000-000000000001",
  "templateId": "general",
  "instructions": "",
  "notes": "",
  "transcript": "",
  "revision": 0,
  "storageRevision": 0,
  "createdAt": "2026-09-21T12:00:00Z",
  "updatedAt": "2026-09-21T12:00:00Z",
  "enhancement": null,
  "commitments": [],
  "syncEnabled": true,
  "completedDocumentSteps": [],
  "meetingDocument": {
    "version": 1,
    "sourceMeetingId": "30000000-0000-4000-8000-000000000001",
    "generatedAt": "2026-09-21T12:00:00Z",
    "startedAt": "2026-09-21T11:30:00Z",
    "summary": "The team agreed to review the launch before Friday.",
    "quickNotes": [
      {"id": "q1", "title": "Launch review", "bullets": ["Review the release checklist."]}
    ],
    "nextSteps": [
      {"id": "s1", "text": "Review the release checklist.", "owner": "Alex"}
    ],
    "details": [
      {"id": "d1", "title": "Review timing", "text": "The team will review before Friday.", "transcriptId": "t1"}
    ],
    "transcript": [
      {"id": "t1", "speaker": "Alex", "text": "Let’s review before Friday.", "offsetSeconds": 318},
      {"id": "t2", "speaker": "Sam", "text": "I will bring the checklist."}
    ],
    "transcriptStatus": "partial"
  }
}
```

`notes` is personal editable writing, **not** a duplicate of the imported packet. `transcript` is the legacy manually pasted transcript field; keep it empty for new structured exports. `completedDocumentSteps` stores the user's personal checkoffs, separate from the immutable imported snapshot. Do not overwrite any of these fields after publishing.

## Save, confirm, then open

1. Capture the signed-in user's identity and access token. Recheck the same account/session before every asynchronous result or mutation. Do not borrow a later account's token.
2. Validate the full payload against `web-whisperweb/src/lib/whisperDocument.ts` and `notebookDocument.ts` (native equivalents: `WhisperDocumentPacket.swift` and `WhisperNotebookDocument.swift`). Never treat the database's structural envelope check as complete packet validation.
3. Persist an export intent containing owner, document ID, operation ID, and the frozen payload so a timeout can be retried after dismissal or relaunch.
4. For a new Meet document, call `import_whisper_meet_document` with `p_id: envelope.id`, `p_operation: stable operation UUID`, and `p_document: envelope`, using the user's bearer and existing public Supabase client key. The wrapper uses revision zero and never updates an edited document. Do not expose a service-role key.
5. Verify the RPC row has the exact `owner_id`, `id`, `operation_id`, `deleted: false`, positive server `revision`, and matching `document.ownerId` / `document.id` / exported packet. Read back the owner/id row before claiming that another app can open it. Store the returned server revision, not the envelope's local `storageRevision`, as cloud revision.
6. Retry an uncertain save with **the same** operation ID, document ID, revision, and frozen payload. The RPC returns an already-applied operation idempotently. A conflict (`40001`) is not success: read the owner-bound row and confirm the retained export mapping. Do not generate a second ID on every retry or overwrite newer personal edits. A deleted snapshot stays deleted; only a separately reviewed new export gets a new UUID.
7. Show **Saved to Whisper Notes** and activate the link only after confirmation. On failure say **Not saved to Notes yet**, preserve retry state, and keep the original meeting available.

Do not use unrestricted client upserts. The existing RPC derives ownership from `auth.uid()`, serializes writes, enforces revisions, refuses resurrection, and supports idempotency. Never loosen RLS to make links work. Verify actual deployed grants and restrictive owner policies rather than relying on an owner filter in the UI.

## Link formats

Preferred and suitable for email, DM cards, browser navigation, and OS open:

```text
https://notes.mydailywhisper.com/d/20000000-0000-4000-8000-000000000001?owner=10000000-0000-4000-8000-000000000001&tab=full
```

- `tab`: `quick`, `full`, or `transcript`; omitted defaults to `full`.
- Exactly one owner UUID; at most one tab. No unknown parameters, text, transcripts, credentials, access tokens, prompts, fragments, or remote content URLs.
- Native explicit **Open in Notes** scheme: `whispernotes://document/<document UUID>?owner=<owner UUID>&tab=full`.
- Legacy parser compatibility alias: `whisperworkspace://document/...`. Do not generate this alias for new integrations: another installed legacy/Meet app may register it. Use the canonical HTTPS URL or explicit `whispernotes` scheme. Custom schemes are not verified app ownership and do not authorize access.
- An absent installation falls back to the Notes website. Browser new-tab links should use a native anchor with `target="_blank" rel="noopener noreferrer"`; do not treat a null `window.open(..., noopener)` result as proof the tab failed.
- A wrong account sees a switch-account screen, not document content. Signed-out users retain the sanitized link through auth/onboarding. Deleted/missing/failed fetches expose retry, not fabricated document content. An online cloud verification is required for new link opens; saved offline copies remain accessible through the library.

## Packet v1 rules

- All contents are plain structured strings, not executable HTML/Markdown. Do not invent new fields and expect a renderer to preserve them.
- Legacy packet `version` is `1`; packet v2 is specified above. Notebook envelope stays `1`.
- `sourceMeetingId` is a UUID. `generatedAt` and optional `startedAt` are ISO-8601 date-times with a zone.
- `summary`: at most 20,000 UTF-16 units.
- `quickNotes`: at most 80 sections; section title ≤180 units, ≤40 bullets each, each bullet ≤3,000 units.
- `nextSteps`: at most 100; text ≤3,000 and owner ≤180 units. Use empty owner if not explicitly known.
- `details`: at most 200; title ≤180, text ≤12,000 units. Optional `transcriptId` must reference a supplied transcript entry.
- `transcript`: at most 4,000 entries; speaker ≤180 and text ≤12,000 units. IDs unique within each collection, matching `^[A-Za-z0-9_-]{1,80}$`.
- `offsetSeconds`: optional integer 0…604800, measured relative to the actual supplied recording/session start. Omit unknown or ambiguous times, especially mixed/reopened sessions. Never derive elapsed labels from row order or a guessed start.
- `transcriptStatus`: `complete`, `partial`, or `unavailable`. Complete requires actual capture/export completeness; successful generation is not proof of complete transcription. Missing sources must be stated, not silently reconstructed by AI.
- Compact JSON packet ≤1,400,000 UTF-8 bytes; full notebook envelope ≤2,000,000 bytes and the server's serialized JSON limit. Use a safety margin because server serialization adds whitespace. Split oversize meetings into deliberately titled separate documents; never silently truncate.
- Envelope title ≤160, folder ≤80, people ≤300, instructions ≤1,000, notes/transcript ≤60,000 UTF-16 units each. Existing notebook account limit is 200 active documents.
- Checkoffs must be unique IDs from `nextSteps` (≤100). Step completion is not meeting-source evidence for Jasper.
- Version 1 does **not** support screenshots/recording references; use the explicit packet v2 extension above. Neither version permits persisted signed playback credentials.

## Jasper privacy and behavior

Notes opens Jasper through the canonical compact pill: a white/silver ghost peeking over a coral/orange/amber-edged capsule, with a readable theme-aware capsule and the same identity inside its attached, upward-expanding question menu. Opening the pill alone sends no document text.

Notes uses Rork Toolkit `openai/gpt-4.1-mini` for approved current-tab passages or personal writing. It does not retrieve meeting history or follow `sourceMeetingId`. The user sees the context and can narrow it to an exact excerpt. Sending a question initiates processing without a separate approval checkbox; Cloud Credits use is disclosed. Requests are bounded to 24,000 characters / 160 source passages; oversize tabs require explicit narrowing without changing the saved document. Closing cancels work. Responses include inspectable source IDs, Stop, and copy; they do not edit or share originals.

Browser AI uses delegated Rork runtime authentication; **never ship the Toolkit secret or service-role key in browser code**. A non-Rork production host must supply an approved server-side/delegated authentication path; verify that host before claiming live AI works. The separate Notes collaboration storage and invitation function are now deployed as described below; production-host AI availability is still unverified.

## Notes editor and collaboration delivery — September 21, 2026

- Private writing retains the existing notebook envelope. Optional UTF-16 styles now preserve title/subtitle/headings, fonts, sizes, inline marks, colors, links, alignment, line height, indentation, and paragraph spacing. Apply styles only when `formattingText === notes`; old writing remains readable.
- Tables, embedded raster images, structural lists/checklists, and page breaks use a **separate reviewed edition**, available through Invite collaborators or Open full editor. It is owner-only until an invitation is accepted. Rich objects are not inserted into the legacy private text envelope or immutable Meet packet.
- Copy creation previews only the selected writing or imported tab. It does not copy other tabs, personal checkoffs, retained Jasper answers, membership, or meeting authorization. The source remains unchanged.
- Additive deployed migrations: `notes-collaboration-v1` and `notes-suggestions-v1`, sourced from `supabase/notes-collaboration.sql` and `supabase/notes-suggestions.sql`. Private-notebook and Meet policies are untouched. Clients use `whisper_notes_library`, `whisper_notes_action`, and `whisper_notes_suggestions`; direct table access is revoked and RLS is enabled.
- Owner/editor/commenter/viewer permissions are checked on each database action. Invitation acceptance is bound to the intended existing user or a matching confirmed email. Only owners invite, change roles, or revoke. Links convey no authority.
- `/shared` opens incoming documents and invitations only; owned rich documents appear in the main library. `/shared/<UUID>` opens an authorized document, including an owner's private rich document. Native routes are `whispernotes://shared` and `whispernotes://shared/<UUID>`. Do not add tokens, content, or ownership claims to these links.
- Shared editing merges Yjs updates through an authenticated ordered log. It includes relative-position cursors, passage comments/replies/resolution, suggested replacements, named versions, and deliberate restore. Restore retains a Before restore checkpoint. Restore and suggestion acceptance require the expected server sequence.
- Connection interruptions pause editing and retain queued updates in account/document/session-scoped recovery. Revocation blocks future reads and edits, not previously downloaded copies. Storage does not automatically migrate across origins or installations.
- Native collaboration loads `Resources/NotesCollaboration/notes-native.html`; rebuild it with `bunx vite build --config vite.native.config.ts` from `web-whisperweb` after web-editor changes. Its CSP forbids network connections. Allowlisted Swift bridge actions perform authenticated RPCs, exports, printing, explicit pasteboard copy, and Jasper. Tokens are never injected into JavaScript.
- Live function `notes-invite` is ACTIVE (version 2) at `https://uryyyegnbtlmyhqlgndy.supabase.co/functions/v1/notes-invite`. It verifies the caller, claims an owner-authorized pending invitation, rate-limits sends, and uses Resend. An unsigned live probe returned 401 `sign_in_required`. Actual email delivery is not verified; accepted for delivery is not an inbox-delivery guarantee.
- Shared Jasper verifies access before and after generation. It uses approved bounded context, discloses Cloud Credits, keeps answers private to the current user, and never applies edits automatically. The attached menu retains its draft while resizing and provides Stop, retry, source inspection, and explicit copy.
- Private exports include paginated PDF, DOCX with clickable links, TXT, HTML, and complete notebook JSON. Shared exports include rich Word structures and page setup, PDF through print preview, TXT/HTML, and content JSON. Shared backups omit comments, memberships, versions, and private Jasper conversations; they are not complete service archives. Word repeats headers/footers/page numbers; browser/native printing has platform-specific limitations disclosed in the menu.

### Validation actually completed

- Both TypeScript configurations, web static checks, and the web production build pass. Latest Rork preview: `https://8kq2ihv8pp417cvkao7s3-web-whisperweb.rork.live`.
- iOS simulator `runChecks` passes. `WhisperTests/WhisperNotesTests`: 13 executed, 13 passed, including portable styles, strict links, PDF pagination, Word package/link generation, bundled-editor presence/CSP, and compact/large-type layout checks.
- 94 relevant Vitest tests pass, including storage/recovery/sync, formatting, bridge failure handling, Word structure, CRDT convergence, and local PGlite permission checks.
- Seven browser scenarios pass. Two isolated synthetic accounts exercise acceptance, concurrent typing, cursors, comments, accepted suggestions, checkpoint restore, interrupted-save recovery, viewer downgrade, and revocation. Other scenarios verify private editing, imported-source preservation, Jasper consent/layout, and route isolation.
- These checks do not prove signed-device operation, real-account iOS/web collaboration, native shared Jasper interaction/cancellation, external Word-reader compatibility, actual inbox delivery, or production-domain Universal Links. Those remain release acceptance tasks.

## September 22 library, navigation, and people-picker completion

- Owned rich documents now appear beside private notebooks in the main library; Shared with me contains only other owners' documents and incoming invitations. Inviting someone does not move an owned document.
- New blank documents and templates create owner-only rich documents directly. Offline private note remains available. Existing private notebooks and Meet snapshots retain their envelopes and originals; Open full editor previews a deliberate copy, not an in-place migration.
- Imported tabs use a floating expanding glass page picker. Rich-editor pages follow actual page-break nodes. Page breaks now leave a paragraph for subsequent typing instead of a selected atom that typing would replace.
- Sharing, comments, suggestions, history, export, and insert menus are redesigned. Modal tools explicitly take focus and pause typing in the document behind them while retaining the selected passage.
- Additive migration `notes-people-picker-v1` was applied from `supabase/notes-people-picker.sql`; generated database types were refreshed. `whisper_notes_people` returns bounded public account matches without email; `whisper_notes_invite_person` validates stable account IDs, ownership, role, invitation identity, and blocks in both directions. Suggestions reuse relationship candidates but are revalidated by this account lookup.
- Recipient selection alone does not create an invitation. Explicit Invite remains required. Unsupported/missing avatars use initials; browser photos are restricted to same-Supabase-host public storage and native photos use a bounded authenticated bridge lookup/download, not direct WebView network access.
- Latest checks: 121 web/SQL tests in 23 files, nine browser scenarios, both TypeScript configurations, and 17 `WhisperTests/WhisperNotesTests` passed. Browser checks cover ownership/template reopen, page-break navigation, modal typing isolation, no invite on selection, concurrent editing, anchored comments, suggestions, history restore, recovery, downgrade, revocation, private data preservation, and Jasper consent.
- The native editor bundle was rebuilt after final focus, menu, avatar, and page-break changes. Final web static/production checks and iOS simulator build both passed. Phone screenshots of page navigation, editor, people search, and access panel were reviewed against the four supplied reference screenshots.
- These results use synthetic browser/database identities and simulator tests. They do not establish live inbox delivery, authenticated production profile-photo loading, real-account cross-platform collaboration, physical-device keyboard/glass/VoiceOver behavior, external-reader pagination, or App Store/TestFlight delivery. Existing production activation tasks below remain required.

## Production activation checklist (remaining live checks)

- Register/sign Notes as `app.rork.whisper-notes` with app group `group.app.rork.whisper-notes`. Match the Notes widget/Watch extension provisioning to the configured Notes targets. A separate native Meet app must keep its own distinct bundle ID and must not register `whispernotes`. Retain old installations until device-only writing has been exported or confirmed synced; the new bundle is not an in-place update of `app.rork.whisper-workspace`.
- Publish this website build in a **separate Notes project** at `notes.mydailywhisper.com` (root `web-whisperweb`, Vite, `bun install`, `bun run build`, output `dist`). Do not redeploy this Notes build over the social or Meet domains. Update only Notes' DNS with the exact host-provided target; leave apex/www/meet/email DNS unchanged.
- Reuse the correct shared public Supabase URL/key and existing auth identities. Add approved Notes auth/reset/confirmation URLs to the existing Supabase redirect allowlist without replacing shared Site URL/settings. Test confirmation, recovery and switching. Browser-local IndexedDB/recovery does not migrate between origins automatically; export from the old origin first.
- Verify deployed `whisper_private_notebooks` and RPC, owner-only reads, denial to another auth user, deletion/retry behavior, and live web↔iOS sync. No new database or permissive policy should be provisioned as a shortcut.
- Use the **verified** Apple signing Team ID in the website build (`APPLE_TEAM_ID`, `REQUIRE_APP_LINKS=1`). Generated AASA claims `/d/*`, `/shared`, and `/shared/*` for `<VERIFIED_APPLE_TEAM_ID>.app.rork.whisper-notes`; `webcredentials.apps` uses the same Notes app ID. Replace the old Workspace claim on the **Notes domain only**, without modifying Meet or social domain associations. Serve real JSON without redirect at `https://notes.mydailywhisper.com/.well-known/apple-app-site-association` with an appropriate JSON content type; never serve the SPA there.
- Notes entitlements now include `applinks:notes.mydailywhisper.com`; sign with an Associated Domains-enabled provisioning profile. Test a installed signed build by tapping links in Mail/Messages, signed out and under a wrong account, with and without the app installed. Simulator build success is not this verification.
- Verify live Jasper under the production host's delegated/server authentication, credit/error handling, device VoiceOver/keyboard behavior, and actual Meet export-to-Notes handoff. Synthetic browser tests cannot establish live service availability.
