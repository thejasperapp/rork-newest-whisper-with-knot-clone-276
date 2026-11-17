// @vitest-environment node
// Capture against synthetic receipts and bytes. No executor, renderer, live AI,
// historical files, native app or authenticated external service runs.
import { afterEach, describe, expect, it, vi } from 'vitest';
import { captureKnotDocument, type KnotDocument } from '../../functions/knot-documents';
import type { ShellEvidence } from '../../functions/knot-shell';
async function fixture(format = 'xyz', bound = format) {
  const bytes = new TextEncoder().encode('Synthetic opaque format bytes');
  const sha256 = [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map(n => n.toString(16).padStart(2, '0')).join('');
  const manifest = { path: 'fresh.' + format, format, sha256, size: bytes.length, pages: 1, proofs: [] };
  const receipt = { proposalID: 'owned-command', bot: 'main', conversationID: 'fresh-conversation', status: 'completed', sessionID: 'owned-session', exitCode: 0, outputComplete: true, terminationConfirmed: true, truncated: false, stdout: 'KNOT_DOCUMENT_V1 ' + JSON.stringify(manifest), stderr: '', reason: '', reviewedCommand: 'synthetic-only', workflow: { rootID: 'fresh-task', originalRequest: 'Create a file in ' + bound + ' format', mode: 'Create', artifactFormat: bound, documentTask: false, documentPolicy: 'author_v1', memoryRead: true, indexRead: true, skills: [], commands: 1, memoryWritten: false }, evidence: [] } as ShellEvidence;
  const documents = new Map<string, KnotDocument>(), stored: Uint8Array[] = [], lookups: string[] = [];
  const sql = { exec: (query: string, ...args: unknown[]) => {
    lookups.push(query); let rows: unknown[] = [];
    if (query.startsWith('SELECT data FROM knot_documents WHERE id = ?')) rows = documents.has(String(args[0])) ? [{ data: JSON.stringify(documents.get(String(args[0]))) }] : [];
    else if (query === 'SELECT COUNT(*) AS count FROM knot_documents') rows = [{ count: documents.size }];
    else if (query.startsWith('SELECT COALESCE(SUM(')) rows = [{ bytes: 0 }];
    else if (query.startsWith('INSERT INTO knot_documents VALUES')) documents.set(String(args[0]), JSON.parse(String(args[5])));
    else if (query.startsWith('INSERT INTO knot_document_bytes VALUES')) stored.push(new Uint8Array(args[3] as ArrayBuffer));
    else if (query.startsWith('SELECT id') || query.startsWith('SELECT 1 FROM') || query.startsWith('DELETE FROM knot_document_bytes') || query.startsWith('INSERT INTO knot_document_sources')) { /* synthetic empty expiry/deletion/storage boundary */ }
    else throw new Error('Unexpected synthetic SQL: ' + query);
    return { toArray: () => rows, one: () => rows[0] };
  } };
  const fetcher = vi.fn(async (url: string) => { expect(new URL(String(url)).pathname).toBe('/files'); return new Response(bytes); });
  vi.stubGlobal('fetch', fetcher);
  const run = () => captureKnotDocument({ storage: { sql, transactionSync: (f: () => unknown) => f() } } as never, { SIDECAR_TOKEN_WHISPER: 'synthetic-only' }, 'owned-workspace', receipt, new AbortController().signal);
  return { run, documents, stored, lookups, fetcher, bytes, manifest };
}
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });
describe('general artifact immutable capture boundaries', () => {
  it('delivers a novel format as opaque exact bytes, not rendered/playable certification', async () => {
    const f = await fixture(), result = await f.run();
    expect(result.document).toMatchObject({ format: 'xyz', contentType: 'application/octet-stream', sha256: f.manifest.sha256, size: f.bytes.length, review: 'not_requested' });
    expect(result.document?.verification).toBeUndefined(); expect(f.documents.size).toBe(1); expect(f.stored[0]).toEqual(f.bytes);
    expect(f.fetcher).toHaveBeenCalledTimes(1);
  });
  it('rejects an extension substitution before file reads or any existing delivery lookup', async () => {
    const f = await fixture('html', 'xyz');
    await expect(f.run()).rejects.toThrow('document_output_format_mismatch');
    expect(f.fetcher).not.toHaveBeenCalled(); expect(f.lookups).toEqual([]); expect(f.stored).toEqual([]);
  });
  it.each(['pdf', 'docx', 'xlsx', 'pptx'])('still requires independent proof for %s even on a general route', async format => {
    const f = await fixture(format);
    await expect(f.run()).rejects.toThrow('document_proof_required');
    expect(f.fetcher).not.toHaveBeenCalled(); expect(f.documents.size).toBe(0); expect(f.stored).toEqual([]);
  });
});
