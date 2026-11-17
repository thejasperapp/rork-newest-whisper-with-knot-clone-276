// @vitest-environment node
import { afterEach, describe, expect, it, vi } from 'vitest';
vi.mock('cloudflare:workers', () => ({ DurableObject: class { constructor(protected ctx: unknown, protected env: unknown) {} } }));
import { JasperMeetingAccount } from '../../functions/jasper-meetings';

afterEach(() => vi.restoreAllMocks());
describe('meeting draft expiry alarm on owned storage', () => {
  it.each([100000, -86400000])('schedules from the earliest retained draft, bounded after now (%s)', async age => {
    const now = 1800000000000, updated = now + age;
    vi.spyOn(Date, 'now').mockReturnValue(now);
    const setAlarm = vi.fn(async () => {});
    const sql = { exec: vi.fn((query: string) => ({ toArray: () => query.startsWith('SELECT updated') ? [{ updated }] : [] })) };
    // The standalone facade exposes fetch only. No synthetic facade alarm helper.
    const account = new JasperMeetingAccount({ id: { name: 'fixture-owner' }, storage: { sql, setAlarm } } as never, { DO: { fetch: vi.fn() } } as never);
    await account.onAlarm();
    expect(setAlarm).toHaveBeenCalledExactlyOnceWith(Math.max(now + 1000, updated + 86400000));
    expect(sql.exec).toHaveBeenCalledWith(expect.stringContaining('DELETE'), now - 86400000);
  });
  it('does not schedule an empty expiry queue', async () => {
    const setAlarm = vi.fn(async () => {});
    const sql = { exec: vi.fn(() => ({ toArray: () => [] })) };
    const account = new JasperMeetingAccount({ storage: { sql, setAlarm } } as never, { DO: { fetch: vi.fn() } } as never);
    await account.onAlarm();
    expect(setAlarm).not.toHaveBeenCalled();
  });
});
