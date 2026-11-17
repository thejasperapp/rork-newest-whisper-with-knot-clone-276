import { beforeEach, describe, expect, it, vi } from 'vitest';
import { addTeamMember, fetchMyBusinessPlus, fetchTeam, removeTeamMember, setCompanyName, updateTeamMember } from './businessPlus';
const db = vi.hoisted(() => ({ from: vi.fn(), replies: [] as { data: unknown; error: unknown }[], ilike: vi.fn(), in: vi.fn(), update: vi.fn(), upsert: vi.fn() }));
vi.mock('./supabase', () => ({ supabase: { from: db.from } }));
vi.mock('./groupChats', () => ({ createGroupThread: vi.fn(), fetchMyGroupThreads: vi.fn() }));
beforeEach(() => {
  vi.clearAllMocks(); db.replies = [];
  db.from.mockImplementation(() => {
    const result = db.replies.shift() ?? { data: [], error: null };
    const q = { select: vi.fn(() => q), eq: vi.fn(() => q), order: vi.fn(() => q), limit: vi.fn(() => q), maybeSingle: vi.fn(() => q), delete: vi.fn(() => q),
      ilike: vi.fn((...args: unknown[]) => { db.ilike(...args); return q; }), in: vi.fn((...args: unknown[]) => { db.in(...args); return q; }),
      update: vi.fn((...args: unknown[]) => { db.update(...args); return q; }), upsert: vi.fn((...args: unknown[]) => { db.upsert(...args); return q; }),
      then: (resolve: (value: typeof result) => unknown) => Promise.resolve(result).then(resolve) };
    return q;
  });
});
describe('existing Business+ team management', () => {
  it('does not treat failed access checks as no plan', async () => { db.replies.push({ data: null, error: { code: 'offline' } }); await expect(fetchMyBusinessPlus('me')).rejects.toThrow('team access'); });
  it('checks all returned seats rather than only the first inactive team', async () => {
    db.replies.push({ data: [], error: null }, { data: [{ business_id: 'old', role_title: 'Old role' }, { business_id: 'active', role_title: 'Designer' }], error: null }, { data: [{ user_id: 'active', status: 'active' }], error: null });
    await expect(fetchMyBusinessPlus('me')).resolves.toMatchObject({ isOwner: false, roleTitle: 'Designer' }); expect(db.in).toHaveBeenCalledWith('user_id', ['old', 'active']);
  });
  it('reports roster failures instead of displaying an empty team', async () => { db.replies.push({ data: null, error: {} }); await expect(fetchTeam('owner')).rejects.toThrow('load the team'); });
  it('requires exact usernames even if a lookup returned another person', async () => {
    db.replies.push({ data: { user_id: 'other', username: 'alexx' }, error: null });
    await expect(addTeamMember({ businessId: 'owner', username: 'alex_', roleTitle: 'Design', accent: '#000000' })).rejects.toThrow('No one named');
    expect(db.ilike).toHaveBeenCalledWith('username', 'alex\\_'); expect(db.upsert).not.toHaveBeenCalled();
  });
  it('adds the exact matched person only after an acknowledged write', async () => {
    db.replies.push({ data: { user_id: 'other', username: 'Alex' }, error: null }, { data: [{ user_id: 'other' }], error: null });
    await expect(addTeamMember({ businessId: 'owner', username: '@Alex', roleTitle: 'Design', accent: '#000000' })).resolves.toBeUndefined();
  });
  it('does not report an unacknowledged role update as saved', async () => { await expect(updateTeamMember('owner', 'member', { role_title: 'Lead' })).rejects.toThrow('update the role'); });
  it('does not report denied removal as successful', async () => { db.replies.push({ data: null, error: {} }); await expect(removeTeamMember('owner', 'member')).rejects.toThrow('confirm removal'); });
  it('requires company-name acknowledgment and never writes entitlement fields', async () => { await expect(setCompanyName('plan', 'Studio')).rejects.toThrow('save the company name'); expect(db.update).toHaveBeenCalledWith({ company_name: 'Studio' }); });
});
