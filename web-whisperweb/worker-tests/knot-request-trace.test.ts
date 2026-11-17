// @vitest-environment node
import { afterEach, describe, expect, it, vi } from 'vitest';
import { knotSourceBuildSHA256, tracedKnotRequest } from '../../functions/knot-request-trace';
afterEach(() => vi.restoreAllMocks());
describe('request source-build diagnostics', () => {
  it('replaces caller tracing, stamps actual source build and keeps queries/auth/body out of logs', async () => {
    const info = vi.spyOn(console, 'info').mockImplementation(() => {});
    const response = await tracedKnotRequest(new Request('https://example.invalid/knot/shell/documents/capture-advisory?secret=private-query', { method: 'POST', headers: { Authorization: 'private-auth', 'X-Knot-Request-ID': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'X-Knot-Worker-Build': 'forged' }, body: 'private-body' }), false, async (request, trace) => {
      expect(request.headers.get('X-Knot-Request-ID')).toBe(trace.requestID);
      expect(trace.requestID).not.toBe('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
      expect(request.headers.get('X-Knot-Worker-Build')).toBe(knotSourceBuildSHA256);
      expect(await request.text()).toBe('private-body');
      return new Response('result', { status: 202 });
    });
    expect(response.status).toBe(202); expect(await response.text()).toBe('result');
    expect(response.headers.get('X-Knot-Worker-Build')).toBe(knotSourceBuildSHA256);
    const log = JSON.stringify(info.mock.calls);
    expect(log).toContain(knotSourceBuildSHA256);
    for (const secret of ['private-query', 'private-auth', 'private-body', 'forged']) expect(log).not.toContain(secret);
  });
  it('does not consume or buffer an open streaming response', async () => {
    vi.spyOn(console, 'info').mockImplementation(() => {});
    let control!: ReadableStreamDefaultController<Uint8Array>;
    const body = new ReadableStream<Uint8Array>({ start(c) { control = c; } });
    const response = await tracedKnotRequest(new Request('https://example.invalid/knot/chat/stream'), false, async () => new Response(body, { headers: { 'Content-Type': 'text/event-stream' } }));
    expect(response.body).toBe(body); expect(body.locked).toBe(false);
    control.enqueue(new TextEncoder().encode('event: done\n\n')); control.close();
    expect(await response.text()).toBe('event: done\n\n');
  });
  it('returns an upgrade untouched', async () => {
    vi.spyOn(console, 'info').mockImplementation(() => {});
    const upgrade = { status: 101, headers: new Headers() } as Response;
    expect(await tracedKnotRequest(new Request('https://example.invalid/socket'), false, async () => upgrade)).toBe(upgrade);
  });
  it('logs exceptions with build and request, not private exception text', async () => {
    const log = vi.spyOn(console, 'error').mockImplementation(() => {});
    await expect(tracedKnotRequest(new Request('https://example.invalid/private-person-id?token=hidden'), false, async () => { throw new Error('private-error'); })).rejects.toThrow('private-error');
    expect(JSON.stringify(log.mock.calls)).toContain(knotSourceBuildSHA256);
    expect(JSON.stringify(log.mock.calls)).not.toMatch(/private-person-id|hidden|private-error/);
  });
});
