# Knot: process and tool inventory for Muse

Source-reviewed snapshot: November 11, 2026. This is a shareable description of the implementation, not a permission grant, an execution request, a live installed-software inventory, or proof that every flow works at runtime. It contains no credentials, private conversation content, or workspace file bodies.

## 1. Core division of responsibility

**Plumbing in code, authorship with the agent.** The answering agent chooses content, reasoning, relevant genuinely read skills, source, design and installed conversion routes. Code owns account/session identity, execution boundaries, consent, limits, receipts, independent verification and private byte capture. A capability description is not evidence that a command ran; a workspace path is not a delivered download.

Knot has five server-owned identities: Knot, Writing Knot, Research Knot, Planning Knot and Community Knot. They share the answering transport but have distinct jobs and supplied private threads. A specialist does not receive another specialist’s private thread. The account-owned persistent workspace and workspace-root `MEMORY.md` are shared across that account’s tasks/specialists; command and delivery records still retain specialist/conversation authorization.

The latest explicit request controls scope. Memory, old questions, quoted replies, archived files and earlier plans are reference data, never authority to revive an unfinished task. Shared-friend answers have narrower context and cannot borrow private history/profile or native action permissions.

## 2. Main request processes

### Conversation and answering

- The work-state modes are Converse, Answer and Create. Answer/Converse do not consume task-skill reads.
- Ordinary private text conversation uses one fixed owned live read of current workspace-root memory, not a backend-preloaded memory snapshot. Preparation, execution and receipt polling have a twenty-second bound; exact owned best-effort cancellation has a separate at-most-five-second allowance.
- After that conversation-only read, the agent gets no task-shell, skill-write or document continuation tools for that turn. Missing/unavailable memory is disclosed narrowly where relevant, not described as nonexistent persistence or invented facts.
- Capability/connection questions can be answered from actual connection evidence without running a task to prove connectivity. Reusable endpoint schemas do not establish present reachability.
- Genuine provider text streams to the client. Internal control envelopes remain hidden; ordinary code fences, backticks and tag examples are not intended to freeze visible streaming. Shared conversations deliver a completed answer rather than provisional private text.

### Foreground workspace work

1. Resolve the original account, specialist, conversation and current explicit request.
2. Read live workspace memory at task start. For Create, discover the live skill index followed by the bounded workspace-draft catalog.
3. Read up to three actual relevant full skills/drafts combined. Only document Create requires the actual indexed document-creation guide; a game or other object needs its relevant guides, not an automatic document guide.
4. Prepare at most one new immutable command per model response. Preparation itself is not execution. The owning foreground native chat dispatches eligible fresh commands and continues only from real owned receipts.
5. Observe completion, preserve failures and stop on uncertainty. A confirmed failed command can permit a distinct owned inspection and genuinely new correction, never automatic replay.
6. Complete/capture the requested result before optional memory or skill learning. Housekeeping cannot become a prerequisite that withholds an otherwise delivered file.

The executor, not the model, creates/resolves sessions, dispatches input, polls real completion, applies Stop and manages ownership. The model cannot choose session IDs or adopt an uncertain session. Ordinary shell work has no individual command-approval dialog; native personal-product writes have a separate exact approval process.

## 3. Actual model-callable tools

Availability below is conditional on the current request, mode, consent, live endpoint projection, remaining budget and owned evidence. This is not a promise that the whole list is supplied on every turn.

### Answer tools

- **`calculate`** — `expression`. Bounded arithmetic grammar using numbers, decimals, parentheses and `+ - * /`; no evaluation of arbitrary code, variables, dates or implicit percentages.
- **`web_search`** — no model-selected query argument. Searches the original explicitly addressed question only. Returns real completed search evidence and validated source URLs or an honest unavailable result. History, files and profile cannot be supplied as a custom search query.
- **`react`** — `message_id`, `emoji`. Places one exact Unicode emoji grapheme on the current authorized user message. Optional; no default emoji or fixed emoji list. Replacement is possible. Identical current emoji is a durable no-op, not a new revision/event/haptic request. Recorded old call identities cannot restore an earlier reaction after a later change. A reaction is not approval, a reply, a push or proof of delivery.

### Live-projected workspace tools

