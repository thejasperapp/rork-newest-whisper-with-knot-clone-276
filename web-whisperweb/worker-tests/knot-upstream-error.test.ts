// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { knotUpstreamDiagnostic } from '../../functions/knot-upstream-error';

const rejected = (body: unknown, status = 401) => Response.json(body, { status });
describe('private, bounded Cloud rejection diagnostics', () => {
  it.each([{}, { error: { message: 'Private synthetic detail' } }, { error: 'Private synthetic detail' }])('retains HTTP 401 authentication without a recognized code: %j', async body => {
    expect(await knotUpstreamDiagnostic(rejected(body))).toMatchObject({ category: 'authentication' });
  });
  it('classifies a known authentication type without returning private messages', async () => {
    const result = await knotUpstreamDiagnostic(rejected({ error: { type: 'authentication_error', message: 'Authentication failed. synthetic-private-marker' } }));
    expect(result).toMatchObject({ category: 'authentication', code: 'authentication_error', authenticationHint: 'authentication_failed' });
    expect(JSON.stringify(result)).not.toContain('synthetic-private-marker');
  });
  it.each([
    ['The API key was revoked; synthetic-private-marker', 'revoked_key'],
    ['Invalid API key: synthetic-private-marker', 'invalid_key'],
    ['Missing authorization token; synthetic-private-marker', 'missing_key'],
    ['Unauthorized: synthetic-private-marker', 'unauthorized'],
  ])('reports only a fixed authentication hint for %s', async (message, hint) => {
    const result = await knotUpstreamDiagnostic(rejected({ error: { message, code: 'synthetic-private-marker' }, request_id: 'synthetic-private-marker' }));
    expect(result).toMatchObject({ category: 'authentication', authenticationHint: hint });
    expect(result.code).toBeUndefined();
    expect(JSON.stringify(result)).not.toContain('synthetic-private-marker');
  });
  it('keeps quota classification separate from authentication and does not infer account balance', async () => {
    expect(await knotUpstreamDiagnostic(rejected({ error: { code: 'INSUFFICIENT_BALANCE', message: 'synthetic-private-marker' } }, 402)))
      .toEqual({ category: 'quota_exhausted', code: 'INSUFFICIENT_BALANCE' });
  });
  it('does not forward unknown codes or arbitrary response fields', async () => {
    expect(await knotUpstreamDiagnostic(rejected({ code: 'synthetic-private-marker', message: 'synthetic-private-marker', organization: 'synthetic-private-marker' }, 400)))
      .toEqual({ category: 'other_rejection' });
  });
  it('bounds oversized bodies, retains HTTP authentication, and cancels the reader', async () => {
    let cancelled = false;
    const body = new ReadableStream<Uint8Array>({ start(controller) { controller.enqueue(new Uint8Array(16385)); }, cancel() { cancelled = true; } });
    expect(await knotUpstreamDiagnostic(new Response(body, { status: 401 }))).toEqual({ category: 'authentication' });
    expect(cancelled).toBe(true);
  });
  it.each(['not-json synthetic-private-marker', 'null', '[]'])('handles non-object error bodies safely: %s', async body => {
    const result = await knotUpstreamDiagnostic(new Response(body, { status: 401 }));
    expect(result.category).toBe('authentication');
    expect(JSON.stringify(result)).not.toContain('synthetic-private-marker');
  });
  it('only preserves bounded retry-after seconds', async () => {
    expect(await knotUpstreamDiagnostic(new Response('', { status: 429, headers: { 'Retry-After': '2.1' } }))).toEqual({ category: 'unclassified', retryAfterSeconds: 3 });
    expect(await knotUpstreamDiagnostic(new Response('', { status: 429, headers: { 'Retry-After': '90000' } }))).toEqual({ category: 'unclassified' });
  });
});
