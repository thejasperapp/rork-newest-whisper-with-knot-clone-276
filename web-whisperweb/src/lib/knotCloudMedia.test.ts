// @vitest-environment node
import { afterEach, describe, expect, it, vi } from 'vitest';
import { knotConverseWithImage, knotImagine } from './knotCloudMedia';
afterEach(() => { vi.unstubAllGlobals(); vi.unstubAllEnvs(); vi.restoreAllMocks(); });
const visionTurn = () => ({ assertCurrent: vi.fn(), signal: new AbortController().signal, system: 'Synthetic system' });
const success = () => Response.json({ choices: [{ finish_reason: 'stop', message: { content: 'Synthetic image description' } }] });
describe('dedicated Knot Cloud-only media', () => {
  it('uses only the official Cloud vision endpoint with delegated auth and no redirects', async () => {
    const fetcher = vi.fn(async () => success()); vi.stubGlobal('fetch', fetcher);
    expect(await knotConverseWithImage([], 'data:image/png;base64,c3ludGhldGlj', 'Describe synthetic image', visionTurn())).toBe('Synthetic image description');
    expect(fetcher).toHaveBeenCalledTimes(1);
    const [url, init] = fetcher.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe('https://toolkit.rork.com/v2/vercel/v1/chat/completions');
    expect(init).toMatchObject({ redirect: 'error', credentials: 'omit', cache: 'no-store', method: 'POST' });
    expect(init.headers).not.toHaveProperty('Authorization');
    expect(JSON.parse(String(init.body))).toMatchObject({ model: 'openai/gpt-4o' });
  });
  it('never transmits when the consent/account/turn guard rejects', async () => {
    const fetcher = vi.fn(); vi.stubGlobal('fetch', fetcher);
    const turn = visionTurn(); turn.assertCurrent.mockImplementation(() => { throw new Error('synthetic withdrawn'); });
    await expect(knotConverseWithImage([], 'synthetic', 'synthetic', turn)).rejects.toThrow('synthetic withdrawn');
    expect(fetcher).not.toHaveBeenCalled();
  });
  it('rejects a late result when the captured guard changes during the request', async () => {
    let current = true;
    const turn = { ...visionTurn(), assertCurrent: () => { if (!current) throw new Error('synthetic account changed'); } };
    const fetcher = vi.fn(async () => { current = false; return success(); }); vi.stubGlobal('fetch', fetcher);
    await expect(knotConverseWithImage([], 'synthetic', 'synthetic', turn)).rejects.toThrow('synthetic account changed');
    expect(fetcher).toHaveBeenCalledTimes(1);
  });
  it('Stop prevents transmission before the request starts', async () => {
    const fetcher = vi.fn(); vi.stubGlobal('fetch', fetcher);
    const controller = new AbortController(); controller.abort();
    await expect(knotConverseWithImage([], 'synthetic', 'synthetic', { ...visionTurn(), signal: controller.signal })).rejects.toMatchObject({ name: 'AbortError' });
    expect(fetcher).not.toHaveBeenCalled();
  });
  it.each([401, 402, 429, 503])('does not retry, switch models or expose the body after HTTP %s', async status => {
    const fetcher = vi.fn(async () => new Response('synthetic-private-marker', { status })); vi.stubGlobal('fetch', fetcher);
    await expect(knotConverseWithImage([], 'synthetic', 'synthetic', visionTurn())).rejects.toThrow('Knot Cloud request rejected');
    expect(fetcher).toHaveBeenCalledTimes(1);
  });
  it('rejects alternate origins before transmission', async () => {
    vi.stubEnv('EXPO_PUBLIC_TOOLKIT_URL', 'https://synthetic.invalid');
    const fetcher = vi.fn(); vi.stubGlobal('fetch', fetcher);
    await expect(knotConverseWithImage([], 'synthetic', 'synthetic', visionTurn())).rejects.toThrow('Knot Cloud configuration unavailable');
    expect(fetcher).not.toHaveBeenCalled();
  });
  it('never treats truncated output as a completed answer', async () => {
    const fetcher = vi.fn(async () => Response.json({ choices: [{ finish_reason: 'length', message: { content: 'Incomplete' } }] })); vi.stubGlobal('fetch', fetcher);
    await expect(knotConverseWithImage([], 'synthetic', 'synthetic', visionTurn())).rejects.toThrow('Knot Cloud image analysis incomplete');
    expect(fetcher).toHaveBeenCalledTimes(1);
  });
  it('uses one official Cloud image request with the native model, without a fallback', async () => {
    const fetcher = vi.fn(async () => Response.json({ images: ['c3ludGhldGlj'] })); vi.stubGlobal('fetch', fetcher);
    expect(await knotImagine('Synthetic orange square', vi.fn(), new AbortController().signal)).toBe('data:image/png;base64,c3ludGhldGlj');
    expect(fetcher).toHaveBeenCalledTimes(1);
    const [url, init] = fetcher.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe('https://toolkit.rork.com/v2/vercel/v3/ai/image-model');
    expect(JSON.parse(String(init.body))).toMatchObject({ model: 'openai/gpt-image-2', n: 1 });
    expect(init.headers).not.toHaveProperty('Authorization');
  });
});
