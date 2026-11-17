// @vitest-environment node
// Real capture/proof/content/visual pipeline over synthetic owned receipts and
// bytes. No renderer, live AI, historical task or external service is executed.
import { afterEach, describe, expect, it, vi } from 'vitest';
import { captureKnotDocument, type DocumentManifest, type KnotDocument, type DocumentCaptureOptions, type DocumentCaptureAssessment } from '../../functions/knot-documents';
import { documentInvocationCommand, documentMemoryCommand } from '../../functions/knot-document-build';
import { documentProofCommand, documentSkillReadCommand } from '../../functions/knot-document-proof';
import { requestedDocumentFormat } from '../../functions/knot-document-format';
import type { DocumentContentCheckAttempt } from '../../functions/knot-document-content';
import { shellCommandLimit } from '../../functions/knot-work-budget';
import type { ShellEvidence } from '../../functions/knot-shell';
const encode = (s: string) => new TextEncoder().encode(s);
const digest = async (b: Uint8Array) => [...new Uint8Array(await crypto.subtle.digest('SHA-256', b))].map(n => n.toString(16).padStart(2, '0')).join('');
const buildID = '00000000-0000-4000-8000-000000000004';
const env = { SIDECAR_TOKEN_WHISPER: 'synthetic-only', EXPO_PUBLIC_TOOLKIT_URL: 'https://checker-dead.invalid', EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY: 'synthetic-only' };
const terminal = { status: 'completed' as const, sessionID: 'owned-synthetic-session', exitCode: 0, outputComplete: true, terminationConfirmed: true, truncated: false, contextTruncated: false };
async function fixture(scenario: string, pageCount = 1) {
  const sourceBytes = encode('<html><body>Serves two. Simmer 100 g beans for 20 minutes, then season.</body></html>');
  const pdf = encode('%PDF-1.7\nSynthetic integrity bytes, not a rendered document.\n%%EOF');
  const png = new Uint8Array(33); png.set([137, 80, 78, 71, 13, 10, 26, 10]); png.set(encode('IHDR'), 12); new DataView(png.buffer).setUint32(16, 640); new DataView(png.buffer).setUint32(20, 800);
  const source = { path: 'fresh-recipes.html', sha256: await digest(sourceBytes), size: sourceBytes.length, format: 'html' };
  const sourceInvocation = { stage: 'source' as const, interpreter: 'python3' as const, path: source.path, code: '# not executed' };
  const invocation = { stage: 'build' as const, interpreter: 'python3' as const, path: 'fresh-recipes.pdf', code: '# not executed' };
  const measured: DocumentManifest = { path: invocation.path, format: 'pdf', pages: pageCount, size: pdf.length, sha256: await digest(pdf), proofs: [] };
  const textPath = 'deliverables/knot-proof-' + buildID + '/text.txt', pngPath = 'deliverables/knot-proof-' + buildID + '/page-1.png';
  const pngSHA256 = await digest(png);
  const manifest: DocumentManifest = { ...measured, proofs: Array.from({ length: pageCount }, (_, i) => ({ page: i + 1, path: pngPath.replace('page-1.png', 'page-' + (i + 1) + '.png'), sha256: pngSHA256, sourceSHA256: measured.sha256 })), verification: { version: 'knot_document_proof_v1', sourceSHA256: measured.sha256, sourceSize: pdf.length, format: 'pdf', renderedPages: pageCount, textSHA256: source.sha256, textSize: source.size, textPath, markupScan: 'clear', renderer: 'poppler', producerChecked: false, structureChecked: true, allPageProofs: true } };
  const receipt = { ...terminal, proposalID: 'owned-proof', bot: 'main', conversationID: 'owned-conversation', stderr: '', stdout: 'KNOT_DOCUMENT_V1 ' + JSON.stringify(manifest), reviewedCommand: documentProofCommand(measured, buildID, true, true, true),
    workflow: { rootID: 'fresh-owned-task', originalRequest: 'Create a PDF guide of recipes.', mode: 'Create', documentTask: true, documentPolicy: 'author_v1', documentValidation: 'structural_v2', documentQuality: 'quality_v1', documentFormat: requestedDocumentFormat('Create a PDF guide of recipes.'), memoryRead: true, indexRead: true, skills: [documentSkillReadCommand], documentSkillCommand: documentSkillReadCommand, commands: 6, memoryWritten: false, documentExecution: { invocation, source, sourceProposalID: 'owned-source' }, documentProof: { manifest: measured, sourceProposalID: buildID } },
    evidence: [{ ...terminal, operation: 'workspace_inventory', stdout: './fresh-recipes.html' }, { ...terminal, proposalID: 'owned-source', documentInvocation: sourceInvocation, reviewedCommand: documentInvocationCommand(sourceInvocation), stdout: 'KNOT_DOCUMENT_SOURCE_V1 ' + JSON.stringify(source) }, { ...terminal, proposalID: buildID, reviewedCommand: documentInvocationCommand(invocation, source, true), stdout: 'KNOT_DOCUMENT_V1 ' + JSON.stringify(measured) }],
  } as ShellEvidence;
  if (scenario === 'missing-proof') delete receipt.workflow!.documentProof;
  const documents = new Map<string, KnotDocument>(), resources: { id: string; resource: number; bytes: Uint8Array }[] = [];
  const sql = { exec: (query: string, ...args: unknown[]) => {
    let rows: unknown[] = [];
    if (query.startsWith('SELECT data FROM knot_documents WHERE id = ?')) rows = documents.has(String(args[0])) ? [{ data: JSON.stringify(documents.get(String(args[0]))) }] : [];
    else if (query === 'SELECT COUNT(*) AS count FROM knot_documents') rows = [{ count: documents.size }];
    else if (query.startsWith('SELECT COALESCE(SUM(')) rows = [{ bytes: 0 }];
    else if (query.startsWith('INSERT INTO knot_documents VALUES')) documents.set(String(args[0]), JSON.parse(String(args[5])));
    else if (query.startsWith('INSERT INTO knot_document_bytes VALUES')) resources.push({ id: String(args[0]), resource: Number(args[1]), bytes: new Uint8Array(args[3] as ArrayBuffer) });
    else if (query === 'SELECT 1 FROM knot_documents WHERE bytes > 0 LIMIT 1' || query.startsWith('SELECT id') || query.startsWith('SELECT 1 FROM knot_document_deletions') || query.startsWith('DELETE FROM knot_document_bytes') || query.startsWith('INSERT INTO knot_document_sources')) { /* Empty expiry/capacity/deletion state or immutable storage boundary. */ }
    else throw new Error('Unexpected capture SQL: ' + query);
    return { toArray: () => rows, one: () => rows[0] };
  } };
  const ctx = { storage: { sql, transactionSync: (f: () => unknown) => f() } } as never;
  const controller = new AbortController(), vitals: DocumentContentCheckAttempt[] = [], visualPages: number[] = [];
  let deleted = false;
  const files = new Map([[source.path, sourceBytes], [measured.path, pdf], [textPath, sourceBytes], [pngPath, png]]);
  manifest.proofs.forEach(proof => files.set(proof.path, png));
  const fetcher = vi.fn(async (url: string, init: RequestInit) => {
    const parsed = new URL(String(url));
    if (parsed.origin === 'https://checker-dead.invalid') {
      const payload = JSON.parse(String(init.body));
      if (scenario === 'visual-outage' && payload.response_format.json_schema.name === 'document_pages') throw new Error('synthetic visual outage');
      if (payload.response_format.json_schema.name === 'document_completeness') {
        if (scenario === 'historical-format-confusion') {
          const data = JSON.parse(payload.messages.find((message: { role: string }) => message.role === 'user').content);
          expect(data.operation).toBe('final'); expect(data.finalPath).toBe(measured.path);
          expect(data.sources.some((item: { role: string; text: string }) => item.role === 'authored_source' && item.text === new TextDecoder().decode(sourceBytes))).toBe(true);
          expect(payload.messages.some((message: { content: string }) => message.content.startsWith('CURRENT PHASE: PRE-CONVERSION'))).toBe(false);
          return Response.json({ choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({ status: 'issues', findings: [{ kind: 'missing_requested_item', item: 'Recipes PDF', detail: "The request was for a PDF document, but the operation specified is 'source' which relies on the HTML content.", repair: 'Convert the HTML source document into a PDF file following the format provided in the request.', evidenceID: 'request', quote: 'Create a PDF guide of recipes.' }], advisories: [], requestedItems: [{ item: 'Recipes PDF', status: 'missing_requested_item', evidenceID: 'request', quote: 'paraphrased invalid anchor', coverageQuote: '', section: 'Recipes', repair: 'Convert the HTML source document into a PDF file.' }] }) } }] });
        }
        if (scenario !== 'final-content-gap') throw new Error('synthetic dead checker');
        return Response.json({ choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({ status: 'issues', findings: [], advisories: [], requestedItems: [{ item: 'Recipes', status: 'underdeveloped_requested_item', evidenceID: 'request', quote: 'guide of recipes', coverageQuote: 'Serves two.', section: 'Recipes', repair: 'Explain the cooking technique in Recipes while preserving the measured ingredients.' }] }) } }] });
      }
      expect(payload.response_format.json_schema.name).toBe('document_pages');
      const labels = payload.messages[0].content.filter((v: { type: string; text?: string }) => v.type === 'text' && v.text?.startsWith('{')).map((v: { text: string }) => JSON.parse(v.text));
      if (scenario === 'partial-visual-outage' && labels.some((v: { page: number }) => v.page > 2)) throw new Error('synthetic later batch outage');
      visualPages.push(...labels.map((v: { page: number }) => v.page));
      return Response.json({ choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({ pages: scenario === 'unread-visual' ? [] : labels.map((label: object) => ({ ...label, verdict: ['visual-issues', 'partial-visual-outage'].includes(scenario) ? 'issues' : 'pass', issues: ['visual-issues', 'partial-visual-outage'].includes(scenario) ? ['Nutrition spacing is inconsistent.'] : [] })) }) } }] });
    }
    expect(parsed.pathname).toBe('/files');
    const path = parsed.searchParams.get('path')!;
    if (scenario === 'changed-bytes' && path === measured.path) return new Response(encode('changed bytes'));
    if (scenario === 'missing-image' && path === pngPath) return new Response('missing', { status: 404 });
    if (scenario === 'delete-during-read') deleted = true;
    expect(files.has(path)).toBe(true); return new Response(files.get(path));
  }); vi.stubGlobal('fetch', fetcher);
  const run = (options: DocumentCaptureOptions = {}) => captureKnotDocument(ctx, env, 'synthetic-owned-workspace', receipt, controller.signal, true, () => { if (deleted) throw new Error('document_capture_cancelled'); }, attempt => { vitals.push(attempt); if (scenario === 'stop-after-retry' && attempt.attempt === 2) controller.abort(); }, options);
  return { run, documents, resources, vitals, visualPages, measured, manifest, receipt, files, pdf, fetcher, controller };
}
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });
describe('nonblocking checker through independent final capture', () => {
  it('captures exact immutable final bytes after two failed content runs and a separate every-page visual pass', async () => {
    const f = await fixture('dead-checker'), result = await f.run();
    expect(result.issue).toBeUndefined();
    expect(result.document).toMatchObject({ sha256: f.measured.sha256, size: f.pdf.length, review: 'visual_ai', contentReview: { status: 'unconfirmed', contentCheckAttempts: [{ reason: 'content_check_transport_error' }, { reason: 'content_check_transport_error' }] }, visualReview: { scope: 'all_pages', status: 'pass' } });
    expect(result.document?.byteFidelity).toEqual({ status: 'pass', scope: 'measured_final_to_immutable_capture', sha256: f.measured.sha256, bytes: f.pdf.length });
    expect(result.document?.contentQuality).toEqual({ status: 'unconfirmed', scope: 'complete_text_coverage', finalSHA256: f.measured.sha256, factualCertification: false });
    expect(documentMemoryCommand(result.document!)).toContain('Byte fidelity (measured final to immutable capture): passed');
    expect(documentMemoryCommand(result.document!)).toContain('not factual');
    expect(result.document?.qualityShortfalls).toBeUndefined(); expect(f.documents.size).toBe(1); expect(f.visualPages).toEqual([1]);
    expect(f.vitals).toHaveLength(2); expect(f.resources.find(r => r.resource === 0)?.bytes).toEqual(f.pdf);
  });
  it('rejects the historical source-versus-PDF phase confusion before malformed-item fallback, never inventing a pass', async () => {
    const f = await fixture('historical-format-confusion', 11), result = await f.run();
    expect(result.issue).toBeUndefined(); expect(result.document?.contentReview?.status).toBe('unconfirmed');
    expect(f.vitals).toHaveLength(2);
    expect(f.vitals).toMatchObject([{ outcome: 'unconfirmed', reason: 'content_check_stage_invalid', failureStage: 'stage', validationCode: 'stage_impossible' }, { outcome: 'unconfirmed', reason: 'content_check_stage_invalid' }]);
    expect(result.document).toMatchObject({ sha256: f.measured.sha256, size: f.pdf.length, pages: 11, proofPages: Array.from({ length: 11 }, (_, i) => i + 1), visualReview: { status: 'pass', scope: 'all_pages' } });
    expect(f.documents.size).toBe(1); expect(f.resources.find(r => r.resource === 0)?.bytes).toEqual(f.pdf);
    expect(f.visualPages).toEqual(Array.from({ length: 11 }, (_, i) => i + 1));
  });
  it('retains grounded final work orders after a source pass, without capturing or claiming delivery', async () => {
    const f = await fixture('final-content-gap');
    const source = f.receipt.workflow!.documentExecution!.source!;
    f.receipt.workflow!.documentSourceCheck = { sourceProposalID: 'owned-source', sourceSHA256: source.sha256, verdict: 'pass', observations: [], workOrders: [] };
    const result = await f.run();
    expect(result).toMatchObject({ issue: 'document_content_incomplete', contentWorkOrders: [{ item: 'Recipes', section: 'Recipes', action: 'expand', requirements: 'Explain the cooking technique in Recipes while preserving the measured ingredients.', preserve: [] }], contentRequestedItems: [{ status: 'underdeveloped_requested_item', evidenceID: 'request', quote: 'guide of recipes' }] });
    expect(result.document).toBeUndefined(); expect(f.documents.size).toBe(0); expect(f.resources).toEqual([]);
    expect(f.visualPages).toEqual([]); expect(f.vitals).toMatchObject([{ outcome: 'issues' }]);
    expect(f.receipt.workflow!.documentSourceCheck.verdict).toBe('pass');
  });
  it('never backfills new fidelity or quality claims onto historical immutable captures', async () => {
    const f = await fixture('dead-checker'), result = await f.run();
    const { byteFidelity: _fidelity, contentQuality: _quality, ...legacy } = result.document!;
    f.documents.set(legacy.id, legacy);
    const callsBefore = f.fetcher.mock.calls.length, resourcesBefore = f.resources.length;
    expect((await f.run()).document).toEqual(legacy);
    expect(f.fetcher).toHaveBeenCalledTimes(callsBefore); expect(f.resources).toHaveLength(resourcesBefore);
    expect(documentMemoryCommand(legacy)).not.toContain('Byte fidelity (');
  });
  it.each(['unconfirmed', 'quality_shortfalls', 'pass'] as const)('completion memory distinguishes the actual raw review verdict: %s', async status => {
    const f = await fixture('dead-checker'), result = await f.run();
    const document: KnotDocument = { ...result.document!, format: 'md', sourcePath: 'fresh.md', verification: undefined, contentReview: { ...result.document!.contentReview!, status } };
    const command = documentMemoryCommand(document);
    expect(command).toContain('complete UTF-8 bytes and format');
    expect(command).toContain('Content comparison: ' + (status === 'pass' ? 'passed' : status === 'quality_shortfalls' ? 'quality shortfalls recorded; not a pass' : 'unconfirmed; not a pass'));
    expect(command).not.toContain('format and independent request/source content comparison');
    expect(command).toContain(document.sha256);
  });
  it('delivers with uncertain visual review recorded, never inventing a pass', async () => {
    const f = await fixture('unread-visual'), result = await f.run();
    expect(result.issue).toBeUndefined();
    expect(result.document).toMatchObject({ review: 'unavailable', reviewIssue: 'document_visual_review_unavailable' });
    expect(result.document?.visualReview).toBeUndefined(); expect(f.documents.size).toBe(1);
  });
  it('delivers with visual findings as advisories when no repair is requested', async () => {
    const f = await fixture('visual-issues'), result = await f.run();
    expect(result.issue).toBeUndefined();
    expect(result.document).toMatchObject({ review: 'issues', visualReview: { status: 'issues' }, qualityShortfalls: ['Page 1: Nutrition spacing is inconsistent.'] });
    expect(f.documents.size).toBe(1);
  });
  it('retains an assessment before budgeted repair, then finalizes without another model call', async () => {
    const f = await fixture('visual-issues');
    let assessment: DocumentCaptureAssessment | undefined;
    const result = await f.run({ repairVisual: true, saveAssessment: value => { assessment = value; } });
    expect(result).toEqual({ visualRepair: { observations: ['Page 1: Nutrition spacing is inconsistent.'] } });
    expect(assessment?.visualReview?.status).toBe('issues'); expect(f.documents.size).toBe(0);
    const modelCalls = () => f.fetcher.mock.calls.filter(([url]) => String(url).startsWith('https://checker-dead.invalid')).length;
    const before = modelCalls();
    expect((await f.run({ assessment, repairVisual: false })).document?.review).toBe('issues');
    expect(modelCalls()).toBe(before); expect(f.documents.size).toBe(1);
  });
  it('keeps earlier observed defects actionable after a later visual batch outage and finalizes without AI', async () => {
    const f = await fixture('partial-visual-outage', 3);
    let assessment: DocumentCaptureAssessment | undefined;
    const observed: number[] = [];
    const result = await f.run({ repairVisual: true, saveAssessment: value => { assessment = value; }, reportVisualPages: pages => observed.push(...pages.map(page => page.page)) });
    const observations = [1, 2].map(page => `Page ${page}: Nutrition spacing is inconsistent.`);
    expect(result).toEqual({ visualRepair: { observations } });
    expect(assessment).toMatchObject({ review: 'unavailable', observations });
    expect(assessment?.visualReview).toBeUndefined(); expect(observed).toEqual([1, 2]);
    const before = f.fetcher.mock.calls.filter(([url]) => String(url).startsWith('https://checker-dead.invalid')).length;
    const final = await f.run({ assessment });
    expect(final.document).toMatchObject({ review: 'unavailable', qualityShortfalls: observations });
    expect(final.document?.visualReview).toBeUndefined(); expect(f.documents.size).toBe(1);
    expect(f.fetcher.mock.calls.filter(([url]) => String(url).startsWith('https://checker-dead.invalid'))).toHaveLength(before);
  });
  it('captures at exhausted command capacity without inventing a visual pass', async () => {
    const f = await fixture('visual-issues'); f.receipt.workflow!.commands = shellCommandLimit - 2;
    expect((await f.run({ repairVisual: true })).document?.review).toBe('issues'); expect(f.documents.size).toBe(1);
  });
  it('does not let missing AI transport bypass validation of the thirteenth required PNG', async () => {
    const f = await fixture('visual-outage', 13);
    f.files.set(f.manifest.proofs[12].path, encode('changed'));
    await expect(f.run()).rejects.toThrow('document_bytes_changed'); expect(f.documents.size).toBe(0); expect(f.visualPages).toEqual([]);
  });
  it('rejects an invalid PNG even when its declared hash matches', async () => {
    const f = await fixture('visual-outage'), proof = f.manifest.proofs[0], invalid = encode('Not a PNG');
    proof.sha256 = await digest(invalid); f.files.set(proof.path, invalid);
    f.receipt.stdout = 'KNOT_DOCUMENT_V1 ' + JSON.stringify(f.manifest);
    await expect(f.run()).rejects.toThrow('invalid_document_proof'); expect(f.documents.size).toBe(0);
  });
  it('records model outage as unavailable and captures after validating every required image', async () => {
    const f = await fixture('visual-outage', 3), result = await f.run();
    expect(result.document).toMatchObject({ review: 'unavailable', proofPages: [1, 2, 3] }); expect(result.document?.visualReview).toBeUndefined();
  });
  it('capture-only validates all nine pages and complete text evidence, preserves flat history and makes zero AI calls', async () => {
    const f = await fixture('visual-issues', 9);
    const observations = ["Page 9: Cook’s Tip spacing.", 'Page 9: Nutrition hierarchy.', 'Page 9: Nutrition spacing.'];
    const result = await f.run({ captureOnly: { finalSHA256: f.manifest.sha256, status: 'issues', observations, basis: 'retained_event', eventSequence: 925, resumeID: 'prior-owned-resume' } });
    expect(result.document).toMatchObject({ pages: 9, review: 'issues', contentReview: { status: 'unconfirmed' }, visualAdvisory: { observations, basis: 'retained_event' }, qualityShortfalls: observations });
    expect(result.document?.visualReview).toBeUndefined(); expect(result.document?.proofPages).toHaveLength(9); expect(f.vitals).toEqual([]);
    expect(f.fetcher.mock.calls.every(([url]) => new URL(String(url)).pathname === '/files')).toBe(true);
    expect(f.resources.find(r => r.resource === 0)?.bytes).toEqual(f.pdf);
  });
  it.each(['changed-source', 'changed-text', 'mismatched-final', 'stopped'])('capture-only never bypasses evidence integrity: %s', async scenario => {
    const f = await fixture('visual-issues', 9);
    if (scenario === 'changed-source') f.files.set('fresh-recipes.html', encode('changed'));
    if (scenario === 'changed-text') f.files.set(f.manifest.verification!.textPath!, encode('changed'));
    if (scenario === 'stopped') f.controller.abort();
    const result = f.run({ captureOnly: { finalSHA256: scenario === 'mismatched-final' ? 'a'.repeat(64) : f.manifest.sha256, status: 'issues', observations: ['Retained finding'], basis: 'retained_event', eventSequence: 925, resumeID: 'prior-owned-resume' } });
    if (['changed-source', 'changed-text'].includes(scenario)) expect(await result).toMatchObject({ issue: 'document_bytes_changed' });
    else await expect(result).rejects.toThrow(scenario === 'stopped' ? 'document_capture_cancelled' : 'document_bytes_changed');
    expect(f.documents.size).toBe(0); expect(f.vitals).toEqual([]);
  });
  it.each(['missing-proof', 'changed-bytes', 'stop-after-retry', 'missing-image', 'delete-during-read'])('still blocks independent unsafe capture: %s', async scenario => {
    const f = await fixture(scenario);
    await expect(f.run()).rejects.toThrow(scenario === 'missing-proof' ? 'document_proof_required' : scenario === 'changed-bytes' ? 'document_bytes_changed' : scenario === 'missing-image' ? 'document_proof_required' : 'document_capture_cancelled');
    expect(f.documents.size).toBe(0); expect(f.resources).toEqual([]);
    expect(f.vitals).toHaveLength(scenario === 'stop-after-retry' ? 2 : 0);
  });
});
