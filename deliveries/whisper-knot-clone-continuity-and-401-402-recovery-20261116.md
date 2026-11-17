# Whisper + Knot: clone continuity, backend transfer and 401/402 recovery

**Owner handoff guide • November 16, 2026**  
**Source project:** `mayokn2749ag072e3uvbh`  
**Scope:** preserve the current service, prepare a future clone, diagnose failures safely, and define acceptance for Knot’s tool families.

This is a documentation handoff, not a backup, a migration, a credential repair or authorization to execute anything. No secret values, member sessions or private workspace contents are included. The preparation of this guide did not change backend configuration, rotate keys, transfer ownership or submit new model/tool requests. Dated runtime evidence below is historical evidence, not a guarantee of current availability.

## 1. Direct answer: can the existing backend be transferred?

**Reused: yes, subject to continued ownership, access and client compatibility. Transferred as a hosted service: not yet established. Re-created elsewhere: source is portable, but a complete state migration is not yet verified.**

There are three different choices:

1. **Keep the existing backend and connect the replacement client to it.** This is the recommended first choice when you want the same accounts, workspaces, files and schedules. Keep its project and billing alive. The clone uses a shared existing service; it does not own an independent copy. Its access must still pass authentication, authorization, consent and admission. Different web origins may need reviewed configuration; a hardcoded URL alone is not acceptance.
2. **Transfer ownership of the hosted project/service.** This requires a supported Rork ownership handoff. No inspected capability establishes that a transfer preserves the project ID, backend origin, physical actor namespaces, managed AI association, secrets, billing and deploy rights. Obtain explicit platform confirmation before promising it. Changing a repository owner, project name or URL is not proof of transferring those resources. Supabase, the sidecar host, DNS and third-party accounts have separate ownership.
3. **Deploy an independent new backend and migrate the data.** This requires coordinated exports and a tested restore across all stores in section 7. Deploying `functions/` or copying Supabase schema does not copy actors, workspace disks, stored file bytes or live integrations. A complete cross-store migration has not been demonstrated.

**Do not delete this project because a clone builds successfully.** If the old app binary is unavailable but you retain administrative access to the services, a replacement client may still provide continuity. If the actual stores disappear without usable independent backups, exact recovery cannot be promised.

## 2. Current authority map

Use these as the dated starting point, then verify the intended environment before any future change:

- **Rork project:** `mayokn2749ag072e3uvbh`.
- **Knot backend:** `https://newest-whisper-with-knot-clone-t6ui3ur-backend.rork.app`.
- **Backend code:** `functions/`, registered as the Cloudflare app.
- **Supabase:** `uryyyegnbtlmyhqlgndy`; URL `https://uryyyegnbtlmyhqlgndy.supabase.co`; native Supabase Auth and existing account UUIDs.
- **External sidecar:** `https://knot-shell.mydailywhisper.com`; principal `whisper`; separate persistent workspace/browser host.
- **Clients:** native Swift app `ios/`, web app `web-whisperweb/`.
- **AI:** Rork Cloud-only. Default gateway `https://toolkit.rork.com`; current centralized text default model `openai/gpt-4o`.
- **Voice completion callback:** current backend origin plus `/knot/voice/completions`. Correct source configuration is not evidence that existing provider agents were retargeted.
- **Contact/push bridge:** Supabase Edge Function `whisper-knot-contact`; fixed backend allowlists and signed, backend-bound tickets.

The November 15 status inspection recorded Supabase as shared with project `uf26aun6d49w1tsjsm2u9`. Treat its schema, functions and rows as shared production dependencies unless a new authorized inspection establishes otherwise. A second frontend is not database isolation.

**Routing correction:** the current dedicated web client uses the current backend origin directly. The hosted `/~api/ping` alias returned 404 during the November 14 cutover. Do not restore that proxy assumption or add an old-backend fallback. Native Debug and Release were also cut over to the current authority. Do not manually edit generated native credential configuration.

### Build identity, not merely hostname

The latest retained backend source fingerprint is `f2910baf23bbaddc8a93b00c2b10a21d21f72dc851b710a8fdcef3c85f4f90c9`, across 101 inputs; retained production artifact `923931dab1225fadbaa7bc46bff2d096`. This is a recorded checkpoint, not a fresh live observation made for this guide. Future changes must use their own verified source stamp.

Capture the expected project, environment, exact backend origin, source stamp, deployment artifact, request ID and observed Worker/actor build headers. A hostname or `/ping` response alone does not prove that the intended actor, model call or tool executed.

## 3. Owner-controlled access and configuration inventory

Before a future clone, keep independent administrative recovery access to Rork, your Supabase organization, the sidecar host and backup volumes, DNS, Apple signing/CloudKit/push, and relevant integration accounts. Do not rely on an installed app or one agent session as the only access path.

Inventory secret **names, owners, environment, version/update time and purpose** securely. Do not paste values into this document, chat, source control, logs or support tickets. This is a source-derived minimum, not a freshly enumerated complete live secret inventory:

