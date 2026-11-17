# Whisper + Knot: current backend, box connection and feature report

**Prepared November 17, 2026.** This describes the Whisper/Knot application backend—not the infrastructure running this coding assistant.

## 1. Executive summary

Knot is not running entirely on the box. It is a distributed system:

- **The iOS and web apps** present chat, consent, Events, files, browser controls and native action reviews.
- **The Rork-managed Cloudflare backend** verifies users, orchestrates model requests, enforces execution rules and stores durable account records.
- **Supabase** supplies existing authentication, application database/storage and the contact/push bridge.
- **Rork AI Cloud** supplies Knot’s model transport. The configured centralized text default is `openai/gpt-4o`; this is a Rork model identifier, not a direct OpenAI connection.
- **The external box/sidecar** exposes authenticated HTTPS APIs for persistent account workspaces, shell execution, files, skills, memory and browser control.
- **Voice** adds ElevenLabs speech sessions and a signed callback to the same Rork answering transport; it is not a separate unrestricted agent.

The app does **not** need SSH to execute a Knot task. It sends authenticated application requests to the backend; the backend calls the box with a server-held token and server-resolved workspace/session identity. The model does not get that token or choose arbitrary session IDs.

**Current availability qualification:** a new unauthenticated `GET /ping` attempt on November 17 returned **HTTP 403 without a Worker build header**. This observation does not establish whether the rejection came from the app, an access layer or the request environment. It neither confirms current deployed build identity nor proves that the backend or box is down. No authenticated member, operator, AI or box check was performed for this report.

## 2. Scope and evidence labels

- **Current source:** configuration and implementation read from the present checkout on November 17.
- **Historical observation:** retained runtime, test or deployment evidence from an earlier date, explicitly identified below.
- **New observation:** only the bounded unauthenticated health request described in section 3.
- **Not verified:** a fact that would require current environment metadata, host administration, authenticated inspection or end-to-end testing.

This is an architecture/configuration report, not an all-features test result. It includes no secret values, member tokens, private memory, file contents or account-wide session inventories. No configuration, credential, deployment, provider agent, schedule or member state was changed.

## 3. Current configured services and build

### Project and clients

The source’s backend identity is **`mayokn2749ag072e3uvbh`**. This is the existing service identity embedded in the code, not a claim that every future clone or editor project has that ID.

Registered applications:

- `ios/`: Swift app, Whisper; configured bundle ID `com.mydailywhisper.whisper`.
- `web-whisperweb/`: web client.
- `functions/`: Cloudflare backend.
- `backend/`: Supabase configuration/functions.

### Knot API authority

**`https://newest-whisper-with-knot-clone-t6ui3ur-backend.rork.app`**

This exact origin appears in backend identity source, native `WhisperKnotBackend` and the dedicated web routing module. Native Debug and Release use the same Knot authority. The dedicated web client calls that origin directly; the historical hosted `/~api` alias returned 404 at cutover and is not the current fallback.

The native module sets `syncRetainedHistory = true`, with authority-change gating handled separately. That does not turn retained executable-looking history into permission to run it.

### Supabase

**`https://uryyyegnbtlmyhqlgndy.supabase.co`**

The API entrypoint’s current constant points here. The previously inspected deployment uses native Supabase Auth. The November 15 status inspection recorded the Supabase service as owner-controlled and shared with another Rork project. That sharing status is historical metadata, not newly queried today.

Supabase is not where all Knot state lives: actor databases and box files are separate.

### Box endpoint

**`https://knot-shell.mydailywhisper.com`**, expected service `knot-sidecar`, expected principal **`whisper`**.

This is the source-pinned HTTPS sidecar origin. Current DNS target, cloud provider, VM identity, IP address, CPU/RAM, OS version, disk utilization, deployed sidecar hash and supervisor configuration were **not independently inspected**. A hostname is not a host inventory.

### Source and deployment checkpoint

Current generated source stamp:

`f2910baf23bbaddc8a93b00c2b10a21d21f72dc851b710a8fdcef3c85f4f90c9`

