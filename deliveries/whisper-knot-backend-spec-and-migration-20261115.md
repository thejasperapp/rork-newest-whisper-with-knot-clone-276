# Whisper + Knot: backend specification and safe migration runbook

**Snapshot:** November 15, 2026. **Project:** `mayokn2749ag072e3uvbh`.

This is a source-reviewed architecture and recovery specification, not a data backup or a completed migration. No member data, credentials, access tokens, private files or secret values are included. Read-only Supabase ownership and backup status were inspected for this document. No database restore, data export, credential rotation or backend cutover was performed.

## Executive answer

**Cloning the project source does not establish that its backend data was cloned.** This application has several independent stores. Copying the code, the database schema, a conversation JSON export, or the app build is not enough to preserve all of them.

The lowest-risk continuity option is to keep the existing backend and Supabase project alive and rebuild the client against those same authorized services. A completely new backend needs a verified export/import process covering every store listed below. No complete, rehearsed cross-store migration facility was established in this review.

**Losing access to the old app build is different from losing access to the old backend.** With administrative backend access, the old binary should not be required for recovery. If the old backend and workspace are gone and no usable backups were made, exact recovery cannot be promised. An untested backup is not proof of recoverability.

## 1. Current authorities

- Rork backend: `https://newest-whisper-with-knot-clone-t6ui3ur-backend.rork.app`.
- Backend code: `functions/`, registered as the existing Cloudflare app.
- Supabase: `uryyyegnbtlmyhqlgndy`, at `https://uryyyegnbtlmyhqlgndy.supabase.co`.
- Fresh read-only status: Supabase belongs to **your Supabase organization**, uses **native Supabase Auth**, and lists deployed Edge Function `whisper-knot-contact`.
- Supabase status reports it is **shared with Rork project `uf26aun6d49w1tsjsm2u9`**. Database/schema/function changes here can affect that app too. Reusing this database is continuity, not an isolated copy.
- External workspace/browser sidecar: `https://knot-shell.mydailywhisper.com`. Its persistent files are separate from Rork actor storage and Supabase.
- Native clients: Swift app in `ios/`; web client in `web-whisperweb/`.

Earlier backend addresses, source clones and historical audits are not fallback authorities. Do not switch to an earlier clone because a request failed.

## 2. Architecture and request boundaries

The native/web clients use Supabase for authenticated application data and the Rork backend for Knot orchestration and other server-owned APIs. The backend verifies identity/ownership and dispatches scoped operations to persistent actors. Knot workspace operations go through the separately hosted sidecar. Model requests use the existing managed Rork AI transport; independent voice, billing, email, realtime and calendar services have their own configuration.

Important API families include Knot live text/owned turns, conversation sync, shell activity/Events and documents, persona/media, browser controls, background responsibilities/contact and voice. Other routes include Jasper meetings/business data, Google Calendar integration, billing/webhooks, transcription, live-room tokens and communications. The complete executable route contract is the source, not this prose inventory; preserve backward compatibility with shipped clients.

Ownership, Stop, revocation epochs, immutable file identity, source-conversation bindings, deletion tombstones, single-use IDs, delivery deduplication and uncertainty quarantine are part of persisted behavior. They must migrate alongside visible messages. Historical approvals and saved commands must never become fresh execution permission.

## 3. Persistence inventory: what must survive

### A. Supabase database and Auth

Preserve all relevant application schemas/rows, native Auth identities and stable user UUIDs, relationships, SQL functions, triggers, policies/RLS, indexes, constraints, extensions, grants and migration history. Application domains include profiles/social content, messages/groups/receipts, meetings/calendars, business/recruiting, subscriptions, private notebook/recording metadata and selected sync blobs.

Source SQL is spread across `supabase/`, timestamped migrations and `backend/` assets. These are not a live row backup and have not been proven to form one clean replayable database baseline. Use an authoritative database export and schema inventory, not blind execution of every historical SQL file.

