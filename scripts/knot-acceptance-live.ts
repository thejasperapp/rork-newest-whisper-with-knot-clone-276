// Dedicated live acceptance only. Never logs tokens or reads an owner account.
// Run with: rork env run -- bun scripts/knot-acceptance-live.ts --setup
// --run submits explicitly selected fresh asks ONCE and executes only their exact owned proposals.
// --provenance-battery <name> may repeat for explicit known ORIGINAL guide reads.
import { readFileSync, writeFileSync, mkdirSync, appendFileSync, existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createHash, randomUUID } from 'node:crypto';
import { AcceptanceSkillProvenance, assertAcceptanceIdentity } from './knot-acceptance-provenance';
const backend = 'https://uf26aun6d49w1tsjsm2u9-backend.rork.app';
const projectRef = 'uryyyegnbtlmyhqlgndy';
const privateDirectory = join(tmpdir(), 'knot-acceptance-uf26aun6d49w1tsjsm2u9');
const account = JSON.parse(readFileSync(join(privateDirectory, 'account.json'), 'utf8')) as { accountID: string; projectRef: string; email: string; accessToken: string };
if (account.projectRef !== projectRef || !/^knot-acceptance-[0-9a-f-]+@example\.com$/.test(account.email) || !/^[a-f0-9-]{36}$/.test(account.accountID) || !account.accessToken) throw new Error('dedicated_acceptance_identity_required');
const workspaceID = 'whisper-' + account.accountID;
// Explicit dedicated-account consent for the existing opt-in task-model route.
// Never infer this from environment, stored history or another account's choice.
const taskModelConsentVersion = process.argv.includes('--task-models') ? 'knot_task_models_v1' : undefined;
// The user's November 14 request authorizes ONE new paid diagnostic document,
// not reuse of either consumed structured scope or any historical task.
const repairScope = process.argv.flatMap((arg, index) => arg === '--repair-once' ? [process.argv[index + 1]] : []);
if (repairScope.length > 1 || repairScope.length && !/^20261114-[a-z][a-z0-9-]{0,60}$/.test(repairScope[0] ?? '')) throw new Error('explicit_unique_repair_scope_required');
const repairOnce = repairScope.length === 1;
const recoveredRepair = process.argv.includes('--recovered-repair');
if (recoveredRepair && !repairOnce) throw new Error('recovery_lane_requires_fresh_repair_scope');
const deliveryDirectory = new URL('../deliveries/', import.meta.url);
const durableScope = repairOnce ? new URL('recipes-paid-scope-' + repairScope[0] + '.json', deliveryDirectory) : undefined;
const durableOutcome = repairOnce ? new URL('recipes-paid-outcome-' + repairScope[0] + '.json', deliveryDirectory) : undefined;
const diagnosticOnce = process.argv.includes('--diagnostic-once');
const structuredReplacementOnce = process.argv.includes('--structured-replacement-once');
const structuredOnce = process.argv.includes('--structured-once') || structuredReplacementOnce || diagnosticOnce || repairOnce;
const speedOnce = process.argv.includes('--speed-once') || structuredOnce;
if ([process.argv.includes('--speed-once'), process.argv.includes('--structured-once'), structuredReplacementOnce, diagnosticOnce, repairOnce].filter(Boolean).length > 1) throw new Error('distinct_once_intent_required');
const onceIntentName = repairOnce ? 'recipes-repair-' + repairScope[0] + '-once-intent.json' : diagnosticOnce ? 'recipes-diagnostic-paid-once-intent.json' : structuredReplacementOnce ? 'recipes-structured-replacement-once-intent.json' : structuredOnce ? 'recipes-structured-run-once-intent.json' : 'recipes-speed-run-once-intent.json';
const setupName = repairOnce ? 'setup-repair-' + repairScope[0] + '.json' : diagnosticOnce ? 'setup-diagnostic-paid.json' : structuredReplacementOnce ? 'setup-structured-replacement.json' : 'setup.json';
const structuredLatencyPlan = structuredOnce ? (recoveredRepair
  ? JSON.parse(readFileSync(new URL('recipes-structured-attempt-19623939.json', deliveryDirectory), 'utf8')).prospectivePlan
  : JSON.parse(readFileSync(join(privateDirectory, 'structured-latency-plan.json'), 'utf8'))) as Record<string, unknown> : undefined;