The latest retained November 16 record ties that stamp to 101 source inputs and production artifact `923931dab1225fadbaa7bc46bff2d096`. Today’s health attempt did not return a build header, so this report does not promote the local stamp/historical deployment into a freshly verified serving build.

### November 17 health observation

- Time: **2026-11-17T04:29:24.644731+00:00**; request-start timestamp.
- Request: unauthenticated `GET` to the current origin’s `/ping`.
- Result: **403**.
- `X-Knot-Worker-Build`: absent.
- No authenticated route, member data, model call or box command.
- No diagnosis of the 403’s internal cause was established; no fallback or repair was attempted.

## 4. How the backend connects to the box

### Connection diagram

```text
Whisper iOS / web
    |
    | HTTPS application request + verified Supabase session
    v
Rork-managed Knot API
    |
    +--> Supabase: authoritative user / permitted application records
    |
    +--> Rork AI Cloud: classification, selection, authorship, answers
    |
    +--> Durable account actors: ownership, intents, receipts, history
              |
              | HTTPS + server-only SIDECAR_TOKEN_WHISPER
              v
       knot-shell.mydailywhisper.com
              |
              +--> account-bound persistent workspace / MEMORY.md
              +--> owned main shell session / files / installed skills
              +--> separately controlled browser process and profile
```

These are distinct paths. A successful model response does not prove a box command ran; a reachable sidecar does not prove AI billing/authentication works; a stored conversation does not back up workspace files.

### Authentication and transport

`sidecarRequest` reads **`SIDECAR_TOKEN_WHISPER`** from the backend environment and sends:

- `Authorization: Bearer <server-held value>`;
- JSON request bodies where appropriate;
- manual redirect handling;
- a bounded timeout, ordinarily ten seconds for the request helper;
- cancellation composed with the calling operation’s signal.

The actual secret was not read for this report. Its presence, current version, validity, expiry and revocation state are not newly verified. Missing configuration fails closed. Sidecar errors log a fixed operation class and status, not raw tokens, commands, stdout, private paths or response bodies.

The client authenticates to the **backend**, not by receiving the sidecar token. Public application routes derive user identity through `requireUser`; arbitrary caller-supplied workspace owners are not trusted.

### Account and workspace mapping

There are two identities to distinguish:

1. **Shell-record actor address:** HMAC-SHA256 keyed by `SUPABASE_SERVICE_ROLE_KEY`, over `knot-shell-account-v1:` plus user ID. This actor contains execution/document/persona records. Replacing the key without routing migration can select different actor storage.
2. **Workspace-binding actor:** logical ID `knot-workspace-account-v1:<lowercase account UUID>`, using class `KnotShellConversation`. It records the selected persistent box namespace and its provenance.

Accepted workspace IDs are `whisper-<UUID>` or `whisper-<48 lowercase hex>`. Resolution is account-based; bot and conversation are validated but do not mint an unrestricted alternate workspace. Known legacy bindings must be preserved, not merged or replaced opportunistically.

The account’s workspace and root `MEMORY.md` are shared across its Knot specialists/tasks. Their supplied private conversation threads remain separate. Execution and artifact records retain specialist/conversation/source-message authorization.

### Durable routing

The existing backend uses `env.DO.fetch` with `X-Rork-DO-Class` and `X-Rork-DO-Id` to reach durable actors. Logical IDs are not the entire hosted resource: physical namespace ownership/bindings also matter. A cloned source tree does not establish that those namespaces or their records were copied.

### Discovery and installed skills

The backend reads **`GET /capabilities`** and validates:

- service `knot-sidecar`, principal `whisper`, valid server timestamp;
- at most 64 unique, schema-validated tool definitions;
- installed skill root `/opt/knot-skills`;
- skill index `/opt/knot-skills/README.md`;
- workspace memory filename `MEMORY.md`.

Only supported name/method/path/schema combinations are projected into model tools. Global job/session/file listings and arbitrary session IDs are deliberately not offered.