- `EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY`: current managed credential selected by the backend AI transport. Its legacy public-prefixed name is **not permission to expose it in browser code or copy it to another project**. Browser media uses delegated authentication.
- `EXPO_PUBLIC_TOOLKIT_URL`: optional gateway address. Current policy audit recorded no override. Gateway validation requires HTTPS and rejects embedded credentials/query/fragment; configured path prefixes are preserved by source.
- `SUPABASE_SERVICE_ROLE_KEY`: server-only privileged database access; also participates in shell actor addressing and signed contact authority. Rotation requires an identity/routing migration plan, not just replacing a value.
- `SIDECAR_TOKEN_WHISPER`: server-only authorization for the current sidecar/principal.
- `BROADCAST_SECRET`: protects operator diagnostics via `X-Whisper-Operator`; not member authentication or a model credential.
- `KNOT_VOICE_BRIDGE_SIGNING_KEY`, `ELEVENLABS_KNOT_BRIDGE_SECRET_ID`, `ELEVENLABS_API_KEY`, `ELEVENLABS_AGENT_ID`, `ELEVENLABS_RELAY_AGENT_ID`: distinct bridge, provider and agent configuration. Provider secret IDs are not secret values or proof of correct callback binding.
- Contact bridge environment includes `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_BUNDLE_ID`, `APNS_PRIVATE_KEY` or `APNS_KEY_P8`, and `APNS_USE_SANDBOX`.
- Preserve existing `OPENAI_API_KEY` and unrelated application secrets. Current Knot text does not select it; unrelated Jasper/Meet/legacy services may still depend on it. Do not delete it or repurpose it as a Knot fallback.
- Separately inventory billing/webhook, email, realtime/TURN, calendar OAuth and signing credentials from their actual current service contracts.

**Do not introduce** `RORK_TOOLKIT_SECRET_KEY`, a private copied override, a direct-provider branch or a saved transport toggle as a workaround. Current `knotAITransport` selects only the managed toolkit credential and validated gateway. A model ID beginning `openai/` describes a model behind Rork, not permission to call OpenAI directly.

A future project should obtain its supported managed AI configuration through the platform. Reusing the current backend and reusing its privately held AI transport is different from extracting its credential into a new project. Independently verify the replacement client’s delegated native/web media paths.

## 4. What actually happened with 401 and 402

The record contains several different incidents. They must not be collapsed into “the balance was empty” or “rotation fixes it.”

### November 11: earlier-project investigation

- A real answer stream returned 402. A separate process diagnostic reported `INSUFFICIENT_BALANCE`; that was not necessarily the identical captured body of the original user request.
- Inherited CLI environment values survived managed rotation. Protected managed keys were not exported by the ordinary environment runner. A process variable was therefore not an authoritative read of the newly rotated managed credential.
- An agent-created private `RORK_TOOLKIT_SECRET_KEY` copied a stale inherited value and sustained 401. Removing that override/rotating later led to 402, **not demonstrated billing recovery**.
- A historical direct OpenAI workaround temporarily worked, then returned 429 `insufficient_quota`. It was removed when the owner required Rork Cloud-only. It is not the present remedy.
- At **2026-11-11T16:18:49.232Z**, a genuine Rork Cloud stream returned 200 with 21 frames and completion. The exact reason the earlier 402 cleared was not established.
- A separate `tool_finish_reason_invalid` after HTTP 200 was repaired in the **request builder**: offer only the required function, require tool selection and disable parallel tool calls. The strict validator was not relaxed. Tool protocol repair is not AI billing repair.

### November 14: this clone

1. **08:30 UTC:** a fresh authorized member prime-sum request was rejected during classification with upstream 402 / `INSUFFICIENT_BALANCE`. No box execution occurred.
2. A supported managed-key rotation was followed by three distinct fresh 401 rejections. Enabled-key metadata and automatic-reload reports were not runtime-key/billing proof.
3. **08:56:39.869Z:** a post-cutover fixed synthetic diagnostic returned upstream 402. The operator endpoint itself returned 200; this was not model success.
4. A second owner-authorized rotation was followed by **09:03:13.660Z upstream 401**. Rotation was not a demonstrated solution.
5. A small diagnostic classification defect was fixed: JSON-formatted 401s had lost their authentication category. That repaired reporting, not authentication.
6. **09:14:15.981Z:** the fresh auth-diagnostic returned upstream 402 / `INSUFFICIENT_BALANCE`, still no reply.
7. After the **owner reported a fix**, exactly one fresh recheck at **09:20:01.010–09:20:02.208Z** returned **Rork upstream 200, 20 frames, terminal frame, normal finish, valid complete reply**. Serving request `4d1b452c-c9c0-415b-935d-440613fa269f`; source fingerprint `178f79bcc6b19776fe27a0aa4bf24dc1a5bfd3e411e7590c798e650ad04dfe97`.