- **`capabilities`** — validated endpoint snapshot; a schema is not a fresh connectivity check.
- **`session_input`** — `data`, containing one complete command. Prepares a bounded immutable command for the executor; it does not directly dispatch stdin. For non-document work this is the scoped Bash-command adapter. In document workflows it is limited to prerequisite/skill reads and permitted full relative-file reads; authoring/building goes through `document_script`.
- **`session_status`, `session_read`, `session_close`** — no model-selected session IDs. Return stored evidence for the server-resolved current owned execution. They do not redispatch work. Close reports foreground termination separately from the retained provider session; it is not a remote Stop command or proof that the shell is dead.
- **`document_script`** — `stage` (`source`, `build`, `existing`), `interpreter` (`python3`, `bash`), complete pure agent-authored `code`, relative `path`, `title`, `deliveryLabel`. Backend invocation/measurement adapter, **not an installed droplet executable**. The agent does not author outer invocation wrappers or measurement/receipt emitters. Empty presentation strings use fallbacks. Legacy stored invocations without the added label fields remain supported.
- **`skill_draft_read`** — `name`. Full bounded read of an actual draft name from the successfully read current workspace catalog. Guessed names are rejected before dispatch. Counts toward the same three-skill total; catalog text is not a full draft read.
- **`skill_draft`** — `name`, `trigger`, complete `content`, `memoryNote`. One optional closing workspace-only draft write/amendment after actual successful requested work, and after private capture for documents. Triggers: `repaired_failure`, `verified_procedure`, `environment_fact`, `library_amendment`. Requires the indexed skill-creation guide; amendments require the complete existing draft read, its expected hash and revision preservation. The agent authors the procedure and honest acceptance. No library promotion/install follows automatically.

A failed optional draft read does not count as guidance. It can permit the exact distinct owned failure inspection and then continuation using successfully read required guides, without retrying that failed read. The twelve-command ceiling and mandatory document guide still apply.

### Dedicated native foreground browser tools

Only an explicit eligible public-browsing request receives autonomous browser actions. Each actual endpoint must be available; browser tools are not granted to speech, shared replies, scheduled work or web’s read-only shell surface.

- **`browser_state`, `browser_content`** — real current browser observations, not a claim the browser exists merely because discovery advertises it.
- **`browser_start`** — start the scoped browser.
- **`browser_navigate`** — explicit public `url`.
- **`browser_screenshot`** — actual provider screenshot, not a generated illustration.
- **`browser_input`** — observed-purpose `kind` (`focus`, `type`, `key`, `click`, `scroll`) with the applicable `selector`, public-search `text`, supported `key`, coordinates or scroll delta. Inapplicable fields are null. Private context/credentials are not allowed in public search text or URLs.
- **`browser_finish`** — `outcome`: `complete`, `boundary`, `unavailable`. For a request only to open a URL, a successful requested navigation and landed public URL/title can complete it. Research requires actual supporting page evidence.
- **`browser_review_report`** — evidence-ledger-backed site/page review output. Coverage derives from actual visited pages, content, screenshots and scroll observations. Unverified coverage must remain partial, not described as a full-site review.

The browser window is bounded to 48 tool calls and 285 seconds. Reobserve after changes; a click/input acknowledgment does not prove the intended result. Reviews require real traversal and fresh screenshots after downward scrolling, with honest coverage limits. Sign-in, credentials, purchases, permissions, private accounts, uploads/downloads and sending messages are boundaries, not available capabilities. Uncertain input is never replayed. Existing browser profiles must not be replaced or reset to bypass this.

## 4. Document workflow and delivery

For a new document, the default is fresh authorship rather than substitution of an earlier final:

