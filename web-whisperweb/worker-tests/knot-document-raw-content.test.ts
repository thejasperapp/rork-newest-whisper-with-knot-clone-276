// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { mkdtempSync, readFileSync, existsSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { documentResponseSlice, replayDocumentResponse } from '../../functions/knot-document-replay';
import { isRawContentInvocation } from '../../functions/knot-document-raw-content';
import { documentInvocationCommand } from '../../functions/knot-document-build';
const envelope = (value: unknown, finish = 'stop') => ({ choices: [{ finish_reason: finish, message: { content: JSON.stringify(value) } }] });
const context = (extension = 'md') => ({ version: 'document_author_replay_v1' as const, preparation: { stage: 'final' as const, interpreter: 'python3' as const, path: 'deliverables/garden.' + extension, authoring: 'author' as const }, prefix: '', index: 0, structured: false, rawContent: true, localPatch: false, targets: [] });
const payload = (content: string) => ({ version: 'raw_content_v1', content });
const markdown = '# Balcony herbs\n\n- [ ] Give mint its own pot: it\'s invasive.\n- [ ] Keep **basil** warm.\n\n```python\nprint("not executed")\n```\nLiteral \\n stays literal; “thyme” 🌱\n';
describe('raw content as data, never model-authored executable source', () => {
  it.each(['md', 'txt', 'html', 'csv', 'json'])('writes complete exact UTF-8 %s bytes through the real adapter', extension => {
    const content = extension === 'json' ? '{"note":"it\'s mint","literal":"\\\\n","unicode":"🌱"}\n' : extension === 'csv' ? 'Plant,Note\r\nMint,"it\'s invasive, contain it"\r\n' : extension === 'html' ? '<!doctype html><html><body><p>It\'s mint 🌱</p></body></html>\n' : markdown;
    const invocation = replayDocumentResponse(envelope(payload(content)), context(extension));
    expect(isRawContentInvocation(invocation)).toBe(true);
    expect(isRawContentInvocation({ ...invocation, code: invocation.code + '\nprint("injected")' })).toBe(false);
    const root = mkdtempSync(join(tmpdir(), 'knot-raw-content-'));
    try {
      const command = documentInvocationCommand(invocation, undefined, false, undefined, false, true);
      const result = spawnSync('/bin/bash', ['--noprofile', '--norc', '-c', command], { cwd: root, encoding: 'utf8' });
      expect(result.status, result.stderr).toBe(0);
      expect(readFileSync(join(root, invocation.path))).toEqual(Buffer.from(content, 'utf8'));
      expect(existsSync(join(root, 'not executed'))).toBe(false);
      expect(result.stdout).toContain('KNOT_DOCUMENT_V1 ');
      expect(documentResponseSlice(envelope(payload(content)), context(extension)).final).toBe(true);
      // Same data replays to exactly the same immutable invocation bytes.
      expect(replayDocumentResponse(envelope(payload(content)), context(extension))).toEqual(invocation);
      writeFileSync(join(root, invocation.path), 'Protected original');
      const collision = spawnSync('/bin/bash', ['--noprofile', '--norc', '-c', command], { cwd: root, encoding: 'utf8' });
      expect(collision.status).not.toBe(0);
      expect(readFileSync(join(root, invocation.path), 'utf8')).toBe('Protected original');
    } finally { rmSync(root, { recursive: true, force: true }); }
  });
  it.each([
    { code: markdown, final: true }, // observed Markdown-as-Python contract
    { code: 'from pathlib import Path\\nPath("garden.md").write_text("mint")', final: true },
    { version: 'raw_content_v1', content: markdown, code: 'print(1)' },
    payload(''), payload('\u0000'), payload('\ud800'), payload({ text: 'wrong' } as unknown as string),
  ])('rejects malformed content before dispatch: %#', value => {
    expect(() => documentResponseSlice(envelope(value), context())).toThrow();
  });
  it.each(['md', 'html'])('writes intermediate %s source data without author loops or executable escaping', extension => {
    const base = context(extension);
    const { rawContent: _raw, ...common } = base;
    const sourceContext = { ...common, sourceContent: true, preparation: { ...base.preparation, stage: 'source' as const } };
    const content = extension === 'html' ? '<!doctype html><html><body><h1>Garden</h1><p>It\'s mint.</p></body></html>' : markdown;
    const invocation = replayDocumentResponse(envelope(payload(content)), sourceContext);
    expect(isRawContentInvocation(invocation, true)).toBe(true);
    expect(isRawContentInvocation(invocation)).toBe(false);
    const root = mkdtempSync(join(tmpdir(), 'knot-source-content-'));
    try {
      const command = documentInvocationCommand(invocation, undefined, false, undefined, false, true);
      const result = spawnSync('/bin/bash', ['--noprofile', '--norc', '-c', command], { cwd: root, encoding: 'utf8' });
      expect(result.status, result.stderr).toBe(0);
      expect(readFileSync(join(root, invocation.path))).toEqual(Buffer.from(content));
      expect(result.stdout).toContain('KNOT_DOCUMENT_SOURCE_V1 ');
      expect(() => documentResponseSlice(envelope({ code: 'for slide in slides:\\nnot_indented()', final: true }), sourceContext)).toThrow();
      expect(() => documentResponseSlice(envelope(payload(content)), { ...sourceContext, rawContent: true })).toThrow();
    } finally { rmSync(root, { recursive: true, force: true }); }
  });
  it('preserves an explicit UTF-8 BOM and rejects source injection as executable authority', () => {
    const invocation = replayDocumentResponse(envelope(payload('\ufeff' + markdown)), context());
    expect(isRawContentInvocation(invocation)).toBe(true);
  });
  it('does not salvage a truncated provider response', () => {
    expect(() => documentResponseSlice(envelope(payload(markdown), 'length'), context())).toThrow();
  });
  it.each([
    { ...context(), prefix: 'accepted prefix' }, { ...context(), index: 1 },
    { ...context(), structured: true }, { ...context(), preparation: { ...context().preparation, stage: 'source' as const } },
    { ...context(), preparation: { ...context().preparation, interpreter: 'bash' as const } },
  ])('rejects mixed or noninitial raw authoring contexts: %#', value => {
    expect(() => documentResponseSlice(envelope(payload(markdown)), value)).toThrow();
  });
  it('retains historical executable code responses without opting into the new policy', () => {
    const { rawContent: _raw, ...historical } = context();
    const code = 'print("historical exact bytes")\n';
    expect(documentResponseSlice(envelope({ code, final: true }), historical)).toEqual({ code, final: true });
  });
});
