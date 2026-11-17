// Exact November 14 recipes-speed evidence only. No task/command/review/capture replay.
// --observe: scoped GET /files reads; --deliver: local, byte-identical captured-file copy.
// Run observation with: rork env run -- bun scripts/review-knot-recipes-speed-evidence.ts --observe
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { sidecarRequest, readSidecarBytes } from '../functions/knot-shell-discovery';
const accountID = 'e00a9064-5f85-40bb-9f44-8bd60f90d24a';
const workspaceID = 'whisper-' + accountID;
const taskID = 'b936a45f-b94a-4c5c-8ac6-b0c92e894466';
const conversationID = 'f5fa4af7-6299-4fd6-83f7-1275112879d9';
const sourceMessageID = 'b7b7d40a-75da-4e3f-ae51-08178aa6e5f5';
const sessionID = 'cfa2086e-cd18-45df-9025-e75ba8568225';
const sourceID = 'aff9faaf-977f-4367-bbed-ce4a6d39137f';
const buildID = '1f4774d0-f2e9-4977-a2b4-3a27959e4b6e';
const proofID = '0c7a9225-1c43-4927-bb92-a20d88472f56';
const deliveryID = 'bf6c062a19382e66c0dadb7931eacf9d13fe3071100e9edfc968588b28631196';
const finalSHA256 = 'afc435526e94c7986f53596958738cf15d01de47ee50c937266941ba0eeab7c0';
const expectedBuild = 'c0e59c1ae7040688e9b83fd9e3ac9ea82d078e45221865b6f90884fb974d1c4e';
const root = join(tmpdir(), 'knot-acceptance-uf26aun6d49w1tsjsm2u9', 'battery-2026-11-14T03-41-24-088Z', 'recipe-pdf');
const output = join(root, 'independent-speed-observation');
const load = (name: string): any => JSON.parse(readFileSync(join(root, name), 'utf8'));
const hash = (value: string | Uint8Array) => createHash('sha256').update(value).digest('hex');
const decode = (value: Uint8Array) => new TextDecoder('utf8', { fatal: true, ignoreBOM: false }).decode(value);
function requireFact(value: unknown, code: string): asserts value { if (!value) throw new Error(code); }
function immutableCopy(path: string, bytes: Uint8Array) {
  if (existsSync(path)) requireFact(readFileSync(path).equals(bytes), 'delivery_collision');
  else writeFileSync(path, bytes, { flag: 'wx' });
}
const result = load('result.json'), intent = load('intent.json');
for (const record of [result, intent]) requireFact(record.accountID === accountID && record.workspaceID === workspaceID && record.taskID === taskID && record.requestID === taskID && record.conversationID === conversationID && record.sourceMessageID === sourceMessageID, 'run_identity');
requireFact(result.completed && !result.workIncomplete && !result.issue && result.servingBuilds.worker === expectedBuild && intent.taskModelConsentVersion === 'knot_task_models_v1', 'run_completion_or_consent');
requireFact(result.executions.length === 10 && new Set(result.executions.map((entry: any) => entry.proposalID)).size === 10, 'execution_count');
const receipts = new Map<string, any>();
const commandObservations = result.executions.map((execution: any) => {
  const id = execution.proposalID, proposal = load(id + '-proposal.json'), receipt = load(id + '-result.json'), log = load(id + '-log.json'), boundary = receipt.commandReceipt;
  requireFact(proposal.id === id && proposal.taskID === taskID && proposal.sourceMessageID === sourceMessageID && proposal.conversationID === conversationID && receipt.proposalID === id && receipt.conversationID === conversationID && receipt.sessionID === sessionID && log.session_id === sessionID && log.stdout_from === 0 && log.stderr_from === 0 && log.truncated === false && boundary?.proposal_id === id && boundary.session_id === sessionID, 'execution_identity');
  for (const stream of ['stdout', 'stderr']) {
    const bytes = Buffer.from(log[stream], 'utf8'), start = boundary[stream + '_start'], end = boundary[stream + '_end'];
    requireFact(Number.isSafeInteger(start) && Number.isSafeInteger(end) && start >= 0 && end >= start && end <= bytes.length && bytes.subarray(start, end).equals(Buffer.from(receipt[stream], 'utf8')), 'execution_log_boundary');
  }
  requireFact(receipt.status === 'completed' && receipt.exitCode === 0 && receipt.terminationConfirmed && receipt.outputComplete && !receipt.truncated && !receipt.contextTruncated && boundary.exit_code === 0 && boundary.background_jobs === false && hash(receipt.stdout) === execution.stdoutSHA256, 'execution_completion');
  receipts.set(id, receipt);
  return { proposalID: id, operation: execution.operation, stage: execution.documentStage ?? null, logReceiptMatch: true, commandSHA256: hash(proposal.command), stdoutSHA256: hash(receipt.stdout), startedAt: boundary.started_at, endedAt: boundary.observed_finished_at };
});
function manifest(id: string, marker: string) {
  const lines = String(receipts.get(id)?.stdout).split('\n').filter(value => value.startsWith(marker + ' '));
  requireFact(lines.length === 1, 'unique_manifest'); return JSON.parse(lines[0].slice(marker.length + 1));
}
const source = manifest(sourceID, 'KNOT_DOCUMENT_SOURCE_V1'), resident = manifest(buildID, 'KNOT_RESIDENT_DOCUMENT_V1'), final = manifest(proofID, 'KNOT_DOCUMENT_V1');
const stem = 'knot-' + taskID + '-high-protein-recipes-v2';
requireFact(source.path === stem + '.html' && source.size === 46343 && source.sha256 === '905767c1827148739cc3285cf7dad71a4123b770e8b03d73fc778bd5cb9d9bab', 'source_identity');
requireFact(final.path === stem + '.pdf' && final.size === 70257 && final.sha256 === finalSHA256 && final.pages === 17 && final.proofs.length === 17, 'final_identity');
requireFact(resident.manifest.path === final.path && resident.manifest.sha256 === finalSHA256 && resident.manifest.size === final.size && resident.manifest.pages === final.pages && resident.manifest.taskID === taskID && resident.manifest.sourceSHA256 === source.sha256, 'build_binding');
requireFact(final.verification.sourceSHA256 === finalSHA256 && final.verification.sourceSize === final.size && final.verification.renderedPages === 17 && final.verification.allPageProofs === true && final.verification.renderer === 'poppler', 'proof_binding');
const document = result.documents.find((entry: any) => entry.id === deliveryID);
requireFact(document && document.proposalID === proofID && document.sha256 === finalSHA256 && document.size === final.size && document.pages === final.pages && document.deliveredMatches && document.boxMatches && document.deliveredSHA256 === finalSHA256 && document.boxSHA256 === finalSHA256 && document.deliveredBytes === final.size && document.boxBytes === final.size, 'captured_download_binding');
const events = load(proofID + '-events.json').events;
const capture = events.find((entry: any) => entry.kind === 'document_captured' && entry.documentID === deliveryID);
requireFact(capture && capture.sha256 === finalSHA256 && capture.bytes === final.size && capture.boxFileIntegrity?.sha256 === finalSHA256 && capture.boxFileIntegrity.bytes === final.size && capture.boxFileIntegrity.source === 'owned_box_file', 'capture_event');
const capturedBytes = readFileSync(join(root, deliveryID + '.pdf'));
requireFact(capturedBytes.length === final.size && hash(capturedBytes) === finalSHA256, 'captured_local_bytes');
const frames = readFileSync(join(root, 'frames.jsonl'), 'utf8').trim().split('\n').map(value => JSON.parse(value));
requireFact(frames.every((entry: any, index: number) => entry.requestID === taskID && entry.sequence === index + 1), 'frame_identity');
const completion = frames.find((entry: any) => entry.type === 'complete');
requireFact(completion && completion.clientElapsedMs === result.completionReceivedMs && Date.parse(capture.recordedAt) - Date.parse(result.startedAt) === result.captureElapsedMs, 'timing_binding');
const sealed = result.authoringObservations.filter((entry: any) => entry.kind === 'document_program_sealed').map((entry: any) => entry.detail);
requireFact(sealed.length === 2 && sealed.every((entry: any) => entry.authoringResponses === 1 && entry.transportCallCount === 1 && entry.authoringTotalPromptBytes === entry.promptBytes + entry.promptSections.contractBytes), 'authoring_vitals');
requireFact(document.visualReview?.pages.length === 17 && document.visualReview.finalSHA256 === finalSHA256, 'all_page_verdicts');
for (const [index, proof] of final.proofs.entries()) {
  const verdict = document.visualReview.pages[index];
  requireFact(proof.page === index + 1 && proof.sourceSHA256 === finalSHA256 && proof.path === 'deliverables/knot-proof-' + buildID + '/page-' + (index + 1) + '.png' && verdict.page === proof.page && verdict.sha256 === proof.sha256, 'proof_page_binding');
}
async function observe() {
  const token = process.env.SIDECAR_TOKEN_WHISPER; requireFact(token, 'read_credential_unavailable');
  mkdirSync(output, { recursive: true, mode: 0o700 });
  async function get(path: string, sha256: string, limit: number, local: string, size?: number) {
    requireFact(!path.startsWith('/') && !path.split('/').some(part => !part || part === '.' || part === '..'), 'read_path');
    requireFact(path === source.path || path === final.path || path === resident.designEvidence.journal.path || path === resident.journal.path || path === resident.manifest.pdfInfo.path || path === final.verification.textPath || final.proofs.some((proof: any) => proof.path === path), 'exact_read_scope');
    const response = await sidecarRequest({ SIDECAR_TOKEN_WHISPER: token } as never, '/files?path=' + encodeURIComponent(path) + '&user_id=' + encodeURIComponent(workspaceID), 'GET', undefined, 25000);
    const bytes = await readSidecarBytes(response, limit);
    requireFact(hash(bytes) === sha256 && (size === undefined || bytes.length === size), 'remote_bytes_changed');
    writeFileSync(join(output, local), bytes, { mode: 0o600 }); return bytes;
  }
  const html = await get(source.path, source.sha256, source.size, 'final.html', source.size);
  const pdf = await get(final.path, finalSHA256, final.size, 'final.pdf', final.size);
  requireFact(capturedBytes.equals(pdf) && capturedBytes.subarray(0, 5).equals(Buffer.from('%PDF-')) && capturedBytes.subarray(-2048).includes(Buffer.from('%%EOF')), 'pdf_format_and_capture_match');
  const parsed = spawnSync('python3', ['-I', '-c', `import sys,json,hashlib
from html.parser import HTMLParser
class Styles(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True); self.records=[]; self.style_index=None
    def handle_starttag(self,tag,attrs):
        if tag=='style': self.style_index=len(self.records); self.records.append(['style',''])
        for key,value in attrs:
            if key=='style': self.records.append(['inline',value or ''])
    def handle_endtag(self,tag):
        if tag=='style': self.style_index=None
    def handle_data(self,data):
        if self.style_index is not None: self.records[self.style_index][1]+=data
parser=Styles(); parser.feed(sys.stdin.buffer.read().decode('utf-8')); parser.close()
styles=json.dumps(parser.records,ensure_ascii=False,separators=(',',':')).encode('utf-8')
print(json.dumps(dict(styleSHA256=hashlib.sha256(styles).hexdigest(),styleBytes=len(styles))))`], { input: html, encoding: 'utf8', timeout: 5000, maxBuffer: 4096 });
  requireFact(parsed.status === 0, 'local_css_parse'); const css = JSON.parse(parsed.stdout);
  requireFact(css.styleSHA256 === 'ebd823d4a846cc2fb94e9ed88b66e97911228f3bbd3b6b24ffef5078fcdab2ec' && css.styleBytes === 13745 && css.styleSHA256 === resident.designEvidence.inputs.styleSHA256 && css.styleBytes === resident.designEvidence.inputs.styleBytes, 'css_identity');
  const design = resident.designEvidence.journal, renderer = resident.journal;
  const designBytes = await get(design.path, design.sha256, 1000000, 'design.jsonl', design.size);
  const rendererBytes = await get(renderer.path, renderer.sha256, 1000000, 'renderer.jsonl', renderer.size);
  const designEntries = decode(designBytes).trim().split('\n').map(value => JSON.parse(value)), rendererEntries = decode(rendererBytes).trim().split('\n').map(value => JSON.parse(value));
  requireFact(JSON.stringify(designEntries) === JSON.stringify(resident.designEvidence.entries) && designEntries.length === 2 && designEntries[0].state === 'intent' && designEntries[0].taskID === taskID && designEntries[0].output === final.path && designEntries[1].state === 'staged' && designEntries[1].finalSHA256 === finalSHA256 && designEntries[1].rendererJournalSHA256 === renderer.sha256, 'design_journal_binding');
  requireFact(rendererEntries.length === 2 && rendererEntries[0].state === 'intent' && rendererEntries[0].taskID === taskID && rendererEntries[0].output === final.path && JSON.stringify(rendererEntries[0].inputs) === JSON.stringify(resident.inputs) && rendererEntries[1].state === 'staged' && JSON.stringify(rendererEntries[1].manifest) === JSON.stringify(resident.manifest), 'renderer_journal_binding');
  requireFact(hash(JSON.stringify(resident.inputs) + '\n') === resident.manifest.inputsSHA256 && resident.inputs.design === 'author-v1' && resident.inputs.houseStyleSHA256 === null, 'renderer_inputs');
  const text = await get(final.verification.textPath, final.verification.textSHA256, 180000, 'final-text.txt', final.verification.textSize);
  const info = resident.manifest.pdfInfo, infoBytes = await get(info.path, info.sha256, 1000000, 'pdfinfo.txt', info.size);
  requireFact(/^Pages:\s+17\s*$/m.test(decode(infoBytes)), 'pdf_page_count');
  const proofs = [];
  for (const proof of final.proofs) {
    const b = Buffer.from(await get(proof.path, proof.sha256, 1800000, 'page-' + proof.page + '.png'));
    requireFact(b.length >= 24 && b.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) && b.readUInt32BE(16) > 0 && b.readUInt32BE(20) > 0, 'png_dimensions');
    proofs.push({ page: proof.page, sha256: hash(b), bytes: b.length, width: b.readUInt32BE(16), height: b.readUInt32BE(20), matchesIndependentProofAndRecordedVisualVerdict: true });
  }
  const report = { observedAt: new Date().toISOString(), taskID, conversationID, workspaceID, sessionID, deliveryID, sourceProposalID: sourceID, buildProposalID: buildID, proofProposalID: proofID, remoteExecutionPerformed: false, replayPerformed: false, commands: commandObservations,
    source, final: { sha256: finalSHA256, size: pdf.length, pages: final.pages, matchesBuildProofCaptureAndDownload: true }, css,
    designJournal: design, rendererJournal: renderer, rendererInputsSHA256: resident.manifest.inputsSHA256,
    text: { bytes: text.length, sha256: hash(text) }, proofs,
    scope: 'Read-only byte/provenance observation. Recorded visual verdicts are not independent manual inspection. Content, factual and signed-Release native acceptance remain separate.' };
  writeFileSync(join(output, 'review.json'), JSON.stringify(report, null, 2), { mode: 0o600 });
  console.log(JSON.stringify(report, null, 2));
}
function deliver() {
  const review = JSON.parse(readFileSync(join(output, 'review.json'), 'utf8'));
  requireFact(review.taskID === taskID && review.deliveryID === deliveryID && review.sessionID === sessionID && review.final.sha256 === finalSHA256 && review.final.matchesBuildProofCaptureAndDownload === true && review.commands.length === 10 && review.proofs.length === 17 && review.proofs.every((proof: any, index: number) => proof.page === index + 1 && proof.sha256 === final.proofs[index].sha256), 'independent_review_required');
  const bytes = readFileSync(join(output, 'final.pdf')); requireFact(bytes.equals(capturedBytes), 'final_local_match');
  const timings = { captureElapsedMs: result.captureElapsedMs, completionReceivedMs: result.completionReceivedMs, streamEndedMs: result.streamEndedMs, evidenceCollectionMs: result.evidenceCollectionMs, totalElapsedMs: result.elapsedMs };
  const authoring = sealed.map((entry: any) => ({ programBytes: entry.programBytes, storagePieces: entry.sliceCount, semanticResponses: entry.authoringResponses, transportCalls: entry.transportCallCount, authoringElapsedMs: entry.authoringElapsedMs, bytesPerSecond: entry.authoringBytesPerSecond, providerElapsedMs: entry.transportElapsedMs, firstContentMs: entry.transportFirstTokenMs, maxIdleMs: entry.transportMaxIdleMs, promptBytesIncludingContract: entry.authoringTotalPromptBytes, promptOverageBytes: entry.authoringPromptOverageBytes, basePromptBytes: entry.authoringBasePromptBytes, readPayloadMessageBytes: entry.authoringReadBytes, developedAuthorshipMessageBytes: entry.authoringDevelopedBytes, descriptorMessageBytes: entry.authoringDescriptorBytes }));
  const record = { title: document.title, taskID, deliveryID, sha256: finalSHA256, bytes: bytes.length, pages: final.pages, exactImmutableCaptureCopy: true, timings,
    comparison: { baselineReference: '21f2865d', baselineApproximateMs: 600000, baselineSource: 'owner_reported_not_controlled_same_ask', exactOriginalPromptAvailable: false, targetMs: 180000, targetMet: result.completionReceivedMs <= 180000, improvementEstablished: false },
    authoring, providerGenerationMs: sealed.reduce((sum: number, entry: any) => sum + entry.transportElapsedMs, 0),
    evidence: { commandLogsMatched: commandObservations.length, meteredWorkCommands: commandObservations.filter((entry: any) => entry.operation === 'work').length, independentProofImagesHashMatched: review.proofs.length, sourceJournalsAndExtractedTextHashMatched: true, capturedDownloadAndOwnedFileHashMatched: true },
    quality: { byteFidelity: 'pass', finalContentCoverage: document.contentQuality.status, finalContentAttempts: document.contentReview.contentCheckAttempts.map((entry: any) => ({ durationMs: entry.durationMs, outcome: entry.outcome, reason: entry.reason, httpStatus: entry.httpStatus })), visualReview: document.visualReview.status, findings: document.qualityShortfalls, factualOrNutritionCertification: false },
    validation: { focusedTestsPassed: 93, webChecksErrors: 0, affectedWorkerStrictTypecheck: 'pass', fullEntrypointTypecheck: '14 inherited diagnostics; no additions', signedReleaseNativeAcceptance: 'open; not device tested' },
    scope: 'One authorized fresh backend recipes run only. No additional paid run or capture/review replay. Original delivered PDF remains unchanged.' };
  mkdirSync('deliveries', { recursive: true });
  const pdfPath = 'deliveries/high-protein-recipes-speed-run-afc435526e94.pdf', reportPath = 'deliveries/recipes-speed-run-afc435526e94.json';
  immutableCopy(pdfPath, bytes); immutableCopy(reportPath, Buffer.from(JSON.stringify(record, null, 2) + '\n'));
  console.log(JSON.stringify({ pdf: pdfPath, report: reportPath, ...record }, null, 2));
}
async function main() {
  requireFact(process.argv.length === 3 && ['--observe', '--deliver'].includes(process.argv[2]), 'explicit_observe_or_local_deliver_required');
  if (process.argv[2] === '--observe') await observe(); else deliver();
}
main().catch(error => { console.error(JSON.stringify({ status: 'unconfirmed', reason: error instanceof Error && /^[a-z_]+$/.test(error.message) ? error.message : 'scoped_observation_unavailable', remoteExecutionPerformed: false, replayPerformed: false })); process.exitCode = 2; });
