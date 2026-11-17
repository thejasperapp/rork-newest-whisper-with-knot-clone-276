// Read only the exact third candidate from the authorized November 14 battery.
// No shell dispatch, rendering, replay, repair, adoption, capture or owner access.
// Run: rork env run -- bun scripts/review-knot-funded-pdf-evidence.ts
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { TextDecoder } from 'node:util';
import { sidecarRequest, readSidecarBytes } from '../functions/knot-shell-discovery';
const workspaceID = 'whisper-e00a9064-5f85-40bb-9f44-8bd60f90d24a';
const taskID = '7028348c-fbea-44f8-9608-1170a8b72696';
const conversationID = '9a113989-c49c-44e1-bd44-058507b3b11b';
const sessionID = 'b07b1d7d-a49a-4d3b-bd84-7bab81cca227';
const sourceMessageID = '3e4856f6-a5e6-43c1-a08d-dd0f23737fef';
const sourceID = '353cface-c2f7-43cd-b88c-edca865e095d';
const buildID = '135beb44-97de-4191-9bc6-c6f9857b1984';
const proofID = '2166cf20-62a1-4f8b-8214-8f0163dc7746';
const root = join(tmpdir(), 'knot-acceptance-uf26aun6d49w1tsjsm2u9', 'battery-2026-11-14T00-28-27-797Z', 'recipe-pdf');
const output = join(root, 'independent-final-observation');
const load = (name: string) => JSON.parse(readFileSync(join(root, name), 'utf8'));
const hash = (data: string | Uint8Array) => createHash('sha256').update(data).digest('hex');
const decode = (data: Uint8Array) => new TextDecoder('utf8', { fatal: true }).decode(data);
function requireFact(condition: unknown, code: string): asserts condition { if (!condition) throw new Error(code); }
function receipt(id: string) {
  const proposal = load(id + '-proposal.json'), result = load(id + '-result.json');
  requireFact(proposal.id === id && proposal.taskID === taskID && proposal.sourceMessageID === sourceMessageID && proposal.conversationID === conversationID, 'proposal_identity');
  requireFact(result.proposalID === id && result.conversationID === conversationID && result.sessionID === sessionID && result.status === 'completed' && result.exitCode === 0 && result.outputComplete && result.terminationConfirmed && !result.truncated && !result.contextTruncated, 'receipt_identity');
  const log = load(id + '-log.json'), b = result.commandReceipt;
  requireFact(log.session_id === sessionID && log.truncated === false && log.stdout_from === 0 && log.stderr_from === 0 && b.proposal_id === id && b.session_id === sessionID && b.exit_code === 0, 'log_identity');
  for (const stream of ['stdout', 'stderr']) {
    const bytes = Buffer.from(log[stream], 'utf8'), start = b[stream + '_start'], end = b[stream + '_end'];
    requireFact(Number.isSafeInteger(start) && Number.isSafeInteger(end) && start >= 0 && end >= start && end <= bytes.length && bytes.subarray(start, end).equals(Buffer.from(result[stream], 'utf8')), 'log_bytes');
  }
  return result;
}
function line(result: { stdout: string }, marker: string) {
  const lines = result.stdout.split('\n').filter(value => value.startsWith(marker + ' '));
  requireFact(lines.length === 1, 'unique_manifest');
  return JSON.parse(lines[0].slice(marker.length + 1));
}
async function main() {
  const intent = load('intent.json');
  requireFact(intent.workspaceID === workspaceID && intent.taskID === taskID && intent.conversationID === conversationID, 'intent_identity');
  const source = line(receipt(sourceID), 'KNOT_DOCUMENT_SOURCE_V1');
  const resident = line(receipt(buildID), 'KNOT_RESIDENT_DOCUMENT_V1');
  const final = line(receipt(proofID), 'KNOT_DOCUMENT_V1');
  const path = 'knot-' + taskID + '-high-protein-recipes-v3';
  requireFact(source.path === path + '.html' && source.size === 33528 && source.sha256 === '4666779b3dc205168461f21e1c6a66044491338b8040e2c73798639eecc40b9e', 'source_identity');
  requireFact(final.path === path + '.pdf' && final.size === 47014 && final.sha256 === 'b2fee52770cb06b4b69bcbdf2af708a51e97e113a3ebefa2ccb90ae5ca350a88' && final.pages === 9 && final.proofs.length === 9, 'final_identity');
  requireFact(resident.manifest.path === final.path && resident.manifest.sha256 === final.sha256 && resident.manifest.size === final.size && resident.manifest.pages === final.pages && resident.manifest.taskID === taskID && resident.manifest.sourceSHA256 === source.sha256, 'build_identity');
  requireFact(final.verification.sourceSHA256 === final.sha256 && final.verification.sourceSize === final.size && final.verification.renderedPages === 9 && final.verification.allPageProofs === true && final.verification.renderer === 'poppler', 'proof_identity');
  const token = process.env.SIDECAR_TOKEN_WHISPER;
  requireFact(token, 'read_credential_unavailable');
  mkdirSync(output, { recursive: true, mode: 0o700 });
  async function get(remotePath: string, sha256: string, max: number, local: string, size?: number) {
    requireFact(!remotePath.startsWith('/') && !remotePath.split('/').some(part => !part || part === '.' || part === '..'), 'read_path');
    requireFact(remotePath === source.path || remotePath === final.path || remotePath.startsWith('.knot-doc/design/' + taskID + '/') || remotePath.startsWith('.knot-doc/v2/' + taskID + '/') || remotePath.startsWith('deliverables/knot-proof-' + buildID + '/') || remotePath.startsWith('deliverables/knot-resident-' + taskID + '/'), 'read_scope');
    const response = await sidecarRequest({ SIDECAR_TOKEN_WHISPER: token } as never, '/files?path=' + encodeURIComponent(remotePath) + '&user_id=' + encodeURIComponent(workspaceID), 'GET', undefined, 25000);
    const bytes = await readSidecarBytes(response, max);
    requireFact(hash(bytes) === sha256 && (size === undefined || bytes.length === size), 'remote_bytes_changed');
    writeFileSync(join(output, local), bytes, { mode: 0o600 });
    return bytes;
  }
  const html = await get(source.path, source.sha256, source.size, 'final.html', source.size);
  const pdf = await get(final.path, final.sha256, final.size, 'final.pdf', final.size);
  requireFact(Buffer.from(pdf).subarray(0, 5).equals(Buffer.from('%PDF-')) && Buffer.from(pdf).subarray(-2048).includes(Buffer.from('%%EOF')), 'pdf_bytes');
  // Parse HTML strictly as data using the same public stdlib CSS record encoding.
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
  requireFact(parsed.status === 0, 'local_css_parser');
  const css = JSON.parse(parsed.stdout);
  requireFact(css.styleSHA256 === '2547643aa623be9b4ec8f13b310c9aed6542eb0653e9c1d7edb2287aa09325cc' && css.styleBytes === 7474 && css.styleSHA256 === resident.designEvidence.inputs.styleSHA256 && css.styleBytes === resident.designEvidence.inputs.styleBytes, 'css_identity');
  const design = resident.designEvidence.journal, renderer = resident.journal;
  const designBytes = await get(design.path, design.sha256, 1000000, 'design.jsonl', design.size);
  const rendererBytes = await get(renderer.path, renderer.sha256, 1000000, 'renderer.jsonl', renderer.size);
  const designEntries = decode(designBytes).trim().split('\n').map(value => JSON.parse(value));
  const rendererEntries = decode(rendererBytes).trim().split('\n').map(value => JSON.parse(value));
  requireFact(JSON.stringify(designEntries) === JSON.stringify(resident.designEvidence.entries), 'design_journal_binding');
  requireFact(designEntries.length === 2 && designEntries[0].state === 'intent' && designEntries[0].taskID === taskID && designEntries[0].output === final.path && designEntries[1].state === 'staged' && designEntries[1].finalSHA256 === final.sha256 && designEntries[1].rendererJournalSHA256 === renderer.sha256, 'design_journal_identity');
  requireFact(rendererEntries.length === 2 && rendererEntries[0].state === 'intent' && rendererEntries[0].taskID === taskID && rendererEntries[0].output === final.path && JSON.stringify(rendererEntries[0].inputs) === JSON.stringify(resident.inputs) && rendererEntries[1].state === 'staged' && JSON.stringify(rendererEntries[1].manifest) === JSON.stringify(resident.manifest), 'renderer_journal_binding');
  requireFact(hash(JSON.stringify(resident.inputs) + '\n') === resident.manifest.inputsSHA256 && resident.inputs.design === 'author-v1' && resident.inputs.houseStyleSHA256 === null, 'renderer_inputs');
  const text = await get(final.verification.textPath, final.verification.textSHA256, 180000, 'final-text.txt', final.verification.textSize);
  const info = resident.manifest.pdfInfo;
  const infoBytes = await get(info.path, info.sha256, 1000000, 'pdfinfo.txt', info.size);
  requireFact(/^Pages:\s+9\s*$/m.test(decode(infoBytes)), 'pdf_page_count');
  const proofs = [];
  for (let i = 0; i < final.proofs.length; i++) {
    const proof = final.proofs[i];
    requireFact(proof.page === i + 1 && proof.sourceSHA256 === final.sha256 && proof.path === 'deliverables/knot-proof-' + buildID + '/page-' + (i + 1) + '.png', 'page_identity');
    const bytes = await get(proof.path, proof.sha256, 1800000, 'page-' + proof.page + '.png');
    const b = Buffer.from(bytes);
    requireFact(b.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) && b.length >= 24, 'page_png');
    proofs.push({ page: proof.page, sha256: hash(bytes), bytes: bytes.length, width: b.readUInt32BE(16), height: b.readUInt32BE(20), matchesOwnedIndependentProof: true });
  }
  const report = { observedAt: new Date().toISOString(), taskID, conversationID, workspaceID, sourceProposalID: sourceID, buildProposalID: buildID, proofProposalID: proofID, remoteExecutionPerformed: false, replayPerformed: false, capturedInApp: false,
    source: { ...source, matchesMeasurement: true }, final: { path: final.path, size: pdf.length, sha256: hash(pdf), pages: final.pages, matchesBuildAndProof: true }, css,
    designJournal: { ...design, entries: designEntries.length, matchesRetainedReceipt: true }, rendererJournal: { ...renderer, entries: rendererEntries.length, matchesRetainedReceipt: true, inputsSHA256: resident.manifest.inputsSHA256, design: resident.inputs.design, houseStyleSHA256: resident.inputs.houseStyleSHA256 },
    text: { bytes: text.length, sha256: hash(text), matchesIndependentProof: true }, proofs,
    acceptance: 'Read-only byte/provenance observation only. Manual content/visual assessment is separate; no capture/delivery, device or game acceptance.' };
  writeFileSync(join(output, 'review.json'), JSON.stringify(report, null, 2), { mode: 0o600 });
  console.log(JSON.stringify(report, null, 2));
}
main().catch(error => { console.error(JSON.stringify({ status: 'unconfirmed', reason: error instanceof Error && /^[a-z_]+$/.test(error.message) ? error.message : 'read_only_observation_unavailable', remoteExecutionPerformed: false, replayPerformed: false, capturedInApp: false })); process.exitCode = 2; });