1. Read actual relevant source/reference content in full, the indexed live document guide and workspace inventory.
2. Author and measure a complete new Markdown/semantic-HTML source at a fresh task-scoped path.
3. Independently rehash/read that source and complete successfully read textual references; run an early source-versus-request completeness comparison. Specific omissions can guide full reference reads and a genuinely new corrected source before build slots are spent.
4. After actual source approval, the agent supplies its own complete installed-guide conversion code and fresh final path. Code invokes and measures; it does not choose document content, layout or a renderer for the agent.
5. A separate server-derived owned verifier checks final structure, extracts/scans actual text and renders **every page**. Office rendering/page measurement is part of this independent process. New workflows accept structurally valid outputs from any installed renderer: Producer branding is not an authorship or validity allowlist.
6. Compare the complete measured source/reference text, all extracted final text and original ask. Missing relevant evidence, omissions, uncertainty or oversized complete evidence blocks delivery honestly. Matching a stub source to its own stub PDF is insufficient.
7. Capture and independently rehash exact final bytes into an authenticated immutable private delivery record. Only this record permits an attached/downloadable claim.
8. Optional image-based visual review is separate and separately consented. Optional factual completion memory and closing skill learning follow delivery, within the remaining budget.

**Independent layers:** measurement is not proof; mechanical proof is not a content-completeness pass; a text-AI pass is not factual, formula, visual, accessibility or human certification. Optional visual review can be incomplete without falsely labelling an already captured file undelivered.

`existing` with empty code is restricted to a final explicitly named for retrieval in the current original request. Editing/rebuilding, negative mentions, memory, inventory and old cards do not authorize it. Archive retrieval requires the full archive path in that request. It still needs the applicable proof/content/capture gates and establishes current byte inspection, not historical authorship.

All previous/rejected/undelivered files remain preserved. Corrections need genuinely new authored source/build and distinct paths, never overwrite, alias, copy or automatic adoption. Completion slots are reserved inside the unchanged command cap; required source/build/proof steps cannot be skipped to fit optional work. Exact confirmed-failure inspections remain charged.

A task-local duplicate guard identifies declared source/conversion inputs even if names change. Narrow continuation can use the **original** successful build/proof in current owned ancestry, only with complete unambiguous unrejected evidence. Content review, rehash and immutable capture still apply. This is not a general artifact cache, a dependency/environment fingerprint or permission to reuse failed/uncertain files.

New validation is versioned `structural_v2`. Historical exact command reconstruction retains its recorded legacy policy; historical commands are not replayed or silently rewritten to apply the new rules. The new markup gate targets whole accidentally unrendered HTML documents, not every legitimate code, math, Markdown or tag example.

### Labels and other artifact formats

- Every document style can supply a human `title` and custom `deliveryLabel`, e.g. Event brief, Research report, Budget workbook, Slide deck. These are presentation only; immutable path/hash/download bytes remain unchanged.
- Non-document games/HTML/files use the ordinary live-authored command adapter and measured manifest protocol. This is distinct from `document_script`; protocol output is data, not a helper executable.
- Safe lowercase 1–16-character extension tokens are accepted for other artifacts. Unknown formats use `application/octet-stream`, native save/share-only handling and opaque web downloads; they are never automatically executed or falsely advertised as playable.
- HTML/game previews require complete local dependencies, inline or in the measured bundle. Preview isolation removes network, account credentials and workspace access. Broad format delivery does not bypass PDF/Office/document proof/content gates.

## 5. Native app actions are review proposals, not shell tools

Native supports at most four deduplicated exact proposals for explicitly requested supported actions. Each needs its own local Allow tap, current account/context and authoritative result. The model cannot approve them, set always-allow or manufacture success.

- **Post:** exact supplied caption/eligible community; publishes as the current member under existing privacy/access rules.
- **Meeting:** exact title/date; ordinary meeting creation does not send invitations.
- **Reminder:** one local notification on this device, not Apple Reminders or cross-device reminder sync; removed on account switching.
- **Community:** canonical catalog membership/interests operation, not a made-up community ID.
- **Follow:** exact account target; private accounts can receive a follow request rather than an immediate relationship.
- **Invitation review:** the internal `tool` proposal opens the existing scheduling/recipient review. That approval itself submits no invitation and is not generic navigation/shell permission.

Restored pending proposals expire; restored running ones become unconfirmed. Saved chat cards do not restore permission or automatically rerun actions. Other app destinations remain normal app navigation, not model-created tools. Existing eligibility, membership, billing and per-record access remain authoritative.

## 6. Scheduled responsibilities, creator reads and contact

Responsibilities are narrowly approved server alarms/read-report checks, not arbitrary background sessions or shell jobs.

