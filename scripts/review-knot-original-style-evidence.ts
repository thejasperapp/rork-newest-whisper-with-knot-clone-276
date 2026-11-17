// Explicit read-only observation of the dedicated ba695fa5 acceptance files.
// No executor input, renderer, replay, adoption, capture or owner-account access.
// Run: rork env run -- bun scripts/review-knot-original-style-evidence.ts
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { TextDecoder } from 'node:util';
import { sidecarRequest, readSidecarBytes } from '../functions/knot-shell-discovery';
const root = join(tmpdir(), 'knot-acceptance-uf26aun6d49w1tsjsm2u9');
const taskID = 'ba695fa5-57d1-4db1-b922-ea380827b7d1';
const workspaceID = 'whisper-e00a9064-5f85-40bb-9f44-8bd60f90d24a';
const prior = join(root, 'battery-2026-11-13T23-20-40-153Z', 'recipe-pdf');
const intent = JSON.parse(readFileSync(join(prior, 'intent.json'), 'utf8'));
const proposal = JSON.parse(readFileSync(join(prior, 'cc81d4b6-7aaa-444b-9c6d-b3d0e50e77ae-proposal.json'), 'utf8'));
const sourceReceipt = JSON.parse(readFileSync(join(prior, '7cb32a71-9ed1-4053-bc01-b706554fa247-result.json'), 'utf8'));
if (intent.workspaceID !== workspaceID || intent.taskID !== taskID || proposal.taskID !== taskID || proposal.conversationID !== intent.conversationID || sourceReceipt.sessionID !== 'b07b1d7d-a49a-4d3b-bd84-7bab81cca227' || sourceReceipt.status !== 'completed' || sourceReceipt.exitCode !== 0 || !sourceReceipt.outputComplete || sourceReceipt.truncated) throw new Error('original_identity_required');
const sourceLine = sourceReceipt.stdout.split('\n').filter((line: string) => line.startsWith('KNOT_DOCUMENT_SOURCE_V1 '));
if (sourceLine.length !== 1) throw new Error('original_source_required');
const source = JSON.parse(sourceLine[0].slice('KNOT_DOCUMENT_SOURCE_V1 '.length));
const sourcePath = 'knot-' + taskID + '-high-protein-recipes.html';
if (source.path !== sourcePath || source.sha256 !== '9a6858c8a3b5797fcf169db379b50342bd3031be2685c7b29234deb0c3e894b8' || source.size !== 31166 || source.format !== 'html') throw new Error('original_source_mismatch');
const token = process.env.SIDECAR_TOKEN_WHISPER;
if (!token) throw new Error('read_credential_unavailable');
const location = join(root, 'original-style-' + taskID); mkdirSync(location, { recursive: true, mode: 0o700 });
const hash = (data: Uint8Array | string) => createHash('sha256').update(data).digest('hex');
async function get(path: string, limit: number) {
  const response = await sidecarRequest({ SIDECAR_TOKEN_WHISPER: token } as never, '/files?path=' + encodeURIComponent(path) + '&user_id=' + encodeURIComponent(workspaceID), 'GET', undefined, 25000);
  return readSidecarBytes(response, limit);
}
async function main() {
  const html = await get(sourcePath, 31166);
  if (html.length !== source.size || hash(html) !== source.sha256) throw new Error('original_source_changed');
  const pdfPath = sourcePath.replace(/\.html$/, '.pdf');
  const pdf = await get(pdfPath, 338245);
  if (pdf.length !== 338245 || !Buffer.from(pdf).subarray(0, 5).equals(Buffer.from('%PDF-')) || !Buffer.from(pdf).subarray(-2048).includes(Buffer.from('%%EOF'))) throw new Error('original_pdf_unconfirmed');
  writeFileSync(join(location, 'original.html'), html, { mode: 0o600 });
  writeFileSync(join(location, 'original.pdf'), pdf, { mode: 0o600 });
  // Same stdlib parsing/encoding as the historical adapter; HTML is data, never
  // evaluated. This local helper does not run the adapter or contact the box.
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
  if (parsed.status !== 0) throw new Error('local_css_observation_unavailable');
  const css = JSON.parse(parsed.stdout);
  const inputs = { design: 'authored-inline-v1', styleEncoding: 'html-parser-style-records-v1', source, styleSHA256: css.styleSHA256, styleBytes: css.styleBytes, resourcePolicy: 'deny-all-v1' };
  const journalPath = '.knot-doc/design/' + taskID + '/' + hash(JSON.stringify({ taskID, output: pdfPath, inputs }) + '\n') + '.jsonl';
  let journalObservation: Record<string, unknown>;
  try {
    const journal = await get(journalPath, 1000000);
    writeFileSync(join(location, 'design.jsonl'), journal, { mode: 0o600 });
    const entries = new TextDecoder('utf-8', { fatal: true }).decode(journal).trim().split('\n').map(line => JSON.parse(line));
    const first = entries[0];
    if (first?.state !== 'intent' || first.taskID !== taskID || first.output !== pdfPath || JSON.stringify(first.inputs) !== JSON.stringify(inputs)) throw new Error('design_journal_mismatch');
    journalObservation = { read: true, path: journalPath, sha256: hash(journal), bytes: journal.length, entries: entries.length, originalIntentMatches: true };
  } catch { journalObservation = { read: false, reason: 'original_design_journal_unavailable_or_mismatch' }; }
  const report = { observedAt: new Date().toISOString(), taskID, workspaceID, remoteExecutionPerformed: false, replayPerformed: false, capturedInApp: false,
    source: { path: sourcePath, bytes: html.length, sha256: hash(html), matchesOriginalMeasurement: true },
    pdf: { path: pdfPath, bytes: pdf.length, sha256: hash(pdf), matchesOperatorReportedPrefix: hash(pdf).startsWith('54c838a6'), pagesIndependentlyVerified: false },
    authoredStyle: { ...css, matchesOperatorReport: css.styleSHA256 === 'fb3937862e750e94b5ee81b2083611de4339af0a2c564c74eeb3f0047f7b6ef4' && css.styleBytes === 6933 }, journal: journalObservation,
    scope: 'Exact original bytes and CSS observation only. Renderer journal null, independent every-page proof, content/visual review and app capture/delivery remain separate.' };
  writeFileSync(join(location, 'review.json'), JSON.stringify(report, null, 2), { mode: 0o600 });
  console.log(JSON.stringify(report, null, 2));
}
main().catch(() => { console.error(JSON.stringify({ status: 'unconfirmed', reason: 'original_read_only_observation_unavailable', remoteExecutionPerformed: false, replayPerformed: false })); process.exitCode = 2; });
