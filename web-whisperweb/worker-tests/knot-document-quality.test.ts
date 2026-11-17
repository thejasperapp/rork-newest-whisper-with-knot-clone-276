// @vitest-environment node
// Synthetic bytes/verdicts only. No model, executor, utility or droplet runs.
import { afterEach, describe, expect, it, vi } from 'vitest';
import { groundedRequestedItems, documentQualityShortfallsEligible, type RequestedDocumentItem } from '../../functions/knot-document-development';
import { documentSourceApproved, documentSourceBuildEligible, documentCompletionBudget } from '../../functions/knot-document-budget';
import { reviewDocumentSourceContent, reviewDocumentContent } from '../../functions/knot-document-content';
import { boundDocumentPageVerdicts, reviewAllDocumentPages } from '../../functions/knot-document-visual';
import { documentInvocationCommand } from '../../functions/knot-document-build';
import { documentProofCommand } from '../../functions/knot-document-proof';
import { documentManifest, type DocumentManifest } from '../../functions/knot-documents';
import { requestedDocumentFormat } from '../../functions/knot-document-format';
import type { ShellEvidence, ShellWorkflow } from '../../functions/knot-shell';
import { safeKnotActivityDetail, knotActivityLabels } from '../../functions/knot-activity';
import { shellCommandLimit } from '../../functions/knot-work-budget';