Auth provider configuration, allowed redirect URLs, signing configuration, email/SMS setup and integration ownership require a separate secure settings inventory. A new Auth project must preserve or explicitly map UUIDs across every store. Existing sessions may require reauthentication; do not promise token portability.

### B. Supabase Storage objects

Database backups are not evidence that stored file bytes are included. Independently inventory and export actual objects, paths, sizes, MIME types, hashes and bucket access policies. Source references include `avatars`, `banners`, `whisper-media`, `whisper-group-avatars` and private recording storage `whisper-private-recordings`; these names are not a freshly enumerated complete live bucket inventory.

Preserve private access and signed-download behavior. Recreating `storage.objects` metadata alone does not restore the files. Expired/disappearing media must not be resurrected by restoring an old snapshot.

### C. Knot conversation actors

`KnotConversationAccount` stores account-owned chat/message JSON, reactions, Events/call metadata, preferences and owned-turn/release bindings in SQLite-backed actor storage. Actors are routed by lowercase account UUID.

Application conversation sync is bounded and intentionally strips execution authority. It is not an administrative whole-actor export and cannot replace a backend backup. Include deleted-state and replay-prevention records, not just visible chat text.

### D. Knot shell, persona, document and artifact actors

`KnotShellConversation` stores shell command/session records, logs/Events, skill/reaction-guide evidence, document programs/rejections/stops, persona metadata, chunked private avatar bytes and single-use generation IDs. Related document/artifact tables store immutable identities, captured byte chunks, review/delivery metadata, source bindings, sharing/import records and deletion tombstones.

**Critical addressing dependency:** shell-account routing derives an actor address using HMAC-SHA256 keyed by the existing Supabase service-role credential over `knot-shell-account-v1:` plus the user ID. A different key can address a different actor even with the same user UUID. Do not blindly change that credential while expecting records to appear automatically. A new destination needs a reviewed actor-address mapping or a backward-compatible identity migration. This is not a reason to retain a compromised key indefinitely: rotation must include explicit routing migration. Never put the key or derived private account inventory into this document.

The selected master, candidates, previous avatar sets, quality descriptions/traits, exact image/video bytes, job outcomes, revocation epoch and consumed-job tombstones all matter. System-facing persona records are not chat UI. The master pick authorizes the fixed derived portrait/state set; independently checked matching output activates automatically. Missing/failed output uses that master still without inventing success.

### E. Workspace bindings and external files

A separate actor address `knot-workspace-account-v1:<lowercase account UUID>` records the chosen persistent workspace and legacy candidates in `workspace_binding`. Current resolution adopts one provenance-backed namespace; it does not merge/copy every old workspace.

Export each actual bound sidecar filesystem, including workspace-root `MEMORY.md`, saved skills/drafts, source/output files, hidden files required by the application and all historical/rejected/undelivered originals that are still retained. Inventory legacy namespaces separately rather than silently abandoning or merging them. Preserve ownership and source bindings.

Browser profiles/cookies, live processes and authenticated remote sessions are sensitive, separate concerns. Do not assume their portability or copy live credentials casually. Prefer a documented provider-supported snapshot procedure and explicit reauthentication where needed. A SQLite snapshot alone does not back up the sidecar disk, and a sidecar disk snapshot does not back up captured delivery records.

### F. Background/contact and owned-turn actors

`KnotBackgroundAccount` contains responsibility definitions/revisions/runs/messages, contact grants and event/daily-limit ledgers, permission epochs, welcome invitations and owned task/frame/Stop/seen/erasure records. Routing is account-scoped. Alarms can act while the app is closed.

Preserve history, deletion and idempotency evidence. During restore, **disable alarms and outbound effects** until deliberate review. Do not automatically resume pending shell work, calls, paid avatar generation, invitations or old approvals. Restoring history is not authorizing work.

### G. Other server actors

`JasperMeetingAccount` holds private/shared business and meeting-related keyed JSON in SQLite (`jasper_values`), routed by account or authorized workspace identity. Inventory all keys and ownership scopes, including Google Calendar associations.

