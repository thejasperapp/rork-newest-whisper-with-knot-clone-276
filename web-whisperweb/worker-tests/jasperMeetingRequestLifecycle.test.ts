// @vitest-environment node
import { afterEach, describe, expect, it, vi } from 'vitest';
vi.mock('cloudflare:workers', () => ({ DurableObject: class { constructor(protected ctx: unknown, protected env: unknown) {} } }));
import { JasperMeetingAccount } from '../../functions/jasper-meetings';
const owner = '10000000-0000-4000-8000-000000000001', meeting = '10000000-0000-4000-8000-000000000002', requestId = '10000000-0000-4000-8000-000000000003';
function fixture() {
  const data = new Map<string, unknown>();
  const sql = { exec: (query: string, ...params: unknown[]) => ({ toArray: () => {
    if (query.startsWith('DELETE') && query.includes("key LIKE 'draft:%' OR key LIKE 'kept:%'")) for (const key of data.keys()) if (key.startsWith('draft:') || key.startsWith('kept:')) data.delete(key);
    if (query.includes('COUNT(*)')) return [{ count: 0 }];
    if (query.startsWith('SELECT updated')) return [];
    if (query.includes('key LIKE ? ORDER BY')) return [...data.entries()].filter(([k]) => k.startsWith(String(params[0]).replace('%', ''))).map(([, value]) => ({ value: JSON.stringify(value) }));
    return [];
  } }) };
  const account = new JasperMeetingAccount({ id: { name: owner }, storage: { sql } } as never, { OPENAI_API_KEY: 'fixture-only', DO: { setAlarm: vi.fn() } } as never);
  account.read = <T>(key: string): T | undefined => data.get(key) as T | undefined;
  account.write = (key, value) => { data.set(key, structuredClone(value)); };
  account.remove = (key) => { data.delete(key); };
  account.list = <T>(prefix: string) => [...data.entries()].filter(([k]) => k.startsWith(prefix)).map(([key, value]) => ({ key, value: value as T }));
  const fetcher = vi.fn(async (url: string | URL | Request) => {
    const path = String(url);
    if (path.includes('openai.com')) return Response.json({ choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({ insufficient: false, related: true, sections: [{ title: 'Related findings', items: [{ text: 'Pilot scope was discussed, but no launch date is established.', sourceIds: ['S1'] }] }], actions: [] }) } }] });
    if (path.includes('whisper_meeting_participants')) return Response.json([]);
    if (path.includes('whisper_meeting_transcripts')) return Response.json([{ id: meeting, meeting_id: meeting, username: 'Alex', text: 'The pilot has ten teams.', spoken_at: '2026-09-01' }]);
    if (path.includes('select=id%2Csummary')) return Response.json([]);
    return Response.json([{ id: meeting, title: 'Pilot review', host_id: owner, created_at: '2026-09-01', ended_at: null, status: 'ended' }]);
  });
  vi.stubGlobal('fetch', fetcher);
  const request = (path: string, body: unknown, signal?: AbortSignal) => new Request(`https://example.com/jasper-meetings/${path}`, { method: 'POST', headers: { 'X-Jasper-Owner': owner, Authorization: 'Bearer fixture-only' }, body: JSON.stringify(body), signal });
  return { account, data, fetcher, request };
}
afterEach(() => vi.unstubAllGlobals());
describe('meeting answer cancellation and retention', () => {
  it('does not send an already-aborted request to AI or retain it', async () => {
    const f = fixture(), abort = new AbortController(); abort.abort();
    const response = await f.account.fetch(f.request('ask', { requestId, question: 'When is launch?', meetingId: meeting, consent: true }, abort.signal));
    expect(response.ok).toBe(false); expect(f.fetcher).not.toHaveBeenCalled(); expect(f.data.has(`draft:${requestId}`)).toBe(false);
  });
  it('a cancellation arriving before the request blocks delayed submission', async () => {
    const f = fixture(); expect((await f.account.fetch(f.request('cancel', { id: requestId }))).ok).toBe(true);
    const response = await f.account.fetch(f.request('ask', { requestId, question: 'When is launch?', meetingId: meeting, consent: true }));
    expect(response.ok).toBe(false); expect(f.fetcher).not.toHaveBeenCalled();
  });
  it('returns cited related findings and cancels only the temporary draft, not kept notes', async () => {
    const f = fixture();
    const response = await f.account.fetch(f.request('ask', { requestId, question: 'When is launch?', meetingId: meeting, consent: true }));
    expect(response.status).toBe(200); expect(await response.json()).toMatchObject({ id: requestId, result: { related: true, insufficient: false } });
    const kept = { untouched: true }; f.data.set(`kept:${meeting}:${requestId}`, kept);
    await f.account.fetch(f.request('cancel', { id: requestId }));
    expect(f.data.has(`draft:${requestId}`)).toBe(false); expect(f.data.get(`kept:${meeting}:${requestId}`)).toEqual(kept);
  });
  it('increments the latest erase epoch even if a request body was delayed', async () => {
    const f = fixture();
    let release: ((value: Uint8Array) => void) | undefined;
    const stream = new ReadableStream<Uint8Array>({ start(controller) { release = (value) => { controller.enqueue(value); controller.close(); }; } });
    const delayed = new Request('https://example.com/jasper-meetings/erase-answers', { method: 'POST', headers: { 'X-Jasper-Owner': owner }, body: stream, duplex: 'half' } as RequestInit);
    const pending = f.account.fetch(delayed);
    await f.account.fetch(f.request('erase-answers', { confirm: true }));
    expect(f.data.get('answer_epoch')).toBe(1);
    release?.(new TextEncoder().encode('{"confirm":true}')); await pending;
    expect(f.data.get('answer_epoch')).toBe(2);
  });
  it('does not let a supplied note grant access to an unselected or inaccessible meeting', async () => {
    const f = fixture();
    const response = await f.account.fetch(f.request('ask', { requestId, question: 'Connect my note', meetingIds: [requestId], mode: 'connections', noteContext: { title: 'Private', text: 'Try a pilot' }, consent: true }));
    expect(response.status).toBe(403); expect(await response.json()).toEqual({ error: 'meeting_access_denied' });
    expect(f.fetcher.mock.calls.some(([url]) => String(url).includes('openai.com'))).toBe(false);
  });
  it('rejects mixed scopes and missing note consent before cloud generation', async () => {
    for (const extra of [{ meetingId: meeting }, { folderId: 'team' }, { recordingContext: {} }, { consent: false }]) {
      const f = fixture();
      const response = await f.account.fetch(f.request('ask', { requestId, question: 'Connect my note', meetingIds: [meeting], mode: 'connections', noteContext: { title: 'Private', text: 'Try a pilot' }, consent: true, ...extra }));
      expect(response.ok).toBe(false); expect(f.fetcher.mock.calls.some(([url]) => String(url).includes('openai.com'))).toBe(false);
    }
  });
  it('will not retain a late provider response after request-specific cancellation', async () => {
    const f = fixture(); const original = f.fetcher.getMockImplementation()!;
    let release: ((value: Response) => void) | undefined;
    f.fetcher.mockImplementation(async (url) => String(url).includes('openai.com') ? new Promise<Response>((resolve) => { release = resolve; }) : original(url));
    const pending = f.account.fetch(f.request('ask', { requestId, question: 'When is launch?', meetingId: meeting, consent: true }));
    await vi.waitFor(() => expect(release).toBeDefined());
    await f.account.fetch(f.request('cancel', { id: requestId }));
    release?.(await original('https://api.openai.com/v1/chat/completions'));
    expect((await pending).ok).toBe(false); expect(f.data.has(`draft:${requestId}`)).toBe(false);
  });
});