Discovery can reuse a credential-fingerprinted stored schema. The in-process cache has a thirty-minute expiry, while actor-persisted session schema reuse follows separate session/fingerprint rules. A requested **fresh** check starts its own request and fails honestly rather than falling back to cache. Consequently, an advertised/cached capability is not current connectivity evidence, and current connectivity is not execution evidence.

No fresh authenticated catalog or installed-package inventory was fetched for this report. Historical endpoint counts must not be advertised as today’s complete catalog.

### Command dispatch lifecycle

1. Bind the current account, Knot specialist, conversation and latest explicit request.
2. Read live workspace-root memory; Create work discovers the installed skill index and workspace draft catalog, then relevant complete skills. Ordinary Answer/Converse does not become arbitrary work just because tools exist.
3. Prepare an immutable owned command/program. The model supplies content/code, not account/session authority.
4. Persist mutation intent before sidecar I/O. Current native foreground orchestration dispatches eligible fresh commands automatically; ordinary shell commands do not require individual Allow dialogs. Consent/admission still apply.
5. Create/attach through **`POST /sessions`** with the server-resolved workspace and terminal name `main`.
6. Validate returned workspace/session identity and existing owned-session knowledge. An unknown attached session is rejected rather than adopted or stopped.
7. Establish the log boundary, then dispatch exactly the recorded input through **`POST /sessions/:id/input`**.
8. Observe **`GET /sessions/:id`** and **`GET /sessions/:id/log?offset=N`**. Separate foreground command exit/output from a still-live persistent shell.
9. Continue only from complete owned receipts. Keep Stop, cancellation, late-result suppression and uncertain outcomes explicit.

`session_status`, `session_read` and `session_close` model adapters return current owned stored evidence; their names do not grant arbitrary provider access. The real executor owns actual provider polling/teardown. Closing foreground work is not proof the retained main shell has exited.

There is one narrow pre-input recovery for an exact confirmed “unknown session” rejection before startup/task input intent. That is not a general retry mechanism. Uncertain creation/input stays quarantined and is never automatically replayed.

### Box isolation: what is and is not established

Historical supplied-source reviews credited bubblewrap workspace/process isolation, offline Whisper shell networking, systemd resource/runtime controls and fixed-size two-gigabyte ext4 workspaces. These were reviewed/operator-reported infrastructure properties from earlier work—not a November 17 host inspection or penetration test. Do not repeat the very earliest obsolete finding that Whisper shells necessarily have public egress.

Equally, do not treat those historical source reviews as a guarantee of today’s installed build, aggregate host capacity, descendant cleanup or restart reconciliation. Current host allocations, cgroup state, free space, snapshots, package versions and physical storage limits remain unverified in this report. Browser networking is a separate controlled service path; an offline shell does not mean public browser navigation is impossible.

## 5. Model configuration and the division of work

The centralized backend transport reads:

- `EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY`: managed AI credential selected by source;
- `EXPO_PUBLIC_TOOLKIT_URL`: optional validated gateway base;
- default base `https://toolkit.rork.com` when no override is set.

It constructs `/v2/vercel/v1/chat/completions`, `/v2/vercel/v1/responses` and `/v2/vercel/v1/messages` paths. Gateway validation requires HTTPS with no URL credentials, query or fragment, and preserves a configured path prefix.

The default centralized text model is **`openai/gpt-4o`**. The actual stage-specific requested model and observed returned identity must be recorded for each call; a configuration name does not prove which upstream provider/model executed a rejected request. The box is not shown running that language model locally.

Current Knot text has **no direct OpenAI/provider fallback and no private copied-key override selection**. Preserve unrelated `OPENAI_API_KEY` dependencies; its presence in broader application environment types does not make it the current Knot text transport.

The credential’s legacy `EXPO_PUBLIC_` prefix is not permission to expose it in browser bundles or extract/copy it. Dedicated web media uses delegated authentication and restricts requests to the official Rork gateway. `openai/gpt-4o` vision and `openai/gpt-image-2` Imagine are source-configured Rork model identifiers.

No model request was made today. Managed environment metadata, serving credential identity and its project/billing association were not newly inspected.