`KnotResponseLimiter` and `WhisperLoginLimiter` also exist. Document rate-limit/security treatment explicitly during cutover rather than confusing them with business records. Inspect any additional platform KV/bindings before claiming the inventory complete.

### H. Device/browser and Apple storage

The app also has account-scoped local settings/history/caches, protected local original-file copies, Keychain/session state and browser-local storage. CloudKit uses the private container `iCloud.com.mydailywhisper.whisper` for selected records. A Supabase `user_data` mirror and CloudKit are not complete snapshots of Knot actor databases or sidecar files.

A new Rork project/build does not automatically inherit Apple entitlements, CloudKit access, push identity, device permissions, local files or browser sessions. Preserve a released app’s bundle ID and legitimate signing/container access when continuing that app. Separately save important originals to independently controlled storage. Ephemeral caches are not archival recovery sources.

## 4. Retention: exact preservation has limits

- Captured delivery bytes: seven-day server retention, with quota eviction possible earlier; current limits include 50 MB per file, 200 MB per account and 500 cards. File identity metadata can outlive byte availability. Workspace originals are separate.
- Persona bytes have private capacity bounds; current source enforces 64 MiB, plus bounded candidate/set/job counts. A capacity limit is not a backup policy.
- Some background/contact histories are pruned/bounded. Jasper draft/request records expire after one day.
- Disappearing media has intentional expiry/open-once semantics. Never restore it into a newly readable state after it should have expired or been consumed.
- Voice-provider retention is separate and must be inspected at migration time; old configuration notes are not a current backup guarantee.

Preserve what actually exists at the checkpoint, maintain intentional expiry/deletion semantics, and list already-missing content explicitly. Do not extend retention or revive deleted/private content merely to make counts match.

## 5. Fresh backup evidence and missing coverage

Read-only `rork supabase backups ls` on November 15 reported `walg_enabled: true`, `pitr_enabled: false`, region `us-west-2`, and eight completed physical backups dated November 8–15. Latest observed backup: **November 15, 2026, 10:43:31.623Z**, ID `2274135630`.

This establishes reported daily database backups at inspection time, not a successful download/restore or whole-application backup. Writes after the chosen backup are outside that checkpoint unless a separate consistent delta/export is obtained. Point-in-time restore was reported off. No freshness or recovery-time guarantee is inferred.

The backup download control returns privileged access and is intentionally not available to this agent. Use your own authorized Supabase administration/account workflow to obtain and securely store supported exports; do not paste download credentials into chat. Source/destination restore options and cross-project physical-backup compatibility must be verified before choosing a method.

Still not established:
- A provider-supported export/import/enumeration path for every Rork actor namespace, including SQLite/BLOBs, platform KV and alarm state.
- A complete sidecar filesystem snapshot/restore procedure and tested independent backup ownership.
- A coordinated checkpoint covering Supabase, object bytes, actors, workspace files and integrations.
- A complete live bucket/row/actor/file inventory, checksummed export, full restore rehearsal or achieved recovery time/data-loss objective.

The November 14 clone configuration audit explicitly did not establish historical durable-state migration. That historical audit is not a backup or proof of present continuity. A project source clone must be treated as empty/new server state until the relevant platform confirms otherwise and restored data is verified.

## 6. Safe option A: keep the existing backend

Use this when replacing/cloning the client or losing the old build, while the current services remain accessible.

1. Secure independent owner/admin access to the Rork project, your Supabase organization, the sidecar host/storage, domain/DNS and integration accounts. Keep recovery contacts and billing under your control.
2. Record exact production authorities, actor namespace ownership, workspace bindings, source/build versions and secret **names** in an owner-controlled inventory. Keep secret values in a secrets manager, not a repository/downloadable spec.
3. Obtain independent verified backups anyway; keeping an endpoint alive is not a backup policy.
4. Build the replacement client against the same intended backend and Auth authority, preserving account IDs and compatibility. Do not change endpoints/keys opportunistically or enable fallback to another clone.
5. Verify sign-in, authorized history/media/download access and fresh deliberately submitted work before release. Check Apple/push/CloudKit identity separately.
6. Leave shared Supabase functions, voice agents and callbacks unchanged unless a reviewed cutover requires it. A clone changing shared settings can break the original build.

