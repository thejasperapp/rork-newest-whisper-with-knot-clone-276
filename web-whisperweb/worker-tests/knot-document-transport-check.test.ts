// @vitest-environment node
import { afterEach, describe, expect, it, vi } from 'vitest';
vi.mock('cloudflare:workers', () => ({ DurableObject: class {} }));
import { documentSliceTokenLimit } from '../../functions/knot-document-authoring-context';
import { inspectKnotDocumentTransport } from '../../functions/knot-document-transport-check';
const env = { EXPO_PUBLIC_TOOLKIT_URL: 'https://synthetic.invalid', EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY: 'synthetic-managed-only' };
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });
describe('fixed operator-only authoring diagnostics', () => {
  it.each(['authoring-chat', 'authoring-messages', 'authoring-bound', 'authoring-beta', 'authoring-beta-bound'] as const)('uses a fixed synthetic same-model request with no execution or credentials in output: %s', async check => {
    const requests: any[] = [];
    vi.stubGlobal('fetch', vi.fn(async (url: string, init: RequestInit) => {
      expect(init.redirect).toBe('manual'); // Cloudflare does not support redirect:error.
      const body = JSON.parse(String(init.body)); requests.push(body);
      expect(body.model).toBe('anthropic/claude-sonnet-4.6');
      expect(body.providerOptions).toEqual({ anthropic: { structuredOutputMode: 'outputFormat' } });
      expect(body).not.toHaveProperty('tools');
      expect(body).not.toHaveProperty('tool_choice');
      expect(body.messages).toHaveLength(1);
      expect(JSON.stringify(body)).not.toMatch(/synthetic-managed-only|MEMORY\.md|owner|sessionID/);
      const beta = check.startsWith('authoring-beta'), large = check.endsWith('bound');
      expect(body.max_tokens).toBe(large ? documentSliceTokenLimit(3000) : 256);
      expect((init.headers as Record<string, string>)['anthropic-beta']).toBe(beta ? 'structured-outputs-2025-11-13' : undefined);
      if (beta) { expect(body).toHaveProperty('output_format.type', 'json_schema'); expect(body).not.toHaveProperty('output_config'); expect(body).not.toHaveProperty('response_format'); }
      else if (check !== 'authoring-chat') { expect(body).toHaveProperty('output_config.format.type', 'json_schema'); expect(body).not.toHaveProperty('output_format'); }
      const native = check !== 'authoring-chat', text = JSON.stringify({ code: large ? '# synthetic\n' : 'ABCDEFGH', final: true });
      expect(url).toBe('https://synthetic.invalid/v2/vercel/v1/' + (native ? 'messages' : 'chat/completions'));
      return Response.json(native ? { type: 'message', role: 'assistant', content: [{ type: 'text', text }], stop_reason: 'end_turn', usage: { input_tokens: 5, output_tokens: 7 } } : { choices: [{ finish_reason: 'stop', message: { content: text } }], usage: { prompt_tokens: 5, completion_tokens: 7 } });
    }));
    const result = await inspectKnotDocumentTransport(env, check);
    expect(requests).toHaveLength(1);
    expect(result).toMatchObject({ completed: true, matchesPattern: true, structuredOutputMode: 'outputFormat', noPersonalData: true, remoteMutationPerformed: false, noAutomaticRetry: true, status: 200, inputTokens: 5, outputTokens: 7 });
    expect(JSON.stringify(result)).not.toMatch(/synthetic-managed-only|ABCDEFGH|# synthetic|Synthetic schema/);
  });
  it('records schema violation as failure, without retry or accepting oversized content', async () => {
    const fetcher = vi.fn(async () => Response.json({ choices: [{ finish_reason: 'stop', message: { content: '{"code":"ABCDEFGHIJKLMNOPQRSTUVWXYZ","final":true}' } }] }));
    vi.stubGlobal('fetch', fetcher);
    expect(await inspectKnotDocumentTransport(env, 'authoring-chat')).toMatchObject({ completed: false, matchesPattern: false, codeCharacters: 26 });
    expect(fetcher).toHaveBeenCalledTimes(1);
  });
  it('keeps thrown transport text private and never falls back', async () => {
    const fetcher = vi.fn(async () => { throw new TypeError('Synthetic private upstream text and synthetic-managed-only'); });
    vi.stubGlobal('fetch', fetcher);
    const result = await inspectKnotDocumentTransport(env, 'authoring-messages');
    expect(result).toMatchObject({ completed: false, failureName: 'TypeError', reason: 'transport_or_schema_failure' });
    expect(JSON.stringify(result)).not.toMatch(/Synthetic private|synthetic-managed-only/);
    expect(fetcher).toHaveBeenCalledTimes(1);
  });
});