- **`public_tracking`:** approved public topic/query and material new evidence; no private context in the search.
- **`goal_followup`:** scheduled question/next step, not observation that the person made progress or finished a goal.
- **`creator_performance`:** separately consented eligible own-account metrics read, not universal Creator Studio/private-account access.

The exact native contract agrees title/instruction, fixed timezone, whole-hour quiet hours, cadence/range and end date before approval. Minimum interval choices are 60/180/360/1440 minutes; maximum is at most 10,080 minutes. Native proposals cap duration at thirty days; server admission permits at most thirty-one. Quiet hours defer work/messages. Fixed and adaptive timing must be agreed, not silently rounded. Web can view/pause/delete existing rules; creating/resuming grants and contact permission require native review.

The creator reader covers current own follower count and the newest hundred authored posts in the thirty-day window, with available likes/comments and top-three summaries. These are current totals on those posts, not reach or interactions occurring solely in that window. Limited coverage and estimated baseline/score are explicit; it cannot read other members’ private data or guarantee growth.

Push and call invitations are separate off-by-default grants tied to actual persisted updates and current rule revision. At most one genuine call invitation per account per twenty-four hours. A grant or notification does not capture the microphone, initiate an answered call, or establish call connection. End/expiry/pause/revocation constrain future work; no historical job recreation is implied.

## 7. Voice, attachments and saved text

Native conversation/invitation/welcome and web conversation/welcome speech are routed to the same Rork answering transport, GPT-4o and selected server-owned Knot identity through a private signed bridge. ElevenLabs provides the speech-session layer, not a separate default answering persona. There is no direct-provider answering fallback for updated Knot clients.

Fresh voice-flow sharing consent is required. Profile/recent-text sharing remains separately optional. Native’s separately optional `ask_knot` relay submits an actual finalized transcript once to the existing text/native-review pipeline; the bridge itself has no workspace tools. Web voice is tool-free. Tools/permissions must not be inferred from spoken requests, history or old toggles.

Per-call signed context and revocable content-free leases bind identity/account/scope without handing managed app credentials to the speech provider. End/withdrawal/background/account changes constrain the exact owned call. Offline revocation is best effort; stranded leases expire within twenty minutes. Interruption/cancellation never authorizes adopting or replaying a late call.

Recording is off and provider conversation history is configured for one day. **This is not a zero-retention promise** about provider processing, derived records or backups. The native SDK remains pinned to 3.4.0 with the complete callback-preserving startup factory.

An explicitly attached native photo goes through the existing image-description path; attached text files are extracted and supplied as context. These are not arbitrary model-selected shell/private-account tools. Saved private conversations synchronize account-owned text, reactions and links between native/web. They do not archive attachment bytes or session-only voice transcripts; restored executable-looking cards remain display-only.

## 8. Important bounds

- Twelve charged commands per owned workspace task; at most one new immutable command per response; 12 KB total command size; foreground execution up to 120 seconds. The document invocation child has a ninety-second bound. These are limits, not latency guarantees.
- Three relevant full skills/drafts combined for Create; draft discovery catalogs at most sixty-four actual names. No task skills for ordinary Answer/Converse. Installed full library contents were not freshly fetched for this handoff.
- Complete source/reference/final textual evidence: 180,000 UTF-8 bytes total, separate 1.1 MB JSON bound, fifteen-second review request timeout. Excerpts must not be claimed as complete evidence.
- Private artifact bytes: 50 MB/file, 200 MB/account, five hundred cards, seven-day server byte retention. Original workspace files are separate from delivery retention.
- Documents: up to three hundred measured pages; every page mechanically rendered/checked. At most twelve captured PNG proofs, 1.8 MB each and 2.8 MB combined; larger visual-review sets are sampled first/middle/last, not a claim that every page image was reviewed by AI.
- HTML bundles: at most sixty-four local assets and 50 MB including entry. Authenticated downloads retain attachment/nosniff/sandbox protections and original-only refetch rules.

## 9. Current changes, validation and unresolved facts

This update replaces Knot’s manual UIKit reply recognizer with directional SwiftUI dragging and guarded deferred composer focus; makes the reaction moat a true transparent alpha cutout with a separate pill; restores native header activity while thinking/working; removes the forced default reaction; and removes broad code/tag streaming truncation. It also adds catalog-authorized draft reads and confirmed-failure recovery, renderer-neutral structural document validation, custom delivery labels and safe opaque artifact formats.

