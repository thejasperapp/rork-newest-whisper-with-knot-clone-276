// Scoped, read-only evidence review for a newly consumed recipes repair scope.
// Never executes commands, renders, reviews with a provider or captures again.
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createHash } from 'node:crypto';
import { AcceptanceSkillProvenance, assertAcceptanceIdentity } from './knot-acceptance-provenance';
import { sidecarRequest, readSidecarBytes } from '../functions/knot-shell-discovery';
const [mode, scope] = process.argv.slice(2);
function fact(value: unknown, code: string): asserts value { if (!value) throw new Error(code); }
const hash = (value: string | Uint8Array) => createHash('sha256').update(value).digest('hex');
const loadAt = (dir: string, name: string): any => JSON.parse(readFileSync(join(dir, name), 'utf8'));
const base = join(tmpdir(), 'knot-acceptance-uf26aun6d49w1tsjsm2u9');
const accountID = 'e00a9064-5f85-40bb-9f44-8bd60f90d24a', workspaceID = 'whisper-' + accountID;
const sessionID = 'cfa2086e-cd18-45df-9025-e75ba8568225';
function immutable(path: string, bytes: Uint8Array) {
  if (existsSync(path)) fact(readFileSync(path).equals(bytes), 'immutable_collision');
  else writeFileSync(path, bytes, { flag: 'wx' });
}
async function main() {
  fact(process.argv.length === 4 && ['--inspect', '--observe', '--deliver'].includes(mode) && /^20261114-[a-z][a-z0-9-]{0,60}$/.test(scope ?? ''), 'explicit_scope_required');
  const once = loadAt(base, 'recipes-repair-' + scope + '-once-intent.json');
  const durable = loadAt('deliveries', 'recipes-paid-scope-' + scope + '.json');
  const terminal = loadAt('deliveries', 'recipes-paid-outcome-' + scope + '.json');
  fact(once.scope === scope && once.authorization === 'explicit_user_paid_document_repair_iterations_2026_11_14' && once.freshTaskOnly && once.noAutomaticRetry && once.accountID === accountID && once.workspaceID === workspaceID && once.backend === 'https://uf26aun6d49w1tsjsm2u9-backend.rork.app' && once.directory.startsWith(base + '/battery-') && durable.scopeConsumed && durable.taskID === terminal.taskID && durable.expectedBuild === once.expectedBuild, 'owned_paid_scope');
  const root = join(once.directory, 'recipe-pdf'), load = (name: string) => loadAt(root, name);
  const result = load('result.json'), intent = load('intent.json'), setup = loadAt(base, 'setup-repair-' + scope + '.json');
  const { taskID, conversationID, sourceMessageID } = result;
  for (const record of [result, intent, durable, terminal]) fact(record.accountID === accountID && record.workspaceID === workspaceID && record.taskID === taskID && record.requestID === taskID && record.conversationID === conversationID && record.sourceMessageID === sourceMessageID, 'exact_run_identity');
  fact(result.completed && result.stopConfirmed && !result.issue && !result.workIncomplete && result.servingBuilds.worker === once.expectedBuild && intent.taskModelConsentVersion === 'knot_task_models_v1' && setup.servingBuilds['/knot/shell/events'].worker === once.expectedBuild && setup.servingBuilds['/knot/shell/events'].actor === once.expectedBuild && Date.parse(intent.startedAt) >= Date.parse(setup.observedAt) && Date.parse(intent.startedAt) - Date.parse(setup.observedAt) < 300000, 'completed_canonical_run');
  const frames = readFileSync(join(root, 'frames.jsonl'), 'utf8').trim().split('\n').map(value => JSON.parse(value));
  fact(frames.length === result.frameCount && frames.every((frame: any, index: number) => frame.requestID === taskID && frame.sequence === index + 1 && (!frame.activity || frame.activity.taskID === taskID && frame.activity.sourceMessageID === sourceMessageID)), 'ordered_frames');
  fact(frames.find((frame: any) => frame.type === 'complete')?.clientElapsedMs === result.completionReceivedMs, 'completion_clock');
  const provenance = new AcceptanceSkillProvenance({ accountID, workspaceID });
  const original = loadAt(once.directory, 'recovered-original-guide-provenance.json'), originalID = '9924aed8-6462-4db0-a779-a0f0400495b0';
  fact(original.proposal.id === originalID && hash(JSON.stringify([original.original.stdout, original.original.stderr])) === 'f82c7eb4ecd411664199f5d16f42afe4dc53651a69400c7537685d72bb78be0e', 'original_hash');
  provenance.remember(original.proposal, original.original, { requestID: 'b936a45f-b94a-4c5c-8ac6-b0c92e894466', conversationID: 'f5fa4af7-6299-4fd6-83f7-1275112879d9', sourceMessageID: 'b7b7d40a-75da-4e3f-ae51-08178aa6e5f5' });
  const receipts = new Map<string, any>(), manifests: { id: string; marker: string; value: any }[] = [], checks: any[] = [], relevantEvents: any[] = [];
  const commands = result.executions.map((execution: any) => {
    const id = execution.proposalID, proposal = load(id + '-proposal.json'), receipt = load(id + '-result.json');
    assertAcceptanceIdentity(proposal, receipt, { requestID: taskID, conversationID, sourceMessageID });
    fact(receipt.sessionID === sessionID && receipt.status === 'completed' && receipt.exitCode === 0 && receipt.terminationConfirmed && receipt.outputComplete && !receipt.truncated && !receipt.contextTruncated && hash(receipt.stdout) === execution.stdoutSHA256, 'complete_receipt');
    receipts.set(id, receipt);
    const cached = !!receipt.cachedData;
    if (cached) fact(receipt.cachedData.sourceProposalID === originalID && provenance.acceptCache(proposal, receipt, { requestID: taskID, conversationID, sourceMessageID }), 'original_cache_binding');
    else {
      const log = load(id + '-log.json'), boundary = receipt.commandReceipt;
      fact(boundary?.source === 'harness_shell_boundaries_v1' && boundary.proposal_id === id && boundary.session_id === sessionID && boundary.exit_code === 0 && boundary.background_jobs === false && log.session_id === sessionID && log.stdout_from === 0 && log.stderr_from === 0 && !log.truncated && receipt.providerReceipt?.user_id === workspaceID && receipt.providerReceipt.output_complete && receipt.providerReceipt.output_late_bytes === 0, 'owned_foreground_boundary');
      for (const stream of ['stdout', 'stderr']) {
        const bytes = Buffer.from(log[stream]), start = boundary[stream + '_start'], end = boundary[stream + '_end'];
        fact(Number.isSafeInteger(start) && Number.isSafeInteger(end) && start >= 0 && end >= start && end <= bytes.length && bytes.subarray(start, end).equals(Buffer.from(receipt[stream])), 'exact_log_bytes');
      }
    }
    for (const marker of ['KNOT_DOCUMENT_SOURCE_V1', 'KNOT_RESIDENT_DOCUMENT_V1', 'KNOT_DOCUMENT_V1']) {
      const lines = receipt.stdout.split('\n').filter((line: string) => line.startsWith(marker + ' '));
      fact(lines.length <= 1, 'unique_manifest');
      if (lines.length) manifests.push({ id, marker, value: JSON.parse(lines[0].slice(marker.length + 1)) });
    }
    const events = load(id + '-events.json').events ?? [];
    for (const event of events) {
      if (event.check) checks.push({ proposalID: id, kind: event.kind, recordedAt: event.recordedAt, check: event.check });
      if (/document_(?:visual|content|captured|quality)/.test(event.kind)) relevantEvents.push({ proposalID: id, kind: event.kind, recordedAt: event.recordedAt, status: event.status, issue: event.issue, observations: event.observations, review: event.review, attempt: event.attempt, delivered: event.delivered, blocking: event.blocking });
    }
    return { proposalID: id, operation: execution.operation, stage: execution.documentStage, tool: execution.tool, newExecution: !cached, exactCompleteOutputVerified: true, commandSHA256: hash(proposal.command), stdoutSHA256: hash(receipt.stdout) };
  });
  fact(new Set(commands.map((entry: any) => entry.proposalID)).size === commands.length && result.documents.length === 1, 'unique_execution_and_document');
  const document = result.documents[0];
  const finalEntry = manifests.find(entry => entry.id === document.proposalID && entry.marker === 'KNOT_DOCUMENT_V1');
  fact(finalEntry, 'captured_proof_manifest');
  const final = finalEntry.value;
  const residentEntry = manifests.find(entry => entry.marker === 'KNOT_RESIDENT_DOCUMENT_V1' && entry.value.manifest.sha256 === final.sha256);
  fact(residentEntry, 'bound_build_manifest');
  const resident = residentEntry.value;
  const sourceEntry = manifests.find(entry => entry.marker === 'KNOT_DOCUMENT_SOURCE_V1' && entry.value.sha256 === resident.manifest.sourceSHA256);
  fact(sourceEntry, 'bound_source_manifest');
  const source = sourceEntry.value;
  fact(final.sha256 === document.sha256 && final.path === document.name && final.size === document.size && final.pages === document.pages && resident.manifest.path === final.path && resident.manifest.taskID === taskID && resident.manifest.size === final.size && resident.manifest.pages === final.pages && final.verification.sourceSHA256 === final.sha256 && final.verification.sourceSize === final.size && final.verification.renderedPages === final.pages && final.verification.allPageProofs && final.verification.renderer === 'poppler' && final.proofs.length === final.pages, 'source_build_proof_capture_binding');
  const captureEvent = load(document.proposalID + '-events.json').events.find((entry: any) => entry.kind === 'document_captured' && entry.documentID === document.id);
  fact(captureEvent && captureEvent.sha256 === final.sha256 && captureEvent.bytes === final.size && captureEvent.boxFileIntegrity?.sha256 === final.sha256 && captureEvent.boxFileIntegrity.bytes === final.size && captureEvent.boxFileIntegrity.source === 'owned_box_file' && Date.parse(captureEvent.recordedAt) - Date.parse(result.startedAt) === result.captureElapsedMs, 'capture_binding');
  const captured = readFileSync(join(root, document.id + '.pdf'));
  fact(captured.length === final.size && hash(captured) === final.sha256 && document.deliveredMatches && document.boxMatches && document.deliveredSHA256 === final.sha256 && document.boxSHA256 === final.sha256 && document.deliveredBytes === final.size && document.boxBytes === final.size, 'download_original_bytes');
  const output = join(root, 'independent-delivery-observation');
  const authoring = result.authoringObservations.filter((entry: any) => ['document_program_sealed', 'model_transport_outcome', 'tool_request_rejected'].includes(entry.kind));
  const summary = { scope, taskID, conversationID, sourceMessageID, sourceBuildSHA256: once.expectedBuild, preflightObservedAt: setup.observedAt, startedAt: result.startedAt, endedAt: result.endedAt,
    timing: { captureMs: result.captureElapsedMs, completionMs: result.completionReceivedMs, streamEndedMs: result.streamEndedMs, evidenceCollectionMs: result.evidenceCollectionMs, totalMs: result.elapsedMs },
    orderedFrames: frames.length, commands, sourceChecks: checks, relevantEvents, authoring, document, manifests: manifests.map(entry => ({ ...entry, value: entry.marker === 'KNOT_RESIDENT_DOCUMENT_V1' ? { manifest: entry.value.manifest, designEvidence: entry.value.designEvidence, journal: entry.value.journal, inputs: entry.value.inputs } : entry.value })),
    historicalReplay: false, baselineRawEvidenceRecovered: false, newRemoteCommands: 0, newProviderCalls: 0 };
  if (mode === '--inspect') { console.log(JSON.stringify(summary, null, 2)); return; }
  if (mode === '--observe') {
    const token = process.env.SIDECAR_TOKEN_WHISPER; fact(token, 'private_read_credential_required');
    mkdirSync(output, { recursive: true, mode: 0o700 });
    const allow = [source, final, resident.designEvidence.journal, resident.journal, resident.manifest.pdfInfo, { path: final.verification.textPath, sha256: final.verification.textSHA256, size: final.verification.textSize }, ...final.proofs];
    async function get(info: any, name: string, max = 1800000) {
      fact(allow.includes(info) && typeof info.path === 'string' && !info.path.startsWith('/') && !info.path.split('/').some((part: string) => !part || part === '.' || part === '..'), 'exact_read_scope');
      const response = await sidecarRequest({ SIDECAR_TOKEN_WHISPER: token } as never, '/files?path=' + encodeURIComponent(info.path) + '&user_id=' + encodeURIComponent(workspaceID), 'GET', undefined, 25000);
      const bytes = Buffer.from(await readSidecarBytes(response, info.size ?? max));
      fact(hash(bytes) === info.sha256 && (info.size === undefined || info.size === bytes.length), 'remote_hash_size');
      writeFileSync(join(output, name), bytes, { mode: 0o600 }); return bytes;
    }
    await get(source, 'source.html');
    const pdf = await get(final, 'final.pdf');
    fact(pdf.equals(captured) && pdf.subarray(0, 5).equals(Buffer.from('%PDF-')) && pdf.subarray(-2048).includes(Buffer.from('%%EOF')), 'valid_original_pdf');
    const design = await get(resident.designEvidence.journal, 'design.jsonl'), renderer = await get(resident.journal, 'renderer.jsonl');
    const parseLines = (b: Buffer) => b.toString('utf8').trim().split('\n').map(line => JSON.parse(line));
    const d = parseLines(design), r = parseLines(renderer);
    fact(JSON.stringify(d) === JSON.stringify(resident.designEvidence.entries) && d.length === 2 && d[0].state === 'intent' && d[0].taskID === taskID && d[0].output === final.path && d[1].state === 'staged' && d[1].finalSHA256 === final.sha256 && d[1].rendererJournalSHA256 === resident.journal.sha256, 'design_journal');
    fact(r.length === 2 && r[0].state === 'intent' && r[0].taskID === taskID && r[0].output === final.path && JSON.stringify(r[0].inputs) === JSON.stringify(resident.inputs) && r[1].state === 'staged' && JSON.stringify(r[1].manifest) === JSON.stringify(resident.manifest) && hash(JSON.stringify(resident.inputs) + '\n') === resident.manifest.inputsSHA256, 'renderer_journal');
    const text = await get(allow[5], 'final-text.txt');
    const info = await get(resident.manifest.pdfInfo, 'pdfinfo.txt');
    fact(new RegExp('^Pages:\\s+' + final.pages + '\\s*$', 'm').test(info.toString('utf8')), 'page_count');
    const pages = [];
    for (const [index, proof] of final.proofs.entries()) {
      fact(proof.page === index + 1 && proof.sourceSHA256 === final.sha256 && proof.path === 'deliverables/knot-proof-' + residentEntry.id + '/page-' + proof.page + '.png', 'proof_identity');
      const bytes = await get(proof, 'page-' + proof.page + '.png');
      fact(bytes.length > 24 && bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])), 'proof_png');
      const downloaded = document.downloadedProofs[index];
      fact(downloaded.page === proof.page && downloaded.sha256 === proof.sha256 && downloaded.bytes === bytes.length, 'download_proof_matches_original');
      if (document.visualReview) fact(document.visualReview.finalSHA256 === final.sha256 && document.visualReview.pages[index]?.page === proof.page && document.visualReview.pages[index]?.sha256 === proof.sha256, 'visual_verdict_binding');
      pages.push({ page: proof.page, bytes: bytes.length, sha256: hash(bytes), width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) });
    }
    const observation = { observedAt: new Date().toISOString(), taskID, documentID: document.id, finalSHA256: final.sha256, finalBytes: final.size, sourceSHA256: source.sha256, sourceBytes: source.size, textSHA256: hash(text), textBytes: text.length, pages, originalBuildProofCaptureDownloadAgree: true, completeSourceAndTextRead: true, journalsVerified: true, allPageAIReviewPresent: !!document.visualReview && document.visualReview.pages.length === final.pages, noNewExecutionOrReview: true };
    writeFileSync(join(output, 'observation.json'), JSON.stringify(observation, null, 2), { mode: 0o600 });
    console.log(JSON.stringify(observation, null, 2)); return;
  }
  const observation = loadAt(output, 'observation.json');
  fact(observation.taskID === taskID && observation.documentID === document.id && observation.finalSHA256 === final.sha256 && observation.originalBuildProofCaptureDownloadAgree && observation.completeSourceAndTextRead && observation.journalsVerified && observation.pages.length === final.pages, 'independent_read_required');
  const pdf = readFileSync(join(output, 'final.pdf')); fact(pdf.equals(captured), 'observed_capture_bytes');
  const suffix = final.sha256.slice(0, 12), pdfPath = 'deliveries/high-protein-recipes-repair-' + suffix + '.pdf', reportPath = 'deliveries/recipes-repair-' + taskID.slice(0, 8) + '.json';
  const report = { title: document.title, ...summary, observation, delivery: { path: pdfPath, id: document.id, sha256: final.sha256, bytes: final.size, pages: final.pages, exactImmutableCaptureCopy: true }, quality: { content: document.contentQuality?.status, visual: document.visualReview?.status ?? 'unavailable', reviewIssue: document.reviewIssue ?? null, certified: false }, comparison: { baselineCompletionMs: 603097, targetMs: 330000, successfulQualityAcceptance: document.contentQuality?.status === 'pass' && document.visualReview?.status === 'pass', targetMet: result.completionReceivedMs <= 330000, speedImprovementEstablished: false }, nativeDeviceAcceptance: 'not performed' };
  immutable(pdfPath, pdf); immutable(reportPath, Buffer.from(JSON.stringify(report, null, 2) + '\n'));
  console.log(JSON.stringify({ pdf: pdfPath, report: reportPath, taskID, timing: report.timing, quality: report.quality, comparison: report.comparison }, null, 2));
}
main().catch(error => { console.error(JSON.stringify({ status: 'unconfirmed', reason: error instanceof Error && /^[a-z_]+$/.test(error.message) ? error.message : 'scoped_review_unavailable', credentialsPrinted: false, commandsExecuted: 0, providerCalls: 0 })); process.exitCode = 2; });