**What is proven:** that last recheck completed a genuine Cloud generation on that build. **What is not proven:** exactly what the owner/platform changed, the serving credential’s independently verified identity, or its project/billing ledger association. The agent made no code, deployment, configuration or key change between the latest failed diagnostic and this successful recheck. Do not claim the reporting patch or another payment fixed the incident.

Later dedicated native computation and an owner game capture establish additional narrowly scoped execution success. They do not establish every tool, voice, phone interaction or permanent service availability.

## 5. Safe 401/402 diagnosis and recovery

### Step A — identify which boundary failed

- **Member API 401:** investigate the intended Supabase session, expiry, authoritative account and intended Auth project. Do not substitute service-role access for member acceptance or mint a session without explicit authorization.
- **AI upstream 401:** investigate the managed credential’s serving identity, enabled/revoked state, project association and exact gateway/environment. The outer member/operator route may still return 200 or a stream error envelope.
- **Sidecar 401:** investigate `SIDECAR_TOKEN_WHISPER`, host/principal and the exact sidecar boundary. Rotating an AI credential does not repair sidecar authentication.
- **Operator 403:** investigate operator authorization to that diagnostic route. It says nothing about member login, AI balance or sidecar health.
- **AI upstream 402:** record the bounded safe category/code and correlation IDs. It may concern provider/platform quota or project/billing association. It does not by itself prove that the owner’s visible balance is empty or that another payment is required.
- **AI 429:** distinguish rate limiting from insufficient quota using safe structured evidence. Do not change provider/model to hide it.
- **HTTP 200 with invalid finish/tool count, malformed frames or failed authoring admission:** diagnose protocol, request construction or receipt/evidence constraints separately. Do not weaken validators or call it a billing issue.

If the request outcome is uncertain, reconcile the existing request’s owned records before doing anything else. Do not resend it to find out whether it ran.

### Step B — verify routing without generating

1. Establish the intended project/environment/current origin from supported configuration and source. Reject older backend aliases, unexpected redirects and inherited process overrides.
2. Compare the expected source stamp with `/ping` and request/build headers. Health proves reachability/build only.
3. If operator access is authorized, inspect `GET /admin/knot-text-policy`. Confirm Rork-only selection, managed source and expected override policy. In current code, `tokenPresent` and `gatewayValid` both derive from whether a transport object can be built. They do **not** validate credential identity, account association or usable balance.
4. Inspect supported managed-key/environment **metadata**, without exposing values. Record project, environment, enabled state and update/version. `enabledNow: false` is not the same as `enabled: false`; metadata does not prove serving bytes.
5. If an authoritative candidate is legitimately available through an approved supported path, the protected `GET /admin/knot-key-binding` can compare it without returning values. It requires operator auth, a fresh 64-hex nonce and HMAC-SHA256 proof over `whisper-knot-key-binding-v1:` plus nonce. It returns equality/source/presence and performs no gateway request. Equality is not billing proof; the current helper validates proof format and equality, not a durable single-use nonce ledger.
6. **If no authoritative candidate is available, stop at “identity unverified.”** A delegated browser placeholder, empty generated native literal, inherited variable or old key is not that candidate. If protected reveal is denied, do not try alternate extraction routes.

### Step C — resolve the actual binding through the responsible owner/platform

For persistent Cloud 401/402 with correct source routing, request a server-side check of managed credential → serving project → billing account/ledger association. Include only safe IDs, UTC times, build, request IDs, outer/inner status and safe error category. Ask what changed and how it was verified.

Do not rotate repeatedly, copy stale values, disable admission, bypass quotas, switch to another backend or recommend payment as an established fix. Rotation is appropriate only for a confirmed credential issue or security need with explicit owner approval and a rebuild/consumer impact plan.

### Step D — one fresh authorized transport check

This is a future procedure, **not permission to run it now**:

- Obtain explicit scope, cost and endpoint approval. Create a new reviewed helper/intent with new unique scope, current project/origin/build and **exclusive durable consumption before dispatch**.
- The POST `/admin/knot-text-transport` generates real paid model output. Its `check` variants can exercise tool selection or authoring transports; they are not read-only configuration checks and do not establish actual tool execution.
- Do not execute the historical `scripts/inspect-knot-clone-transport-once.ts`: its four named scopes are consumed and its metadata includes historical key identifiers. Changing or deleting an old latch is prohibited. Review other historical scripts for stale origins/process defaults before any separately approved adaptation.
- Require exact serving build, outer route 200, **inner upstream 200**, `eventStream`, `normalFinish`, `terminalFrame`, `validReply` and `completed` all true. Record timing scope accurately: client round trip is not pure model latency.
- Preserve intent/outcome separately and immutably. On timeout or ambiguous response, mark uncertain and reconcile; no automatic replay. Never replay consumed, dispatched, aborted or uncertain work.
- A successful fixed greeting unlocks a proposal for separate fresh member/tool acceptance. It is not itself that acceptance.

