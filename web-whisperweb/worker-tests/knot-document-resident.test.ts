// @vitest-environment node
// Synthetic receipt/unit regressions only. No utility, generated Python, model,
// network, workspace command or authenticated app interaction runs in this file.
import { describe, expect, it } from 'vitest';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { documentInvocationCommand, documentSource, validatedDocumentInvocation, verifiedDocumentExecution, type DocumentInvocation, type DocumentSource } from '../../functions/knot-document-build';
import { knotDocSHA256, knotDocV2SHA256, residentDocumentTransport, verifiedResidentDocumentEvidence, residentDocumentStyleObservation, type ResidentDocumentTransport } from '../../functions/knot-document-resident';
import { documentFormatIssue, requestedDocumentFormat } from '../../functions/knot-document-format';
import { documentRequest, needsDocumentProof, verifiedDocumentProof } from '../../functions/knot-document-proof';
import { knotSelectionDirective, validatedKnotSelection } from '../../functions/knot-tool-selection';
import type { DocumentManifest } from '../../functions/knot-documents';
import type { ShellEvidence } from '../../functions/knot-shell';

const taskID = '00000000-0000-4000-8000-000000000001';
const sourceID = '00000000-0000-4000-8000-000000000002';
const source: DocumentSource = { path: 'fixture-source.md', sha256: 'a'.repeat(64), size: 12, format: 'md' };
const resident: ResidentDocumentTransport = { version: 'knot_doc_1_0_0', taskID };
const invocation: DocumentInvocation = { stage: 'build', interpreter: 'knot-doc', code: '', path: 'fixture-final.pdf' };
const final: DocumentManifest = { path: invocation.path, sha256: 'b'.repeat(64), size: 120, format: 'pdf', pages: 1, proofs: [] };
function fixture(version: '1.0.0' | '2.0.0' = '1.0.0') {
  const transport = residentDocumentTransport(version, taskID)!;
  const audit = {
    version: transport.version, toolSHA256: version === '1.0.0' ? knotDocSHA256 : knotDocV2SHA256,
    inputs: { toolVersion: version, sourceSHA256: source.sha256, sourceBytes: source.size, sourceFormat: source.format, ...(version === '2.0.0' ? { design: 'house-v1', houseStyleSHA256: 'd'.repeat(64) } : {}) },
    manifest: { ...final, toolVersion: version, taskID, sourceSHA256: source.sha256, inputsSHA256: 'c'.repeat(64), proofStageOnly: true, independentVerification: false },
  };
  const sourceInvocation: DocumentInvocation = { stage: 'source', interpreter: 'python3', code: '# Synthetic fixture, never executed.', path: source.path };
  const terminal = { status: 'completed' as const, exitCode: 0, sessionID: 'fixture-only-session', outputComplete: true, terminationConfirmed: true, truncated: false, contextTruncated: false };
  const sourceEvidence = { ...terminal, proposalID: sourceID, documentInvocation: sourceInvocation, reviewedCommand: documentInvocationCommand(sourceInvocation), stdout: 'KNOT_DOCUMENT_SOURCE_V1 ' + JSON.stringify(source) };
  const buildEvidence = { ...terminal, proposalID: taskID, reviewedCommand: documentInvocationCommand(invocation, source, true, transport), stdout: '' };
  const receipt = {
    ...terminal, proposalID: taskID, bot: 'main', conversationID: taskID, stderr: '', reason: '', title: 'Synthetic fixture', tool: 'document_script',
    reviewedCommand: buildEvidence.reviewedCommand, stdout: '',
    workflow: { rootID: taskID, originalRequest: 'Create a PDF document', mode: 'Create', memoryRead: true, indexRead: true, skills: [], commands: 5, memoryWritten: false, residentDocumentTool: version, documentValidation: 'structural_v2', documentFormat: requestedDocumentFormat('Create a PDF document'), documentExecution: { invocation, source, sourceProposalID: sourceID, resident: transport } },
    evidence: [sourceEvidence, buildEvidence],
  } as ShellEvidence;
  const refresh = () => {
    const stdout = 'KNOT_RESIDENT_DOCUMENT_V1 ' + JSON.stringify(audit) + '\nKNOT_DOCUMENT_V1 ' + JSON.stringify(final);
    buildEvidence.stdout = stdout; receipt.stdout = stdout;
    return stdout;
  };
  refresh();
  return { receipt, sourceEvidence, buildEvidence, audit, refresh };
}

