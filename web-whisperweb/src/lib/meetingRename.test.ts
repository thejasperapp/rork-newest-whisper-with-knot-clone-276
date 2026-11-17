import { beforeEach, describe, expect, it, vi } from 'vitest';
import { renameMeeting, type WhisperMeeting } from './meetings';
const mock = vi.hoisted(() => ({ owner: 'host', result: { data: null as unknown, error: null as unknown }, update: vi.fn(), eq: vi.fn() }));
vi.mock('./supabase', () => {
  const query = { update: (value: unknown) => { mock.update(value); return query; }, eq: (...value: unknown[]) => { mock.eq(...value); return query; }, select: () => query, maybeSingle: async () => mock.result };
  return { supabase: { auth: { getSession: async () => ({ data: { session: { user: { id: mock.owner } } } }) }, from: () => query } };
});
vi.mock('./billing', () => ({ BACKEND_URL: '' }));
vi.mock('./ember', () => ({ emberCompletion: vi.fn() }));
const meeting = { id: 'meeting', host_id: 'host', title: 'Meeting' } as WhisperMeeting;
beforeEach(() => { mock.owner = 'host'; mock.result = { data: { ...meeting, title: 'Weekly planning' }, error: null }; vi.clearAllMocks(); });
describe('shared meeting rename', () => {
  it('updates only the original host row and compares the previous title', async () => {
    expect((await renameMeeting(meeting, ' Weekly planning ')).title).toBe('Weekly planning');
    expect(mock.update).toHaveBeenCalledWith({ title: 'Weekly planning' }); expect(mock.eq).toHaveBeenCalledWith('title', 'Meeting'); expect(mock.eq).toHaveBeenCalledWith('host_id', 'host');
  });
  it('does not claim success when access is denied or another device changed the title', async () => { mock.result.data = null; await expect(renameMeeting(meeting, 'New name')).rejects.toThrow('could not be renamed'); });
  it('does not permit another participant or an empty name', async () => { mock.owner = 'other'; await expect(renameMeeting(meeting, 'New name')).rejects.toThrow('original meeting host'); expect(mock.update).not.toHaveBeenCalled(); await expect(renameMeeting(meeting, ' ')).rejects.toThrow('meeting name'); });
});
