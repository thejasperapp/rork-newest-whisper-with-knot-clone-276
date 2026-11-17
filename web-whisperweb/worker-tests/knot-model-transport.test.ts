// @vitest-environment node
import { afterEach, describe, expect, it, vi } from 'vitest';
import { knotModelTransport, KnotModelTransportExhausted } from '../../functions/knot-model-transport';
afterEach(() => vi.useRealTimers());
const http = (status: number) => Object.assign(new Error('synthetic_http'), { status });
describe('nonexecuting model transport attempts', () => {
  it('recovers from 520 with bounded backoff and observed attempts', async () => {
    vi.useFakeTimers(); const observed = vi.fn(), run = vi.fn().mockRejectedValueOnce(http(520)).mockResolvedValue('exact');
    const result = knotModelTransport({ signal: new AbortController().signal, expiresAt: Date.now() + 285000, timeoutMs: 60000, run, observed });
    await vi.advanceTimersByTimeAsync(249); expect(run).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(1); expect(await result).toBe('exact'); expect(run).toHaveBeenCalledTimes(2);
    expect(observed.mock.calls.map(c => c[0].transportOutcome)).toEqual(['attempt', 'retry', 'attempt', 'recovered']);
    expect(observed.mock.calls[1][0]).toMatchObject({ status: 520, transportDelayMs: 250 });
  });
  it('ends after three 503 attempts without changing the final error', async () => {
    vi.useFakeTimers(); const error = http(503), run = vi.fn().mockRejectedValue(error);
    const result = knotModelTransport({ signal: new AbortController().signal, expiresAt: Date.now() + 285000, timeoutMs: 60000, run, observed: vi.fn() }).catch(e => e);
    await vi.advanceTimersByTimeAsync(750); const failure = await result;
    expect(failure).toBeInstanceOf(KnotModelTransportExhausted); expect(failure.lastError).toBe(error); expect(run).toHaveBeenCalledTimes(3);
  });
  it('bounds a stalled read at sixty seconds and retries only before dispatch', async () => {
    vi.useFakeTimers(); const run = vi.fn().mockImplementationOnce(() => new Promise(() => {})).mockResolvedValue('read-complete');
    const result = knotModelTransport({ signal: new AbortController().signal, expiresAt: Date.now() + 285000, timeoutMs: 90000, run, observed: vi.fn() });
    await vi.advanceTimersByTimeAsync(59999); expect(run).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(251); expect(await result).toBe('read-complete'); expect(run).toHaveBeenCalledTimes(2);
  });
  it.each([25000, 60000, 120000])('all stalled attempts share one %i ms stage budget', async timeoutMs => {
    vi.useFakeTimers(); const start = Date.now(), observed = vi.fn(), run = vi.fn(() => new Promise(() => {}));
    const result = knotModelTransport({ signal: new AbortController().signal, expiresAt: start + 285000, timeoutMs, run, observed }).catch(error => error);
    await vi.advanceTimersByTimeAsync(timeoutMs - 1);
    expect(observed.mock.calls.some(([facts]) => facts.transportOutcome === 'ended')).toBe(false);
    await vi.advanceTimersByTimeAsync(1);
    expect(await result).toBeInstanceOf(KnotModelTransportExhausted);
    expect(Date.now() - start).toBe(timeoutMs);
    expect(run).toHaveBeenCalledTimes(timeoutMs > 60000 ? 2 : 1);
    await vi.advanceTimersByTimeAsync(180000); expect(run).toHaveBeenCalledTimes(timeoutMs > 60000 ? 2 : 1);
  });
  it('counts transport backoff within the remaining stage budget', async () => {
    vi.useFakeTimers(); const run = vi.fn().mockImplementation(() => new Promise((_resolve, reject) => setTimeout(() => reject(http(503)), 998)));
    const result = knotModelTransport({ signal: new AbortController().signal, expiresAt: Date.now() + 285000, timeoutMs: 1000, run, observed: vi.fn() }).catch(error => error);
    await vi.advanceTimersByTimeAsync(1000);
    expect(await result).toBeInstanceOf(KnotModelTransportExhausted); expect(run).toHaveBeenCalledTimes(1);
  });
  it.each([400, 401, 402, 403, 413, 429])('does not retry HTTP %s', async status => {
    const error = http(status), run = vi.fn().mockRejectedValue(error);
    await expect(knotModelTransport({ signal: new AbortController().signal, expiresAt: Date.now() + 285000, timeoutMs: 60000, run, observed: vi.fn() })).rejects.toBe(error);
    expect(run).toHaveBeenCalledTimes(1);
  });
  it('Stop interrupts backoff without a second request', async () => {
    vi.useFakeTimers(); const aborter = new AbortController(), run = vi.fn().mockRejectedValue(http(520));
    const result = knotModelTransport({ signal: aborter.signal, expiresAt: Date.now() + 285000, timeoutMs: 60000, run, observed: vi.fn() }).catch(e => e);
    await vi.advanceTimersByTimeAsync(100); aborter.abort(); await vi.advanceTimersByTimeAsync(1000);
    expect((await result).name).toBe('AbortError'); expect(run).toHaveBeenCalledTimes(1);
  });
  it('does not schedule a retry without the owned reserve', async () => {
    const run = vi.fn().mockRejectedValue(http(520));
    await expect(knotModelTransport({ signal: new AbortController().signal, expiresAt: Date.now() + 15000, timeoutMs: 60000, run, observed: vi.fn() })).rejects.toBeInstanceOf(KnotModelTransportExhausted);
    expect(run).toHaveBeenCalledTimes(1);
  });
  it('an observer failure never replays a successful request', async () => {
    const run = vi.fn().mockResolvedValue('exact');
    expect(await knotModelTransport({ signal: new AbortController().signal, expiresAt: Date.now() + 285000, timeoutMs: 60000, run, observed: () => { throw Error('diagnostic'); } })).toBe('exact');
    expect(run).toHaveBeenCalledTimes(1);
  });
});