describe('versioned resident PDF admission', () => {
  it('preserves the pre-v2 version-one command byte for byte', () => {
    const command = documentInvocationCommand(invocation, source, true, resident);
    expect(createHash('sha256').update(command).digest('hex')).toBe('492f82b6a2e09eb6314456d48e897046f4ce2795d36e64c08310a80c4e84be38');
    expect(Buffer.byteLength(command)).toBe(5799);
  });
  it('pins version two separately and binds design metadata without inventing a stylesheet hash', () => {
    const transport = residentDocumentTransport('2.0.0', taskID)!;
    const command = documentInvocationCommand(invocation, source, true, transport);
    expect(command).toContain('/opt/knot-tools/knot-doc/v2/knot-doc');
    expect(command).toContain(knotDocV2SHA256);
    expect(command).toContain(".knot-doc/v2/");
    expect(command).toContain("inputs['design']==('house-v1' if c['source']['format']=='md' else 'author-v1')");
    expect(command).toContain("inputs['houseStyleSHA256']");
    expect(Buffer.byteLength(command)).toBeLessThanOrEqual(12000);
    const f = fixture('2.0.0');
    expect(verifiedDocumentExecution(f.receipt, final)).toBe(true);
    expect(verifiedDocumentProof(f.receipt, final)).toBeUndefined();
    expect(verifiedResidentDocumentEvidence(f.refresh(), source, resident, final)).toBe(false);
    f.receipt.workflow!.residentDocumentTool = '1.0.0';
    expect(verifiedDocumentExecution(f.receipt, final)).toBe(false);
  });
  it('rejects absent or mismatched v2 design/style bindings, including author HTML', () => {
    const transport = residentDocumentTransport('2.0.0', taskID)!;
    for (const fields of [{ design: undefined }, { design: 'author-v1' }, { houseStyleSHA256: undefined }, { houseStyleSHA256: 'invalid' }]) {
      const f = fixture('2.0.0'); Object.assign(f.audit.inputs, fields);
      expect(verifiedResidentDocumentEvidence(f.refresh(), source, transport, final)).toBe(false);
    }
    const html = fixture('2.0.0');
    Object.assign(html.audit.inputs, { sourceFormat: 'html', design: 'author-v1' });
    expect(verifiedResidentDocumentEvidence(html.refresh(), { ...source, format: 'html' }, transport, final)).toBe(true);
    expect(residentDocumentTransport('3.0.0', taskID)).toBeUndefined();
  });
  it.each([null, undefined, 'invalid', 19, 'd'.repeat(64)])('records Markdown house metadata nonblockingly: %s', houseStyleSHA256 => {
    const f = fixture('2.0.0'); Object.assign(f.audit.inputs, { houseStyleSHA256 });
    const fresh = residentDocumentTransport('2.0.0', taskID, undefined, false, 'record_v1')!;
    expect(verifiedResidentDocumentEvidence(f.refresh(), source, fresh, final)).toBe(true);
    const observation = residentDocumentStyleObservation(f.refresh(), source, fresh, final);
    expect(observation).toMatchObject({ blocking: false, status: houseStyleSHA256 === 'd'.repeat(64) ? 'recorded' : 'advisory', sourceFormat: 'md' });
    if (houseStyleSHA256 === null) expect(observation).toMatchObject({ houseStyleSHA256: { type: 'null', value: null } });
    expect(documentInvocationCommand(invocation, source, true, fresh)).not.toContain("assert isinstance(inputs['houseStyleSHA256'],str)");
    expect(residentDocumentTransport('1.0.0', taskID, undefined, false, 'record_v1')).toEqual(resident);
  });
  it('keeps fresh bounded failure diagnostics inside all adapter command limits', () => {
    for (const template of [undefined, 'guide@1.0.0', 'report@1.0.0', 'letter@1.0.0'] as const) {
      const transport = residentDocumentTransport('2.0.0', taskID, template, !template, 'record_v1', 'bounded_v1')!;
      const command = documentInvocationCommand(invocation, { ...source, format: 'html' }, true, transport, true);
      expect(Buffer.byteLength(command)).toBeLessThanOrEqual(12000);
      expect(command).toContain('KNOT_RESIDENT_FAILURE_V1 ');
      expect(command).toContain("proof_root='deliverables/knot-resident-'+c['taskID']");
    }
  });
  it.each(['exit', 'timeout'] as const)('exposes only allowlisted diagnostic facts on child %s, never replaying', scenario => {
    const transport = residentDocumentTransport('2.0.0', taskID, undefined, false, 'record_v1', 'bounded_v1')!;
    const command = documentInvocationCommand(invocation, source, true, transport);
    const run = command.slice(command.indexOf('def run(args):'), command.indexOf('\npinned()\nassert run'));
    expect(run).toContain('def failure(');
    const program = `import subprocess,json,hashlib,time\nfrom types import SimpleNamespace\nstarted=time.monotonic();root='.';env={};calls=0\ndef digest(b): return hashlib.sha256(b).hexdigest()\ndef fake(*args,**kwargs):\n    global calls\n    calls+=1\n    ${scenario === 'timeout' ? "raise subprocess.TimeoutExpired('synthetic-private-command',1,output=b'private-output',stderr=b'FileExistsError: synthetic-private-path')" : "return SimpleNamespace(returncode=2,stdout=b'private-output',stderr=b'FileExistsError: synthetic-private-path')"}\nsubprocess.run=fake\n` + run + `\ntry:\n    run(['synthetic-private-command','build'])\nexcept AssertionError as error:\n    print(str(error))\nprint('calls='+str(calls))\n`;
    const result = spawnSync('python3', ['-I', '-c', program], { encoding: 'utf8' });
    expect(result.status, result.stderr).toBe(0);
    expect(result.stdout).not.toMatch(/private-output|synthetic-private-path|synthetic-private-command/);
    const lines = result.stdout.trim().split('\n');
    expect(JSON.parse(lines[0].slice('KNOT_RESIDENT_FAILURE_V1 '.length))).toMatchObject({ phase: 'build', exitCode: scenario === 'timeout' ? 'timeout' : 2, errorClasses: ['FileExistsError'], stdoutBytes: 14, noReplay: true, stdoutSHA256: createHash('sha256').update('private-output').digest('hex') });
    expect(lines.at(-1)).toBe('calls=1');
    expect(result.stdout).not.toContain('KNOT_DOCUMENT_V1');
  });
  it('binds fresh diagnostics to the recorded workflow without upgrading historical evidence', () => {
    const f = fixture('2.0.0');
    f.receipt.workflow!.residentFailurePolicy = 'bounded_v1';
    expect(verifiedDocumentExecution(f.receipt, final)).toBe(false);
    const fresh = residentDocumentTransport('2.0.0', taskID, undefined, false, undefined, 'bounded_v1')!;
    f.receipt.workflow!.documentExecution!.resident = fresh;
    f.buildEvidence.reviewedCommand = documentInvocationCommand(invocation, source, true, fresh);
    expect(verifiedDocumentExecution(f.receipt, final)).toBe(true);
    delete f.receipt.workflow!.residentFailurePolicy;
    expect(verifiedDocumentExecution(f.receipt, final)).toBe(false);
  });
  it('accepts only an empty-code PDF build', () => {
    expect(validatedDocumentInvocation(invocation)).toEqual(invocation);
    for (const change of [{ stage: 'source' }, { stage: 'existing' }, { stage: 'final' }, { code: 'print(1)' }, { path: 'fixture.docx' }, { path: 'fixture.md' }, { path: '../fixture.pdf' }]) {
      expect(() => validatedDocumentInvocation({ ...invocation, ...change })).toThrow('invalid_document_invocation');
    }
  });
  it('requires measured source and a fresh explicit transport version', () => {
    expect(() => documentInvocationCommand(invocation)).toThrow('document_source_required');
    expect(() => documentInvocationCommand(invocation, source)).toThrow('invalid_document_invocation');
    expect(() => documentInvocationCommand(invocation, source, true, { ...resident, version: 'unaccepted' } as never)).toThrow('invalid_document_invocation');
    expect(() => documentInvocationCommand(invocation, source, true, { ...resident, taskID: '-'.repeat(36) })).toThrow('invalid_document_invocation');
    expect(() => documentInvocationCommand({ ...invocation, interpreter: 'python3', code: '# fixture' }, source, true, resident)).toThrow('invalid_document_invocation');
  });
  it('constructs a fixed pinned command and does not expose staged proofs as independent proof', () => {
    const command = documentInvocationCommand(invocation, source, true, resident);
    expect(command).toContain('/opt/knot-tools/knot-doc/v1/knot-doc');
    expect(command).toContain(knotDocSHA256);
    expect(command).toContain("m['proofStageOnly'] is True and m['independentVerification'] is False");
    expect(command).toContain("dict(path=c['path'],sha256=digest(final),size=len(final),format='pdf',pages=m['pages'],proofs=[]");
    expect(command).toContain("entries[1]['manifest']==m");
    expect(command).toContain("inputs['resourcePolicy']=='deny-all-v1'");
    expect(new TextEncoder().encode(command).length).toBeLessThanOrEqual(12000);
  });
});