const env = { EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY: 'synthetic-not-a-key', EXPO_PUBLIC_TOOLKIT_URL: 'https://fixture.invalid' };
const encode = (text: string) => new TextEncoder().encode(text);
const digest = async (bytes: Uint8Array) => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), b => b.toString(16).padStart(2, '0')).join('');
const request = 'Create a PDF report that develops risk and sizing with worked numerical examples.';
const sourceText = '<html><body><h1>Report</h1><h2>Risk</h2><p>Risk explained using a worked loss example.</p><h2>Sizing</h2><p>Size trades.</p></body></html>';
const risk: RequestedDocumentItem = { item: 'Risk', status: 'developed', evidenceID: 'request', quote: 'risk and sizing with worked numerical examples', coverageQuote: 'Risk explained using a worked loss example.', section: 'Risk', repair: '' };
const sizing: RequestedDocumentItem = { item: 'Sizing', status: 'underdeveloped_requested_item', evidenceID: 'request', quote: risk.quote, coverageQuote: 'Size trades.', section: 'Sizing', repair: 'Write and explain an account-risk / stop-distance calculation in Sizing; label invented numbers as assumptions.' };
const terminal = { status: 'completed' as const, exitCode: 0, outputComplete: true, terminationConfirmed: true, truncated: false, contextTruncated: false };
const reply = (value: unknown) => Response.json({ choices: [{ finish_reason: 'stop', message: { content: JSON.stringify(value) } }] });
async function fixture() {
  const source = { path: 'current.html', sha256: await digest(encode(sourceText)), size: encode(sourceText).length, format: 'html' };
  const invocation = { stage: 'source' as const, interpreter: 'python3' as const, code: '# Never executed', path: source.path };
  const workflow: ShellWorkflow = { rootID: 'owned-task', originalRequest: request, mode: 'Create', documentTask: true, documentPolicy: 'author_v1', documentQuality: 'quality_v1', documentSourceReview: true, documentFormat: requestedDocumentFormat(request), memoryRead: true, indexRead: true, skills: [], commands: 7, memoryWritten: false };
  const receipt = { ...terminal, proposalID: 'owned-source', sessionID: 'owned-session', bot: 'main', conversationID: 'owned-conversation', stderr: '', title: 'Synthetic', tool: 'document_script', documentInvocation: invocation, reviewedCommand: documentInvocationCommand(invocation), stdout: 'KNOT_DOCUMENT_SOURCE_V1 ' + JSON.stringify(source), workflow, evidence: [{ ...terminal, operation: 'workspace_inventory', stdout: './current.html' }] } as ShellEvidence;
  const read = vi.fn(async (_path: string, _digest: string, _size: number) => encode(sourceText));
  return { receipt, workflow, read, source };
}
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });
describe('fresh grounded per-item development', () => {
  it('produces named-section expand/insert work orders and preserves developed items', () => {
    const missing = { ...sizing, status: 'missing_requested_item', coverageQuote: '' };
    for (const gap of [sizing, missing]) {
      const result = groundedRequestedItems([risk, gap], new Map([['request', request]]), sourceText);
      expect(result.workOrders).toEqual([{ item: 'Sizing', section: 'Sizing', action: gap === sizing ? 'expand' : 'insert', requirements: sizing.repair, preserve: ['Risk'] }]);
      expect(result.requestedItems).toHaveLength(2);
    }
  });
  it.each(['invented-anchor', 'authored-authority', 'missing-coverage', 'duplicate', 'undeveloped-repair', 'false-missing', 'empty', 'over-limit'] as const)('fails closed on %s', scenario => {
    let items: unknown[] = [risk, sizing];
    if (scenario === 'invented-anchor') items = [{ ...risk, quote: 'Invented requirement' }];
    if (scenario === 'authored-authority') items = [{ ...risk, evidenceID: 'authored' }];
    if (scenario === 'missing-coverage') items = [{ ...risk, coverageQuote: 'Not in complete content' }];
    if (scenario === 'duplicate') items = [risk, { ...risk, item: 'risk' }];
    if (scenario === 'undeveloped-repair') items = [{ ...sizing, repair: '' }];
    if (scenario === 'false-missing') items = [{ ...sizing, status: 'missing_requested_item' }];
    if (scenario === 'empty') items = [];
    if (scenario === 'over-limit') items = Array.from({ length: 33 }, (_, index) => ({ ...risk, item: 'Risk ' + index }));
    expect(() => groundedRequestedItems(items, new Map([['request', request]]), sourceText)).toThrow('document_content_unavailable');
  });
  it('independently compares every item and returns concrete development orders, not a pass', async () => {
    const f = await fixture();
    vi.stubGlobal('fetch', vi.fn(async (_url, init) => {
      const payload = JSON.parse(String(init.body));
      expect(payload.response_format.json_schema.schema.required).toContain('requestedItems');
      expect(payload.messages[0].content).toContain('EVERY actually requested item');
      const data = JSON.parse(payload.messages.find((m: { role: string }) => m.role === 'user').content);
      expect(data.originalRequest).toBe(request); expect(data.finalText).toBe(sourceText);
      return reply({ status: 'issues', findings: [], advisories: [], requestedItems: [risk, sizing] });
    }));
    const result = await reviewDocumentSourceContent(env, f.receipt, f.read, new AbortController().signal);
    expect(result).toMatchObject({ verdict: 'issues', issue: 'document_content_incomplete', requestedItems: [risk, sizing], workOrders: [{ section: 'Sizing', action: 'expand', preserve: ['Risk'] }] });
    expect(result.observations?.[0]).toContain('Write developed text');
  });
  it.each(['false-pass', 'empty-issues', 'uncertain', 'missing-reference', 'omitted-prior-item', 'regression'] as const)('never conceals %s as a qualified pass', async scenario => {
    const f = await fixture();
    const developedSizing = { ...sizing, status: 'developed' as const, repair: '' };
    let requestedItems = [risk, sizing]; let status = 'issues'; let findings: unknown[] = [];
    if (scenario === 'false-pass') status = 'pass';
    if (scenario === 'empty-issues') requestedItems = [risk, developedSizing];
    // This case is absent judgment; grounded gaps under an uncertain status are
    // separately tested as concrete repairs in knot-content-checker.test.ts.
    if (scenario === 'uncertain') { status = 'uncertain'; requestedItems = []; }
    if (scenario === 'missing-reference') { status = 'missing_reference'; findings = [{ kind: 'missing_reference_material', item: 'Original', detail: 'Required reference not read.', repair: 'Read the exact reference in full.', evidenceID: 'request', quote: risk.quote }]; }
    if (scenario === 'omitted-prior-item' || scenario === 'regression') {
      f.receipt.evidence.push({ documentSourceCheck: { requestedItems: [risk, developedSizing] } });
      if (scenario === 'omitted-prior-item') requestedItems = [risk];
    }
    vi.stubGlobal('fetch', vi.fn(async () => reply({ status, findings, advisories: [], requestedItems })));
    const result = await reviewDocumentSourceContent(env, f.receipt, f.read, new AbortController().signal);
    if (['empty-issues', 'uncertain', 'omitted-prior-item'].includes(scenario)) {
      expect(result.verdict).toBe('unconfirmed'); expect(result.issue).toBeUndefined();
      expect(result.contentCheckAttempts).toHaveLength(2); expect(documentQualityShortfallsEligible(result)).toBe(false);
    } else {
      expect(result.issue).toBe('document_content_incomplete'); expect(result.verdict).toBe('issues');
      // A contradictory label cannot erase a real grounded gap. It may only
      // qualify under the separately enforced exhausted-capacity policy.
      expect(documentQualityShortfallsEligible(result)).toBe(scenario === 'false-pass');
    }
    if (scenario === 'regression') expect(result.observations?.some(v => v.startsWith('regressed_requested_content:'))).toBe(true);
  });
  it('uses stable reference identities even with a prior authored attempt', async () => {
    const f = await fixture(), reference = 'Actual referenced coverage of risk and sizing.';
    f.receipt.evidence.push({ ...terminal, operation: 'workspace_read', reviewedCommand: 'cat -- reference.md', stdout: reference });
    f.read.mockImplementation(async path => encode(path === 'reference.md' ? reference : sourceText));
    vi.stubGlobal('fetch', vi.fn(async (_url, init) => {
      const data = JSON.parse(JSON.parse(String(init.body)).messages.find((m: { role: string }) => m.role === 'user').content);
      expect(data.sources.find((s: { role: string }) => s.role === 'reference').evidenceID).toBe('reference_' + await digest(encode(reference)));
      return reply({ status: 'issues', findings: [], advisories: [], requestedItems: [risk, sizing] });
    }));
    expect((await reviewDocumentSourceContent(env, f.receipt, f.read, new AbortController().signal)).verdict).toBe('issues');
  });
  it('keeps raw repair capacity until no new final command fits', async () => {
    for (const commands of [shellCommandLimit - 3, shellCommandLimit - 2, shellCommandLimit - 1, shellCommandLimit]) {
      const f = await fixture(); f.workflow.commands = commands;
      f.workflow.originalRequest = 'Create an MD report that develops risk and sizing with worked numerical examples.';
      f.workflow.documentFormat = requestedDocumentFormat(f.workflow.originalRequest);
      f.workflow.documentExecution = { invocation: { stage: 'final', interpreter: 'python3', code: '# Not executed', path: 'current.md' } };
      vi.stubGlobal('fetch', vi.fn(async () => reply({ status: 'issues', findings: [], advisories: [], requestedItems: [risk, sizing] })));
      const result = await reviewDocumentContent(env, f.receipt, { path: 'current.md', sha256: f.source.sha256, size: f.source.size, format: 'md', pages: 1, proofs: [] }, f.read, new AbortController().signal);
      if (commands < shellCommandLimit) { expect(result.review).toBeUndefined(); expect(result.issue).toBe('document_content_incomplete'); }
      else expect(result.review).toMatchObject({ status: 'quality_shortfalls', shortfalls: [expect.stringContaining('underdeveloped_requested_item:Sizing')] });
    }
  });
  it('only qualifies rendered shortfalls when a full source/build/proof correction cannot fit', async () => {
    for (const commands of [shellCommandLimit - 3, shellCommandLimit - 2, shellCommandLimit - 1, shellCommandLimit]) {
      const f = await fixture(); f.workflow.commands = commands;
      f.workflow.documentExecution = { invocation: { stage: 'build', interpreter: 'python3', code: '# Not executed', path: 'current.pdf' }, source: f.source };
      const verification = { version: 'knot_document_proof_v1' as const, sourceSHA256: 'b'.repeat(64), sourceSize: 100, format: 'pdf', renderedPages: 1, textSHA256: f.source.sha256, markupScan: 'clear' as const, renderer: 'poppler' as const, producerChecked: false, textPath: 'extracted.txt', textSize: f.source.size };
      vi.stubGlobal('fetch', vi.fn(async () => reply({ status: 'issues', findings: [], advisories: [], requestedItems: [risk, sizing] })));
      const result = await reviewDocumentContent(env, f.receipt, { path: 'current.pdf', sha256: 'b'.repeat(64), size: 100, format: 'pdf', pages: 1, proofs: [], verification }, f.read, new AbortController().signal);
      if (commands === shellCommandLimit - 3) { expect(result.review).toBeUndefined(); expect(result.issue).toBe('document_content_incomplete'); }
      else expect(result.review).toMatchObject({ status: 'quality_shortfalls', shortfalls: [expect.stringContaining('underdeveloped_requested_item:Sizing')] });
    }
  });
});
describe('owned exhausted-capacity source admission', () => {
  it('exposes final build/proof reserve without fabricating source approval', async () => {
    const f = await fixture();
    const check = { sourceProposalID: 'owned-source', sourceSHA256: f.source.sha256, verdict: 'issues' as const, issue: 'document_content_incomplete', observations: ['underdeveloped_requested_item:Sizing'], requestedItems: [risk, sizing], findings: [] };
    const workflow: ShellWorkflow = { ...f.workflow, commands: shellCommandLimit - 2, documentSource: { source: f.source, proposalID: 'owned-source' }, documentSourceCheck: check };
    expect(documentSourceApproved(workflow)).toBe(false); expect(documentSourceBuildEligible(workflow)).toBe(true);
    expect(documentCompletionBudget(workflow)).toMatchObject({ remaining: 2, requiredSteps: 2, stages: ['build'], canReadReference: false, reserved: true });
    expect(documentSourceBuildEligible({ ...workflow, commands: shellCommandLimit - 1 })).toBe(true);
    expect(documentCompletionBudget({ ...workflow, commands: shellCommandLimit - 1 }).stages).toEqual(['build']);
    // Reauthoring needs an actual actor-owned finding, not merely an issues label.
    const ownedFinding = { issue: 'document_content_incomplete' as const, observations: ['underdeveloped_requested_item:Sizing'] };
    expect(documentCompletionBudget({ ...workflow, documentContentFinding: ownedFinding }).stages).toEqual(['source', 'build']);
    for (const change of [{ commands: shellCommandLimit - 3 }, { commands: shellCommandLimit }, { documentQuality: undefined }, { documentSourceCheck: { ...check, sourceSHA256: 'b'.repeat(64) } }, { documentSourceCheck: { ...check, verdict: 'uncertain' as const } }, { documentSourceCheck: { ...check, findings: [{ kind: 'regressed_requested_content' } as never] } }, { documentSourceCheck: { ...check, findings: [{ kind: 'missing_reference_material' } as never] } }]) {
      expect(documentSourceBuildEligible({ ...workflow, ...change })).toBe(false);
    }
  });
});
describe('mandatory hash-bound every-page visual review', () => {
  async function pages(count = 3) {
    const bytes = encode('synthetic PNG bytes; no real image/model'), sha256 = await digest(bytes);
    const manifest: DocumentManifest = { path: 'original.pdf', sha256: 'a'.repeat(64), size: 100, pages: count, format: 'pdf', proofs: Array.from({ length: count }, (_, i) => ({ path: 'page-' + (i + 1) + '.png', page: i + 1, sha256, sourceSHA256: 'a'.repeat(64) })) };
    return { bytes, manifest };
  }
  it('supplies every actual rehashed image in two-page batches and binds each verdict', async () => {
    const f = await pages(13), seen: number[] = [];
    const fetcher = vi.fn(async (_url, init) => {
      const payload = JSON.parse(String(init.body)); expect(payload.model).toBe('openai/gpt-4o');
      const content = payload.messages[0].content;
      const labels = content.filter((v: { type: string; text?: string }) => v.type === 'text' && v.text?.startsWith('{')).map((v: { text: string }) => JSON.parse(v.text));
      expect(content.filter((v: { type: string }) => v.type === 'image_url')).toHaveLength(labels.length);
      seen.push(...labels.map((v: { page: number }) => v.page));
      return reply({ pages: labels.map((v: object) => ({ ...v, verdict: 'pass', issues: [] })) });
    }); vi.stubGlobal('fetch', fetcher);
    const read = vi.fn(async () => f.bytes);
    const result = await reviewAllDocumentPages(env, f.manifest, read, new AbortController().signal, () => {});
    expect(result).toMatchObject({ scope: 'all_pages', status: 'pass', finalSHA256: f.manifest.sha256 });
    expect(result.pages).toHaveLength(13); expect(seen).toEqual(Array.from({ length: 13 }, (_, i) => i + 1));
    expect(read).toHaveBeenCalledTimes(13); expect(fetcher).toHaveBeenCalledTimes(7);
  });
  it.each(['missing', 'duplicate', 'wrong-hash', 'false-pass', 'empty-issue', 'wrong-page', 'uncertain'] as const)('rejects %s page verdicts', async scenario => {
    const { manifest } = await pages(2);
    let values = manifest.proofs.map(p => ({ page: p.page, sha256: p.sha256, verdict: 'pass', issues: [] as string[] }));
    if (scenario === 'missing') values.pop();
    if (scenario === 'duplicate') values[1] = values[0];
    if (scenario === 'wrong-hash') values[0].sha256 = 'f'.repeat(64);
    if (scenario === 'false-pass') values[0].issues = ['Clipped text'];
    if (scenario === 'empty-issue') values[0].verdict = 'issues';
    if (scenario === 'wrong-page') values[0].page = 3;
    if (scenario === 'uncertain') { values[0].verdict = 'uncertain'; values[0].issues = ['Cannot read the supplied page.']; }
    expect(() => boundDocumentPageVerdicts({ pages: values }, manifest.proofs)).toThrow('document_visual_review_unavailable');
  });
  it('retains bound concrete findings in a mixed issues/uncertain batch without certifying complete review', async () => {
    const { manifest } = await pages(2), report = vi.fn();
    const observed = { pages: manifest.proofs.map(p => ({ page: p.page, sha256: p.sha256, verdict: p.page === 1 ? 'issues' : 'uncertain', issues: p.page === 1 ? ['Title clips at the page edge.'] : [] })) };
    expect(() => boundDocumentPageVerdicts(observed, manifest.proofs, report)).toThrow('document_visual_review_unavailable');
    expect(report).toHaveBeenCalledExactlyOnceWith([observed.pages[0]]);
  });
  it.each(['refusal', 'truncated', 'stopped', 'changed-bytes', 'incomplete-proof', 'deadline'] as const)('never certifies unread/unsafe pages: %s', async scenario => {
    const f = await pages(), controller = new AbortController(); let checks = 0;
    if (scenario === 'stopped') controller.abort();
    if (scenario === 'incomplete-proof') f.manifest.proofs.pop();
    const fetcher = vi.fn(async () => scenario === 'refusal' ? Response.json({ choices: [{ finish_reason: 'stop', message: { refusal: 'Uncertain' } }] }) : scenario === 'truncated' ? Response.json({ choices: [{ finish_reason: 'length', message: { content: '{}' } }] }) : reply({ pages: [] })); vi.stubGlobal('fetch', fetcher);
    await expect(reviewAllDocumentPages(env, f.manifest, async () => scenario === 'changed-bytes' ? encode('changed') : f.bytes, controller.signal, () => { if (scenario === 'deadline' && ++checks === 2) throw new Error('document_capture_cancelled'); })).rejects.toThrow();
    expect(fetcher.mock.calls.length).toBeLessThanOrEqual(1);
    if (['stopped', 'changed-bytes', 'incomplete-proof', 'deadline'].includes(scenario)) expect(fetcher).not.toHaveBeenCalled();
  });
  it('keeps visual issues explicit, separate from pass and optional review labels', async () => {
    const f = await pages(1);
    vi.stubGlobal('fetch', vi.fn(async () => reply({ pages: [{ page: 1, sha256: f.manifest.proofs[0].sha256, verdict: 'issues', issues: ['Title clips at the page edge.'] }] })));
    expect(await reviewAllDocumentPages(env, f.manifest, async () => f.bytes, new AbortController().signal, () => {})).toMatchObject({ status: 'issues', pages: [{ verdict: 'issues' }] });
    expect(knotActivityLabels.document_quality_qualified).toContain('not a quality pass');
    expect(safeKnotActivityDetail({ reason: 'document_visual_review_unavailable', observations: ['private document text'] })).toEqual({ reason: 'document_visual_review_unavailable' });
  });
  it('preserves default historical proof framing and requires the fresh all-page variant explicitly', () => {
    const manifest: DocumentManifest = { path: 'report.pdf', sha256: 'a'.repeat(64), size: 100, format: 'pdf', pages: 25, proofs: [] }, id = '00000000-0000-4000-8000-000000000001';
    const historical = documentProofCommand(manifest, id, true, true), fresh = documentProofCommand(manifest, id, true, true, true);
    expect(historical).toBe(documentProofCommand(manifest, id, true, true, false));
    expect(historical).toContain('if pages<=12 else'); expect(historical).not.toContain('allPageProofs=True');
    expect(fresh).toContain('sampled=list(range(1,pages+1))\n'); expect(fresh).toContain('allPageProofs=True'); expect(fresh).toContain('total<=50000000');
    const declared = { ...manifest, proofs: Array.from({ length: 25 }, (_, i) => ({ page: i + 1, path: 'page-' + (i + 1) + '.png', sha256: 'b'.repeat(64), sourceSHA256: manifest.sha256 })) };
    const receipt = { ...terminal, sessionID: 'owned-session', stdout: 'KNOT_DOCUMENT_V1 ' + JSON.stringify(declared), workflow: { documentQuality: 'quality_v1' } } as ShellEvidence;
    expect(documentManifest(receipt)?.proofs).toHaveLength(25);
    delete receipt.workflow!.documentQuality;
    expect(documentManifest(receipt)?.proofIssue).toBe('invalid_document_proof');
  });
});
