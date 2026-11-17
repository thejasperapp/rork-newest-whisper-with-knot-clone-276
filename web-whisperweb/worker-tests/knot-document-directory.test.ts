// @vitest-environment node
// Real generated adapters in isolated local directories. No hosted execution,
// renderer, model, credentials or capture runs; not device acceptance.
import { describe, expect, it } from 'vitest';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, symlinkSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { documentInvocationCommand, documentSource, type DocumentInvocation } from '../../functions/knot-document-build';
import { structuredSourceCode } from '../../functions/knot-document-structured';
import type { ShellEvidence } from '../../functions/knot-shell';
const digest = (s: string) => createHash('sha256').update(s).digest('hex');
function isolated(work: (root: string) => void) {
  const root = mkdtempSync(join(tmpdir(), 'knot-output-parent-'));
  try { work(root); } finally { rmSync(root, { recursive: true, force: true }); }
}
function execute(root: string, invocation: DocumentInvocation, fresh = true) {
  const source = { path: 'source.md', sha256: digest('Measured source'), size: 15, format: 'md' as const };
  if (invocation.stage === 'build') writeFileSync(join(root, source.path), 'Measured source');
  const command = documentInvocationCommand(invocation, invocation.stage === 'build' ? source : undefined, false, undefined, false, fresh);
  return { command, ...spawnSync('/bin/bash', ['--noprofile', '--norc', '-c', command], { cwd: root, encoding: 'utf8' }) };
}
describe('fresh receipt-bound output_parent_v1 directory preparation', () => {
  it.each(['source', 'final', 'build'] as const)('creates only the permitted declared parent before %s code', stage => isolated(root => {
    const path = 'deliverables/herbs/' + (stage === 'source' ? 'source.html' : stage === 'build' ? 'herbs.docx' : 'herbs.csv');
    const text = stage === 'source' ? '<h1>Balcony Herb Plan</h1>' : stage === 'build' ? 'fixture-only-not-office-proof' : 'Plant,Containers\nBasil,2\n';
    const invocation: DocumentInvocation = { stage, interpreter: 'python3', path, code: `from pathlib import Path\nwith Path(${JSON.stringify(path)}).open('xb') as f: f.write(${JSON.stringify(text)}.encode())` };
    const result = execute(root, invocation);
    expect(result.status, result.stderr).toBe(0);
    expect(readFileSync(join(root, path), 'utf8')).toBe(text);
    expect(result.stdout).toContain(stage === 'source' ? 'KNOT_DOCUMENT_SOURCE_V1 ' : 'KNOT_DOCUMENT_V1 ');
    expect(existsSync(join(root, 'archives'))).toBe(false);
  }));
  it('executes the exact deterministic structured writer in a fresh deliverables directory', () => isolated(root => {
    const path = 'deliverables/reading.html';
    const invocation: DocumentInvocation = { stage: 'source', interpreter: 'python3', path, code: structuredSourceCode({ version: 'content_v1', patched: false, layout: {}, document: { title: 'Reading Plan', subtitle: 'A rainy weekend', sections: [{ id: 'prep', title: 'Prepare', blocks: [{ kind: 'paragraph', text: 'Choose a comfortable chair.' }] }] } }, path) };
    const result = execute(root, invocation);
    expect(result.status, result.stderr).toBe(0);
    expect(readFileSync(join(root, path), 'utf8')).toContain('Choose a comfortable chair.');
    const receipt = { workflow: { documentDirectoryPolicy: 'output_parent_v1' }, status: 'completed', exitCode: 0, sessionID: 'local-fixture', outputComplete: true, terminationConfirmed: true, documentInvocation: invocation, reviewedCommand: result.command, stdout: result.stdout } as ShellEvidence;
    expect(documentSource(receipt)?.path).toBe(path);
    expect(() => documentSource({ ...receipt, workflow: undefined })).toThrow('document_source_incomplete');
  }));
  it.each(['source', 'final'] as const)('refuses existing output bytes before %s author code', stage => isolated(root => {
    mkdirSync(join(root, 'deliverables'));
    const path = 'deliverables/herbs.' + (stage === 'source' ? 'html' : 'txt');
    writeFileSync(join(root, path), 'Original immutable bytes');
    const result = execute(root, { stage, interpreter: 'python3', path, code: "from pathlib import Path; Path('ran.txt').write_text('bad')" });
    expect(result.status).not.toBe(0); expect(existsSync(join(root, 'ran.txt'))).toBe(false);
    expect(readFileSync(join(root, path), 'utf8')).toBe('Original immutable bytes');
  }));
  it('rejects a symlink parent without writing through it', () => isolated(root => {
    mkdirSync(join(root, 'outside')); symlinkSync(join(root, 'outside'), join(root, 'deliverables'));
    const result = execute(root, { stage: 'source', interpreter: 'python3', path: 'deliverables/source.html', code: "from pathlib import Path; Path('ran.txt').write_text('bad')" });
    expect(result.status).not.toBe(0); expect(existsSync(join(root, 'ran.txt'))).toBe(false);
    expect(existsSync(join(root, 'outside/source.html'))).toBe(false);
  }));
  it('fails preparation once, with bounded private diagnostics and without author execution', () => isolated(root => {
    writeFileSync(join(root, 'deliverables'), 'Not a directory');
    const result = execute(root, { stage: 'final', interpreter: 'python3', path: 'deliverables/herbs.txt', code: "from pathlib import Path; Path('ran.txt').write_text('bad')" });
    expect(result.status).toBe(73); expect(existsSync(join(root, 'ran.txt'))).toBe(false);
    expect(result.stdout.trim()).toBe('KNOT_DOCUMENT_PREPARATION_FAILURE_V1 {"phase":"output_parent","noReplay":true}');
    expect(result.stderr).toBe(''); expect(readFileSync(join(root, 'deliverables'), 'utf8')).toBe('Not a directory');
  }));
  it('never creates missing directories for an inspection-only source', () => isolated(root => {
    const result = execute(root, { stage: 'source', interpreter: 'python3', path: 'deliverables/source.md', code: '' });
    expect(result.status).not.toBe(0); expect(existsSync(join(root, 'deliverables'))).toBe(false);
  }));
  it('does not change historical commands or retroactively prepare historical parents', () => isolated(root => {
    const invocation: DocumentInvocation = { stage: 'source', interpreter: 'python3', path: 'deliverables/source.html', code: "from pathlib import Path; Path('deliverables/source.html').write_text('<h1>Fixture</h1>')" };
    const historical = execute(root, invocation, false);
    expect(historical.status).not.toBe(0); expect(historical.stderr).toContain('FileNotFoundError');
    expect(historical.command).not.toContain('output_parent_v1');
    expect(documentInvocationCommand(invocation)).toBe(documentInvocationCommand(invocation, undefined, false, undefined, false, false));
  }));
});
