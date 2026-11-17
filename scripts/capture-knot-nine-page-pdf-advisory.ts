// Explicit unchanged-final capture only. No author, AI, shell, build, renderer,
// verifier or memory requests. New routing authorization, never old-intent reset.
// --preflight: read only; --capture: exactly one new-route attempt; --observe: reads.
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createHash, randomUUID } from 'node:crypto';
import type { KnotDocument, DocumentManifest } from '../functions/knot-documents';
import { knotSourceBuildSHA256 } from '../functions/knot-source-build';
const backend = 'https://uf26aun6d49w1tsjsm2u9-backend.rork.app';
const accountID = 'e00a9064-5f85-40bb-9f44-8bd60f90d24a';
const taskID = '7028348c-fbea-44f8-9608-1170a8b72696';
const conversationID = '9a113989-c49c-44e1-bd44-058507b3b11b';
const sourceMessageID = '3e4856f6-a5e6-43c1-a08d-dd0f23737fef';
const sourceProposalID = '353cface-c2f7-43cd-b88c-edca865e095d';
const buildProposalID = '135beb44-97de-4191-9bc6-c6f9857b1984';
const proposalID = '2166cf20-62a1-4f8b-8214-8f0163dc7746';
const reviewResumeID = '14416f3a-169a-4ef1-8cb5-471956ab2256';
const sha256 = 'b2fee52770cb06b4b69bcbdf2af708a51e97e113a3ebefa2ccb90ae5ca350a88';
const privateRoot = join(tmpdir(), 'knot-acceptance-uf26aun6d49w1tsjsm2u9');
const output = join(privateRoot, 'nine-page-pdf-advisory-routed-capture');
const hash = (bytes: Uint8Array) => createHash('sha256').update(bytes).digest('hex');
function fact(value: unknown, code: string): asserts value { if (!value) throw new Error(code); }
type Event = Record<string, unknown> & { sequence: number; kind: string; proposalID: string };
type Diagnostic = { requestID: string | null; workerBuildSHA256: string | null; actorBuildSHA256: string | null; handler: string | null };
type Status = { captureHandler: string; trace: Diagnostic; manifest: DocumentManifest; reviewResume: { id: string; state: string; issue: string; finalSHA256: string }; advisoryCapture: unknown };
const account = JSON.parse(readFileSync(join(privateRoot, 'account.json'), 'utf8')) as { accountID: string; projectRef: string; accessToken: string };
fact(account.accountID === accountID && account.projectRef === 'uryyyegnbtlmyhqlgndy' && account.accessToken, 'dedicated_identity_required');
const claims = JSON.parse(Buffer.from(account.accessToken.split('.')[1], 'base64url').toString()) as { sub: string; exp: number };
fact(claims.sub === accountID && claims.exp * 1000 > Date.now() + 120000, 'dedicated_auth_refresh_required');
const save = (name: string, value: unknown) => writeFileSync(join(output, name), JSON.stringify(value, null, 2), { mode: 0o600 });
async function request(path: 'documents' | 'events' | 'documents/capture-advisory' | 'documents/capture-status', body: object, maximumMs = 25000) {
  return fetch(backend + '/knot/shell/' + path, { method: 'POST', redirect: 'error', headers: { 'X-Whisper-Authorization': 'Bearer ' + account.accessToken, 'Content-Type': 'application/json' }, body: JSON.stringify({ bot: 'main', conversationID, ...body }), signal: AbortSignal.timeout(maximumMs) });
}
function diagnostic(response: Response): Diagnostic { return { requestID: response.headers.get('X-Knot-Request-ID'), workerBuildSHA256: response.headers.get('X-Knot-Worker-Build'), actorBuildSHA256: response.headers.get('X-Knot-Actor-Build'), handler: response.headers.get('X-Knot-Handler') }; }
function checkTrace(trace: Diagnostic, handler: string) {
  fact(trace.requestID && /^[a-f0-9-]{36}$/.test(trace.requestID) && trace.workerBuildSHA256 === knotSourceBuildSHA256 && trace.actorBuildSHA256 === knotSourceBuildSHA256 && trace.handler === handler, 'actual_serving_build_or_handler_mismatch');
}
async function json<T>(response: Response): Promise<T> { fact(response.ok, 'http_' + response.status); return await response.json() as T; }
async function observe(label: string) {
  const events = await json<{ events: Event[] }>(await request('events', { proposalID }));
  const listing = await json<{ documents: KnotDocument[] }>(await request('documents', { action: 'list' }));
  fact(Array.isArray(events.events) && Array.isArray(listing.documents), 'observation_shape');
  save(label + '-events.json', events); save(label + '-documents.json', listing);
  const historical = events.events.find(event => event.sequence === 925);
  fact(historical?.proposalID === proposalID && historical.kind === 'document_visual_blocked' && historical.resumeID === reviewResumeID && historical.issue === 'document_visual_incomplete' && Array.isArray(historical.observations) && historical.observations.length === 3, 'historical_finding_binding');
  fact(events.events.some(event => event.sequence === 920 && event.kind === 'document_visual_blocked'), 'original_event_preserved');
  return { events: events.events, documents: listing.documents, historical };
}
async function preflight(label: string) {
  const response = await request('documents/capture-status', { proposalID });
  const trace = diagnostic(response), raw = await response.text();
  save(label + '-status.json', { observedAt: new Date().toISOString(), status: response.status, trace, raw });
  fact(response.ok, 'preflight_http_' + response.status); checkTrace(trace, 'capture_status');
  const status = JSON.parse(raw) as Status;
  fact(status.captureHandler === 'capture_advisory' && status.trace.requestID === trace.requestID && status.trace.workerBuildSHA256 === trace.workerBuildSHA256 && status.trace.actorBuildSHA256 === trace.actorBuildSHA256, 'preflight_trace_binding');
  fact(status.reviewResume?.id === reviewResumeID && status.reviewResume.state === 'finished' && status.reviewResume.issue === 'document_visual_incomplete' && status.reviewResume.finalSHA256 === sha256, 'completed_review_binding');
  const m = status.manifest;
  fact(m?.sha256 === sha256 && m.size === 47014 && m.pages === 9 && m.format === 'pdf' && m.proofs.length === 9 && m.proofs.every(p => p.sourceSHA256 === sha256), 'retained_manifest_binding');
  return { status, trace };
}
async function main() {
  const capture = process.argv.includes('--capture'), onlyPreflight = process.argv.includes('--preflight');
  fact(Number(capture) + Number(onlyPreflight) + Number(process.argv.includes('--observe')) === 1, 'explicit_capture_preflight_or_observe_required');
  mkdirSync(output, { recursive: true, mode: 0o700 });
  const before = await observe('before');
  const verified = await preflight('before');
  if (onlyPreflight) { console.log(JSON.stringify({ status: 'read_only_preflight_verified', observedAt: new Date().toISOString(), preflightState: verified.status, trace: verified.trace, lastEventSequence: Math.max(...before.events.map(e => e.sequence)), documentsForProof: before.documents.filter(d => d.proposalID === proposalID).length, captureAttempted: false, output })); return; }
  const intentPath = join(output, 'new-route-intent.json');
  if (capture) {
    fact(!before.documents.some(document => document.proposalID === proposalID), 'already_captured_observe_only');
    fact(verified.status.advisoryCapture === null && !before.events.some(e => e.kind === 'document_advisory_capture_started'), 'server_intent_consumed_observe_only');
    fact(!existsSync(intentPath), 'new_route_capture_already_requested_observe_only');
    const advisoryCapture = { version: 'knot_document_advisory_capture_v1', id: randomUUID(), taskID, sourceMessageID, sourceProposalID, buildProposalID, proofProposalID: proposalID, finalSHA256: sha256, finalSize: 47014, pages: 9, reviewResumeID, eventSequence: 925, noFurtherRepair: true };
    writeFileSync(intentPath, JSON.stringify({ observedAt: new Date().toISOString(), accountID, conversationID, proposalID, advisoryCapture, verifiedServingSourceBuild: knotSourceBuildSHA256, priorAttempt: { at: '2026-11-14T01:35:17.700Z', http: 400, error: 'invalid_document', historicalServingBuild: 'unknown', originalPrivateIntentFile: 'not_available_in_this_sandbox' }, newAuthorization: 'fix_explicit_routing_add_request_build_logs_then_one_capture', noAutomaticRetry: true, noRebuild: true, noNewReview: true }), { flag: 'wx', mode: 0o600 });
    try {
      const response = await request('documents/capture-advisory', { action: 'capture_advisory', proposalID, consentVersion: 'knot_ai_consent_v4', visualReviewAllowed: true, advisoryCapture, expiresAt: Date.now() + 44000 }, 48000);
      const trace = diagnostic(response), result = await response.json(); save('response.json', { observedAt: new Date().toISOString(), status: response.status, trace, result });
      console.log(JSON.stringify({ phase: 'capture_response', status: response.status, trace, result }));
      checkTrace(trace, 'capture_advisory');
    } catch { save('response-unconfirmed.json', { observedAt: new Date().toISOString(), noReplay: true }); }
  }
  const after = await observe('after');
  fact(JSON.stringify(before.historical) === JSON.stringify(after.historical), 'historical_finding_unchanged');
  const document = after.documents.find(item => item.proposalID === proposalID && item.sha256 === sha256 && item.size === 47014 && item.pages === 9 && item.format === 'pdf');
  const newEvents = after.events.filter(event => event.sequence > 925);
  if (!document) { console.log(JSON.stringify({ status: 'not_captured', observedAt: new Date().toISOString(), postReviewEvents: newEvents, advisoryCaptureStartObserved: newEvents.some(e => e.kind === 'document_advisory_capture_started'), noReplay: true, noRebuild: true, output })); process.exitCode = 2; return; }
  fact(existsSync(intentPath), 'capture_intent_required_for_delivery');
  const intent = JSON.parse(readFileSync(intentPath, 'utf8'));
  const start = newEvents.find(e => e.kind === 'document_advisory_capture_started' && e.captureID === intent.advisoryCapture.id);
  fact(start && typeof start.requestID === 'string', 'capture_start_event_required');
  const capturedEvent = newEvents.find(e => e.kind === 'document_captured' && e.documentID === document.id);
  fact(capturedEvent && capturedEvent.requestID === start.requestID && capturedEvent.sha256 === sha256 && capturedEvent.bytes === 47014, 'captured_event_binding');
  for (const e of [start, capturedEvent]) fact(e.handler === 'capture_advisory' && e.workerBuildSHA256 === knotSourceBuildSHA256 && e.actorBuildSHA256 === knotSourceBuildSHA256, 'capture_event_serving_build_binding');
  const box = capturedEvent.boxFileIntegrity as { source: string; sha256: string; bytes: number };
  fact(box?.source === 'owned_box_file' && box.sha256 === sha256 && box.bytes === 47014, 'actual_box_file_hash_required');
  fact(newEvents.some(e => e.kind === 'document_advisory_capture_finished' && e.documentID === document.id && e.requestID === start.requestID && e.newExecution === false && e.newReview === false), 'finished_event_binding');
  fact(document.review === 'issues' && document.contentReview?.status === 'unconfirmed' && !document.visualReview && document.visualAdvisory?.eventSequence === 925 && document.visualAdvisory.resumeID === reviewResumeID && JSON.stringify(document.visualAdvisory.observations) === JSON.stringify(after.historical.observations), 'honest_review_metadata');
  const allowed = new Set(['document_advisory_capture_started', 'document_advisory_capture_finished', 'document_fidelity_verified', 'document_content_quality', 'document_proof_passed', 'document_content_unconfirmed', 'document_quality_shortfalls', 'document_visual_advisory', 'document_captured']);
  fact(newEvents.every(e => allowed.has(e.kind)), 'unexpected_post_review_event');
  const response = await request('documents', { action: 'file', documentID: document.id });
  fact(response.ok && response.headers.get('X-Knot-SHA256') === sha256 && response.headers.get('Content-Type') === 'application/pdf', 'delivery_headers');
  const bytes = new Uint8Array(await response.arrayBuffer()); fact(bytes.length === box.bytes && hash(bytes) === box.sha256, 'download_matches_measured_box_bytes');
  writeFileSync(join(output, 'captured-original.pdf'), bytes, { mode: 0o600 });
  const manifest = verified.status.manifest;
  fact(JSON.stringify(document.proofPages) === JSON.stringify([1, 2, 3, 4, 5, 6, 7, 8, 9]), 'all_proof_pages');
  const previews = [];
  for (let i = 0; i < 9; i++) {
    const preview = await request('documents', { action: 'preview', documentID: document.id, pageIndex: i }); fact(preview.ok, 'preview_unavailable');
    const image = new Uint8Array(await preview.arrayBuffer()), proof = manifest.proofs.find(p => p.page === i + 1);
    fact(proof?.sourceSHA256 === sha256 && hash(image) === proof.sha256, 'preview_proof_binding');
    writeFileSync(join(output, 'captured-page-' + (i + 1) + '.png'), image, { mode: 0o600 }); previews.push({ page: i + 1, sha256: hash(image), bytes: image.length });
  }
  mkdirSync('deliveries', { recursive: true });
  const deliveryPath = 'deliveries/high-protein-recipes-nine-pages-' + sha256.slice(0, 12) + '.pdf';
  if (existsSync(deliveryPath)) fact(hash(readFileSync(deliveryPath)) === sha256, 'delivery_collision');
  else writeFileSync(deliveryPath, bytes, { flag: 'wx' });
  const result = { status: 'captured_and_original_download_verified', observedAt: new Date().toISOString(), requestID: start.requestID, handler: start.handler, workerBuildSHA256: start.workerBuildSHA256, actorBuildSHA256: start.actorBuildSHA256, captureStartEvent: start.sequence, capturedEvent: capturedEvent.sequence, boxFileIntegrity: box, document, deliveryPath, deliveredSHA256: hash(bytes), deliveredBytes: bytes.length, previews, newEvents: newEvents.map(e => ({ sequence: e.sequence, kind: e.kind, recordedAt: e.recordedAt })), noRebuild: true, noNewReview: true, historicalFindingsPreserved: true };
  save('delivery.json', result); console.log(JSON.stringify(result));
}
main().catch(error => { console.error(JSON.stringify({ status: 'unconfirmed', reason: error instanceof Error && /^[a-z0-9_]+$/.test(error.message) ? error.message : 'capture_transport_unavailable', noRebuild: true, noAutomaticRetry: true })); process.exitCode = 2; });
