// @vitest-environment node
// Synthetic complete files and a stubbed comparator: no model, shell or droplet.
import { afterEach, describe, expect, it, vi } from 'vitest';
import { reviewDocumentSourceContent, reviewDocumentContent, groundedComparison, validateContentStage } from '../../functions/knot-document-content';
import { documentInvocationCommand } from '../../functions/knot-document-build';
import { requestedDocumentFormat } from '../../functions/knot-document-format';
import type { ShellEvidence } from '../../functions/knot-shell';
const env = { EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY: 'synthetic-not-a-key', EXPO_PUBLIC_TOOLKIT_URL: 'https://fixture.invalid' };
const source = '<!doctype html><html><head><style>@page{margin:20mm}h2{break-before:page}</style></head><body><h1>Trade guide</h1><h2>Risk</h2><p>Manage risk.</p><h2>Sizing</h2><p>Size trades.</p></body></html>';
const reference = 'Complete original reference\nRisk example: losing 2% across five positions.\nSizing example: account balance times risk divided by stop distance.\nEND OF ORIGINAL REFERENCE';
const terminal = { status: 'completed' as const, exitCode: 0, outputComplete: true, terminationConfirmed: true, truncated: false, contextTruncated: false };
const digest = async (text: string) => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text))), b => b.toString(16).padStart(2, '0')).join('');
async function fixture() {
  const descriptor = { path: 'fixture-source.html', sha256: await digest(source), size: new TextEncoder().encode(source).length, format: 'html' };
  const invocation = { stage: 'source' as const, interpreter: 'python3' as const, code: '# synthetic, never executed', path: descriptor.path };
  const receipt = { ...terminal, proposalID: 'synthetic-source', sessionID: 'synthetic-session', bot: 'main', conversationID: 'synthetic-conversation', stderr: '', reason: '', title: 'Synthetic source', tool: 'document_script', documentInvocation: invocation, reviewedCommand: documentInvocationCommand(invocation), stdout: 'KNOT_DOCUMENT_SOURCE_V1 ' + JSON.stringify(descriptor),
    workflow: { rootID: 'synthetic-task', originalRequest: 'Create a designed PDF guide that develops risk and sizing with worked numerical examples from reference.md.', documentFormat: requestedDocumentFormat('Create a PDF guide'), mode: 'Create', commands: 5, memoryRead: true, indexRead: true, skills: [], memoryWritten: false },
    evidence: [{ ...terminal, operation: 'workspace_inventory', stdout: './reference.md\n./fixture-source.html' }, { ...terminal, operation: 'workspace_read', reviewedCommand: "cat -- 'reference.md'", stdout: reference }],
  } as ShellEvidence;
  const read = vi.fn(async (path: string) => new TextEncoder().encode(path === descriptor.path ? source : reference));
  return { receipt, descriptor, read };
}
const finding = { kind: 'underdeveloped_requested_item', item: 'sizing', detail: 'Sizing has no developed calculation.', repair: 'Add and explain a worked account-risk/stop-distance calculation.', evidenceID: 'request', quote: 'risk and sizing with worked numerical examples' };
const observation = `${finding.kind}:${finding.item} — ${finding.detail} Repair: ${finding.repair}`;
function comparison(status: string, findings: unknown[] = [], advisories: string[] = []) {
  return new Response(JSON.stringify({ choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({ status, findings, advisories }) } }] }));
}
afterEach(() => { vi.unstubAllGlobals(); });
describe('independent evidence-grounded complete content findings', () => {
  it('rejects source-phase conversion claims, but retains requested substantive conversion instructions', () => {
    const falseFinding = { ...finding, detail: "The request was for a PDF document, but the operation specified is 'source' which relies on the HTML content.", repair: 'Convert the HTML source document into a PDF file following the format provided in the request.' };
    for (const operation of ['source', 'final']) expect(() => validateContentStage({ findings: [falseFinding], requestedItems: [] }, operation)).toThrow('content_check_stage_invalid');
    const substantive = { ...finding, item: 'HTML to PDF conversion procedure', detail: 'The requested explanation omits the conversion command and its required flags.', repair: 'Explain how to convert the HTML source document into a PDF file, with the command and flags.', quote: 'Explain HTML to PDF conversion' };
    for (const operation of ['source', 'final']) expect(() => validateContentStage({ findings: [substantive], requestedItems: [] }, operation)).not.toThrow();
    expect(groundedComparison({ status: 'issues', findings: [substantive], advisories: [] }, new Map([['request', 'Explain HTML to PDF conversion']]))).toMatchObject({ verdict: 'issues', issue: 'document_content_incomplete', findings: [substantive] });
  });
  it('sends the complete original ask/source/reference and retains anchored underdevelopment repairs', async () => {
    const f = await fixture();
    const fetcher = vi.fn(async (_url: string, init: RequestInit) => {
      const payload = JSON.parse(String(init.body)); const evidence = JSON.parse(payload.messages[1].content);
      expect(evidence.originalRequest).toBe(f.receipt.workflow!.originalRequest); expect(evidence.finalText).toBe(source);
      expect(evidence.sources.find((s: { path: string }) => s.path === 'reference.md')).toMatchObject({ text: reference, role: 'reference' });
      expect(payload.messages[0].content).toContain('underdeveloped_requested_item:<item>');
      expect(payload.messages[0].content).toContain('inline print CSS');
      return comparison('issues', [finding]);
    });
    vi.stubGlobal('fetch', fetcher);
    const result = await reviewDocumentSourceContent(env, f.receipt, f.read, new AbortController().signal);
    expect(result).toMatchObject({ sourceSHA256: f.descriptor.sha256, verdict: 'issues', issue: 'document_content_incomplete', observations: [observation] });
    expect(fetcher).toHaveBeenCalledTimes(1); expect(f.read).toHaveBeenCalledTimes(2);
  });
  it('keeps guessed prior-conversation requirements advisory without inventing a pass', async () => {
    const f = await fixture();
    vi.stubGlobal('fetch', vi.fn(async () => comparison('issues', [{ ...finding, detail: 'Economic and regulatory impacts may have been in a previous conversation.' }])));
    const result = await reviewDocumentSourceContent(env, f.receipt, f.read, new AbortController().signal);
    expect(result.verdict).toBe('unconfirmed'); expect(result.issue).toBeUndefined(); expect(result.observations).toEqual([]);
    expect(result.contentCheckAttempts).toHaveLength(2);
    expect(result.advisories?.[0]).toContain('previous conversation');
  });
  it('does not accept invented quotes or authored/prior text as requirement authority', async () => {
    for (const changed of [{ ...finding, quote: 'also include regulatory impacts' }, { ...finding, evidenceID: 'source_0', quote: 'Trade guide' }]) {
      const f = await fixture(); vi.stubGlobal('fetch', vi.fn(async () => comparison('issues', [changed])));
      const result = await reviewDocumentSourceContent(env, f.receipt, f.read, new AbortController().signal);
      expect(result.verdict).toBe('unconfirmed'); expect(result.issue).toBeUndefined(); expect(result.observations).toEqual([]);
      expect(result.contentCheckAttempts).toHaveLength(2); expect(result.advisories).toHaveLength(1);
    }
  });
  it('retains genuine reference-anchored findings with concrete repair instructions', () => {
    const result = groundedComparison({ status: 'issues', findings: [{ ...finding, evidenceID: 'actual_ref', quote: 'account balance times risk divided by stop distance' }], advisories: [] }, new Map([['actual_ref', reference]]));
    expect(result).toMatchObject({ issue: 'document_content_incomplete', observations: [observation] });
  });
  it('records unusable verdicts as unconfirmed, while contradictory passes retain anchored repairs', async () => {
    for (const [status, findings] of [['issues', []], ['pass', [finding]], ['uncertain', []], ['issues', [{ kind: finding.kind }]]] as const) {
      const f = await fixture(), fetcher = vi.fn(async () => comparison(status, [...findings])); vi.stubGlobal('fetch', fetcher);
      const result = await reviewDocumentSourceContent(env, f.receipt, f.read, new AbortController().signal);
      if (status === 'pass') {
        expect(result).toMatchObject({ verdict: 'issues', issue: 'document_content_incomplete', observations: [observation], contentCheckAttempts: [{ reason: 'content_check_contradictory_verdict', outcome: 'issues' }] });
        expect(fetcher).toHaveBeenCalledTimes(1);
      } else {
        expect(result.verdict).toBe('unconfirmed'); expect(result.issue).toBeUndefined(); expect(result.observations).toEqual([]);
        expect(result.contentCheckAttempts).toHaveLength(2); expect(fetcher).toHaveBeenCalledTimes(2);
      }
    }
  });
  it('fails without complete inventory before contacting the comparison service', async () => {
    const f = await fixture(); f.receipt.evidence = f.receipt.evidence.filter(e => e.operation !== 'workspace_inventory');
    const fetcher = vi.fn(); vi.stubGlobal('fetch', fetcher);
    expect((await reviewDocumentSourceContent(env, f.receipt, f.read, new AbortController().signal)).issue).toBe('document_content_source_required'); expect(fetcher).not.toHaveBeenCalled();
  });
  it('returns source-only approval without claiming delivery or rendered proof', async () => {
    const f = await fixture(); vi.stubGlobal('fetch', vi.fn(async () => comparison('pass')));
    expect(await reviewDocumentSourceContent(env, f.receipt, f.read, new AbortController().signal)).toMatchObject({ sourceProposalID: 'synthetic-source', sourceSHA256: f.descriptor.sha256, observations: [], verdict: 'pass', contentCheckAttempts: [{ outcome: 'pass', model: 'openai/gpt-4o' }] });
  });
  it('compares full measured prior source attempts as preservation context, not new scope', async () => {
    const f = await fixture(); const previous = '<html><body>A complete developed earlier risk calculation. END OF PREVIOUS SOURCE</body></html>';
    const prior = { ...f.receipt, proposalID: 'prior-source', documentInvocation: { ...f.receipt.documentInvocation!, path: 'prior.html' } };
    prior.reviewedCommand = documentInvocationCommand(prior.documentInvocation);
    prior.stdout = 'KNOT_DOCUMENT_SOURCE_V1 ' + JSON.stringify({ path: 'prior.html', sha256: await digest(previous), size: new TextEncoder().encode(previous).length, format: 'html' });
    f.receipt.evidence.unshift(prior as unknown as Record<string, unknown>);
    f.read.mockImplementation(async path => new TextEncoder().encode(path === 'prior.html' ? previous : path === f.descriptor.path ? source : reference));
    vi.stubGlobal('fetch', vi.fn(async (_url, init) => {
      const data = JSON.parse(JSON.parse(String(init.body)).messages[1].content);
      expect(data.sources.find((s: { path: string }) => s.path === 'prior.html')).toMatchObject({ text: previous, role: 'prior_attempt' });
      return comparison('issues', [{ ...finding, kind: 'regressed_requested_content', detail: 'The requested sizing calculation was lost in the rewrite.' }]);
    }));
    const result = await reviewDocumentSourceContent(env, f.receipt, f.read, new AbortController().signal);
    expect(result.issue).toBe('document_content_incomplete'); expect(f.read).toHaveBeenCalledWith('prior.html', await digest(previous), new TextEncoder().encode(previous).length);
  });
  it('compares a full prior same-task raw final while keeping the new raw extension', async () => {
    const f = await fixture(); const previous = '# Full prior report\nDetailed earlier sizing calculation.\nEND OF RAW ATTEMPT';
    const priorInvocation = { stage: 'final' as const, interpreter: 'python3' as const, path: 'prior.md', code: '# prior, never executed' };
    f.receipt.evidence.unshift({ ...terminal, sessionID: 'owned-session', documentInvocation: priorInvocation, reviewedCommand: documentInvocationCommand(priorInvocation), stdout: 'KNOT_DOCUMENT_V1 ' + JSON.stringify({ path: 'prior.md', format: 'md', sha256: await digest(previous), size: new TextEncoder().encode(previous).length }) });
    const current = '# New report\nComplete current content';
    const invocation = { ...priorInvocation, path: 'current.md', code: '# new, never executed' };
    f.receipt.workflow!.originalRequest = 'Create an MD file with the complete sizing calculation.';
    f.receipt.workflow!.documentFormat = requestedDocumentFormat('Create an MD file');
    f.receipt.workflow!.documentExecution = { invocation };
    f.read.mockImplementation(async path => new TextEncoder().encode(path === 'prior.md' ? previous : path === 'current.md' ? current : reference));
    vi.stubGlobal('fetch', vi.fn(async (_url, init) => {
      const data = JSON.parse(JSON.parse(String(init.body)).messages[1].content);
      expect(data.requestedFormat.format).toBe('md'); expect(data.finalText).toBe(current);
      expect(data.sources.find((s: { path: string }) => s.path === 'prior.md')).toMatchObject({ role: 'prior_attempt', text: previous });
      return comparison('pass');
    }));
    const result = await reviewDocumentContent(env, f.receipt, { path: 'current.md', format: 'md', sha256: await digest(current), size: new TextEncoder().encode(current).length, pages: 1, proofs: [] }, f.read, new AbortController().signal);
    expect(result.review).toMatchObject({ status: 'pass', scope: 'complete_text' });
  });
});