Current nonexecuting transport source permits bounded timeout/5xx recovery inside an immutable stage. It does not retry 401/402/429. Never apply model-transport retry rules to shell commands, calls, invitations, uploads, paid generations or other stateful tools.

### Prevent recurrence without false guarantees

Keep routing centralized, use supported managed environment configuration, verify build identity, avoid credential copies, retain structured safe diagnostics, bound attempts and monitor both upstream status and completion. Preserve an escalation trail with exact operator-reported changes. These reduce preventable mistakes; they cannot guarantee a platform credential/billing incident never recurs.

## 6. Recommended continuity path: reuse the current backend

- [ ] Confirm the owner will keep the current Rork project, Supabase and sidecar funded and accessible; record recovery access outside this project.
- [ ] Record source/build versions, authorities, actor namespace ownership, workspace bindings and secure configuration owners.
- [ ] Obtain independent backups even though no data relocation is planned.
- [ ] Build the clone against the same backend and Supabase Auth authority. Preserve API compatibility and existing stable user IDs; do not introduce old-authority fallback or auto-import local historical executable cards.
- [ ] Review replacement web origin/Auth redirect/consent behavior and native signing, bundle identity, push and CloudKit separately. A released app’s bundle ID must not be changed casually.
- [ ] Verify current account-scoped history, memory/workspace binding, original-file access, fresh member response and separately authorized tools using section 8.
- [ ] Keep contact authority and callbacks stable unless an explicitly reviewed change is necessary. Do not provision duplicate alarms, invitations or voice agents just because a client was cloned.
- [ ] Establish who deploys the shared service. A deployment by either client project’s operator can affect every client using it.

No data migration is implied. Original project ownership/billing and shared state remain dependencies. A new client’s own media/auth configuration still requires acceptance.

## 7. Independent migration: what must move and how

### Store-by-store coverage

1. **Supabase:** actual database rows/schema/Auth UUIDs; RLS, grants, functions, triggers, constraints/indexes, extensions and migration state; Auth provider/redirect/email/signing configuration. Source SQL is not a row backup or a proven clean replay sequence.
2. **Supabase Storage:** actual object bytes, paths, MIME, size, hash and bucket policies, not only metadata. Preserve private downloads and expiry/deletion. The previously inspected bucket references are not an exhaustive live inventory.
3. **Rork durable actors:** all relevant physical namespaces plus logical IDs, SQL, KV, BLOB chunks, schemas, alarms and metadata. Six exported classes overall: `KnotShellConversation`, `KnotConversationAccount`, `KnotBackgroundAccount`, `KnotResponseLimiter`, `JasperMeetingAccount`, `WhisperLoginLimiter`. Owned-turn/contact helpers are not additional separately exported actor classes.
4. **Shell/persona/documents/artifacts:** commands, sessions, receipts, stdout/logs/Events, skills/read evidence, document programs/rejections, original byte chunks, reviews, source bindings, sharing/import records, avatar master/candidates/sets/media, revoked/consumed IDs, Stop/deletion and replay-prevention records.
5. **External sidecar:** the actual account-bound filesystem/volumes including workspace-root memory, installed/custom skills, drafts, hidden required files and retained originals/rejected outputs. Browser profiles/cookies are highly sensitive; use a supported snapshot or explicit reauthentication, not indiscriminate credential copying. Live process/session portability is not assumed.
6. **Background/contact:** responsibility revisions/runs, grants, revocation epochs, invitations, event/daily-limit ledgers and alarm intentions. Restore inert; do not reissue historical work.
7. **Other app dependencies:** Jasper meeting/business/calendar actor data; external billing, email, realtime, calendar, push and provider associations. Include independent device/browser/CloudKit identity and legitimately retained local originals; caches are not a backup.

### Addressing trap: same user does not guarantee same actor

The legacy `env.DO.fetch` transport uses `X-Rork-DO-Class` and `X-Rork-DO-Id`. Preserving those strings without preserving/mapping the underlying **physical namespace** is insufficient.

- Shell account actor ID is an HMAC using the service-role key over `knot-shell-account-v1:` plus user ID. Replacing that key can address different storage. If rotation is necessary, implement a reviewed mapping/identity transition; never retain a compromised key merely for convenience.
- Workspace binding uses `KnotShellConversation` with ID `knot-workspace-account-v1:<lowercase UUID>`. Preserve its chosen namespace and provenance; valid forms include `whisper-<UUID>` and provenance-backed `whisper-<48 hex>`. Do not merge legacy candidates or silently select a fresh workspace.
- Conversation and background accounts use account-scoped lowercase UUID addressing. Preserve their ownership relationships and all references across stores.

### Ordered migration gates

**Gate 1 — prerequisites:** establish supported export/import and namespace enumeration for every actor; supported sidecar snapshot/restore; database and actual object-byte exports; ownership and environment access; migration scope, downtime and recovery objectives. These are not all established today. If a facility is missing, design/review it separately before cutover. Do not expose a public all-account export endpoint.