This avoids relocating data. It does not provide an independent backend or protection if the original backend is later deleted.

## 7. Safe option B: migrate everything to a new backend

### Phase 1 — prerequisites, before losing old access

- Agree scope: every account or a selected authorized cohort, every store, expiry rules, acceptable downtime, maximum data loss and recovery time.
- Obtain documented actor export/import and sidecar snapshot support. If unavailable, design and security-review a restricted administrative migration facility first; do not expose a public all-account export route.
- Inventory all actor IDs/namespaces, account/workspace bindings, schema versions, bucket objects and integrations. Include deleted/tombstoned and consumed-action identities needed to prevent resurrection/replay.
- Choose whether to keep the existing Supabase project or copy into a new one. Keeping it shares live data with both Rork projects; a new project needs separate Auth/data/object/policy/settings migration.
- Resolve the credential-derived shell actor-address issue explicitly before any key rotation or target import.

### Phase 2 — consistent export

- Establish a maintenance/quiescence boundary: stop new writes and coordinate active owned turns, background alarms, invitations, webhooks and sidecar writes. Preserve uncertain execution as uncertain; do not replay it to get a clean checkpoint.
- Snapshot all stores at an auditable common checkpoint or use a reviewed change-capture/reconciliation protocol. Independent snapshots at unrelated times can break file/message/permission relationships.
- Export Supabase schema/data/Auth and access configuration with an owner-approved supported method; export actual Storage bytes separately.
- Export all actor SQL/KV/BLOB data and secure logical actor mappings; inventory alarm intentions separately with execution disabled.
- Snapshot actual sidecar volumes/files and namespace bindings. Verify the snapshot includes persistent memory and original files, not just current shell output.
- Encrypt archives and an integrity manifest; store independently of the original Rork project with owner-held recovery keys and least-privilege access. Maintain more than one independently accessible copy and explicit rotation/retention.

Manifest requirements: export ID; UTC checkpoint; source project/environment; code/schema versions; per-store coverage/exclusions; account/actor/workspace mapping reference; row/object/file counts; byte sizes; SHA-256 per file/chunk; ordering for chunked BLOBs; ownership; expiry/deletion state; failed/missing entries; encryption/recovery instructions. Do not store secret values in the general manifest. Checksums prove byte identity, not export completeness or consistency.

### Phase 3 — isolated restore

- Create an isolated destination with no production traffic, outbound notifications/webhooks/calls, automatic schedules, paid generation or remote execution enabled.
- Restore schema/constraints/RLS/functions and data in a supported order, preserving UUIDs. If mapping is unavoidable, audit every foreign key, actor address, source binding, workspace, media/card link, ownership record and external association.
- Restore actor records and exact ordered byte chunks; restore workspace files with their actual ownership. Preserve failed/rejected/consumed/tombstoned state.
- Import historical pending/running work as inert/unconfirmed history; never turn saved approval flags or unfinished provider sessions into permission to run.
- Securely configure destination secrets and external callbacks with the owner. Do not copy expired sessions blindly. Keep current credentials untouched until the destination identity strategy is proven.

### Phase 4 — parity and recovery rehearsal

Require actual observed results, not just a successful build:
- Counts and hashes match the checkpoint manifest; every missing/expired item is explained.
- Native Auth resolves the same intended account and RLS blocks cross-account/group access.
- Conversation order, reactions, source-bound Events, Stop/deletion markers and original-file identity match.
- Avatar master/sets/traits remain exact private data; candidate selection and state fallback preserve the chosen identity without displaying the internal record.
- Downloaded original bytes match original recorded hashes; preview metadata alone is insufficient.
- Workspace memory, skills, draft/original files and account-to-workspace bindings match without namespace merging.
- Responsibilities/contact history is preserved while old jobs remain disabled; revoked permissions remain revoked.
- Fresh synthetic requests can complete after deliberate enabling, and old consumed requests do not run.
- Shared Supabase users/other builds are unaffected; voice, push, calendar and billing callbacks reach the intended authority once, not both.
- Perform a full restore from the independent encrypted backup with the old app build unavailable. Record duration, data-loss window, failures and rollback results.

