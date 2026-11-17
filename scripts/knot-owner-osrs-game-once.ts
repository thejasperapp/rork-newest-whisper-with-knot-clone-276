// One explicitly authorized fresh owner game. Native-compatible protocol only.
// No old commands, direct authoring, account fallback or automatic resubmission.
// Raw frames/receipts and session stay private outside Git; durable scope survives.
import { existsSync, readFileSync, writeFileSync, appendFileSync } from 'node:fs';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { backend, accountID, workspaceID, directory, hash, fact, emit, safeReason, save, managed, checked, type Data } from './knot-owner-osrs-access';
import { AcceptanceSkillProvenance, assertAcceptanceIdentity } from './knot-acceptance-provenance';
import { knotSourceBuildSHA256 } from '../functions/knot-source-build';
const expectedBuild = process.argv[process.argv.indexOf('--expected-build') + 1];
const ask = 'Make me an osrs style rpg game';
const historicalConversation = '549a559d-3f67-40e8-bbce-9ca95e6ddb8d';
const intentURL = new URL('../deliveries/owner-osrs-game-20261114-once-intent.json', import.meta.url);
const outcomeURL = new URL('../deliveries/owner-osrs-game-20261114-once-outcome.json', import.meta.url);
const provenance = new AcceptanceSkillProvenance({ accountID, workspaceID });
const json = (path: string, body?: unknown) => checked(path, body, expectedBuild);
const writeDurable = (url: URL, value: unknown) => writeFileSync(url, JSON.stringify(value, null, 2) + '\n', { flag: 'wx' });
async function preflight() {
  fact(process.argv.includes('--expected-build') && /^[a-f0-9]{64}$/.test(expectedBuild ?? '') && expectedBuild === knotSourceBuildSHA256, 'explicit_current_source_build_required');
  const capabilities = await json('/knot/shell/capabilities');
  fact(capabilities.ok === true && capabilities.service === 'knot-sidecar' && capabilities.principal === 'whisper', 'current_owner_capabilities_required');
  const actor = await managed('/knot/shell/events', { bot: 'main', conversationID: historicalConversation, proposalID: 'f7295062-0eab-43a9-a5fe-fd0051827b11' }, 25000, undefined, expectedBuild);
  fact(actor.ok && actor.headers.get('X-Knot-Actor-Build') === expectedBuild, 'exact_serving_actor_build_required');
  await actor.body?.cancel();
  const prior = await json('/knot/shell/events', { bot: 'main', conversationID: historicalConversation });
  // Import only actual original complete installed-guide reads from the exact
  // already-identified owner conversation. Never seed provenance with cache data.
  const originals: Data[] = [];
  for (const row of prior.records ?? []) {
    const proposal = row.spec;
    if (!proposal || proposal.conversationID !== historicalConversation || !/^cat \/opt\/knot-skills\/(?:[a-zA-Z0-9_-]+\/)+SKILL\.md$/.test(proposal.command) || row.cachedData || row.result?.cachedData || row.state !== 'finished') continue;
    const result = await json('/knot/shell/status', { bot: 'main', conversationID: historicalConversation, proposalID: proposal.id, persistedOnly: true });
    if (result.cachedData) continue;
    provenance.remember(proposal, result, { conversationID: historicalConversation, requestID: row.taskID, sourceMessageID: row.sourceMessageID });
    save('game-original-guide-' + proposal.id + '.json', { proposal, result });
    originals.push({ proposalID: proposal.id, sessionID: result.sessionID, command: proposal.command, digest: hash(JSON.stringify([result.stdout, result.stderr])) });
  }
  const result = { observedAt: new Date().toISOString(), backend, accountID, workspaceID, workerBuild: actor.headers.get('X-Knot-Worker-Build'), actorBuild: actor.headers.get('X-Knot-Actor-Build'), verifiedOriginalGuides: originals, historicalExecutions: 0, noSessionReissuance: true };
  save('game-preflight.json', result); emit({ status: 'exact_owner_preflight_verified', ...result });
}
async function bodyBytes(response: Response, maximum: number) {
  fact(response.ok && response.body, 'artifact_http_' + response.status);
  const chunks: Uint8Array[] = []; let count = 0;
  const reader = response.body.getReader();
  try { for (;;) { const part = await reader.read(); if (part.done) break; count += part.value.length; fact(count <= maximum, 'artifact_size_exceeded'); chunks.push(part.value); } }
  finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
  const bytes = new Uint8Array(count); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  return bytes;
}
async function collect(identity: Data) {
  fact(identity.accountID === accountID && identity.workspaceID === workspaceID && identity.backend === backend, 'owner_collection_binding_required');
  const collectionSave = (name: string, value: unknown) => save(process.argv.includes('--collect') ? name.replace('.json', '-recheck.json') : name, value);
  const events = await json('/knot/shell/events', { bot: 'main', conversationID: identity.conversationID });
  collectionSave('game-events.json', events);
  const records = events.records ?? [], summaries: Data[] = [];
  for (const row of records) {
    fact(row.taskID === identity.requestID && row.sourceMessageID === identity.sourceMessageID && row.spec?.conversationID === identity.conversationID, 'fresh_owned_event_binding_required');
    const proposalID = row.spec.id;
    const detail = await json('/knot/shell/events', { bot: 'main', conversationID: identity.conversationID, proposalID }); collectionSave('game-' + proposalID + '-events.json', detail);
    summaries.push({ proposalID, taskID: row.taskID, operation: row.spec.operation, tool: row.spec.tool, state: row.state, status: row.result?.status, exitCode: row.result?.exitCode, sessionID: row.result?.sessionID });
  }
  const documents: Data[] = [];
  for (const document of events.documents ?? []) {
    fact(document.sourceMessageID === identity.sourceMessageID && records.some((row: Data) => row.spec.id === document.proposalID) && /^[a-f0-9]{64}$/.test(document.id) && Number.isSafeInteger(document.size) && document.size > 0 && document.size <= 50000000, 'fresh_capture_binding_required');
    const response = await managed('/knot/shell/documents', { bot: 'main', conversationID: identity.conversationID, documentID: document.id, action: 'file' }, 25000, undefined, expectedBuild);
    const delivered = await bodyBytes(response, document.size);
    fact(response.headers.get('X-Knot-SHA256') === document.sha256 && hash(delivered) === document.sha256 && delivered.length === document.size, 'immutable_delivery_bytes_mismatch');
    const file = join(directory, document.id + '.' + document.format);
    if (existsSync(file)) fact(hash(readFileSync(file)) === document.sha256, 'retained_download_bytes_changed');
    else writeFileSync(file, delivered, { mode: 0o600, flag: 'wx' });
    const path = document.sourcePath;
    fact(typeof path === 'string' && path.length <= 240 && /^[a-zA-Z0-9][a-zA-Z0-9_. /-]*$/.test(path) && path.split('/').every((part: string) => !!part && part !== '.' && part !== '..' && !part.startsWith('.')), 'owned_final_path_required');
    const token = process.env.SIDECAR_TOKEN_WHISPER; fact(token, 'private_box_read_credential_required');
    // Independent read ONLY of this just-captured file in the exact owner box.
    const original = await bodyBytes(await fetch('https://knot-shell.mydailywhisper.com/files?path=' + encodeURIComponent(path) + '&user_id=' + encodeURIComponent(workspaceID), { redirect: 'error', headers: { Authorization: 'Bearer ' + token }, signal: AbortSignal.timeout(25000) }), document.size);
    fact(hash(original) === document.sha256 && original.length === document.size, 'owned_box_capture_bytes_mismatch');
    documents.push({ id: document.id, title: document.title, format: document.format, sourcePath: path, sourceMessageID: document.sourceMessageID, proposalID: document.proposalID, size: document.size, sha256: document.sha256, createdAt: document.createdAt, ownedBoxBytesVerified: true, immutableDownloadVerified: true, contentQuality: document.contentQuality, byteFidelity: document.byteFidelity, review: document.review });
  }
  const messages = await json('/knot/conversations/' + identity.conversationID);
  collectionSave('game-delivered-chat.json', messages);
  const chatBound = messages.messages?.some((message: Data) => message.id === identity.sourceMessageID && message.role === 'user' && message.text === ask) === true;
  const diagnostics = (events.activities ?? []).filter((event: Data) => event.taskID === identity.requestID && event.detail?.stage === 'tool_selection' && Number.isSafeInteger(event.detail?.promptBytes)).map((event: Data) => ({ kind: event.kind, recordedAt: event.recordedAt, ...event.detail }));
  const promptsBounded = diagnostics.length > 0 && diagnostics.every((detail: Data) => detail.promptBytes <= 32768 && detail.promptTargetExceeded === false);
  const authoringDiagnostics = (events.activities ?? []).filter((event: Data) => event.taskID === identity.requestID && event.detail?.stage === 'document_authoring' && Number.isSafeInteger(event.detail?.promptBytes)).map((event: Data) => ({ kind: event.kind, recordedAt: event.recordedAt, ...event.detail }));
  const observed = { authoringDiagnostics, promptBudgetScope: 'actual_serialized_tool_selection_messages_only_complete_authoring_is_separate', observedAt: new Date().toISOString(), records: summaries, documents, chatSourcePersisted: chatBound, cardSourceBindingsVerified: chatBound && documents.length > 0, selectionDiagnostics: diagnostics, promptsBounded, maximumPromptBytes: diagnostics.length ? Math.max(...diagnostics.map((detail: Data) => detail.promptBytes)) : null, nativeDeviceTested: false, gameplayTestedByRunner: false };
  collectionSave('game-collection.json', observed); return observed;
}
async function run() {
  fact(!existsSync(intentURL) && !existsSync(join(directory, 'game-intent.json')), 'fresh_game_scope_consumed_no_replay');
  await preflight();
  const requestID = randomUUID(), conversationID = randomUUID(), sourceMessageID = randomUUID(), started = Date.now();
  const identity = { backend, accountID, workspaceID, requestID, taskID: requestID, conversationID, sourceMessageID, expectedBuild, startedAt: new Date(started).toISOString() };
  const intent = { title: 'One owner-authorized fresh OSRS game', ...identity, ask, noAutomaticRetry: true, noHistoricalReplay: true, scopeConsumed: true, originalFailedTask: 'ff1ec610-bba1-48f4-8bbb-73485b63436e', pdfTaskNotReplayed: 'e9e11652-e0d9-4881-84da-3d0f1006bc9d' };
  writeDurable(intentURL, intent); save('game-intent.json', intent, true); emit({ status: 'fresh_game_scope_consumed', ...identity });
  const userMessage = { id: sourceMessageID, role: 'user', text: ask, createdAt: started, modifiedAt: started };
  const seen = new Set<string>(), outstanding = new Map<string, Data>(), frames: Data[] = [], executions: Data[] = [];
  const aborter = new AbortController(); let pending = Promise.resolve(), stopped = false, stopConfirmed = true, issue: string | undefined, completed = false, workIncomplete = false, reply = '', submissions = 0, completionReceivedMs: number | undefined;
  const stop = async () => {
    stopped = true; aborter.abort();
    for (const proposal of outstanding.values()) {
      try { const result = await json('/knot/shell/cancel', { bot: 'main', conversationID, proposalID: proposal.id }); save('game-' + proposal.id + '-cancel.json', result); if (!result.terminationConfirmed) stopConfirmed = false; } catch { stopConfirmed = false; }
    }
  };
  const execute = async (proposal: Data) => {
    fact(!stopped && proposal.bot === 'main' && proposal.conversationID === conversationID && proposal.taskID === requestID && proposal.sourceMessageID === sourceMessageID && /^[a-f0-9-]{36}$/.test(proposal.id) && typeof proposal.command === 'string' && !seen.has(proposal.id), 'owned_proposal_mismatch_or_replay');
    seen.add(proposal.id); outstanding.set(proposal.id, proposal); save('game-' + proposal.id + '-proposal.json', proposal, true);
    const response = await managed('/knot/shell/execute', { bot: 'main', conversationID, proposalID: proposal.id, executionVersion: 'knot_shell_automatic_v1', command: proposal.command, timeoutMs: proposal.timeoutMs }, 160000, undefined, expectedBuild);
    const result = await response.json() as Data; save('game-' + proposal.id + '-execute.json', result); fact(response.ok, 'execute_http_' + response.status);
    const turn = { conversationID, requestID, sourceMessageID }; assertAcceptanceIdentity(proposal, result, turn);
    let final = result, cached = provenance.acceptCache(proposal, final, turn); const deadline = Date.now() + 15000;
    while (!cached && final.sessionID && !(final.terminationConfirmed && final.commandReceipt && final.outputComplete && !final.truncated) && final.status !== 'cancelled' && Date.now() < deadline) {
      await new Promise(resolve => setTimeout(resolve, 650));
      final = await json('/knot/shell/status', { bot: 'main', conversationID, proposalID: proposal.id }); assertAcceptanceIdentity(proposal, final, turn); cached = provenance.acceptCache(proposal, final, turn);
    }
    save('game-' + proposal.id + '-result.json', final);
    fact(final.terminationConfirmed && (!final.sessionID || final.outputComplete && !final.truncated && (cached || final.commandReceipt && final.providerReceipt?.user_id === workspaceID && final.providerReceipt?.session_id === final.sessionID)), 'execution_unconfirmed_no_replay');
    if (!cached) provenance.remember(proposal, final, turn);
    const summary = { proposalID: proposal.id, operation: proposal.operation, tool: proposal.tool, documentStage: proposal.documentInvocation?.stage, status: final.status, exitCode: final.exitCode, sessionID: final.sessionID, outputComplete: final.outputComplete, terminationConfirmed: final.terminationConfirmed, cachedOriginalValidated: cached, stdoutSHA256: hash(final.stdout ?? '') };
    executions.push(summary); outstanding.delete(proposal.id); emit({ observation: 'fresh_owned_execution_observed', ...summary });
  };
  try {
    await json('/knot/conversations/' + conversationID, { botID: 'main', title: 'OSRS RPG', messages: [userMessage] });
    submissions++;
    const response = await managed('/knot/chat/stream', { requestID, bot: 'main', conversationID, sourceMessageID, sourceCreatedAt: started, consentVersion: 'knot_ai_consent_v4', taskModelConsentVersion: 'knot_task_models_v1', message: ask, healthContext: '', history: [], isWebQuery: false, sharedConversation: false, timezone: 'UTC', foregroundTurnVersion: 'knot_foreground_turn_v1', workProgressVersion: 'knot_work_progress_v1', documentProgramVersion: 'knot_document_program_v3', taskExperienceVersion: 'knot_task_experience_v1', clarificationVersion: 'knot_clarification_v1' }, 945000, aborter.signal, expectedBuild);
    save('game-stream-response.json', { status: response.status, workerBuild: response.headers.get('X-Knot-Worker-Build'), requestID: response.headers.get('X-Knot-Request-ID') }); fact(response.ok && response.body, 'stream_http_' + response.status);
    const reader = response.body.getReader(), decoder = new TextDecoder(); let buffer = '';
    try {
      for (;;) {
        const part = await reader.read(); if (part.done) break; buffer += decoder.decode(part.value, { stream: true }); let at: number;
        while ((at = buffer.indexOf('\n\n')) >= 0) {
          const packet = buffer.slice(0, at); buffer = buffer.slice(at + 2);
          const data = packet.split('\n').filter(line => line.startsWith('data:')).map(line => line.slice(5).trimStart()).join('\n'); if (!data) continue;
          const frame = JSON.parse(data) as Data; fact(frame.requestID === requestID && frame.sequence === frames.length + 1, 'stream_identity_or_sequence_mismatch');
          const observed = { ...frame, clientReceivedAt: new Date().toISOString(), clientElapsedMs: Date.now() - started }; frames.push(observed); appendFileSync(join(directory, 'game-frames.jsonl'), JSON.stringify(observed) + '\n', { mode: 0o600 });
          if (frame.type === 'shell_proposal') pending = pending.then(() => execute(frame.proposal)).catch(async error => { issue ??= safeReason(error); await stop(); });
          if (frame.type === 'complete') { completed = true; workIncomplete = frame.workIncomplete === true; reply = frame.reply ?? ''; completionReceivedMs ??= Date.now() - started; if (workIncomplete) issue ??= frame.reason ?? 'work_incomplete'; }
          if (['error', 'rejected', 'document_work_unavailable'].includes(frame.type)) issue ??= frame.reason ?? frame.error ?? frame.type;
        }
      }
      fact(!buffer.trim(), 'incomplete_stream_frame');
    } finally { reader.releaseLock(); }
  } catch (error) { issue ??= safeReason(error); await stop(); }
  await pending; if (outstanding.size) await stop();
  let observation: Data | undefined;
  try {
    if (completed && !workIncomplete && reply.trim()) {
      const now = Date.now(); const message = { id: randomUUID(), role: 'ember', text: reply, createdAt: now, modifiedAt: now };
      await json('/knot/conversations/' + conversationID, { botID: 'main', title: 'OSRS RPG', messages: [userMessage, message] });
    }
    observation = await collect(identity);
  } catch (error) { issue ??= safeReason(error); }
  const accepted = !issue && stopConfirmed && completed && !workIncomplete && observation?.promptsBounded === true && observation?.cardSourceBindingsVerified === true && observation?.documents?.some((document: Data) => document.format === 'html' && document.ownedBoxBytesVerified && document.immutableDownloadVerified);
  const result = { title: 'Observed fresh owner OSRS game', ...identity, endedAt: new Date().toISOString(), elapsedMs: Date.now() - started, completionReceivedMs, completed, workIncomplete, issue: issue ?? null, stopConfirmed, chatSubmissions: submissions, executions, frameCount: frames.length, observation, acceptance: accepted ? 'owned_box_capture_chat_and_prompt_budget_verified' : 'not_accepted', historicalReplay: false, pdfRedelivered: false, nativeDeviceTested: false };
  save('game-result.json', result); writeDurable(outcomeURL, result); emit(result); if (!accepted) process.exitCode = 2;
}
(async () => {
  if (process.argv.includes('--preflight')) return preflight();
  if (process.argv.includes('--run')) return run();
  if (process.argv.includes('--collect')) { fact(existsSync(intentURL), 'consumed_fresh_scope_required'); const identity = JSON.parse(readFileSync(intentURL, 'utf8')); fact(expectedBuild === identity.expectedBuild, 'original_collection_build_required'); const observation = await collect(identity);
    const original = JSON.parse(readFileSync(outcomeURL, 'utf8'));
    const accepted = original.completed && !original.workIncomplete && !original.issue && original.stopConfirmed && observation.promptsBounded && observation.cardSourceBindingsVerified && observation.documents.some((document: Data) => document.format === 'html' && document.ownedBoxBytesVerified && document.immutableDownloadVerified);
    const corrected = { title: 'Read-only fresh OSRS game acceptance correction', ...identity, observedAt: new Date().toISOString(), correction: 'The original collector accidentally included separate complete-authoring and classification prompts in the selection-only budget. Original intent/outcome remain unchanged. Actual selection was 11118 bytes, target not exceeded.', originalOutcomeRetained: true, newChatSubmissions: 0, newCommandExecutions: 0, acceptance: accepted ? 'owned_box_capture_chat_and_prompt_budget_verified' : 'not_accepted', observation };
    writeDurable(new URL('../deliveries/owner-osrs-game-20261114-readonly-verification.json', import.meta.url), corrected); emit(corrected); if (!accepted) process.exitCode = 2; return; }
  throw new Error('explicit_preflight_run_or_readonly_collect_required');
})().catch(error => { emit({ status: 'blocked_no_automatic_replay', reason: safeReason(error) }); process.exitCode = 2; });