## 6. Knot feature inventory

“Implemented” below describes current source and retained implementation evidence; it does not imply a new live test of every feature.

### 6.1 Five Knot identities and conversational modes

- Knot (`main`), Writing Knot (`writer`), Research Knot (`researcher`), Planning Knot (`planner`), Community Knot (`social`).
- Server-owned jobs and identity; optional main-agent nickname/vibe are presentation data, not permission or instruction authority.
- Converse, Answer and Create work modes with different admitted tools and prerequisites.
- Private text streaming, separately completed shared-friend answers, account-scoped conversation history and reactions.
- Live persistent memory reads; unavailable reads do not imply memory is empty or nonexistent.
- Latest explicit request controls scope. Old memory, files and saved plans cannot authorize restarting tasks.

### 6.2 Arithmetic, public search and reactions

- `calculate`: bounded arithmetic grammar, not arbitrary evaluation/code.
- `web_search`: searches the originally addressed question, not private context or an arbitrary model-selected query.
- `react`: authorized current message and exact emoji; deduplication and old-call replay guards.

These are different mechanisms from executing a shell command or driving the browser.

### 6.3 Workspace computation and code execution

- Backend-prepared immutable commands, persistent account workspace/main terminal, actual stdout/stderr/exit/completeness receipts.
- Model-projected `capabilities`, `session_input`, `session_status`, `session_read`, `session_close`, conditionally admitted from validated discovery.
- Task-specific ownership, source-message binding, phase/status/Events, cancellation and no uncertain replay.
- Shell commands are distinct from native personal-product writes and from background Responsibilities.
- Current work accounting separates infrastructure/required skill reads from charged work under a shared runaway ceiling. Earlier fixed three-skill/twelve-total-command descriptions must not replace current source policy.

### 6.4 Memory, skills and learning

- Workspace-root `MEMORY.md` read from real owned evidence, not a fabricated backend-preloaded memory snapshot.
- Installed skill library discovered at runtime; complete relevant skill reads can be cached only with actual session/provenance binding.
- Workspace draft catalog, catalog-authorized `skill_draft_read`, optional `skill_draft` after verified work and relevant creation-guide reads.
- Draft learning remains workspace-local, not automatic promotion into the installed read-only library.
- Optional completion notes/learning must not prevent an already captured file being delivered.

### 6.5 Document and file creation

- TXT, Markdown, HTML, CSV and JSON: fresh content-as-data authoring/reconstruction with exact format and byte binding.
- PDF and Office: source/build paths plus independent structure/text/page/cell proof appropriate to format and content comparison.
- Current document adapters include source/build invocation and sealed author/program preparation paths; they are backend adapters, not assumed installed box executables.
- Fresh task-scoped paths, collision refusal, preserved rejected files and no substitution of neighboring/archived output.
- Layout/palette/source receipt binding; meaningful human title and format metadata.
- Immutable private capture, byte/hash verification, protected original download, source conversation and account authorization.
- A build or exit-zero command is not delivery, and a SHA match is not visual/factual certification.

Formats are not all accepted at runtime: see section 10 for observed PDF/Office/raw-format gaps.

### 6.6 Games and interactive HTML

- Authored self-contained HTML/game artifacts with measured local dependencies and immutable original bytes.
- Native live original-file preview with account/artifact-isolated storage, local-resource restrictions, no app bridge and explicit Restart behavior.
- Inline/expanded continuity is implemented; actual game controls, touch, scroll, battle/animation and relaunch acceptance require observed interactions, not screenshots.
- Download/share the original, not a recreated approximation. Unknown formats use safe opaque handling rather than automatic execution.

### 6.7 Files shared with friends

- Native “Send to a friend” uses existing recipient review and ordinary DM delivery.
- Received artifact cards retain sender/title/original identity; protected viewing and save-to-workspace preserve provenance.
- Sharing is not a grant to execute old commands or adopt another person’s workspace.
- Web/native feature parity must be checked individually; native implementation is not evidence of a matching web control.

