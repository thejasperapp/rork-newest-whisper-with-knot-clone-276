// @vitest-environment node
// Synthetic owned bytes and provider boundaries only; no live task is replayed.
import { afterEach, describe, expect, it, vi } from 'vitest';
import { reviewDocumentSourceContent, reviewDocumentContent } from '../../functions/knot-document-content';
import { documentSourceApproved, documentSourceBuildEligible, documentCompletionBudget } from '../../functions/knot-document-budget';
import { documentInvocationCommand } from '../../functions/knot-document-build';
import { requestedDocumentFormat } from '../../functions/knot-document-format';
import type { ShellEvidence } from '../../functions/knot-shell';

const env = { EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY: 'synthetic-only', EXPO_PUBLIC_TOOLKIT_URL: 'https://fixture.invalid' };
const text = '<html><body><h1>Recipes</h1><p>Serves two. Cook 20 minutes. Use 100 g beans. Simmer, then season.</p></body></html>';
const request = 'Create a PDF guide with recipes and quantified ingredients.';
const bytes = new TextEncoder().encode(text);
const digest = async (value: Uint8Array) => [...new Uint8Array(await crypto.subtle.digest('SHA-256', value))].map(b => b.toString(16).padStart(2, '0')).join('');
const terminal = { status: 'completed' as const, exitCode: 0, outputComplete: true, terminationConfirmed: true, truncated: false, contextTruncated: false };
const item = { item: 'Recipes', status: 'developed', evidenceID: 'request', quote: 'recipes and quantified ingredients', coverageQuote: 'Serves two. Cook 20 minutes.', section: 'Recipes', repair: '' };
const verdict = () => ({ status: 'pass', findings: [], advisories: [], requestedItems: [item] });
const reply = (value: unknown, finish = 'stop') => Response.json({ choices: [{ finish_reason: finish, message: { content: JSON.stringify(value) } }] });
async function fixture() {
  const source = { path: 'fresh-recipes.html', sha256: await digest(bytes), size: bytes.length, format: 'html' };
  const invocation = { stage: 'source' as const, interpreter: 'python3' as const, code: '# never executed', path: source.path };
  const receipt = { ...terminal, proposalID: 'owned-source', sessionID: 'owned-session', bot: 'main', conversationID: 'owned-conversation', stdout: 'KNOT_DOCUMENT_SOURCE_V1 ' + JSON.stringify(source), stderr: '', reviewedCommand: documentInvocationCommand(invocation), documentInvocation: invocation,
    workflow: { rootID: 'owned-task', originalRequest: request, mode: 'Create', documentTask: true, documentPolicy: 'author_v1', documentSourceReview: true, documentQuality: 'quality_v1', documentFormat: requestedDocumentFormat(request), memoryRead: true, indexRead: true, skills: [], commands: 4, memoryWritten: false },
    evidence: [{ ...terminal, operation: 'workspace_inventory', stdout: './fresh-recipes.html' }],
  } as ShellEvidence;
  const read = vi.fn(async () => bytes);
  return { receipt, read, source };
}
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });
describe('bounded diagnosable content quality infrastructure', () => {
  it.each([
    ['missing-transport', 'content_check_transport_missing'], ['http', 'content_check_http_503'],
    ['network', 'content_check_transport_error'], ['timeout', 'content_check_timeout'],
    ['length', 'content_check_finish_length'], ['finish', 'content_check_finish_content_filter'],
    ['invalid-envelope', 'content_check_unparseable'], ['invalid-json', 'content_check_unparseable'],
    ['no-body', 'content_check_unparseable'], ['no-choice', 'content_check_unparseable'],
    ['refusal', 'content_check_refusal'], ['oversize', 'content_check_response_too_large'],
    ['contradiction', 'content_check_contradictory_verdict'],
    ['non-object', 'content_check_unparseable'], ['uncertain', 'content_check_uncertain'],
    ['missing-reference', 'content_check_missing_reference'], ['preservation', 'content_check_preservation_mismatch'],
  ])('retries once and permits the next build without claiming approval: %s', async (scenario, reason) => {
    const f = await fixture();
    if (scenario === 'preservation') f.receipt.evidence.push({ documentSourceCheck: { requestedItems: [{ ...item, item: 'Ingredients' }] } });
    const fetcher = vi.fn(async () => {
      if (scenario === 'http') return new Response(null, { status: 503 });
      if (scenario === 'network') throw new Error('private endpoint and payload must not leak');
      if (scenario === 'timeout') throw new DOMException('private timeout', 'TimeoutError');
      if (scenario === 'invalid-envelope') return new Response('invalid outer JSON');
      if (scenario === 'no-body') return new Response(null);
      if (scenario === 'no-choice') return Response.json({ choices: [] });
      if (scenario === 'refusal') return Response.json({ choices: [{ finish_reason: 'stop', message: { refusal: 'private refusal' } }] });
      if (scenario === 'oversize') return new Response('x'.repeat(110001));
      if (scenario === 'contradiction') return reply({ ...verdict(), status: 'issues' });
      if (scenario === 'invalid-json') return Response.json({ choices: [{ finish_reason: 'stop', message: { content: '{broken' } }] });
      if (scenario === 'non-object') return reply([]);
      if (scenario === 'uncertain' || scenario === 'missing-reference') return reply({ ...verdict(), requestedItems: [], status: scenario === 'uncertain' ? 'uncertain' : 'missing_reference' });
      return reply(verdict(), scenario === 'length' ? 'length' : scenario === 'finish' ? 'content_filter' : 'stop');
    }); vi.stubGlobal('fetch', fetcher);
    const result = await reviewDocumentSourceContent(scenario === 'missing-transport' ? {} : env, f.receipt, f.read, new AbortController().signal);
    expect(result).toMatchObject({ sourceProposalID: 'owned-source', sourceSHA256: f.source.sha256, verdict: 'unconfirmed', observations: [] });
    expect(result.issue).toBeUndefined(); expect(result.workOrders).toBeUndefined();
    expect(result.contentCheckAttempts).toHaveLength(2);
    expect(result.contentCheckAttempts?.map(a => a.reason)).toEqual([reason, reason]);
    for (const attempt of result.contentCheckAttempts ?? []) {
      expect(attempt).toMatchObject({ model: 'openai/gpt-4o', finishReason: expect.any(String), durationMs: expect.any(Number), responseBytes: expect.any(Number), contentBytes: expect.any(Number), outcome: 'unconfirmed' });
      expect(attempt.durationMs).toBeGreaterThanOrEqual(0);
    }
    if (scenario === 'http') expect(result.contentCheckAttempts?.every(a => a.httpStatus === 503)).toBe(true);
    expect(fetcher).toHaveBeenCalledTimes(scenario === 'missing-transport' ? 0 : 2);
    const workflow = { ...f.receipt.workflow!, documentSource: { source: f.source, proposalID: 'owned-source' }, documentSourceCheck: result };
    expect(documentSourceApproved(workflow)).toBe(false);
    expect(documentSourceBuildEligible(workflow)).toBe(true);
    expect(documentCompletionBudget(workflow).stages).toContain('build');
    expect(JSON.stringify(result.contentCheckAttempts)).not.toContain('private');
  });
  it('escalates truncation once and retains both attempts when the next verdict succeeds', async () => {
    const f = await fixture(), limits: number[] = [];
    const fetcher = vi.fn(async (_url, init) => { limits.push(JSON.parse(String(init.body)).max_tokens); return limits.length === 1 ? reply({}, 'length') : reply(verdict()); });
    vi.stubGlobal('fetch', fetcher);
    const result = await reviewDocumentSourceContent(env, f.receipt, f.read, new AbortController().signal);
    expect(limits).toEqual([6500, 10000]); expect(result.verdict).toBe('pass');
    expect(result.contentCheckAttempts).toMatchObject([{ attempt: 1, reason: 'content_check_finish_length', tokenLimit: 6500 }, { attempt: 2, outcome: 'pass', tokenLimit: 10000, finishReason: 'stop' }]);
    expect(result.contentCheckAttempts?.every(a => a.responseBytes > 0 && a.httpStatus === 200)).toBe(true);
  });
  it('uses normalized item identity, not identical literal quotes across independent reviews', async () => {
    const f = await fixture(); f.receipt.evidence.push({ documentSourceCheck: { requestedItems: [item] } });
    vi.stubGlobal('fetch', vi.fn(async () => reply({ ...verdict(), requestedItems: [{ ...item, item: '  RECIPES  ', quote: 'quantified ingredients' }] })));
    const result = await reviewDocumentSourceContent(env, f.receipt, f.read, new AbortController().signal);
    expect(result.verdict).toBe('pass'); expect(result.issue).toBeUndefined(); expect(result.contentCheckAttempts).toHaveLength(1);
    expect(result.requestedItems?.[0].quote).toBe('quantified ingredients');
  });
  it('retains positive anchored gaps from a contradictory pass as repair work, not checker absence', async () => {
    const f = await fixture();
    const gap = { ...item, status: 'underdeveloped_requested_item', repair: 'Add numbered technique and useful storage guidance in Recipes.' };
    const fetcher = vi.fn(async () => reply({ ...verdict(), requestedItems: [gap] })); vi.stubGlobal('fetch', fetcher);
    const result = await reviewDocumentSourceContent(env, f.receipt, f.read, new AbortController().signal);
    expect(result).toMatchObject({ verdict: 'issues', issue: 'document_content_incomplete', workOrders: [{ item: 'Recipes', action: 'expand' }], contentCheckAttempts: [{ reason: 'content_check_contradictory_verdict', outcome: 'issues' }] });
    expect(fetcher).toHaveBeenCalledTimes(1);
    expect(documentSourceBuildEligible({ ...f.receipt.workflow!, documentSource: { source: f.source, proposalID: 'owned-source' }, documentSourceCheck: result })).toBe(false);
  });
  it.each(['uncertain', 'missing_reference'])('keeps independently grounded per-item repairs despite declared %s', async status => {
    const f = await fixture();
    vi.stubGlobal('fetch', vi.fn(async () => reply({ ...verdict(), status, requestedItems: [{ ...item, status: 'underdeveloped_requested_item', repair: 'Add numbered technique and storage guidance.' }] })));
    const result = await reviewDocumentSourceContent(env, f.receipt, f.read, new AbortController().signal);
    expect(result).toMatchObject({ verdict: 'issues', issue: 'document_content_incomplete', workOrders: [{ item: 'Recipes', action: 'expand' }] });
    expect(result.contentCheckAttempts).toHaveLength(1);
  });
  it.each(['missing-items', 'preservation-mismatch'])('does not discard a separately grounded finding because of %s', async scenario => {
    const f = await fixture();
    if (scenario === 'preservation-mismatch') f.receipt.evidence.push({ documentSourceCheck: { requestedItems: [{ ...item, item: 'Ingredients' }] } });
    vi.stubGlobal('fetch', vi.fn(async () => reply({ ...verdict(), status: 'issues', ...(scenario === 'missing-items' ? { requestedItems: undefined } : {}), findings: [{ kind: 'underdeveloped_requested_item', item: 'Recipes', detail: 'Technique is thin.', repair: 'Add numbered technique.', evidenceID: 'request', quote: 'recipes and quantified ingredients' }] })));
    const result = await reviewDocumentSourceContent(env, f.receipt, f.read, new AbortController().signal);
    expect(result).toMatchObject({ verdict: 'issues', issue: 'document_content_incomplete', findings: [{ item: 'Recipes' }] });
    expect(result.observations.some(value => value.includes('Technique is thin.'))).toBe(true);
    expect(result.contentCheckAttempts).toHaveLength(scenario === 'missing-items' ? 2 : 1);
    if (scenario === 'missing-items') expect(result.contentCheckAttempts).toMatchObject([{ outcome: 'unconfirmed', validationCode: 'items_shape' }, { outcome: 'unconfirmed', validationCode: 'items_shape' }]);
  });
  it('repairs malformed coverage once while preserving grounded findings and exact work orders', async () => {
    const f = await fixture();
    const finding = { kind: 'underdeveloped_requested_item', item: 'Recipes', detail: 'Technique is thin.', repair: 'Add numbered technique.', evidenceID: 'request', quote: 'recipes and quantified ingredients' };
    const gap = { ...item, status: 'underdeveloped_requested_item', repair: finding.repair };
    const fetcher = vi.fn().mockResolvedValueOnce(reply({ ...verdict(), status: 'issues', findings: [finding], requestedItems: [{ ...gap, coverageQuote: 'not present in source' }] }))
      .mockResolvedValueOnce(reply({ ...verdict(), status: 'issues', findings: [finding], requestedItems: [gap] }));
    vi.stubGlobal('fetch', fetcher);
    const result = await reviewDocumentSourceContent(env, f.receipt, f.read, new AbortController().signal);
    expect(fetcher).toHaveBeenCalledTimes(2);
    expect(result).toMatchObject({ verdict: 'issues', issue: 'document_content_incomplete', findings: [finding], workOrders: [{ item: 'Recipes', section: 'Recipes', action: 'expand', requirements: finding.repair }] });
    expect(result.contentCheckAttempts).toMatchObject([{ outcome: 'unconfirmed', validationCode: 'item_coverage_anchor' }, { outcome: 'issues' }]);
    expect(documentSourceBuildEligible({ ...f.receipt.workflow!, documentSource: { source: f.source, proposalID: 'owned-source' }, documentSourceCheck: result })).toBe(false);
  });
  it.each(['transport', 'malformed', 'contradictory-pass'])('retains the grounded rejection if coverage repair ends with %s', async scenario => {
    const f = await fixture();
    const finding = { kind: 'underdeveloped_requested_item', item: 'Recipes', detail: 'Technique is thin.', repair: 'Add numbered technique.', evidenceID: 'request', quote: 'recipes and quantified ingredients' };
    const fetcher = vi.fn().mockResolvedValueOnce(reply({ ...verdict(), status: 'issues', findings: [finding], requestedItems: [] }));
    if (scenario === 'transport') fetcher.mockRejectedValueOnce(new Error('synthetic unavailable'));
    else if (scenario === 'malformed') fetcher.mockResolvedValueOnce(reply({ ...verdict(), status: 'issues', findings: [finding], requestedItems: [] }));
    else fetcher.mockResolvedValueOnce(reply(verdict()));
    vi.stubGlobal('fetch', fetcher);
    const result = await reviewDocumentSourceContent(env, f.receipt, f.read, new AbortController().signal);
    expect(fetcher).toHaveBeenCalledTimes(2);
    expect(result).toMatchObject({ verdict: 'issues', issue: 'document_content_incomplete', findings: [finding] });
    expect(result.workOrders ?? []).toEqual([]);
    expect(result.contentCheckAttempts).toHaveLength(2);
    expect(documentSourceBuildEligible({ ...f.receipt.workflow!, documentSource: { source: f.source, proposalID: 'owned-source' }, documentSourceCheck: result })).toBe(false);
  });
  it('binds a final unconfirmed review to complete final/source hashes, not a pass or qualified shortfall', async () => {
    const f = await fixture(); f.receipt.workflow!.documentExecution = { invocation: { stage: 'build', interpreter: 'python3', code: '# never executed', path: 'fresh-recipes.pdf' }, source: f.source };
    const manifest = { path: 'fresh-recipes.pdf', sha256: 'b'.repeat(64), size: 100, format: 'pdf', pages: 1, proofs: [], verification: { version: 'knot_document_proof_v1' as const, sourceSHA256: 'b'.repeat(64), sourceSize: 100, format: 'pdf', renderedPages: 1, textSHA256: f.source.sha256, textSize: bytes.length, textPath: 'complete.txt', markupScan: 'clear' as const, renderer: 'poppler' as const, producerChecked: false } };
    vi.stubGlobal('fetch', vi.fn(async () => { throw new Error('synthetic dead endpoint'); }));
    const result = await reviewDocumentContent(env, f.receipt, manifest, f.read, new AbortController().signal);
    expect(result.issue).toBeUndefined();
    expect(result.review).toMatchObject({ status: 'unconfirmed', finalSHA256: manifest.sha256, finalTextSHA256: f.source.sha256, sourceSHA256s: [f.source.sha256], scope: 'complete_text', contentCheckAttempts: [{ reason: 'content_check_transport_error' }, { reason: 'content_check_transport_error' }] });
    expect(result.review?.shortfalls).toBeUndefined();
  });
  it.each(['stop', 'changed-bytes', 'missing-inventory', 'evidence-limit'])('does not degrade execution/integrity/complete-read safeguards: %s', async scenario => {
    const f = await fixture(), controller = new AbortController();
    if (scenario === 'stop') controller.abort();
    if (scenario === 'changed-bytes') f.read.mockRejectedValue(new Error('document_bytes_changed'));
    if (scenario === 'missing-inventory') f.receipt.evidence = [];
    if (scenario === 'evidence-limit') f.receipt.workflow!.originalRequest = 'x'.repeat(180001);
    const fetcher = vi.fn(async () => reply(verdict())); vi.stubGlobal('fetch', fetcher);
    if (scenario === 'stop') await expect(reviewDocumentSourceContent(env, f.receipt, f.read, controller.signal)).rejects.toThrow('document_capture_cancelled');
    else expect((await reviewDocumentSourceContent(env, f.receipt, f.read, controller.signal)).issue).toBe(scenario === 'changed-bytes' ? 'document_bytes_changed' : scenario === 'evidence-limit' ? 'document_content_evidence_too_large' : 'document_content_source_required');
    expect(fetcher).not.toHaveBeenCalled();
  });
  it('never treats legacy opaque failure, missing check or another source hash as degraded authority', async () => {
    const f = await fixture();
    const base = { ...f.receipt.workflow!, documentSource: { source: f.source, proposalID: 'owned-source' } };
    for (const check of [undefined, { sourceProposalID: 'owned-source', sourceSHA256: f.source.sha256, issue: 'document_content_unavailable', observations: [] }, { sourceProposalID: 'other-source', sourceSHA256: f.source.sha256, verdict: 'unconfirmed' as const, observations: [] }]) expect(documentSourceBuildEligible({ ...base, documentSourceCheck: check })).toBe(false);
  });
});
