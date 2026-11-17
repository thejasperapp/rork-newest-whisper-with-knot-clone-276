import 'fake-indexeddb/auto';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { supabase } from './supabase';
import { flushTranscriptOutbox, retainTranscript } from './transcriptOutbox';
vi.mock('./supabase', () => ({ supabase: { auth: { getSession: vi.fn() }, from: vi.fn() } }));
let owner: string;
beforeEach(() => { vi.clearAllMocks(); owner = crypto.randomUUID(); vi.mocked(supabase.auth.getSession).mockResolvedValue({ data: { session: { user: { id: owner } } }, error: null } as never); });
afterEach(() => vi.restoreAllMocks());
describe('durable transcript delivery', () => {
  it('still uploads memory-retained speech when recovery storage cannot open', async () => {
    const open = vi.spyOn(indexedDB, 'open').mockImplementation(() => { throw new Error('storage blocked'); });
    const insert = vi.fn().mockReturnValue({ abortSignal: async () => ({ error: null }) }); vi.mocked(supabase.from).mockReturnValue({ insert } as never);
    await expect(retainTranscript({ userId: owner, meetingId: crypto.randomUUID(), username: 'A', text: 'Retain this phrase.' })).rejects.toThrow();
    await expect(flushTranscriptOutbox(owner)).rejects.toThrow('recovery storage');
    expect(insert).toHaveBeenCalledOnce();
    open.mockRestore(); await flushTranscriptOutbox(owner); expect(insert).toHaveBeenCalledOnce();
  });
  it('retains a failed insert and retries the same segment ID and capture timestamp', async () => {
    const insert = vi.fn().mockReturnValue({ abortSignal: async () => ({ error: { code: 'offline' } }) }); vi.mocked(supabase.from).mockReturnValue({ insert } as never);
    await retainTranscript({ userId: owner, meetingId: crypto.randomUUID(), username: 'Alex', text: 'Final decision.' });
    await expect(flushTranscriptOutbox(owner)).rejects.toThrow('waiting to save'); const original = insert.mock.calls[0][0];
    insert.mockReturnValue({ abortSignal: async () => ({ error: null }) }); await flushTranscriptOutbox(owner);
    expect(insert.mock.calls[1][0]).toEqual(original); await flushTranscriptOutbox(owner); expect(insert).toHaveBeenCalledTimes(2);
  });
  it('bounds duplicate verification and keeps the same speech available for retry', async () => {
    const meetingId = crypto.randomUUID(); await retainTranscript({ userId: owner, meetingId, username: 'Alex', text: 'Recovered final phrase.' });
    const insert = vi.fn().mockReturnValue({ abortSignal: async () => ({ error: { code: '23505' } }) });
    let verificationSignal: AbortSignal | undefined;
    const query = { select: vi.fn().mockReturnThis(), eq: vi.fn().mockReturnThis(), abortSignal: (signal: AbortSignal) => { verificationSignal = signal; return query; }, maybeSingle: vi.fn().mockResolvedValue({ error: { code: 'timeout' } }), insert };
    vi.mocked(supabase.from).mockReturnValue(query as never);
    await expect(flushTranscriptOutbox(owner)).rejects.toThrow('waiting to save'); expect(verificationSignal).toBeInstanceOf(AbortSignal);
    const original = insert.mock.calls[0][0]; query.maybeSingle.mockResolvedValue({ data: original, error: null } as never);
    await flushTranscriptOutbox(owner); expect(insert.mock.calls[1][0]).toEqual(original);
  });
  it('never uploads another account’s retained speech', async () => { const another = crypto.randomUUID(); await retainTranscript({ userId: another, meetingId: crypto.randomUUID(), username: 'Other', text: 'Private to another account.' }); await flushTranscriptOutbox(another); expect(supabase.from).not.toHaveBeenCalled(); });
  it('continues independent phrases after one failure and drains speech added during a flush', async () => {
    const meetingId = crypto.randomUUID(); await retainTranscript({ userId: owner, meetingId, username: 'A', text: 'First.' });
    const insert = vi.fn().mockImplementation((entry: { text: string }) => ({ abortSignal: async () => { if (entry.text === 'First.') { await retainTranscript({ userId: owner, meetingId, username: 'A', text: 'Final phrase.' }); return { error: { code: 'offline' } }; } return { error: null }; } })); vi.mocked(supabase.from).mockReturnValue({ insert } as never);
    await expect(flushTranscriptOutbox(owner)).rejects.toThrow('waiting to save'); expect(insert.mock.calls.map(([entry]) => entry.text)).toEqual(['First.', 'Final phrase.']);
  });
});