### 6.8 Browser / Computer surface

- Actual sidecar browser state/content/PNG screenshots and start/navigate/input/stop operations.
- Route-level tabs, open/activate/close tab, back/forward/find/download, take-control/hand-back, subject to live shape and ownership checks.
- `wait`/`upload` appear in extended endpoint definitions but are not current public route-verb allowlist entries. Catalog presence alone does not enable them.
- Autonomous public-browsing tools include finish/report evidence controls. Their restrictions differ from user-driven Computer controls; a route is not a universal autonomous permission.
- Actual screenshot/content evidence, not generated pictures. Opening the viewer does not itself prove that a browser was started or an always-running desktop exists.
- Public navigation and review do not authorize sign-in, private accounts, purchases, uploads, messages or arbitrary sensitive inputs.
- Existing browser profiles are separate sensitive box state and must not be reset to bypass ownership or uncertainty.

### 6.9 Persona, nickname and avatar media

- Account-owned name/vibe, consent, available models/candidates, pick/revert/approve/generate/media APIs.
- Persisted master/candidate/derived sets, traits, exact private media chunks and job outcomes.
- Revocation epochs and consumed generation IDs prevent restored records from causing new paid generation.
- Capacity checks include 64 MiB of private persona media in source; a capacity bound is not a backup policy.
- Main persona presentation does not alter specialist job/tool/safety authority.

### 6.10 Photo understanding, text attachments and Imagine

- Explicitly attached photo analysis and extracted text context.
- Image generation via managed Cloud media, with consent/account/Stop guards.
- Dedicated web transport rejects alternate origins/redirects, uses delegated authentication, and does not retry by changing provider/model.
- A retained text conversation is not an archive of the original attachment bytes.

### 6.11 Responsibilities and creator monitoring

Three supported server-alarm kinds:

- `public_tracking`: approved public topic/query and material evidence.
- `goal_followup`: scheduled question/next step, not surveillance or proof of progress.
- `creator_performance`: separately approved eligible own-account counters with bounded coverage, not universal private analytics.

Rules carry account/Knot/conversation, revision, timezone, quiet hours, interval range, end, runs/findings and permission state. Minimum interval options in source are 60/180/360/1440 minutes, maximum 10,080; native proposals cap at thirty days and server admission at thirty-one. Quiet hours defer work/messages.

Native review creates/resumes grants; web can view/pause/delete existing rules. This is not an arbitrary background shell. Cloning/restoring must not duplicate alarms or reactivate historical pending work.

### 6.12 Contact, push, welcome and invitations

- Off-by-default scoped contact grants, actual persisted updates and deduplicated claims.
- Supabase `whisper-knot-contact` bridge validates fixed backend authority and signed v2 backend/owner/event/expiry tickets.
- APNs delivery and call invitation are separate from a connected microphone/call.
- Welcome/invitation state and seen/revoked/consumed history are persisted to avoid duplicate effects.
- No arbitrary callback derived from user ticket text and no fallback claim at a different backend.

### 6.13 Voice

- ElevenLabs provides speech-session/audio behavior; the private signed completion bridge uses the current backend’s `/knot/voice/completions` and Rork answering transport.
- Routing marker `knot_rork_voice_v2`; HMAC-signed per-call context; content-free revocable leases in `KnotResponseLimiter`; bounded twenty-minute lease/context.
- Token/end/completion paths have separate identity/policy gates. Fresh voice sharing and optional profile/recent-text sharing are distinct choices.
- Optional native `ask_knot` relay forwards the actual finalized transcript once to the normal native text/review pipeline. The voice bridge itself does not gain arbitrary workspace tools; web voice is tool-free.
- Source policy disables model fallback, recording and forwarding, and requests one-day provider retention. This is not a zero-retention guarantee or a current provider-side audit.
- **Voice remains parked:** last retained callback audit found provider agents still bound to a previous clone. Source correctness is not evidence of retargeting, actual startup or audio success.

### 6.14 Native personal-product actions