**Gate 2 — consistent checkpoint:** coordinate one writer; pause new writes and outward effects; reconcile active turns using exact owned evidence. Quarantine uncertainty without replay. Take a common checkpoint or reviewed change-capture protocol across database, actors, files and callbacks.

**Gate 3 — encrypted export:** maintain a manifest with UTC checkpoint, source project/environment/code/schema, complete per-store coverage/exclusions, counts, sizes, hashes/chunk order, secure actor/workspace mapping reference, ownership, expiry/tombstones, failures and recovery instructions. Encrypt independently stored archives with owner-controlled recovery keys. General manifests must not contain secret values. Checksums establish byte identity, not completeness.

**Gate 4 — isolated restore:** production outbound networking/effects and alarms stay disabled. Restore supported schema/data/Auth, exact byte chunks, workspace files and mappings. Preserve consumed/stopped/deleted/revoked state. Pending/running history becomes inert/unconfirmed, never permission to execute. Do not resurrect expired or open-once media.

**Gate 5 — parity and rehearsal:** compare counts and hashes; verify original downloads, memory, account boundaries, RLS and revoked grants; prove old requests cannot rerun. Perform a full isolated restore with the old binary unavailable; record duration, missing coverage and data-loss window. Use fresh separately approved acceptance, not historical command replay.

**Gate 6 — deliberate cutover:** final coordinated checkpoint/delta; one authoritative writer; route clients and signed callbacks explicitly; enable only reviewed future work. Maintain a secured old service during the rollback period. No dual active schedulers or sidecar writers.

**Gate 7 — rollback:** pause writes/outbound effects; reconcile all new writes and consumed effects before switching back. A URL reversal alone can lose post-cutover writes or duplicate jobs/calls. Do not delete old services/backups until acceptance, retention review and explicit approval.

### Retention and current backup limits

Captured delivery bytes have seven-day retention and may be evicted sooner by quota. Metadata can outlive the original bytes; sidecar originals are separate. Preserve intentional expiry/deletion rather than claiming permanent archives.

The November 15 Supabase inspection reported eight completed daily physical backups, WAL-G enabled and PITR off; latest observed backup was **2026-11-15T10:43:31.623Z**, ID `2274135630`. This is a dated reported backup list, **not** a downloaded/rehearsed whole-application backup or proof of current freshness. Database backup coverage does not establish Storage bytes, actor state or sidecar volumes. Use owner-authorized supported access; do not paste privileged download credentials into chat.

### Integration-specific cutover traps

- **Contact:** current v2 tickets bind backend, owner, event and expiry using service-role HMAC. A new backend requires an additive reviewed fixed-authority mapping in the shared bridge, not arbitrary callback URLs or fallback claiming at another backend. Preserve existing consumers.
- **Voice:** private signed `knot_rork_voice_v2` bridge context, leases, signing secret IDs and provider agents/callbacks must agree with the new authority. The November 14 audit found existing callbacks still on a previous clone; the owner parked voice. No voice fix or call acceptance is claimed.
- **AI:** confirm the destination project’s supported managed credential/project/billing association. Do not transplant a private override or assume a copied environment carries service entitlement.
- **Apple/external providers:** signing, CloudKit, push tokens, webhook signatures, OAuth redirects, sender/domain identity and subscriptions are not transferred by application source. Some require reauthorization.

## 8. Acceptance plan for Knot’s tools and surfaces

This is a **future verification checklist**, not a statement that these checks ran for this document. Use synthetic data and an explicitly approved dedicated account where possible. Do not inspect personal workspaces without permission. Keep separate evidence for source inspection, mocked tests, build, actual backend execution and observed native/web behavior.

For every case retain: fresh scope/intent, UTC start/end, project/environment/build, account authorization reference (not token), request/task/call/proposal IDs, expected result, actual result, Stop/consent state, receipt/exit status, output identity/hash where applicable and exact failure/unknown. States should distinguish not run, blocked, pass, fail and uncertain. Never turn “not observed” into “passed.”

### A. Establish the actual tool catalog

- [ ] Extract current source-defined tool names, schemas, mode/platform restrictions and route allowlists.
- [ ] With approval, perform a **fresh** authenticated sidecar capabilities read through the application boundary. Save the sanitized advertised name/method/path/schema inventory and version/fingerprint. Cached schema is not fresh reachability; fresh reachability is not execution.
- [ ] Compare source projection against the live catalog. Test only the intersection actually admitted for this mode/platform/request; report missing, changed and disabled tools. Never make a capability available by widening the allowlist merely to finish a checklist.
- [ ] Inventory live installed skills/libraries through their supported owned path. Do not claim the November 11 process inventory is the current full tool/limit contract: later changes superseded several caps and document paths.

### B. Identity, basic answers and streaming

