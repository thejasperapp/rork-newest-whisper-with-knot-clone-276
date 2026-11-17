// @vitest-environment node
import { describe, expect, it, vi } from 'vitest';
vi.mock('cloudflare:workers', () => ({ DurableObject: class {} }));
import { authorKnotDocumentProgram } from '../../functions/knot-document-authoring';
import { appendDocumentProgram, beginDocumentProgram, documentProgramReceipt, documentProgramSHA256, documentProgramSliceCharacters, documentProgramSliceBytes, type DocumentProgram } from '../../functions/knot-document-program';
import type { ShellWorkflow } from '../../functions/knot-shell';

const uuid = (n: number) => '00000000-0000-4000-8000-' + String(n).padStart(12, '0');
const workflow: ShellWorkflow = { rootID: uuid(1), parentID: uuid(2), sourceMessageID: uuid(3), originalRequest: 'Create a substantive Markdown guide', mode: 'Create', documentTask: true, memoryRead: true, indexRead: true, workspaceInspected: true, skills: [], commands: 0, memoryWritten: false };
async function harness(responses: unknown[], action?: 'tamper' | 'stop', wholeResponseCapacity = true) {
  let program: DocumentProgram | undefined, mutations = 0, cancelled = false;
  const aborter = new AbortController(), calls: { prefix: string; index: number }[] = [], observations: Record<string, unknown>[] = [];
  const env = { SUPABASE_SERVICE_ROLE_KEY: 'synthetic-signing', SIDECAR_TOKEN_WHISPER: 'synthetic-sidecar', DO: { fetch: vi.fn(async (request: Request) => {
    const path = new URL(request.url).pathname, body = await request.json() as any;
    if (path === '/workspace/resolve') return Response.json({ workspace: 'whisper-' + 'a'.repeat(48) });
    if (path === '/document-program/begin') { program = await beginDocumentProgram(body.owner, body.preparation, body.expiresAt, Date.now()); return Response.json(documentProgramReceipt(program)); }
    if (path === '/document-program/append') {
      mutations++; program = await appendDocumentProgram(program!, body.owner, body.slice, Date.now());
      const receipt = documentProgramReceipt(program);
      if (action === 'tamper') receipt.prefixSHA256 = 'f'.repeat(64);
      if (action === 'stop') aborter.abort();
      return Response.json(receipt);
    }
    if (path === '/document-program/cancel') { cancelled = true; return Response.json({ ok: true }); }
    throw Error('unexpected_actor_route');
  }) } };
  const result = authorKnotDocumentProgram({ env, userID: uuid(9), bot: 'main', conversationID: uuid(4), workflow,
    preparation: { authoring: 'author', stage: 'final', interpreter: 'python3', path: 'guide.md', title: '', deliveryLabel: '' },
    expiresAt: Date.now() + 280000, signal: aborter.signal, wholeResponseCapacity,
    next: async (_preparation, prefix, index) => { calls.push({ prefix, index }); return responses[calls.length - 1]; },
    observed: (_kind, facts) => observations.push(facts),
  });
  return { outcome: await result.then(value => ({ value, error: undefined }), error => ({ value: undefined, error })), program, mutations, cancelled, calls, observations };
}
describe('harness-owned exact response splitting', () => {
  it.each([false, true])('accepts a complete 9025-character response above the model target (%s)', async wholeResponseCapacity => {
    const code = '#'.repeat(9025);
    const run = await harness([{ code, final: true }], undefined, wholeResponseCapacity);
    expect(run.outcome.error).toBeUndefined();
    expect(run.outcome.value?.invocation.code).toBe(code);
    expect(run.calls).toHaveLength(1); expect(run.cancelled).toBe(false);
    expect(run.program?.state).toBe('sealed');
    expect(run.program?.slices.map(slice => slice.code).join('')).toBe(code);
  });
  it('retries one locally malformed first response before any append', async () => {
    const run = await harness([{ code: 42, final: true }, { code: '# exact complete program', final: true }]);
    expect(run.outcome.error).toBeUndefined();
    expect(run.calls).toEqual([{ prefix: '', index: 0 }, { prefix: '', index: 0 }]);
    expect(run.mutations).toBe(1);
    expect(run.outcome.value?.invocation.code).toBe('# exact complete program');
  });
  it('does not retry a locally malformed continuation after banking a prefix', async () => {
    const run = await harness([{ code: '# exact banked prefix', final: false }, { code: 42, final: true }]);
    expect(run.outcome.error?.detail.check).toBe('slice_shape');
    expect(run.calls).toHaveLength(2); expect(run.mutations).toBe(1); expect(run.cancelled).toBe(true);
    expect(run.program?.slices.map(slice => slice.code).join('')).toBe('# exact banked prefix');
  });
  it.each([
    '#'.repeat(9004),
    '🙂'.repeat(6001),
    '\u0001'.repeat(9004),
    'a'.repeat(5999) + '🙂' + '\\"\n'.repeat(2000),
    '#'.repeat(63999),
  ])('stores a complete long response in bounded exact Unicode/JSON pieces', async code => {
    const run = await harness([{ code, final: true }]);
    expect(run.outcome.error).toBeUndefined();
    expect(run.outcome.value?.invocation.code).toBe(code);
    expect(run.calls).toEqual([{ prefix: '', index: 0 }]);
    expect(run.cancelled).toBe(false);
    expect(run.program?.state).toBe('sealed');
    expect(run.program!.slices.map(slice => slice.code).join('')).toBe(code);
    let prefix = '';
    for (const [index, slice] of run.program!.slices.entries()) {
      expect(Array.from(slice.code).length).toBeLessThanOrEqual(documentProgramSliceCharacters);
      expect(Buffer.byteLength(JSON.stringify(slice.code))).toBeLessThanOrEqual(documentProgramSliceBytes);
      expect(slice.index).toBe(index);
      expect(slice.final).toBe(index === run.program!.slices.length - 1);
      expect(slice.sha256).toBe(await documentProgramSHA256(slice.code));
      prefix += slice.code;
      expect(slice.prefixSHA256).toBe(await documentProgramSHA256(prefix));
    }
  });
  it('continues from the full acknowledged response prefix, not the last storage piece', async () => {
    const first = '#'.repeat(25004), second = '\n# exact suffix\n';
    const run = await harness([{ code: first, final: false }, { code: second, final: true }]);
    expect(run.outcome.error).toBeUndefined();
    expect(run.outcome.value?.invocation.code).toBe(first + second);
    expect(run.calls).toEqual([{ prefix: '', index: 0 }, { prefix: first, index: 2 }]);
    expect(run.program?.slices.map(s => s.final)).toEqual([false, false, true]);
  });
  it.each(['#'.repeat(64001), '\u0001'.repeat(13000)])('rejects whole-program capacity before appending any piece', async code => {
    const run = await harness([{ code, final: true }]);
    expect(run.outcome.error?.reason).toBe('document_program_capacity_exceeded');
    expect(run.outcome.error?.detail.check).toBe('program_size');
    expect(run.mutations).toBe(0);
    expect(run.cancelled).toBe(true);
    expect(run.calls).toHaveLength(1);
  });
  it('preflights the entire response against remaining storage slots before any of its pieces append', async () => {
    const run = await harness([...Array.from({ length: 31 }, () => ({ code: '#', final: false })), { code: '#'.repeat(25004), final: true }]);
    expect(run.outcome.error?.reason).toBe('document_program_capacity_exceeded');
    expect(run.outcome.error?.detail.check).toBe('slice_limit');
    expect(run.mutations).toBe(31);
    expect(run.program?.slices).toHaveLength(31);
    expect(run.program?.slices.every(slice => slice.code === '#' && !slice.final)).toBe(true);
    expect(run.calls).toHaveLength(32);
    expect(run.calls[31]).toEqual({ prefix: '#'.repeat(31), index: 31 });
    expect(run.cancelled).toBe(true);
  });
  it.each(['tamper', 'stop'] as const)('never retries or appends another piece after %s', async action => {
    const run = await harness([{ code: '#'.repeat(9004), final: true }], action);
    expect(run.outcome.value).toBeUndefined();
    expect(run.outcome.error).toBeDefined();
    expect(run.mutations).toBe(1);
    expect(run.calls).toHaveLength(1);
    expect(run.cancelled).toBe(true);
  });
});