Exact current supported proposals include posting, meeting creation, local-device reminders, canonical community join, following and invitation review. Each requires the member’s explicit local review/Allow and an authoritative result. The server model cannot silently write to Whisper.

Saved/restored proposals do not retain live execution permission. A local reminder is not Apple Reminders sync; creating a meeting is not proof of invitations sent. These actions do not execute through the offline shell merely because the model requested them.

### 6.15 Events, Stop and cross-device history

- Owned turns, cancellation, durable ordered evidence and source-bound task/command Events.
- Native task presentation, phases, receipts, protected file cards and history synchronization.
- Stream framing/completion guards; late/outgoing-account/withdrawn-consent result rejection.
- Restored history remains display/history, not execution authority.
- Quiet/silent failure policy can leave the visible chat without narration while Events retain a failure. An idle screen alone does not establish successful completion.

## 7. API and persistent store inventory

### Principal API families

- `/knot/chat/stream`: authenticated streamed Knot turn.
- `/knot/conversations` and descendants: account conversation synchronization.
- `/knot/turns` and descendants: owned task/turn state and cancellation.
- `/knot/shell/…`: scoped capabilities, memory, proposal/execution, status/log/receipt, cancellation, Events, permission and documents; verify exact verb in source before use.
- `/knot/browser/…`: validated browser route/control surfaces.
- `/knot/artifacts/…`: sharing/import and original-artifact behavior.
- `/knot/documents` DELETE: account-owned document erasure dispatch.
- `/knot/persona/{read,name,vibe,consent,models,candidates,pick,revert,approve,generate,media}`: authenticated bounded persona requests.
- `/knot/background` and descendants: rules, grants, messages and responsibility controls.
- `/knot/voice/token`, `/knot/voice/end`, `/knot/voice/completions`: distinct member/provider boundaries.
- `/internal/knot/contact-claim`: signed internal event claim, not a general public notification interface.
- Operator diagnostics: `/admin/knot-text-policy`, `/admin/knot-key-binding`, `/admin/knot-text-transport`, `/admin/knot-voice-policy`.

A route inventory describes boundaries, not authorization to call them. In particular, POST text-transport diagnostics generate real paid model output.

### Durable actor classes and contents

- **`KnotShellConversation`:** shell records/session ownership, command logs/Events, workspace-binding records, skill evidence, document programs, persona and artifact metadata/bytes, Stops/rejections/tombstones.
- **`KnotConversationAccount`:** account conversation/message JSON, reactions/Events/preferences and related bindings.
- **`KnotBackgroundAccount`:** rule revisions/runs/messages, grants/contact/welcome state and owned-turn history.
- **`KnotResponseLimiter`:** response-security/rate-limit behavior and voice leases.
- **`JasperMeetingAccount`:** separate meeting/business/calendar state, relevant when discussing the whole shared backend.
- **`WhisperLoginLimiter`:** login/security state.

Owned-turn and contact stores are helpers inside existing actors, not automatically separate exported actor namespaces.

### Outside actor storage

- Supabase database/Auth and actual Storage objects.
- Box filesystem, root memory, skills/drafts/originals and browser profile state.
- Native/browser private caches/settings/original copies and sessions.
- Selected CloudKit data in `iCloud.com.mydailywhisper.whisper`.
- Voice, push, billing, OAuth and other external provider state.

No single one is a complete backup of the others.

### Retention and limits

Source document capture limits include **50,000,000 bytes/file**, **200,000,000 bytes/account**, **500 cards**, up to **300 measured pages**, and seven-day byte retention with quota eviction possible earlier. Metadata can survive after bytes disappear. Independent box originals are a different store. Do not promise permanent download availability from a saved card.

## 8. Configuration names and security responsibilities

Values are intentionally omitted. This is not a fresh complete environment enumeration.