- [ ] Supabase sign-in/current user, expired/revoked session rejection, outgoing-account result rejection and cross-account denial.
- [ ] Fresh Converse/Answer response, current workspace-root memory read where required, genuinely streamed provisional text and completed answer; validate all five server-owned specialist identities and their thread isolation.
- [ ] `calculate`: valid bounded arithmetic plus unsupported expressions rejected; `web_search`: original addressed question only, real evidence and honest unavailable behavior; `react`: correct authorized message/emoji, deduplication and no replay of an older reaction.
- [ ] Stop during preparation, generation and continuation; no late answer, action, new dispatch or outgoing-account publication. Confirm events/frame terminal behavior rather than inferring Stop from a dismissed UI.
- [ ] Shared-friend replies deliver only completed authorized output without borrowing private history/native permissions; consent withdrawal blocks further sharing.

### C. Workspace and command lifecycle

- [ ] Correct current account-to-workspace binding, no namespace adoption/merge; live memory/index/required skill reads and provenance.
- [ ] `capabilities`, `session_input`, `session_status`, `session_read`, `session_close` projected only when admitted. The executor, not the model, selects/resolves sessions. Prepare is not dispatch; close evidence is not proof of remote termination.
- [ ] Exactly one fresh approved synthetic execution through client → Knot → backend → sidecar, with owned proposal, dispatch receipt, complete log/stdout and exit. No sandbox/direct-sidecar substitute.
- [ ] Distinct confirmed-failure inspection/correction, collision rejection and timeout/uncertainty reconciliation without redispatch. Historical approvals, restored cards and old sessions remain nonauthorizing.
- [ ] `skill_draft_read` uses catalog-proven names; optional `skill_draft` requires relevant read evidence and verified procedure. Housekeeping never withholds an already captured deliverable.

### D. Authoring, all formats and delivery

- [ ] Current `document_script` / document-program / `document_prepare` flow, sealed author evidence, current layout/palette binding and exact invocation admission; do not substitute the old November 11 flow or caps for current source.
- [ ] Fresh TXT, MD, HTML, CSV and JSON: exact requested format/bytes/Unicode/line endings, complete content-as-data reconstruction, fresh collision-safe output and immutable capture.
- [ ] Fresh PDF: complete authored source, actual installed build, independent every-page render/text proof and final-content comparison; inspect pagination, typography and unintended protocol text. Hash alone does not prove quality.
- [ ] Fresh DOCX/PPTX/XLSX: exact declared output path, package guards, independent render/page/cell/formula evidence appropriate to each, completeness and visual review. XML inspection is not a rendered pass; child exit zero does not override a wrapper/path/proof failure.
- [ ] Games/interactive HTML: exact local dependencies, playable controls and real interaction, restart/reopen/relaunch, original byte identity and network/account isolation. Screenshot or thumbnail is not behavior proof.
- [ ] Authenticated original download equals captured hash; human title/format/size and source conversation are correct; retention/unavailable bytes are handled honestly. Capture and delivery are distinct from build/proof.
- [ ] Share to a friend, recipient authorization and exact original bytes; save-to-workspace provenance; revocation/deletion/account switching. Never alias an old file into a new delivery.

### E. Browser

- [ ] Source browser model adapters include `browser_state`, `browser_content`, `browser_start`, `browser_navigate`, `browser_screenshot`, `browser_input`, `browser_finish` and evidence-ledger `browser_review_report`, when actually projected.
- [ ] Check current route verbs separately: state/content/screenshot/start/navigate/input/stop, tabs/tab_open/tab_activate/tab_close, back/forward/find/download, take-control/hand-back. These are not a blanket autonomous model permission list.
- [ ] `wait` and `upload` appear in extended catalog definitions but are not current public route-verb allowlist entries. An advertised endpoint does not grant it. Downloads/user-driven control and autonomous public-review restrictions also differ.
- [ ] Observe actual landed pages, content, screenshot and results after actions; public-only boundaries and private-input protection; tab ownership, handoff/return and Stop. Do not reset browser profiles, enumerate principal-wide sessions or replay uncertain clicks.

### F. Persona, media and previews

- [ ] Read/name/vibe/consent/model/candidate/pick/revert/approve/generate/media paths preserve ownership, exact master/candidate identity, revoked epochs and consumed jobs; paid operations require separate authorization.
- [ ] Native photo understanding, attached text context and Imagine use the intended Rork transport. Dedicated web photo/Imagine use delegated Cloud-only authentication, reject alternate origins/redirects and have no direct-provider fallback.
- [ ] Consent/Stop/account changes prevent sending or publishing late media. Verify failures do not switch model/provider or reuse an old generation.
- [ ] Native live HTML uses the exact protected original, isolated storage/resources and no app bridge; real touch/scroll/leave-return/restart/relaunch checks. Verify PDF/Markdown/image viewers separately.

### G. Background, creator, contact and voice