describe('resident audit bound to exact owned execution', () => {
  it('recognizes the complete synthetic source/build chain, not independent delivery', () => {
    const f = fixture();
    expect(documentSource({ ...f.sourceEvidence, evidence: [] } as unknown as ShellEvidence)).toEqual(source);
    expect(verifiedResidentDocumentEvidence(f.refresh(), source, resident, final)).toBe(true);
    expect(verifiedDocumentExecution(f.receipt, final)).toBe(true);
    expect(verifiedDocumentProof(f.receipt, final)).toBeUndefined();
  });
  it.each(['toolVersion', 'taskID', 'sourceSHA256', 'sha256', 'path', 'size', 'pages', 'inputsSHA256'] as const)('rejects a different resident manifest %s', key => {
    const f = fixture();
    Object.assign(f.audit.manifest, { [key]: typeof f.audit.manifest[key] === 'number' ? -1 : 'wrong' });
    f.refresh();
    expect(verifiedDocumentExecution(f.receipt, final)).toBe(false);
  });
  it('rejects missing, duplicate or falsely independent resident evidence', () => {
    const f = fixture();
    expect(verifiedResidentDocumentEvidence('KNOT_DOCUMENT_V1 ' + JSON.stringify(final), source, resident, final)).toBe(false);
    expect(verifiedResidentDocumentEvidence(f.refresh() + '\n' + f.refresh(), source, resident, final)).toBe(false);
    f.audit.manifest.independentVerification = true;
    expect(verifiedResidentDocumentEvidence(f.refresh(), source, resident, final)).toBe(false);
    f.audit.manifest.independentVerification = false; f.audit.toolSHA256 = 'd'.repeat(64);
    expect(verifiedResidentDocumentEvidence(f.refresh(), source, resident, final)).toBe(false);
  });
  it.each(['source', 'build'] as const)('rejects incomplete, failed or uncertain %s receipts', which => {
    for (const change of [{ status: 'failed' }, { status: 'uncertain' }, { exitCode: 1 }, { outputComplete: false }, { terminationConfirmed: false }, { truncated: true }, { contextTruncated: true }, { sessionID: undefined }]) {
      const f = fixture(); Object.assign(which === 'source' ? f.sourceEvidence : f.buildEvidence, change);
      expect(verifiedDocumentExecution(f.receipt, final)).toBe(false);
    }
  });
  it('rejects command edits, missing owned source, unadvertised version and foreign task identity', () => {
    const changedCommand = fixture(); changedCommand.buildEvidence.reviewedCommand += '\n# different command';
    expect(verifiedDocumentExecution(changedCommand.receipt, final)).toBe(false);
    const changedSource = fixture(); changedSource.sourceEvidence.reviewedCommand += '\n# different command';
    expect(verifiedDocumentExecution(changedSource.receipt, final)).toBe(false);
    const missingSource = fixture(); missingSource.receipt.evidence = [missingSource.buildEvidence];
    expect(verifiedDocumentExecution(missingSource.receipt, final)).toBe(false);
    const oldWorkflow = fixture(); delete oldWorkflow.receipt.workflow!.residentDocumentTool;
    expect(verifiedDocumentExecution(oldWorkflow.receipt, final)).toBe(false);
    const foreignWorkflow = fixture(); foreignWorkflow.receipt.workflow!.rootID = sourceID;
    expect(verifiedDocumentExecution(foreignWorkflow.receipt, final)).toBe(false);
    const substitutedFormat = fixture(); substitutedFormat.receipt.workflow!.documentFormat = requestedDocumentFormat('Create an MD file');
    expect(verifiedDocumentExecution(substitutedFormat.receipt, final)).toBe(false);
  });
});