- `SIDECAR_TOKEN_WHISPER`: backend → box bearer authorization.
- `SUPABASE_SERVICE_ROLE_KEY`: server privileged access, shell actor-address HMAC and contact signing dependencies; rotation affects more than database requests.
- `EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY`, optional `EXPO_PUBLIC_TOOLKIT_URL`: current managed model transport contract. Do not manually copy protected values into a clone or client.
- `BROADCAST_SECRET`: operator diagnostic authorization through `X-Whisper-Operator`, not member authentication.
- `KNOT_VOICE_BRIDGE_SIGNING_KEY`, `ELEVENLABS_KNOT_BRIDGE_SECRET_ID`, `ELEVENLABS_API_KEY`, `ELEVENLABS_AGENT_ID`, `ELEVENLABS_RELAY_AGENT_ID`: separate signed bridge/provider-agent configuration.
- Contact bridge: `SUPABASE_URL`, server role credential and APNs team/key/bundle/private-key/environment settings.
- Preserve unrelated `OPENAI_API_KEY`, billing/webhook, email, realtime/TURN, calendar and Apple configuration until their own consumers are reviewed.

Account authorization, consent, Stop, immutable command intent, deletion/revocation and replay prevention are independent of secret possession. A valid server token must not become permission for a model to enumerate all sessions or adopt unknown work.

Operator presence checks do not prove credential identity or billing. The key-binding helper returns only comparison flags and does not send an AI request; it requires an authoritative candidate through a supported authorized path. Do not bypass protected reveal restrictions. Environment metadata is not proof of serving key bytes.

## 9. 401/402 status in context

These errors occur on different connections:

- Member API 401: Supabase session/account boundary.
- Sidecar 401: box token/principal/host boundary.
- Rork upstream 401: model credential/authentication boundary.
- Rork upstream 402: quota/project/billing rejection; not proof of the owner’s visible balance.
- Operator 403: operator permission boundary, where identified.
- Today’s unauthenticated `/ping` 403: rejection layer not established; do not conflate it with an authenticated operator or AI error.

On November 14, repeated rotations changed observed failures between 402 and 401 without establishing recovery. After the owner reported a fix, the **09:20 UTC** fresh recheck genuinely returned Rork upstream 200, twenty frames and a valid terminal completion. No agent code/key/configuration change occurred between the latest failed diagnostic and that success. The actual credential/project/billing repair was not independently identified.

That is a historical successful Cloud connection, not a current all-tools health assertion. Never reuse those consumed diagnostic scopes or introduce a direct-provider workaround.

## 10. Verified history and remaining gaps

### Retained successful evidence

- November 14 dedicated native computation: actual owned box execution, complete stdout `866525`, exit zero and a visible completed native card. That run still had final-narration/duplicate-proposal issues; do not call the whole flow flawless.
- November 14 separate owner HTML-game task: real box original and protected download had matching size/hash and captured chat binding. Gameplay/touch acceptance was not established by capture.
- November 16 selected backend regressions: **574 pass**, not the full backend suite.
- Full-entry compiler comparison: **14 current / 14 inherited diagnostics**, not a globally clean typecheck.
- Latest retained native selection: **51 pass**, simulator build `src_1ac5e36bac5f58034`; not current signed-in phone/Device/Release acceptance.
- November 16 supplemental review: eighteen preserved format outcomes; actual d-HTML load/scroll/screenshots passed that file inspection, not Whisper UI interactions.

### Open or blocked

1. **Fresh current connectivity:** no authenticated sidecar capabilities, operator policy, member turn, AI call or tool run was performed today. The new unauthenticated health request was 403 without build identity.
2. **Host verification:** live physical box specs, installed sidecar/build/packages, isolation/resource configuration, capacity and restore state are unverified.
3. **Owner uncertainty:** historical owner session start remains quarantined without authoritative scoped correlation; no permission to enumerate all sessions, clear it or retry.
4. **PDF presentation:** orphaned ending/safety pages, a protocol metadata leak in a letter and a green subtitle in a monochrome output remain recorded issues.
5. **Office:** d-DOCX output-path mismatch; d-PPTX package guard rejected an entry whose exact name was not observed. Printer-settings binary remains a hypothesis. Independent Office rendering was incomplete; local LibreOffice unavailable.
6. **Raw-format review:** some historical Markdown/TXT harness passes had unconfirmed backend content review; TXT contained literal Markdown bold markers.
7. **Native runtime:** delivered previews, real touch/gameplay/relaunch, active-work smoothness, signed-Release, Stop/account/privacy and cross-device acceptance remain partial or unverified.
8. **Voice:** parked, with prior callback mismatch; no current successful call/audio evidence.
9. **Recovery:** no complete coordinated actor/BLOB/KV/alarm + Supabase object bytes + sidecar backup/restore rehearsal established.

