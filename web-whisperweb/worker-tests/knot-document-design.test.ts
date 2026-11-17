// @vitest-environment node
// Synthetic metadata/command construction only. No generated Python, utility,
// renderer, model, executor, workspace read or authenticated interaction runs.
import { describe, expect, it } from 'vitest';
import { createHash } from 'node:crypto';
import { documentInvocationCommand, verifiedDocumentExecution, type DocumentSource } from '../../functions/knot-document-build';
import { verifiedDocumentProof } from '../../functions/knot-document-proof';
import type { ShellEvidence } from '../../functions/knot-shell';
import { residentDocumentTransport, knotDocV2SHA256, verifiedResidentDocumentEvidence, residentDocumentStyleObservation } from '../../functions/knot-document-resident';
import { authoredDesignResidentCommand } from '../../functions/knot-document-design';
const taskID = '00000000-0000-4000-8000-000000000001';
const source: DocumentSource = { path: 'fresh.html', sha256: 'a'.repeat(64), size: 1200, format: 'html' };
const invocation = { stage: 'build' as const, interpreter: 'knot-doc' as const, code: '', path: 'fresh.pdf' };
const final = { path: invocation.path, format: 'pdf', sha256: 'b'.repeat(64), size: 3000, pages: 2, proofs: [] };
function fixture() {
  const inputs = { design: 'authored-inline-v1', styleEncoding: 'html-parser-style-records-v1', source, styleSHA256: 'c'.repeat(64), styleBytes: 100, resourcePolicy: 'deny-all-v1' };
  return {
    version: 'knot_doc_2_0_0', toolSHA256: knotDocV2SHA256,
    manifest: { ...final, toolVersion: '2.0.0', taskID, sourceSHA256: source.sha256, inputsSHA256: 'd'.repeat(64), proofStageOnly: true, independentVerification: false },
    inputs: { toolVersion: '2.0.0', sourceSHA256: source.sha256, sourceBytes: source.size, sourceFormat: source.format, design: 'author-v1', houseStyleSHA256: 'e'.repeat(64) },
    journal: { path: '.knot-doc/v2/' + taskID + '/' + 'd'.repeat(64) + '.jsonl', sha256: 'f'.repeat(64), size: 900 },
    designEvidence: { inputs, entries: [
      { state: 'intent', taskID, output: final.path, inputs },
      { state: 'staged', taskID, output: final.path, rendererInputsSHA256: 'd'.repeat(64), rendererJournalSHA256: 'f'.repeat(64), finalSHA256: final.sha256, finalBytes: final.size },
    ], journal: { path: '.knot-doc/design/' + taskID + '/' + '1'.repeat(64) + '.jsonl', sha256: '2'.repeat(64), size: 1200 } },
  };
}
const transport = residentDocumentTransport('2.0.0', taskID, undefined, true)!;
const verified = (value: unknown) => verifiedResidentDocumentEvidence('KNOT_RESIDENT_DOCUMENT_V1 ' + JSON.stringify(value), source, transport, final);
describe('nonblocking fresh style evidence', () => {
  const fresh = { ...transport, styleEvidencePolicy: 'record_v1' as const };
  const accepts = (value: unknown) => verifiedResidentDocumentEvidence('KNOT_RESIDENT_DOCUMENT_V1 ' + JSON.stringify(value), source, fresh, final);
  it('accepts the actual authored HTML lane with a null house hash and separate CSS hash', () => {
    const value = fixture(); Object.assign(value.inputs, { houseStyleSHA256: null });
    expect(accepts(value)).toBe(true);
    expect(verified(value)).toBe(false); // Historical policy is unchanged.
  });
  it.each(['missing-design-journal', 'missing-house-hash', 'malformed-house-hash', 'missing-css-hash', 'malformed-css-hash', 'empty-css', 'wrong-design-label'])('does not strand delivery for style-only metadata: %s', scenario => {
    const value = fixture();
    if (scenario === 'missing-design-journal') delete (value as Partial<typeof value>).designEvidence;
    if (scenario === 'missing-house-hash') delete (value.inputs as Partial<typeof value.inputs>).houseStyleSHA256;
    if (scenario === 'malformed-house-hash') value.inputs.houseStyleSHA256 = 'malformed';
    if (scenario === 'missing-css-hash') delete (value.designEvidence.inputs as Partial<typeof value.designEvidence.inputs>).styleSHA256;
    if (scenario === 'malformed-css-hash') value.designEvidence.inputs.styleSHA256 = 'malformed';
    if (scenario === 'empty-css') value.designEvidence.inputs.styleBytes = 0;
    if (scenario === 'wrong-design-label') value.inputs.design = 'house-v1';
    expect(accepts(value)).toBe(true);
  });
  it.each(['source', 'task', 'final', 'renderer-journal', 'tool', 'renderer-source', 'renderer-task'])('retains hard provenance and byte bindings: %s', scenario => {
    const value = fixture();
    if (scenario === 'source') value.designEvidence.inputs.source = { ...source, sha256: '9'.repeat(64) };
    if (scenario === 'task') value.designEvidence.entries[0].taskID = 'foreign';
    if (scenario === 'final') value.designEvidence.entries[1].finalSHA256 = '9'.repeat(64);
    if (scenario === 'renderer-journal') value.designEvidence.entries[1].rendererJournalSHA256 = '9'.repeat(64);
    if (scenario === 'tool') value.toolSHA256 = '9'.repeat(64);
    if (scenario === 'renderer-source') value.manifest.sourceSHA256 = '9'.repeat(64);
    if (scenario === 'renderer-task') value.manifest.taskID = 'foreign';
    expect(accepts(value)).toBe(false);
  });
  it('records HTML null and the actual independent authored CSS hash as nonblocking facts', () => {
    const value = fixture(); Object.assign(value.inputs, { houseStyleSHA256: null });
    const stdout = 'KNOT_RESIDENT_DOCUMENT_V1 ' + JSON.stringify(value);
    expect(residentDocumentStyleObservation(stdout, source, fresh, final)).toMatchObject({ status: 'recorded', blocking: false, issues: [], houseStyleSHA256: { type: 'null', value: null }, styleSHA256: { type: 'string', value: 'c'.repeat(64) }, styleBytes: { type: 'number', value: 100 } });
    value.designEvidence.inputs.styleSHA256 = 'bad';
    expect(residentDocumentStyleObservation('KNOT_RESIDENT_DOCUMENT_V1 ' + JSON.stringify(value), source, fresh, final)).toMatchObject({ status: 'advisory', blocking: false, issues: ['authored_css_evidence_unavailable_or_malformed'], styleSHA256: { type: 'string', value: 'bad' } });
    expect(residentDocumentStyleObservation(stdout, source, transport, final)).toBeUndefined();
    value.manifest.taskID = 'foreign';
    expect(residentDocumentStyleObservation('KNOT_RESIDENT_DOCUMENT_V1 ' + JSON.stringify(value), source, fresh, final)).toBeUndefined();
  });
  it('describes unsafe or oversize style values without dumping structured contents', () => {
    for (const [actual, expected] of [[undefined, { type: 'missing' }], [{ secret: 'never in Events' }, { type: 'object', valueOmitted: true }], ['x'.repeat(161), { type: 'string', length: 161, valueOmitted: true }], [23, { type: 'number', value: 23 }]] as const) {
      const value = fixture(); Object.assign(value.inputs, { houseStyleSHA256: actual });
      const observation = residentDocumentStyleObservation('KNOT_RESIDENT_DOCUMENT_V1 ' + JSON.stringify(value), source, fresh, final);
      expect(observation).toMatchObject({ blocking: false, status: 'advisory', houseStyleSHA256: expected });
      expect(JSON.stringify(observation)).not.toContain('never in Events');
    }
  });
  it('constructs a separate nonblocking adapter without removing byte/journal checks', () => {
    const command = documentInvocationCommand(invocation, source, true, fresh);
    expect(command).not.toContain("assert isinstance(inputs['houseStyleSHA256'],str)");
    expect(command).toContain("designEvidence=dict(status='unavailable'");
    expect(command).toContain("'document_design_journal_changed'");
    expect(command).toContain("'document_source_changed'");
    expect(command).toContain("assert measured(c['path'])==final, 'document_bytes_changed'");
    expect(command).toContain("'document_output_exists'");
    expect(Buffer.byteLength(command)).toBeLessThanOrEqual(12000);
  });
  it('retains both historical v2 command identities', () => {
    for (const [journal, sha256, bytes] of [[false, '6e453ab3394953cf85692471275032f58ef15a099f7b6f8f1834cc1eb732bf50', 5985], [true, 'b8c39c00fff8444f753858f39333584a96e060fb408230c7caeff5795b596b70', 8927]] as const) {
      const command = documentInvocationCommand(invocation, source, true, residentDocumentTransport('2.0.0', taskID, undefined, journal));
      expect(createHash('sha256').update(command).digest('hex')).toBe(sha256);
      expect(Buffer.byteLength(command)).toBe(bytes);
    }
  });
});
describe('fresh authored CSS journal', () => {
  it('requires fresh opt-in, leaves both historical transports and explicit templates alone', () => {
    expect(residentDocumentTransport('2.0.0', taskID)?.designJournal).toBeUndefined();
    expect(residentDocumentTransport('1.0.0', taskID, undefined, true)?.designJournal).toBeUndefined();
    expect(residentDocumentTransport('2.0.0', taskID, 'guide', true)).toEqual({ version: 'knot_doc_2_0_0', taskID, template: 'guide' });
    const old = documentInvocationCommand(invocation, { path: 'fixture-source.md', sha256: 'a'.repeat(64), size: 12, format: 'md' }, true, { version: 'knot_doc_1_0_0', taskID });
    // Existing byte-identity fixture has a different declared output name here;
    // prove opting out adds no journal code rather than rebinding the old fixture.
    expect(old).not.toContain('DesignStyles');
    const previous = documentInvocationCommand(invocation, source, true, residentDocumentTransport('2.0.0', taskID));
    expect(previous).not.toContain('designEvidence');
    expect(createHash('sha256').update(previous).digest('hex')).not.toBe(createHash('sha256').update(documentInvocationCommand(invocation, source, true, transport)).digest('hex'));
  });
  it('binds source, parsed style bytes, renderer journal and unchanged final in a separate exclusive journal', () => {
    const command = documentInvocationCommand(invocation, source, true, transport);
    expect(command).toContain("target.open('xb')");
    expect(command).toContain("styleSHA256=digest(styles),styleBytes=len(styles)");
    expect(command).toContain("rendererJournalSHA256=digest(journal)");
    expect(command).toContain("assert design_inputs()==designInputs");
    expect(command).toContain("assert measured(c['path'])==final");
    expect(command).toContain("'document_authored_style_required'");
    expect(Buffer.byteLength(command)).toBeLessThanOrEqual(12000);
    expect(verified(fixture())).toBe(true);
  });
  it.each(['absent', 'source', 'style-hash', 'style-size', 'encoding', 'policy', 'intent', 'renderer-inputs', 'renderer-journal', 'final-hash', 'final-size', 'foreign-journal', 'extra-entry'])('rejects %s design metadata', scenario => {
    const value = fixture();
    if (scenario === 'absent') delete (value as Partial<typeof value>).designEvidence;
    if (scenario === 'source') value.designEvidence.inputs.source = { ...source, sha256: '9'.repeat(64) };
    if (scenario === 'style-hash') value.designEvidence.inputs.styleSHA256 = 'invalid';
    if (scenario === 'style-size') value.designEvidence.inputs.styleBytes = 0;
    if (scenario === 'encoding') value.designEvidence.inputs.styleEncoding = 'unbound';
    if (scenario === 'policy') value.designEvidence.inputs.resourcePolicy = 'allow-network';
    if (scenario === 'intent') value.designEvidence.entries[0].taskID = 'foreign';
    if (scenario === 'renderer-inputs') value.designEvidence.entries[1].rendererInputsSHA256 = '9'.repeat(64);
    if (scenario === 'renderer-journal') value.designEvidence.entries[1].rendererJournalSHA256 = '9'.repeat(64);
    if (scenario === 'final-hash') value.designEvidence.entries[1].finalSHA256 = '9'.repeat(64);
    if (scenario === 'final-size') value.designEvidence.entries[1].finalBytes = 1;
    if (scenario === 'foreign-journal') value.designEvidence.journal.path = '.knot-doc/design/foreign/' + '1'.repeat(64) + '.jsonl';
    if (scenario === 'extra-entry') value.designEvidence.entries.push(value.designEvidence.entries[0]);
    expect(verified(value)).toBe(false);
  });
  it.each(['owned', 'fresh-policy', 'policy-only-in-workflow', 'policy-only-in-transport', 'no-workflow-opt-in', 'no-transport-opt-in', 'missing-source', 'incomplete-build'] as const)('checks the full owned execution chain: %s', scenario => {
    const sourceID = '00000000-0000-4000-8000-000000000002';
    const sourceInvocation = { stage: 'source' as const, interpreter: 'python3' as const, code: '# Synthetic fixture, never executed.', path: source.path };
    const terminal = { status: 'completed' as const, exitCode: 0, sessionID: 'synthetic-design-session', outputComplete: true, terminationConfirmed: true, truncated: false, contextTruncated: false };
    const resident = { ...transport, ...(['fresh-policy', 'policy-only-in-transport'].includes(scenario) ? { styleEvidencePolicy: 'record_v1' as const } : {}) };
    const sourceEvidence = { ...terminal, proposalID: sourceID, documentInvocation: sourceInvocation, reviewedCommand: documentInvocationCommand(sourceInvocation), stdout: 'KNOT_DOCUMENT_SOURCE_V1 ' + JSON.stringify(source) };
    const stdout = 'KNOT_RESIDENT_DOCUMENT_V1 ' + JSON.stringify(fixture()) + '\nKNOT_DOCUMENT_V1 ' + JSON.stringify(final);
    const buildEvidence = { ...terminal, proposalID: taskID, reviewedCommand: documentInvocationCommand(invocation, source, true, resident), stdout };
    const receipt = {
      ...terminal, proposalID: taskID, bot: 'main', conversationID: taskID, stderr: '', reason: '', title: 'Synthetic authored document', tool: 'document_script', stdout, reviewedCommand: buildEvidence.reviewedCommand,
      workflow: { rootID: taskID, originalRequest: 'Create a PDF document', mode: 'Create', memoryRead: true, indexRead: true, skills: [], commands: 5, memoryWritten: false, residentDocumentTool: '2.0.0', documentValidation: 'structural_v2', documentDesignJournal: 'author_css_v1', documentExecution: { invocation, source, sourceProposalID: sourceID, resident } },
      evidence: [sourceEvidence, buildEvidence],
    } as ShellEvidence;
    if (['fresh-policy', 'policy-only-in-workflow'].includes(scenario)) receipt.workflow!.styleEvidencePolicy = 'record_v1';
    if (scenario === 'no-workflow-opt-in') delete receipt.workflow!.documentDesignJournal;
    if (scenario === 'no-transport-opt-in') delete resident.designJournal;
    if (scenario === 'missing-source') receipt.evidence = [buildEvidence];
    if (scenario === 'incomplete-build') buildEvidence.outputComplete = false;
    expect(verifiedDocumentExecution(receipt, final)).toBe(scenario === 'owned' || scenario === 'fresh-policy');
    // Even complete authored-design execution evidence is not independent proof
    // or permission to capture/deliver an unreviewed PDF.
    expect(verifiedDocumentProof(receipt, final)).toBeUndefined();
  });
  it('refuses a changed adapter skeleton rather than silently omitting part of the journal', () => {
    expect(() => authoredDesignResidentCommand('def check_source():\n    pass')).toThrow('invalid_document_design_adapter');
  });
  it('never applies HTML journaling to Markdown or v1', () => {
    expect(() => documentInvocationCommand(invocation, { ...source, format: 'md' }, true, transport)).toThrow('invalid_document_invocation');
    expect(() => documentInvocationCommand(invocation, source, true, { ...transport, version: 'knot_doc_1_0_0' })).toThrow('invalid_document_invocation');
  });
});