Only this rehearsal establishes a recoverable migration for the tested checkpoint and coverage.

### Phase 5 — cutover and rollback

- Take a final consistent checkpoint/delta under controlled writes and repeat reconciliation.
- Switch clients/routes/callbacks deliberately to one authoritative writer. Source code deployment copies no database or workspace data by itself.
- Reenable only reviewed future schedules/work and newly authorized actions. Do not drain historical pending work automatically.
- Keep the old backend unchanged and secured for an agreed rollback period; avoid dual writes unless a proven reconciliation protocol exists.
- Rollback must account for writes made after cutover. Switching a URL back can lose those writes or duplicate effects. Pause writes, reconcile verified deltas, then switch authority.
- Delete old services/backups only after acceptance, legal retention review and explicit owner approval.

## 8. External configuration checklist

Securely inventory ownership, secret names/versions and callback destinations for Rork AI, sidecar authorization, ElevenLabs voice/bridge agents, Stripe customer/subscription/webhook links, Resend sender/domain, LiveKit/realtime and TURN configuration, Google Calendar OAuth, Supabase Edge Functions/secrets, APNs push identity, Apple signing/CloudKit and DNS/domain routing. Preserve existing `OPENAI_API_KEY` and other required secrets through an owner-controlled secure process; never publish their values.

Remote provider data and live sessions are not automatically included in source or database exports. Some integrations require reauthentication/re-registration. Verify current configuration at migration time rather than treating a historical callback audit as present truth.

## 9. What to do now

1. Download this specification and keep it outside Rork with your recovery inventory.
2. Retain owner/admin access to your Supabase organization and workspace host independently of this app build.
3. Arrange supported Rork actor and sidecar exports, plus independent Supabase database and Storage exports, before abandoning/deleting this project.
4. Implement/review any missing administrative export/import coverage, then rehearse a full isolated restore. Until that passes, exact future migration remains **not guaranteed**.

No migration or member-data export has been executed as part of preparing this document.

## Source map and evidence boundaries

- `functions/index.ts`: API entrypoint, actor exports and external-service environment contract.
- `functions/knot-backend.ts`: current backend authority.
- `functions/knot-conversations.ts`: conversation schemas, ownership and bounded application sync.
- `functions/knot-shell.ts`: shell schemas, HMAC actor addressing, workspace bindings and dispatch.
- `functions/knot-documents.ts`, `knot-artifact-sharing.ts`: file bytes, retention, identity, notes and sharing.
- `functions/knot-persona.ts`, `knot-persona-tools.ts`: private avatar state, media, consent and no-replay jobs.
- `functions/knot-background.ts`, `knot-owned-turns.ts`, `knot-contact-store.ts`, `knot-welcome.ts`: alarms, tasks, grants and retained/deleted history.
- `functions/knot-shell-discovery.ts`: external sidecar boundary.
- `functions/jasper-meetings.ts`, `jasper-google-calendar.ts`: other actor data/integrations.
- `backend/`, `supabase/`: relational schema/policy/function source, not row/object backups.
- Native `CloudKitService.swift`, `SupabaseSyncService.swift`, `WhisperKnotOriginalStore.swift`, `WhisperKnotPersona.swift`: device/cloud sync and private media boundaries.
- `deliveries/clone-migration-20261114-configuration.json`: dated prior configuration audit, explicitly not a durable-state migration.
- `handoff/knot-process-tool-inventory-2026-11-11.md`: earlier process inventory; historical limits/statements may have been superseded. Use current source and this document's dated observations, not an assumption that the old inventory is current everywhere.

**Verification scope:** source review and the read-only Supabase status/backup-list responses above. No full live data inventory, actor export, object-byte backup, sidecar snapshot, restore rehearsal, phone/browser acceptance or recovery guarantee is claimed.