Validation completed:

- Native iOS simulator checks/build passed: `src_ae1431d8e09e3eb3b`. Device/Release compilation remains unverified.
- Web strict types/lint/build passed: `art_bf1e42655bd83e083`. Existing unrelated legacy-asset/redirect/URL-centralization notices remain.
- Strict affected backend TypeScript and whitespace checks passed. Sixteen generated-Python AST/12 KB validations plus the resident-utility AST parse passed **without executing the generated commands or utility**. No behavior tests were written/run.
- Supported backend bundle/deploy succeeded without warnings: `ebfc0f6b6f8e51285aeb04642018b754`, source `src_4ae13569d8a37d136`. Permanent app backend configuration/aliases were retained. Cloudflare app checks are unsupported; strict types and supported bundle/deploy are the active backend validation surface.

Unresolved / not established:

- No matching slide-to-reply crash stack or authenticated reproduction was obtained. Gesture/focus changes are hardening, not a confirmed root-cause crash repair. The reference-matched visual result and interactions still need device acceptance.
- Voice still has reported zero-duration provider startup failures, code 3000 / `agent_not_available`, including November 11 at 23:26:50Z and 23:27:03Z. GET-only readiness checks passed; that does not prove bridge reachability at the failed instant or explain startup rejection. Zero deployment-history rows alone are not a diagnosis.
- No new authenticated device/browser interaction, cross-device round trip, fresh document/task run, call/token/audio probe or droplet operation was performed for this update. Static/build/deploy success is not runtime acceptance or one-to-one parity evidence.
- The resident `tools/knot-doc/v1/knot-doc` is an **uninstalled, unadvertised mechanical draft**, not a currently available agent command. Installation/security/live-guide review and deliberate fresh acceptance remain outstanding.

## 10. Instructions for a safe Muse handoff

Use this inventory to compare actual process, tool schemas, restrictions and missing evidence. It does **not** authorize executing commands, installing the resident draft, adopting/closing uncertain sessions, copying or rebinding files, changing credentials/provider agents, replaying historical tasks or recreating jobs.

Preserve original authentication/backend/history, managed credentials, browser/signing profiles, schedules/grants, all workspace memory and every rejected/undelivered output. Do not put member file contents, credentials or raw provider responses into general logs. Any later live acceptance should be a deliberately submitted fresh request with its own Events/request identity, not a resumed failed run.

### Source map

- Identity, native proposal contract and arithmetic/search tools: `functions/knot-agent.ts`.
- Turn orchestration, streaming, capability selection and foreground browser budget: `functions/knot-live.ts`.
- Owned command lifecycle/admission/recovery: `functions/knot-shell.ts`; live tool projection: `functions/knot-shell-discovery.ts`.
- Live catalog/draft learning: `functions/knot-skill-drafts.ts`; reaction placement: `functions/knot-reactions.ts` and `functions/knot-message-skills.ts`.
- Documents/artifacts: `functions/knot-document-build.ts`, `functions/knot-document-proof.ts`, `functions/knot-document-content.ts`, `functions/knot-documents.ts`.
- Browser actions and review evidence: `functions/knot-browser.ts`, `functions/knot-browser-agent.ts`, `functions/knot-browser-review.ts`.
- Scheduled grants/contact/creator metrics: `functions/knot-background.ts`, `functions/knot-contact-store.ts`, `functions/knot-creator-performance.ts`.
- Voice: `functions/knot-voice-bridge.ts` and shared `functions/knot-ai-transport.ts`, plus existing native/web consent/session clients.
- Native exact approvals: `ios/Whisper/WhisperFitnessApp/Views/Whisper/WhisperKnotActionProposal.swift`.
- Native presentation: `WhisperKnotMessageReply.swift`, `WhisperKnotReactionCutout.swift`, `WhisperEmberChatView.swift`, `WhisperKnotOutput.swift`, `WhisperKnotDocumentsView.swift` in that native views folder; web delivery: `web-whisperweb/src/components/KnotDocumentCards.tsx` and `web-whisperweb/src/lib/knotDocuments.ts`.
