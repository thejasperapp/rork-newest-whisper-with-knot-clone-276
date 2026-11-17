import { beforeEach, describe, expect, it, vi } from 'vitest';
import { generateMeetingNotes } from './meetings';
const mock = vi.hoisted(() => ({ rows: [] as { username: string; text: string }[], complete: vi.fn(), update: vi.fn(), acknowledged: true }));
vi.mock('./supabase', () => {
  const query = { select: () => query, eq: () => query, lte: () => query, order: () => query, range: async () => ({ data: mock.rows, error: null }), update: (patch: unknown) => { mock.update(patch); return query; }, single: async () => ({ data: mock.acknowledged ? { id: 'meeting' } : null, error: null }) };
  return { supabase: { from: () => query } };
});
vi.mock('./billing', () => ({ BACKEND_URL: '' }));
vi.mock('./ember', () => ({ emberCompletion: mock.complete }));
beforeEach(() => { vi.clearAllMocks(); mock.rows = [{ username: 'Alex', text: 'Ship Thursday.' }]; mock.complete.mockResolvedValue('**Decisions**\n- Ship Thursday.'); mock.acknowledged = true; });
describe('truthful shared recap snapshots', () => {
  it('refuses overflow rather than silently excluding early decisions', async () => {
    mock.rows = [{ username: 'Alex', text: 'Important early decision.' }, { username: 'Josh', text: 'x'.repeat(24000) }];
    await expect(generateMeetingNotes('meeting')).rejects.toThrow('too long'); expect(mock.complete).not.toHaveBeenCalled(); expect(mock.update).not.toHaveBeenCalled();
  });
  it('sends all bounded speech and labels the generated result as a saved snapshot', async () => {
    const result = await generateMeetingNotes('meeting'); expect(mock.complete.mock.calls[0][0][1].content).toBe('Alex: Ship Thursday.');
    expect(result.summary).toContain('Pending or later-arriving speech is not included'); expect(mock.update.mock.calls[0][0].summary).toBe(result.summary);
  });
  it('does not claim a saved recap without the returned database row', async () => {
    mock.acknowledged = false; await expect(generateMeetingNotes('meeting')).rejects.toThrow('could not be saved');
  });
});