if (recoveredRepair && (structuredLatencyPlan?.referenceTaskID !== 'b936a45f-b94a-4c5c-8ac6-b0c92e894466' || structuredLatencyPlan?.targetMs !== 330000)) throw new Error('committed_prospective_plan_required');
const expectedSpeedAccount = 'e00a9064-5f85-40bb-9f44-8bd60f90d24a';
const expectedBuild = process.argv.flatMap((arg, index) => arg === '--expected-build' ? [process.argv[index + 1]] : [])[0];
const hash = (data: string | Uint8Array) => createHash('sha256').update(data).digest('hex');
const save = (path: string, value: unknown) => writeFileSync(path, JSON.stringify(value, null, 2), { mode: 0o600 });
const emit = (value: unknown) => console.log(JSON.stringify(value));
const observedBuilds = new Map<string, { worker: string | null; actor: string | null }>();
async function request(path: string, body?: unknown, maximumMs = 25000, signal?: AbortSignal): Promise<Response> {
  const response = await fetch(backend + path, { method: body === undefined ? 'GET' : 'POST', redirect: 'error', headers: { 'X-Whisper-Authorization': 'Bearer ' + account.accessToken, 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.any([AbortSignal.timeout(maximumMs), ...(signal ? [signal] : [])]) });
  const builds = { worker: response.headers.get('X-Knot-Worker-Build'), actor: response.headers.get('X-Knot-Actor-Build') };
  observedBuilds.set(path, builds);
  if (expectedBuild && (builds.worker !== expectedBuild || builds.actor !== null && builds.actor !== expectedBuild || path === '/knot/shell/events' && (body as Record<string, unknown> | undefined)?.proposalID && builds.actor !== expectedBuild)) {
    emit({ step: 'read_response_build_mismatch', path, status: response.status, expectedBuild, observed: builds });
    await response.body?.cancel(); throw new Error('serving_build_mismatch_no_retry');
  }
  return response;
}
async function bytes(response: Response, limit: number): Promise<Uint8Array> {
  if (!response.ok || !response.body) { await response.body?.cancel(); throw new Error('file_http_' + response.status); }
  const reader = response.body.getReader(), chunks: Uint8Array[] = []; let size = 0;
  try {
    for (;;) { const part = await reader.read(); if (part.done) break; size += part.value.length; if (size > limit) throw new Error('file_size_limit'); chunks.push(part.value); }
  } finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
  const result = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { result.set(chunk, offset); offset += chunk.length; }
  return result;
}
const safeReason = (error: unknown, fallback: string) => error instanceof Error && /^[a-z0-9_]+$/.test(error.message) ? error.message : fallback;
async function collectDocuments(events: Record<string, any>, conversationID: string, location: string) {
  const documents: Record<string, any>[] = [];
  for (const document of events.documents ?? []) {
    if (!/^[a-f0-9]{64}$/.test(document.id) || !/^[a-z0-9_-]{1,16}$/.test(document.format) || !Number.isSafeInteger(document.size) || document.size < 1 || document.size > 50000000) throw new Error('invalid_delivery_metadata');
    const summary: Record<string, any> = { id: document.id, title: document.title, name: document.name, format: document.format, sha256: document.sha256, size: document.size, pages: document.pages, createdAt: document.createdAt, proposalID: document.proposalID, review: document.review, reviewIssue: document.reviewIssue, proofPages: document.proofPages, byteFidelity: document.byteFidelity, contentQuality: document.contentQuality, contentReview: document.contentReview, visualReview: document.visualReview, visualAdvisory: document.visualAdvisory, qualityShortfalls: document.qualityShortfalls, downloadedProofs: [] };
    try {
      const response = await request('/knot/shell/documents', { bot: 'main', conversationID, documentID: document.id, action: 'file' });
      const headerHash = response.headers.get('X-Knot-SHA256');
      const delivered = await bytes(response, document.size);
      summary.deliveredSHA256 = hash(delivered); summary.deliveredBytes = delivered.length;
      summary.deliveredMatches = headerHash === document.sha256 && summary.deliveredSHA256 === document.sha256 && delivered.length === document.size;
      writeFileSync(join(location, document.id + '.' + document.format), delivered, { mode: 0o600 });
      if (!summary.deliveredMatches) throw new Error('delivery_byte_mismatch');
      const path = document.sourcePath;
      if (typeof path !== 'string' || path.length > 240 || !/^[a-zA-Z0-9][a-zA-Z0-9_. /-]*$/.test(path) || path.split('/').some(part => !part || part.startsWith('.'))) throw new Error('invalid_owned_source_path');
      const token = process.env.SIDECAR_TOKEN_WHISPER;
      if (!token) throw new Error('box_read_credential_unavailable');
      // Read-only original-file observation scoped exclusively to this acceptance workspace.
      const original = await bytes(await fetch('https://knot-shell.mydailywhisper.com/files?path=' + encodeURIComponent(path) + '&user_id=' + encodeURIComponent(workspaceID), { redirect: 'error', headers: { Authorization: 'Bearer ' + token }, signal: AbortSignal.timeout(25000) }), document.size);
      summary.boxSHA256 = hash(original); summary.boxBytes = original.length;
      summary.boxMatches = summary.boxSHA256 === document.sha256 && original.length === document.size;
      if (!summary.boxMatches) throw new Error('box_byte_mismatch');
      for (let pageIndex = 0; pageIndex < document.proofPages.length; pageIndex++) {
        const preview = await bytes(await request('/knot/shell/documents', { bot: 'main', conversationID, documentID: document.id, action: 'preview', pageIndex }), 1800000);
        writeFileSync(join(location, document.id + '-page-' + document.proofPages[pageIndex] + '.png'), preview, { mode: 0o600 });
        summary.downloadedProofs.push({ page: document.proofPages[pageIndex], bytes: preview.length, sha256: hash(preview) });
      }
    } catch (error) { summary.issue = safeReason(error, 'document_observation_unavailable'); }
    documents.push(summary);
  }
  return documents;
}
async function checked(path: string, body?: unknown): Promise<Record<string, any>> {
  const response = await request(path, body);
  const raw = await response.text();
  if (!response.ok) {
    let reason = 'http_rejection';
    try { const error = JSON.parse(raw)?.error; if (typeof error === 'string' && /^[a-z0-9_]{1,80}$/.test(error)) reason = error; } catch { /* Never print raw responses. */ }
    throw new Error('managed_' + response.status + '_' + reason);
  }
  return JSON.parse(raw);
}
const asks = [
  { key: 'recipe-pdf', text: 'Create and deliver a beautifully designed PDF with three high-protein recipes suitable for fat loss. For each recipe include measured ingredients, clear cooking steps, approximate calories and protein per serving, and an explanation of why it supports a high-protein fat-loss diet. Make the recipes practical and substantive, with a considered editorial layout, not a decorative list.' },
  { key: 'markdown-guide', text: 'Create and deliver an actual short Markdown (.md) file: a practical beginner guide to planning a week of high-protein meals. Include a simple method, a small grocery checklist, a sample day and actionable tips. Deliver the Markdown file itself, not a PDF, plan or promise.' },
  { key: 'battle-game', text: 'Build and deliver a small playable Pokémon-style battle game as a self-contained HTML file, using original creature names and simple original artwork. Include a player creature, an opponent, visible health, attack choices, turn feedback, a win/loss state and restart. It must actually respond to the controls, not be a guide or source-only description.' },
  { key: 'prime-sum', text: 'Use the real workspace to compute the sum of all prime numbers below 1000. Show the actual computation tool card and give the numeric answer based on its command result.' },
] as const;
async function setup() {
  const conversationID = randomUUID();
  const capabilities = await checked('/knot/shell/capabilities');
  const events = await checked('/knot/shell/events', { bot: 'main', conversationID, proposalID: randomUUID() });
  if (capabilities.ok !== true || capabilities.service !== 'knot-sidecar' || capabilities.principal !== 'whisper' || !Array.isArray(events.records) || events.records.length !== 0) throw new Error('unexpected_setup_evidence');
  const result = { observedAt: new Date().toISOString(), accountID: account.accountID, expectedWorkspaceID: workspaceID, managedAuthentication: 'passed', sidecarDiscovery: 'passed', existingWorkspaceSessionCreated: false, ownerDataAccessed: false, servingBuilds: Object.fromEntries(observedBuilds) };
  save(join(privateDirectory, setupName), result); emit(result);
}
async function runAsk(ask: typeof asks[number], directory: string, provenance: AcceptanceSkillProvenance) {
  const requestID = randomUUID(), conversationID = randomUUID(), sourceMessageID = randomUUID();
  const started = Date.now();
  const location = join(directory, ask.key); mkdirSync(location, { mode: 0o700 });
  const identity = { key: ask.key, requestID, conversationID, sourceMessageID, taskID: requestID, accountID: account.accountID, workspaceID, startedAt: new Date(started).toISOString() };
  // Persist intent before submission; the same ask is never automatically retried.
  save(join(location, 'intent.json'), { ...identity, ask: ask.text, taskModelConsentVersion: taskModelConsentVersion ?? null, modelPolicy: taskModelConsentVersion ? 'opt_in_task_models_no_cross_provider_fallback' : 'openai_only' });
  if (durableScope) writeFileSync(durableScope, JSON.stringify({ title: 'Consumed paid recipes scope', scope: repairScope[0], scopeConsumed: true, ...identity, backend, expectedBuild, askSHA256: hash(ask.text), taskModelConsentVersion, noAutomaticRetry: true, recoveryLane: recoveredRepair, historicalScopesRemainConsumed: true }, null, 2) + '\n', { flag: 'wx' });
  let issue: string | undefined, completed = false, workIncomplete = false, reply = '', stopped = false, stopConfirmed = true;
  let completionReceivedMs: number | undefined, streamEndedMs: number | undefined;
  const servingBuilds: Record<string, string | null> = {};
  const streamAbort = new AbortController();
  const outstanding = new Map<string, Record<string, any>>();
  const seen = new Set<string>(); const executions: Record<string, any>[] = []; const frames: Record<string, any>[] = [];
  let pending: Promise<void> = Promise.resolve();
  const stop = async () => {
    stopped = true; streamAbort.abort();
    for (const proposal of outstanding.values()) {
      try {
        const result = await checked('/knot/shell/cancel', { bot: 'main', conversationID, proposalID: proposal.id });
        save(join(location, proposal.id + '-stop.json'), result);
        if (!result.terminationConfirmed) stopConfirmed = false;
      } catch { stopConfirmed = false; }
    }
  };
  const execute = async (proposal: Record<string, any>) => {
    if (stopped) return;
    if (proposal.bot !== 'main' || proposal.conversationID !== conversationID || proposal.taskID !== requestID || proposal.sourceMessageID !== sourceMessageID || !/^[a-f0-9-]{36}$/.test(proposal.id) || seen.has(proposal.id) || typeof proposal.command !== 'string') throw new Error('owned_proposal_mismatch_or_replay');
    seen.add(proposal.id); outstanding.set(proposal.id, proposal);
    save(join(location, proposal.id + '-proposal.json'), proposal);
    const response = await request('/knot/shell/execute', { bot: 'main', conversationID, proposalID: proposal.id, executionVersion: 'knot_shell_automatic_v1', command: proposal.command, timeoutMs: proposal.timeoutMs }, 160000);
    const result = await response.json() as Record<string, any>;
    save(join(location, proposal.id + '-execute.json'), result);
    if (!response.ok) throw new Error('execute_http_' + response.status);
    const turn = { conversationID, requestID, sourceMessageID };
    assertAcceptanceIdentity(proposal, result, turn);
    let final = result;
    let cached = provenance.acceptCache(proposal, final, turn);
    // Idempotent status recovery only; never retry the mutation.
    const recoveryDeadline = Date.now() + 15000;
    while (!cached && final.sessionID && !(final.terminationConfirmed && final.commandReceipt && final.outputComplete && !final.truncated) && final.status !== 'cancelled' && Date.now() < recoveryDeadline) {
      await new Promise(resolve => setTimeout(resolve, 650));
      final = await checked('/knot/shell/status', { bot: 'main', conversationID, proposalID: proposal.id });
      assertAcceptanceIdentity(proposal, final, turn);
      cached = provenance.acceptCache(proposal, final, turn);
    }
    save(join(location, proposal.id + '-result.json'), final);
    executions.push({ proposalID: proposal.id, operation: proposal.operation, tool: proposal.tool, documentStage: proposal.documentInvocation?.stage, commandBytes: Buffer.byteLength(proposal.command), status: final.status, exitCode: final.exitCode, terminationConfirmed: final.terminationConfirmed, outputComplete: final.outputComplete, truncated: final.truncated, sessionID: final.sessionID, stdoutSHA256: hash(final.stdout ?? '') });
    emit({ key: ask.key, proposalID: proposal.id, operation: proposal.operation, documentStage: proposal.documentInvocation?.stage, status: final.status, exitCode: final.exitCode });
    if (!final.terminationConfirmed || final.sessionID && (!final.outputComplete || final.truncated || !cached && !final.commandReceipt)) throw new Error('execution_unconfirmed_no_replay');
    if (!cached) provenance.remember(proposal, final, turn);
    outstanding.delete(proposal.id);
  };
  try {
    const response = await request('/knot/chat/stream', { requestID, bot: 'main', conversationID, sourceMessageID, sourceCreatedAt: started, consentVersion: 'knot_ai_consent_v4', ...(taskModelConsentVersion ? { taskModelConsentVersion } : {}), message: ask.text, healthContext: '', history: [], isWebQuery: false, sharedConversation: false, timezone: 'UTC', foregroundTurnVersion: 'knot_foreground_turn_v1', workProgressVersion: 'knot_work_progress_v1', documentProgramVersion: 'knot_document_program_v3', taskExperienceVersion: 'knot_task_experience_v1', clarificationVersion: 'knot_clarification_v1' }, 945000, streamAbort.signal);
    servingBuilds.worker = response.headers.get('X-Knot-Worker-Build');
    save(join(location, 'stream-response.json'), { status: response.status, servingBuilds, requestID: response.headers.get('X-Knot-Request-ID') });
    if (expectedBuild && servingBuilds.worker !== expectedBuild) throw new Error('stream_serving_build_mismatch_no_retry');
    if (!response.ok || !response.body) throw new Error('stream_http_' + response.status);
    const reader = response.body.getReader(), decoder = new TextDecoder(); let buffer = '';
    try {
      for (;;) {
        const part = await reader.read(); if (part.done) break;
        buffer += decoder.decode(part.value, { stream: true });
        let at: number;
        while ((at = buffer.indexOf('\n\n')) >= 0) {
          const packet = buffer.slice(0, at); buffer = buffer.slice(at + 2);
          const data = packet.split('\n').filter(line => line.startsWith('data:')).map(line => line.slice(5).trimStart()).join('\n');
          if (!data) continue;
          const frame = JSON.parse(data) as Record<string, any>;
          if (frame.requestID !== requestID || frame.sequence !== frames.length + 1) throw new Error('stream_identity_or_sequence_mismatch');
          const observed = { ...frame, clientReceivedAt: new Date().toISOString(), clientElapsedMs: Date.now() - started };
          frames.push(observed); appendFileSync(join(location, 'frames.jsonl'), JSON.stringify(observed) + '\n', { mode: 0o600 });
          if (frame.type === 'shell_proposal') {
            // Serialize executors even if the next SSE arrives before the prior HTTP response.
            pending = pending.then(() => execute(frame.proposal)).catch(async error => { issue ??= safeReason(error, 'execution_transport_unconfirmed'); await stop(); });
          }
          if (frame.type === 'complete') { completionReceivedMs ??= Date.now() - started; completed = true; workIncomplete = frame.workIncomplete === true; reply = frame.reply ?? ''; if (workIncomplete) issue ??= frame.reason ?? 'work_incomplete'; }
          if (frame.type === 'error' || frame.type === 'rejected' || frame.type === 'document_work_unavailable') issue ??= frame.reason ?? frame.error ?? frame.type;
        }
      }
      if (buffer.trim()) issue ??= 'incomplete_sse_frame';
    } finally { reader.releaseLock(); }
  } catch (error) { issue ??= safeReason(error, 'stream_transport_unconfirmed'); await stop(); }
  streamEndedMs = Date.now() - started;
  await pending;
  const collectionStartedMs = Date.now() - started;
  if (outstanding.size && !stopped) await stop();
  if (!stopConfirmed) issue = 'stop_unconfirmed';
  let events: Record<string, any> | undefined;
  try { events = await checked('/knot/shell/events', { bot: 'main', conversationID }); save(join(location, 'events.json'), events); }
  catch { issue ??= 'events_unavailable'; }
  for (const record of events?.records ?? []) {
    const proposalID = record.spec?.id;
    if (!/^[a-f0-9-]{36}$/.test(proposalID) || record.taskID !== requestID || record.sourceMessageID !== sourceMessageID) { issue ??= 'events_identity_mismatch'; continue; }
    try {
      save(join(location, proposalID + '-events.json'), await checked('/knot/shell/events', { bot: 'main', conversationID, proposalID }));
      if (record.result?.sessionID) save(join(location, proposalID + '-log.json'), await checked('/knot/shell/log', { bot: 'main', conversationID, proposalID }));
    } catch { issue ??= 'retained_evidence_unavailable'; }
  }
  const documents = events ? await collectDocuments(events, conversationID, location) : [];
  const authoringObservations = frames.filter(frame => frame.activity?.detail && (frame.activity.detail.stage === 'document_authoring' || frame.activity.kind === 'document_program_sealed' || frame.activity.detail.sizeClass)).map(frame => ({ kind: frame.activity.kind, receivedMs: frame.clientElapsedMs, detail: frame.activity.detail }));
  const capturedAt = documents.length ? Math.min(...documents.map(document => Date.parse(document.createdAt)).filter(Number.isFinite)) : NaN;
  const result = { ...identity, endedAt: new Date().toISOString(), elapsedMs: Date.now() - started, completionReceivedMs, streamEndedMs, captureElapsedMs: Number.isFinite(capturedAt) ? capturedAt - started : undefined, evidenceCollectionMs: Date.now() - started - collectionStartedMs, servingBuilds, completed, workIncomplete, issue: issue ?? (workIncomplete ? 'work_incomplete' : completed ? undefined : 'no_completion'), reply, executions, documents, authoringObservations, frameCount: frames.length, stopConfirmed, baseline: structuredOnce ? { reference: 'b936a45f-b94a-4c5c-8ac6-b0c92e894466', exactSameAsk: true, baselineCompletionMs: 603097, planning: structuredLatencyPlan } : speedOnce ? { reference: '21f2865d', approximateMs: 600000, source: 'owner_reported_not_controlled_same_ask', targetMs: 180000, exactOriginalPromptAvailable: false } : undefined, acceptance: 'requires_independent_evidence_review' };
  save(join(location, 'result.json'), result);
  if (durableOutcome) writeFileSync(durableOutcome, JSON.stringify({ title: 'Paid recipes terminal observation', scope: repairScope[0], ...identity, expectedBuild, endedAt: result.endedAt, completed, workIncomplete, issue: result.issue, stopConfirmed, servingBuilds, completionReceivedMs, streamEndedMs, captureElapsedMs: result.captureElapsedMs, frameCount: frames.length, executions, documents, historicalReplay: false, orderedStreamRetainedPrivately: true, acceptance: result.acceptance }, null, 2) + '\n', { flag: 'wx' });
  emit({ ...result, reply: '[retained privately]', authoringObservations: authoringObservations.map(item => ({ kind: item.kind, receivedMs: item.receivedMs, detail: item.detail })) }); return result;
}
async function assertDurableRepairHistory() {
  // Committed observations preserve consumed scopes even after temporary raw
  // evidence is lost. Never manufacture old intent/result files to pass a gate.
  const reports = [
    ['recipes-structured-attempt-19623939.json', '19623939-62a4-4efc-b3b7-19e74b786840'],
    ['recipes-structured-replacement-0f1801ec.json', '0f1801ec-e34e-4cf7-8b4f-3b3aeb81ecd3'],
    ['recipes-paid-diagnostic-129ba717.json', '129ba717-8b7f-43c3-b9ff-107c09ea1de4'],
    ['recipes-repair-98db00bd.json', '98db00bd-3276-41e6-9c65-876e506d1a72'],
    ['recipes-repair-52e0077d.json', '52e0077d-d57d-488f-b2e6-2db8f6fe6ae6'],
  ];
  for (const [name, taskID] of reports) {
    const report = JSON.parse(readFileSync(new URL(name, deliveryDirectory), 'utf8'));
    if (report.taskID !== taskID || !/^[a-f0-9]{64}$/.test(report.sourceBuildSHA256)) throw new Error('committed_historical_outcome_required');
    if (report.scope === repairScope[0]) throw new Error('once_scope_consumed_no_retry');
    if (report.sourceBuildSHA256 === expectedBuild) throw new Error('failed_build_requires_targeted_change_before_paid_repeat');
  }
  for (const name of readdirSync(deliveryDirectory).filter(name => /^recipes-paid-scope-20261114-[a-z0-9-]+\.json$/.test(name))) {
    const intent = JSON.parse(readFileSync(new URL(name, deliveryDirectory), 'utf8'));
    if (intent.accountID !== account.accountID || intent.workspaceID !== workspaceID || intent.backend !== backend || !intent.noAutomaticRetry || !intent.scopeConsumed) throw new Error('durable_scope_binding');
    const outcomeURL = new URL('recipes-paid-outcome-' + intent.scope + '.json', deliveryDirectory);
    if (!existsSync(outcomeURL)) throw new Error('durable_scope_outcome_uncertain_no_new_submission');
    const outcome = JSON.parse(readFileSync(outcomeURL, 'utf8'));
    if (outcome.taskID !== intent.taskID || outcome.conversationID !== intent.conversationID || outcome.sourceMessageID !== intent.sourceMessageID || outcome.expectedBuild !== intent.expectedBuild || !outcome.stopConfirmed || !outcome.completed || outcome.servingBuilds?.worker !== intent.expectedBuild) throw new Error('durable_scope_outcome_uncertain_no_new_submission');
    if (intent.expectedBuild === expectedBuild) throw new Error('prior_paid_build_requires_targeted_change');
  }
  if (!recoveredRepair) return;
  const conversationID = '945599ab-4390-4ae9-b38c-f2fcd12a3efd', taskID = '52e0077d-d57d-488f-b2e6-2db8f6fe6ae6', sourceMessageID = '76128aef-8fc3-457d-99d2-e96f2fc474bf';
  const prior = await checked('/knot/shell/events', { bot: 'main', conversationID });
  if (prior.records?.length !== 10 || prior.documents?.length || !prior.records.every((row: Record<string, any>) => row.state === 'finished' && row.taskID === taskID && row.sourceMessageID === sourceMessageID && row.result?.status === 'completed' && row.result?.exitCode === 0 && row.result?.terminationConfirmed && row.receiptOutputComplete && !row.receiptTruncated) || !prior.activities?.some((row: Record<string, any>) => row.kind === 'rejected' && row.taskID === taskID && row.sourceMessageID === sourceMessageID && row.detail?.reason === 'upstream_quota_exhausted' && row.detail?.status === 402)) throw new Error('recovered_prior_terminal_evidence_required');
  save(join(privateDirectory, 'recovered-prior-terminal-before-' + repairScope[0] + '.json'), prior);
  emit({ step: 'recovered_prior_terminal_verified_read_only', taskID, originalOrderedStreamRecovered: false, fabricatedHistoricalIntents: false, newHistoricalCommands: 0 });
}
async function importRecoveredOriginalGuide(provenance: AcceptanceSkillProvenance, directory: string) {
  const conversationID = 'f5fa4af7-6299-4fd6-83f7-1275112879d9', requestID = 'b936a45f-b94a-4c5c-8ac6-b0c92e894466', sourceMessageID = 'b7b7d40a-75da-4e3f-ae51-08178aa6e5f5';
  const id = '9924aed8-6462-4db0-a779-a0f0400495b0';
  const prior = await checked('/knot/shell/events', { bot: 'main', conversationID, proposalID: id });
  const rows = (prior.records ?? []).filter((row: Record<string, any>) => row.spec?.id === id);
  if (rows.length !== 1) throw new Error('exact_original_guide_record_required');
  const row = rows[0], proposal = row.spec;
  if (row.state !== 'finished' || row.taskID !== requestID || row.sourceMessageID !== sourceMessageID || proposal.command !== 'cat /opt/knot-skills/document-creation/SKILL.md' || row.cachedData || row.result?.cachedData || row.result?.status !== 'completed') throw new Error('original_not_cached_guide_required');
  const original = await checked('/knot/shell/status', { bot: 'main', conversationID, proposalID: id, persistedOnly: true });
  if (original.cachedData || original.sessionID !== 'cfa2086e-cd18-45df-9025-e75ba8568225' || hash(JSON.stringify([original.stdout, original.stderr])) !== 'f82c7eb4ecd411664199f5d16f42afe4dc53651a69400c7537685d72bb78be0e') throw new Error('original_guide_session_or_hash_mismatch');
  provenance.remember(proposal, original, { conversationID, requestID, sourceMessageID });
  save(join(directory, 'recovered-original-guide-provenance.json'), { proposal, original });
  emit({ step: 'known_original_guide_verified', sourceProposalID: id, persistedOnly: true, historicalExecution: false, originalNotCached: true });
}
async function main() {
  if (process.argv.includes('--setup')) return setup();
  if (!process.argv.includes('--run')) throw new Error('choose_setup_or_run');
  if (!existsSync(join(privateDirectory, setupName))) throw new Error('successful_setup_required');
  const selectedKeys = process.argv.flatMap((arg, index) => arg === '--only' ? [process.argv[index + 1]] : []);
  if (!selectedKeys.length || new Set(selectedKeys).size !== selectedKeys.length || selectedKeys.some(key => !asks.some(ask => ask.key === key))) throw new Error('explicit_valid_unique_ask_selection_required');
  const selectedAsks = asks.filter(ask => selectedKeys.includes(ask.key));
  if (speedOnce && (selectedKeys.length !== 1 || selectedKeys[0] !== 'recipe-pdf' || !taskModelConsentVersion || account.accountID !== expectedSpeedAccount || !expectedBuild || !/^[a-f0-9]{64}$/.test(expectedBuild))) throw new Error('speed_once_scope_and_verified_build_required');
  // A consumed scope cannot even enter preparation for another run. Its intent
  // is permanent; a replacement requires new explicit authorization and scope.
  if (speedOnce && (existsSync(join(privateDirectory, onceIntentName)) || durableScope && existsSync(durableScope))) throw new Error('once_scope_consumed_no_retry');
  if (repairOnce) await assertDurableRepairHistory();
  if (repairOnce && !recoveredRepair) {
    // Broader November 14 approval permits fresh FIXED iterations, not removal
    // of old once-latches or automatic repetition of an uncertain/failed task.
    const names = ['recipes-diagnostic-paid-once-intent.json', ...readdirSync(privateDirectory).filter(name => /^recipes-repair-20261114-[a-z0-9-]+-once-intent\.json$/.test(name))];
    for (const name of names) {
      const earlier = JSON.parse(readFileSync(join(privateDirectory, name), 'utf8'));
      if (earlier.accountID !== account.accountID || earlier.workspaceID !== workspaceID || earlier.backend !== backend || !earlier.noAutomaticRetry || typeof earlier.directory !== 'string' || !earlier.directory.startsWith(privateDirectory + '/battery-')) throw new Error('prior_repair_scope_binding');
      const result = JSON.parse(readFileSync(join(earlier.directory, 'recipe-pdf/result.json'), 'utf8'));
      if (!result.stopConfirmed || result.accountID !== account.accountID || !result.completed || result.servingBuilds?.worker !== earlier.expectedBuild) throw new Error('prior_repair_outcome_uncertain_no_new_submission');
      const failed = result.workIncomplete || result.issue || !result.documents?.length || result.documents.some((document: Record<string, any>) => document.issue || document.contentQuality?.status !== 'pass' || document.visualReview?.status !== 'pass' || document.qualityShortfalls?.length);
      if (failed && earlier.expectedBuild === expectedBuild) throw new Error('failed_build_requires_targeted_change_before_paid_repeat');
    }
  }
  if (diagnosticOnce || repairOnce) {
    for (const name of recoveredRepair ? [] : ['recipes-structured-run-once-intent.json', 'recipes-structured-replacement-once-intent.json']) {
      const consumed = JSON.parse(readFileSync(join(privateDirectory, name), 'utf8'));
      if (consumed.accountID !== account.accountID || !consumed.noAutomaticRetry) throw new Error('historical_consumed_scope_required');
    }
    const preflight = JSON.parse(readFileSync(join(privateDirectory, setupName), 'utf8'));
    if (preflight.accountID !== account.accountID || preflight.managedAuthentication !== 'passed' || preflight.sidecarDiscovery !== 'passed' || preflight.servingBuilds?.['/knot/shell/events']?.worker !== expectedBuild || preflight.servingBuilds?.['/knot/shell/events']?.actor !== expectedBuild || !Number.isFinite(Date.parse(preflight.observedAt)) || Date.now() - Date.parse(preflight.observedAt) > 300000 || Date.now() < Date.parse(preflight.observedAt)) throw new Error('fresh_diagnostic_build_preflight_required');
  }
  if (structuredReplacementOnce) {
    const earlier = JSON.parse(readFileSync(join(privateDirectory, 'recipes-structured-run-once-intent.json'), 'utf8'));
    const failed = JSON.parse(readFileSync(join(privateDirectory, 'battery-2026-11-14T04-22-25-789Z/recipe-pdf/result.json'), 'utf8'));
    if (earlier.directory !== join(privateDirectory, 'battery-2026-11-14T04-22-25-789Z') || earlier.accountID !== account.accountID || failed.taskID !== '19623939-62a4-4efc-b3b7-19e74b786840' || failed.accountID !== account.accountID || failed.completed || failed.issue !== 'cached_skill_provenance_unconfirmed' || !failed.stopConfirmed || failed.documents.length || failed.executions.some((entry: Record<string, unknown>) => !['memory_read', 'skill_index'].includes(String(entry.operation)))) throw new Error('exact_aborted_scope_required');
    const preflight = JSON.parse(readFileSync(join(privateDirectory, setupName), 'utf8'));
    if (preflight.accountID !== account.accountID || preflight.managedAuthentication !== 'passed' || preflight.sidecarDiscovery !== 'passed' || preflight.servingBuilds?.['/knot/shell/events']?.worker !== expectedBuild || preflight.servingBuilds?.['/knot/shell/events']?.actor !== expectedBuild || !Number.isFinite(Date.parse(preflight.observedAt)) || Date.now() - Date.parse(preflight.observedAt) > 300000) throw new Error('fresh_replacement_build_preflight_required');
  }
  const directory = join(privateDirectory, 'battery-' + new Date().toISOString().replace(/[:.]/g, '-')); mkdirSync(directory, { mode: 0o700 });
  save(join(directory, 'battery-intent.json'), { startedAt: new Date().toISOString(), accountID: account.accountID, workspaceID, backend, selectedKeys, noAutomaticRetry: true, taskModelConsentVersion: taskModelConsentVersion ?? null, modelPolicy: taskModelConsentVersion ? 'opt_in_task_models_no_cross_provider_fallback' : 'openai_only' });
  const provenance = new AcceptanceSkillProvenance({ accountID: account.accountID, workspaceID });
  if (recoveredRepair) await importRecoveredOriginalGuide(provenance, directory);
  if (structuredOnce && !recoveredRepair) {
    // The prior exact same-ask run established the still-live session's ORIGINAL
    // document-guide read. Import this one explicitly known local receipt before
    // submission; do not discover history or accept a cache without its original.
    const previous = join(privateDirectory, 'battery-2026-11-14T03-41-24-088Z', 'recipe-pdf');
    const baseline = JSON.parse(readFileSync(join(previous, 'result.json'), 'utf8'));
    const id = '9924aed8-6462-4db0-a779-a0f0400495b0';
    if (baseline.taskID !== 'b936a45f-b94a-4c5c-8ac6-b0c92e894466' || baseline.requestID !== baseline.taskID || baseline.conversationID !== 'f5fa4af7-6299-4fd6-83f7-1275112879d9' || baseline.sourceMessageID !== 'b7b7d40a-75da-4e3f-ae51-08178aa6e5f5' || baseline.accountID !== account.accountID || baseline.workspaceID !== workspaceID || !baseline.completed || baseline.issue || structuredLatencyPlan?.referenceTaskID !== baseline.taskID || !baseline.executions.some((entry: Record<string, unknown>) => entry.proposalID === id && entry.operation === 'skill_read')) throw new Error('structured_baseline_provenance_required');
    const proposal = JSON.parse(readFileSync(join(previous, id + '-proposal.json'), 'utf8'));
    const original = JSON.parse(readFileSync(join(previous, id + '-result.json'), 'utf8'));
    if (proposal.command !== 'cat /opt/knot-skills/document-creation/SKILL.md' || original.cachedData) throw new Error('structured_original_guide_required');
    provenance.remember(proposal, original, { requestID: baseline.requestID, conversationID: baseline.conversationID, sourceMessageID: baseline.sourceMessageID });
    emit({ step: 'known_structured_baseline_original_validated', sourceProposalID: id, historicalExecution: false, localRetainedEvidenceOnly: true });
  }
  // Explicit read-only import of this account's KNOWN completed original guide
  // receipts. Never execute, recover, resume or adopt a historical task/session.
  // Repeat the flag to validate separate KNOWN original executions. A cached
  // receipt never seeds another cache; no recursive discovery or task adoption.
  const seedNames = process.argv.flatMap((arg, index) => arg === '--provenance-battery' ? [process.argv[index + 1]] : []);
  for (const name of seedNames) {
    if (!/^battery-[0-9TZ-]+$/.test(name ?? '')) throw new Error('invalid_provenance_battery');
    const priorDirectory = join(privateDirectory, name);
    const prior = JSON.parse(readFileSync(join(priorDirectory, 'results.json'), 'utf8')) as Record<string, any>[];
    for (const result of prior) {
      if (result.accountID !== account.accountID || result.workspaceID !== workspaceID || !asks.some(ask => ask.key === result.key)) throw new Error('provenance_owner_mismatch');
      const turn = { requestID: result.requestID, conversationID: result.conversationID, sourceMessageID: result.sourceMessageID };
      for (const execution of result.executions ?? []) {
        if (!/^[a-f0-9-]{36}$/.test(execution.proposalID)) throw new Error('invalid_provenance_proposal');
        const stem = join(priorDirectory, result.key, execution.proposalID);
        const proposal = JSON.parse(readFileSync(stem + '-proposal.json', 'utf8'));
        if (!/^cat \/opt\/knot-skills\//.test(proposal.command) || !existsSync(stem + '-result.json')) continue;
        const original = JSON.parse(readFileSync(stem + '-result.json', 'utf8'));
        if (!original.cachedData && original.status === 'completed') provenance.remember(proposal, original, turn);
      }
    }
    emit({ step: 'known_original_skill_receipts_validated', accountID: account.accountID, workspaceID, historicalExecution: false });
  }
  // Read-only import of explicitly known completed ORIGINAL installed-guide
  // receipts. Only terminal completed receipts with complete retained output
  // are eligible; persistedOnly explicitly forbids provider observation.
  const knownTurns: Record<string, { requestID: string; sourceMessageID: string }> = {
    '9a113989-c49c-44e1-bd44-058507b3b11b': { requestID: '7028348c-fbea-44f8-9608-1170a8b72696', sourceMessageID: '3e4856f6-a5e6-43c1-a08d-dd0f23737fef' },
    'd65dca62-4095-4585-b637-f7ee29677284': { requestID: '11ad2f4c-5144-484c-9c7e-55e9ff20f2fd', sourceMessageID: '6a058884-6307-418e-b543-43c4d6c6d7dd' },
  };
  for (const conversationID of process.argv.flatMap((arg, index) => arg === '--provenance-conversation' ? [process.argv[index + 1]] : [])) {
    const known = knownTurns[conversationID];
    if (!speedOnce || account.accountID !== expectedSpeedAccount || !known) throw new Error('unknown_provenance_conversation');
    const prior = await checked('/knot/shell/events', { bot: 'main', conversationID });
    const imports: unknown[] = [];
    for (const record of prior.records ?? []) {
      if (record.state !== 'finished' || record.taskID !== known.requestID || record.sourceMessageID !== known.sourceMessageID || record.cachedData || record.result?.cachedData || record.result?.status !== 'completed' || !/^cat \/opt\/knot-skills\/(?:[a-zA-Z0-9_-]+\/)+SKILL\.md$/.test(record.spec?.command ?? '')) continue;
      const original = await checked('/knot/shell/status', { bot: 'main', conversationID, proposalID: record.spec.id, persistedOnly: true });
      if (original.cachedData) throw new Error('original_provenance_receipt_required');
      provenance.remember(record.spec, original, { conversationID, ...known });
      imports.push({ proposal: record.spec, original });
    }
    save(join(directory, 'original-guide-provenance-' + conversationID + '.json'), imports);
    emit({ step: 'known_original_skill_receipts_validated', conversationID, count: imports.length, historicalExecution: false, persistedOnly: true });
  }
  if (speedOnce) writeFileSync(join(privateDirectory, onceIntentName), JSON.stringify({ startedAt: new Date().toISOString(), accountID: account.accountID, workspaceID, backend, expectedBuild, directory, selectedKeys, taskModelConsentVersion, ...(repairOnce ? { authorization: 'explicit_user_paid_document_repair_iterations_2026_11_14', scope: repairScope[0], allHistoricalIntentsPreserved: true, freshTaskOnly: true } : diagnosticOnce ? { authorization: 'explicit_user_one_new_paid_document_request_2026_11_14', allHistoricalIntentsPreserved: true } : structuredReplacementOnce ? { authorization: 'explicit_user_yes_one_replacement_fresh_measurement', replacesAbortedTaskID: '19623939-62a4-4efc-b3b7-19e74b786840', oldIntentPreserved: true } : {}), noAutomaticRetry: true }), { flag: 'wx', mode: 0o600 });
  const results: unknown[] = [];
  for (const ask of selectedAsks) {
    const result = await runAsk(ask, directory, provenance); results.push(result);
    // Do not send more work while a dispatched task's Stop remains uncertain.
    if (!result.stopConfirmed) break;
  }
  save(join(directory, 'results.json'), results); emit({ batteryDirectory: directory, acceptance: 'pending_independent_review' });
}
main().catch(error => { emit({ observedAt: new Date().toISOString(), status: 'blocked', reason: error instanceof Error && /^[a-z0-9_]+$/.test(error.message) ? error.message : 'setup_transport_unavailable', accountID: account.accountID, expectedWorkspaceID: workspaceID, credentialsPrinted: false }); process.exitCode = 2; });