- [ ] `public_tracking`, `goal_followup`, `creator_performance`: approved scope, timezone/cadence/end/quiet-hours, actual bounded own-account metric coverage, material-change evidence and truthful unavailable reporting.
- [ ] Responsibility view/pause/delete, explicit native grants for creation/resume/contact, revocation, daily limits, alarms and update deduplication. No duplicated schedule after clone/restart/restore.
- [ ] Contact/invitation/claim path: correct backend/owner/event/expiry/signature, single claimed effect, appropriate APNs environment, no arbitrary callback/fallback; test push/call invitations only with approval.
- [ ] Voice remains a **separate parked gate** until owner authorization. Then verify current provider-agent callbacks, signed context/leases, consent, actual start/audio/answer/end/interruption and account/withdrawal handling. Token readiness or callback source alone is insufficient. Tools are not inferred from speech; web voice is not a shell agent.

### H. Native actions, persistence and final cross-platform gates

- [ ] Exact supported post/meeting/local reminder/community/follow/invitation-review proposals require the current local Allow action and authoritative result. Restored pending/running actions expire or become unconfirmed, not runnable.
- [ ] Conversations, reactions, Events, owned turns/cancel, tombstones, artifact bytes, persona and background state survive intended restart/cross-device sync without restoring authority or resurrecting deletions.
- [ ] Exercise native and web separately under slow network, foreground/background, sign-out/account change and temporary service failures. A backend pass does not prove either UI.
- [ ] Measure native active-work scrolling and actual delivered-file/game interactions. Build/unit/layout screenshots do not establish phone smoothness or the signed-Release gate.

**All-tools acceptance means the current admitted catalog and these applicable families have explicit observed outcomes, with exclusions named. It does not mean turning on every tool for every platform.**

## 9. Current evidence and unresolved holds

Use the latest dated records, not an earlier unchecked plan section, as the status checkpoint:

- **Backend selected regressions:** 574 pass; not the full suite. Full-entry compiler comparison retains 14 current / 14 inherited diagnostics, not a clean global typecheck. Latest retained managed static/build/deploy result passed at the fingerprint in section 2. Some older broader test expectations remain unresolved.
- **Native selected validation:** latest recorded 51 tests pass; simulator build `src_1ac5e36bac5f58034`. This is not current signed-in phone, Device/Release or smoothness acceptance.
- **Real execution:** November 14 dedicated native computation produced owned stdout `866525`, exit zero and a visible completed card; final narration/duplicate-proposal issues were recorded. A separately authorized owner HTML game was later captured with matching original/download bytes. These are narrow historical successes, not all-tools certification.
- **Format matrix:** November 16 supplemental review preserves 18 immutable c/d outcomes. Actual d-HTML file load/scroll and four screenshots passed that file’s visual checks; it was not Whisper UI testing. PDF issues remain, including orphaned conclusion/safety pages, protocol metadata in a letter and a mono green subtitle.
- **Office:** d-DOCX declared/measured output path differed from authored save path; no neighbor was adopted. d-PPTX build succeeded but a package guard rejected an entry whose exact name was not observed. Printer-settings binary is only a hypothesis. Independent Office rendering remains incomplete; local LibreOffice was unavailable.
- **Raw formats:** c-MD/d-TXT historical harness passes require qualification: backend content review was unconfirmed; d-TXT contained literal Markdown bold markers. Do not mark all formats accepted.
- **Owner uncertainty:** historical owner session start remains uncorrelated and quarantined. Proposal `3d6d6c3f-29f1-45ab-b00e-6fd700755e28`, task `34cf36a2-9dcd-42c4-b457-1c52997dda7e`. No authority to enumerate all sessions, clear quarantine, adopt or replay it.
- **Still open:** complete actor/sidecar export and isolated restore, current managed-key/billing association proof, current phone/file/game/Stop/account/privacy/cross-device acceptance, signed-Release performance and parked voice.

## 10. Questions for Rork/platform support and the workspace operator

### Hosted continuity and AI

1. Can ownership of this exact project/backend be transferred while retaining its project ID, origin, physical actor namespaces, secrets, billing and deployed aliases? Which resources require separate handoff, and how is rollback handled?
2. What supported procedure exports/enumerates/imports every actor’s SQL/KV/BLOB data and alarm state, including physical namespace mappings? What is excluded?
3. For the November 14 401/402 sequence, which serving managed credential/project/billing association was checked or repaired? What exact owner/platform change preceded the successful 09:20 UTC recheck? Provide safe audit IDs, not credential values.
4. How can runtime binding be verified without exporting protected managed credentials? How should replacement clients obtain delegated AI/media configuration while retaining the current backend?
5. What backup, restore and continuity guarantees exist if the original Rork project changes owner or is disabled? Do not assume source-repository availability preserves hosted state.

### Workspace/Muse and document proof

1. What supported consistent sidecar snapshot/restore covers account bindings, memory, skills, originals, hidden files and browser profile policy? How are uncertain sessions kept inert?
2. For diagnostics task `2627847c-f135-454c-b7bb-ee50235ea35d`, build `36f70d26-b9c6-4f39-baa0-1216021a6447`, provide exact utility stderr, failure phase, journal and proof-root semantics. Do not presume a collision or replay it.
3. Which exact ZIP entry triggered the d-PPTX macro/binary/embedding guard? Was it policy-forbidden content or a legitimate renderer asset? Do not relax the guard without that evidence.
4. Why did the d-DOCX measured path differ from the authored save path? Preserve both paths and original failure; do not substitute the neighboring file.
5. What authoritative owner-scoped evidence can correlate the quarantined historical session start without principal-wide enumeration or renewed execution?

