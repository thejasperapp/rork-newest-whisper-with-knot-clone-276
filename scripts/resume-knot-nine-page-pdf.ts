// Owner-authorized exact nine-page final only. Never authors, executes, renders,
// rebuilds or replays a shell command. One request intent precedes review I/O.
// Run: rork env run -- bun scripts/resume-knot-nine-page-pdf.ts --resume
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createHash, randomUUID } from 'node:crypto';
const backend = 'https://uf26aun6d49w1tsjsm2u9-backend.rork.app';
const accountID = 'e00a9064-5f85-40bb-9f44-8bd60f90d24a';
const conversationID = '9a113989-c49c-44e1-bd44-058507b3b11b';
const proposalID = '2166cf20-62a1-4f8b-8214-8f0163dc7746';
const sha256 = 'b2fee52770cb06b4b69bcbdf2af708a51e97e113a3ebefa2ccb90ae5ca350a88';
const privateRoot = join(tmpdir(), 'knot-acceptance-uf26aun6d49w1tsjsm2u9');
const output = join(privateRoot, 'nine-page-pdf-review-continuation');
const hash = (bytes: Uint8Array) => createHash('sha256').update(bytes).digest('hex');
const account = JSON.parse(readFileSync(join(privateRoot, 'account.json'), 'utf8'));
if (account.accountID !== accountID || account.projectRef !== 'uryyyegnbtlmyhqlgndy' || !account.accessToken) throw new Error('dedicated_identity_required');
const save = (name: string, value: unknown) => writeFileSync(join(output, name), JSON.stringify(value, null, 2), { mode: 0o600 });
async function request(body: unknown, maximumMs = 25000) {
  return fetch(backend + '/knot/shell/documents', { method: 'POST', redirect: 'error', headers: { 'X-Whisper-Authorization': 'Bearer ' + account.accessToken, 'Content-Type': 'application/json' }, body: JSON.stringify({ bot: 'main', conversationID, ...body as object }), signal: AbortSignal.timeout(maximumMs) });
}
async function json(response: Response) {
  const data = await response.json() as Record<string, any>;
  if (!response.ok) throw new Error(typeof data.error === 'string' && /^[a-z_]+$/.test(data.error) ? data.error : 'http_' + response.status);
  return data;
}
async function observe() {
  const response = await fetch(backend + '/knot/shell/events', { method: 'POST', redirect: 'error', headers: { 'X-Whisper-Authorization': 'Bearer ' + account.accessToken, 'Content-Type': 'application/json' }, body: JSON.stringify({ bot: 'main', conversationID, proposalID }), signal: AbortSignal.timeout(25000) });
  const events = await json(response); save('events.json', events);
  const listing = await json(await request({ action: 'list' })); save('documents.json', listing);
  return listing;
}
async function main() {
  if (!process.argv.includes('--resume') && !process.argv.includes('--observe')) throw new Error('explicit_resume_or_observe_required');
  mkdirSync(output, { recursive: true, mode: 0o700 });
  if (process.argv.includes('--resume')) {
    const intentPath = join(output, 'intent.json');
    if (existsSync(intentPath)) throw new Error('review_already_requested_observe_only');
    const reviewResume = { version: 'knot_document_review_resume_v1', id: randomUUID(), taskID: '7028348c-fbea-44f8-9608-1170a8b72696', sourceMessageID: '3e4856f6-a5e6-43c1-a08d-dd0f23737fef', sourceProposalID: '353cface-c2f7-43cd-b88c-edca865e095d', buildProposalID: '135beb44-97de-4191-9bc6-c6f9857b1984', finalSHA256: sha256, finalSize: 47014, pages: 9 };
    writeFileSync(intentPath, JSON.stringify({ observedAt: new Date().toISOString(), accountID, conversationID, proposalID, reviewResume, noAutomaticRetry: true, noRebuild: true }), { flag: 'wx', mode: 0o600 });
    try {
      const response = await request({ action: 'resume_review', proposalID, consentVersion: 'knot_ai_consent_v4', visualReviewAllowed: true, reviewResume, expiresAt: Date.now() + 175000 }, 180000);
      const result = await response.json(); save('response.json', { observedAt: new Date().toISOString(), status: response.status, result });
      console.log(JSON.stringify({ phase: 'review_response', status: response.status, result }));
    } catch { save('response-unconfirmed.json', { observedAt: new Date().toISOString(), noReplay: true }); }
  }
  const listing = await observe();
  const document = listing.documents?.find((item: Record<string, any>) => item.proposalID === proposalID && item.sha256 === sha256 && item.size === 47014 && item.pages === 9 && item.format === 'pdf');
  if (!document) { console.log(JSON.stringify({ status: 'not_captured', noRebuild: true, output })); return; }
  const response = await request({ action: 'file', documentID: document.id });
  if (!response.ok || response.headers.get('X-Knot-SHA256') !== sha256 || response.headers.get('Content-Type') !== 'application/pdf') throw new Error('delivery_headers');
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.length !== 47014 || hash(bytes) !== sha256) throw new Error('delivery_bytes');
  writeFileSync(join(output, 'captured-original.pdf'), bytes, { mode: 0o600 });
  mkdirSync('deliveries', { recursive: true });
  const deliveryPath = 'deliveries/high-protein-recipes-nine-pages-' + sha256.slice(0, 12) + '.pdf';
  if (existsSync(deliveryPath)) { if (hash(readFileSync(deliveryPath)) !== sha256) throw new Error('delivery_collision'); }
  else writeFileSync(deliveryPath, bytes, { flag: 'wx' });
  for (let i = 0; i < document.proofPages.length; i++) {
    const preview = await request({ action: 'preview', documentID: document.id, pageIndex: i });
    if (!preview.ok) throw new Error('preview_unavailable');
    writeFileSync(join(output, 'captured-page-' + document.proofPages[i] + '.png'), new Uint8Array(await preview.arrayBuffer()), { mode: 0o600 });
  }
  const result = { status: 'captured_and_original_download_verified', observedAt: new Date().toISOString(), document, deliveryPath, deliveredSHA256: hash(bytes), deliveredBytes: bytes.length, noRebuild: true };
  save('delivery.json', result); console.log(JSON.stringify(result));
}
main().catch(error => { console.error(JSON.stringify({ status: 'unconfirmed', reason: error instanceof Error && /^[a-z0-9_]+$/.test(error.message) ? error.message : 'review_transport_unavailable', noRebuild: true, noAutomaticRetry: true })); process.exitCode = 2; });