## 11. Operational implications and recommended next verification

For continuity, keep the existing backend/Supabase/box alive rather than assuming a client clone copied them. A real independent migration needs namespace mapping, exact byte exports, consistent checkpoints and inert restoration of pending work; hosted ownership transfer has not been established.

A sensible next **separately approved** verification sequence is:

1. Resolve the new `/ping` 403 using safe response-layer/request evidence; do not guess a secret or change routing.
2. Verify exact serving Worker/actor build and read-only environment/policy presence without exposing values.
3. Fresh sidecar discovery through the intended backend, without session creation; reconcile source projection with the returned current catalog.
4. Obtain operator-provided content-free box build/host/supervisor/capacity/snapshot metadata. Do not execute stress/escape tests or request SSH credentials as a shortcut.
5. If desired and explicitly authorized, submit one fresh synthetic member turn and one fresh owned box task, each with unique consumed intent and correlated actual receipts. No old-scope replay.
6. Test each requested native/web feature using actual interactions. Keep voice, paid media, notifications and schedules separately authorized.

This report authorizes none of those follow-up actions by itself.

## 12. Sources and companion documents

### Current source inspected for this report

- `rork.json`.
- `functions/knot-backend.ts`, `knot-source-build.ts`, `knot-ai-transport.ts`, `knot-gateway.ts`.
- `functions/knot-shell-discovery.ts`: sidecar origin/authentication, schema validation/cache and least-privilege tools.
- `functions/knot-shell.ts`: environment, workspace/actor addressing, session ownership/recovery, receipt and route boundaries.
- `functions/knot-agent.ts`: identities, current platform/memory/tool contract, native review actions and arithmetic/search.
- `functions/index.ts`: Supabase authority, actor exports and public/operator/voice route boundaries.
- `functions/knot-background.ts`, `knot-browser.ts`, `knot-voice-policy.ts`, `knot-voice-bridge.ts`; document/persona capacity constants and web Cloud-media source matches.
- `ios/Whisper/WhisperFitnessApp/Views/Whisper/WhisperKnotBackend.swift`.
- `web-whisperweb/src/lib/knotBackend.ts`, `knotCloudMedia.ts`.

### Retained evidence and fuller handoffs

- [Backend architecture, stores and recovery specification — November 15](whisper-knot-backend-spec-and-migration-20261115.md).
- [Clone continuity and 401/402 recovery guide — November 16](whisper-knot-clone-continuity-and-401-402-recovery-20261116.md).
- [Cloud owner-fix recheck — actual upstream completion](managed-clone-transport-20261114-owner-fix-recheck-01-outcome.json).
- [Historical configuration and callback audit](clone-migration-20261114-configuration.json).
- [Native dedicated-run summary](native-knot-ui-20261114-summary.json).
- [Owner game byte/capture verification](owner-osrs-game-20261114-readonly-verification.json).
- [Format supplemental review — eighteen immutable outcomes](knot-format-matrix-20261116-supplemental-review.json).
- [Dated implementation/incident record](../.rork/plans/faster-messages-and-coordinated-page-loa_1793859553941.plan.md), including historical box hardening reviews. Later sections supersede earlier status without overwriting evidence.

**Bottom line:** the box is connected in source through a server-authenticated, account-bound HTTPS sidecar—not SSH, not a local language model and not direct client access. The repository contains broad Knot functionality with real narrowly scoped historical execution successes, but present configuration, fresh service reachability, host deployment and every feature’s runtime acceptance are separate questions. This report preserves those distinctions rather than claiming everything is currently working.