## 11. Copy-paste handoff for a future clone agent

> Read this entire guide and the referenced current source before proposing changes. I want continuity with the existing Whisper/Knot service, not an automatic data migration. First report the intended project, environment, backend origin, Supabase identity, physical actor/storage dependencies and sidecar binding; distinguish reuse, hosted ownership transfer and independent deployment. Preserve Rork Cloud-only transport, all existing credentials including OPENAI_API_KEY, account/workspace ownership, Stop/consent/deletion/revocation, immutable files and consumed/uncertain state. Do not edit generated credential configuration, copy inherited/placeholder/protected keys, rotate anything, submit paid probes, execute tools, enumerate principal-wide sessions, replay historical scopes or enable schedules without separate explicit approval. Start with authorized read-only source/configuration evidence. For 401/402, identify the failing boundary and exact outer/inner status; do not infer empty visible balance, recommend payment as a proven fix or introduce a direct-provider fallback. If a managed identity/billing association is unavailable, state the gap and ask the responsible platform owner to verify it. Before any cutover, require complete supported cross-store exports and an isolated restore rehearsal; before all-tools claims, reconcile the actual current admitted catalog with observed per-family acceptance. Preserve all original evidence and report what is verified, failed, blocked, uncertain and not run.

## 12. Evidence and source index

Paths are relative to this project. Retain these references with the handoff; the guide is readable without the repository, but its linked source/evidence requires the repository. No secret or private-session files are part of this index.

- [Earlier architecture, stores and backup specification](whisper-knot-backend-spec-and-migration-20261115.md): November 15 source review and dated Supabase status/backup observations.
- [Post-cutover 402 outcome](managed-clone-transport-20261114-post-migration-outcome.json).
- [Post-second-rotation 401 outcome](managed-clone-transport-20261114-rotation-02-outcome.json).
- [09:14 auth-diagnostic 402 outcome](managed-clone-transport-20261114-auth-diagnostic-01-outcome.json).
- [Owner-fix recheck: actual Cloud 200 stream](managed-clone-transport-20261114-owner-fix-recheck-01-outcome.json). This record explicitly leaves runtime credential and billing association unverified.
- [Configuration/callback audit](clone-migration-20261114-configuration.json); [managed-store authority limitation](clone-managed-store-authority-20261114.json).
- [Supplemental format review](knot-format-matrix-20261116-supplemental-review.json): references the 18 immutable originals with their hashes and qualified outcomes.
- [Native dedicated acceptance summary](native-knot-ui-20261114-summary.json); [native HTML isolated session validation](native-knot-html-20261114-file-session-validation.json); [owner game read-only verification](owner-osrs-game-20261114-readonly-verification.json).
- [Historical process/tool inventory](../handoff/knot-process-tool-inventory-2026-11-11.md): November 11 only; not an authoritative current cap/catalog snapshot.
- [Dated implementation/incident record](../.rork/plans/faster-messages-and-coordinated-page-loa_1793859553941.plan.md): November 11 Cloud-only correction; November 14 clone/recheck/native sections; latest November 16 validation/format continuation. Later entries supersede earlier status, without rewriting original evidence.
- Current routing/AI: `functions/knot-backend.ts`, `functions/knot-ai-transport.ts`, `functions/knot-gateway.ts`, `functions/knot-key-binding.ts`, `functions/knot-upstream-error.ts`, `functions/knot-model-transport.ts`, `functions/index.ts`; `web-whisperweb/src/lib/knotBackend.ts`; native `WhisperKnotBackend.swift` under `ios/Whisper/WhisperFitnessApp/Views/Whisper/`.
- Current tools/state: `functions/knot-shell.ts`, `knot-shell-discovery.ts`, `knot-agent.ts`, `knot-live.ts`, `knot-browser.ts`, `knot-browser-agent.ts`, `knot-browser-review.ts`, `knot-documents.ts`, `knot-document-build.ts`, `knot-document-proof.ts`, `knot-document-content.ts`, `knot-artifact-sharing.ts`, `knot-persona.ts`, `knot-background.ts`, `knot-owned-turns.ts`, `knot-conversations.ts`, `knot-contact.ts`, `knot-voice.ts`, `knot-voice-bridge.ts`, `knot-voice-policy.ts`.
- Shared notification bridge: `backend/functions/whisper-knot-contact/index.ts`.

**Delivery/verification boundary:** this guide is a downloadable project document, not a Knot member-artifact capture, live backend backup or proof of a new in-app delivery. Document existence, local references and safe content can be checked without deploying anything. No new runtime acceptance or migration is claimed.