describe('original-format and selection controls', () => {
  it.each(['txt', 'md'] as const)('keeps %s final identity and rejects a substituted PDF', format => {
    const binding = requestedDocumentFormat('Create a ' + format + ' file');
    expect(binding).toMatchObject({ status: 'bound', format });
    expect(documentFormatIssue(binding, 'fresh.' + format, format)).toBeUndefined();
    expect(documentFormatIssue(binding, 'fresh.pdf', 'pdf')).toBe('document_output_format_mismatch');
    expect(needsDocumentProof({ ...final, path: 'fresh.' + format, format }, true, binding)).toBe(false);
    const raw = documentInvocationCommand({ stage: 'final', interpreter: 'python3', code: '# never executed', path: 'fresh.' + format });
    expect(raw).toContain('KNOT_RAW_DOCUMENT_INVOKE'); expect(raw).not.toContain('/opt/knot-tools/knot-doc');
  });
  it('retains independent proof for PDF and does not classify the fresh equivalent game as a document', () => {
    expect(needsDocumentProof(final, true, requestedDocumentFormat('Create a PDF document'))).toBe(true);
    expect(documentRequest('Build a fresh Pokémon-style RPG with a world map, battles and save progress')).toBe(false);
    expect(documentInvocationCommand({ stage: 'build', interpreter: 'python3', code: '# fixture', path: 'legacy.pdf' }, source)).toContain('KNOT_DOCUMENT_INVOKE');
  });
  it('rejects empty required selections while preserving optional final answers', () => {
    const empty = { choices: [{ finish_reason: 'stop', message: { content: 'Done.' } }] };
    const directive = knotSelectionDirective([], undefined, true);
    expect(directive.tool_choice).toBe('required');
    expect(() => validatedKnotSelection(empty, [], 1, new Set(), true)).toThrow('requested_work_step_required');
    expect(validatedKnotSelection(empty, [], 1, new Set())).toEqual([]);
  });
});
