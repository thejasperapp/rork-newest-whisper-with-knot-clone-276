// @vitest-environment node
import { afterEach, describe, expect, it, vi } from 'vitest';
vi.mock('cloudflare:workers', () => ({ DurableObject: class {} }));
import { knotAuthorStreaming, KnotAuthorPolicyBoundary } from '../../functions/knot-author-streaming';
import { KnotModelTransportExhausted } from '../../functions/knot-model-transport';
import { DocumentProgramRejected } from '../../functions/knot-document-program';
import { safeKnotActivityDetail } from '../../functions/knot-activity';
const enc = new TextEncoder();
const frame = (content: unknown, finish: unknown = null, extra: Record<string, unknown> = {}) => 'data: ' + JSON.stringify({ choices: [{ index: 0, delta: { content, ...extra }, finish_reason: finish }] }) + '\n\n';
const done = 'data: [DONE]\n\n';
const response = (wire: string) => new Response(wire, { headers: { 'Content-Type': 'text/event-stream' } });
afterEach(() => { vi.useRealTimers(); vi.restoreAllMocks(); });

describe('author-only complete streaming transport', () => {
  it('allows healthy complete generation beyond the removed 280-second cap', async () => {
    vi.useFakeTimers(); const observed = vi.fn();
    const request = vi.fn(async () => new Response(new ReadableStream({ start(controller) {
      controller.enqueue(enc.encode(frame('{"code":"')));
      for (let n = 1; n <= 5; n++) setTimeout(() => controller.enqueue(enc.encode(frame('x'))), n * 50000);
      setTimeout(() => { controller.enqueue(enc.encode(frame('","final":true}', 'stop') + done)); controller.close(); }, 300000);
    } }), { headers: { 'Content-Type': 'text/event-stream' } }));
    const pending = knotAuthorStreaming({ signal: new AbortController().signal, expiresAt: Date.now() + 915000, timeoutMs: 60000, request, observed });
    await vi.advanceTimersByTimeAsync(300000);
    expect((await pending).choices[0].message.content).toBe('{"code":"xxxxx","final":true}');
    expect(request).toHaveBeenCalledTimes(1);
    expect(observed.mock.calls.at(-1)?.[0]).toMatchObject({ transportElapsedMs: 300000, transportMaxIdleMs: 50000 });
  });
  it('never renews a longer caller-owned deadline despite healthy content', async () => {
    vi.useFakeTimers(); const observed = vi.fn(), cancel = vi.fn();
    const request = vi.fn(async () => new Response(new ReadableStream({ start(controller) {
      controller.enqueue(enc.encode(frame('prefix')));
      for (let n = 1; n <= 10; n++) setTimeout(() => controller.enqueue(enc.encode(frame('x'))), n * 50000);
    }, cancel }), { headers: { 'Content-Type': 'text/event-stream' } }));
    const pending = knotAuthorStreaming({ signal: new AbortController().signal, expiresAt: Date.now() + 555000, timeoutMs: 60000, request, observed }).catch(e => e);
    await vi.advanceTimersByTimeAsync(550000);
    expect(await pending).toBeInstanceOf(KnotModelTransportExhausted); expect(request).toHaveBeenCalledTimes(1); expect(cancel).toHaveBeenCalledTimes(1);
    expect(observed.mock.calls.at(-1)?.[0]).toMatchObject({ transportTimeoutKind: 'owned_deadline', transportElapsedMs: 550000 });
  });
  it('serves a generation longer than sixty seconds while genuine content keeps arriving', async () => {
    vi.useFakeTimers(); const observed = vi.fn(), request = vi.fn(async () => new Response(new ReadableStream({ start(controller) {
      controller.enqueue(enc.encode(frame('{"code":"')));
      setTimeout(() => controller.enqueue(enc.encode(frame('one'))), 50000);
      setTimeout(() => controller.enqueue(enc.encode(frame('two'))), 100000);
      setTimeout(() => { controller.enqueue(enc.encode(frame('","final":true}', 'stop') + done)); controller.close(); }, 150000);
    } }), { headers: { 'Content-Type': 'text/event-stream' } }));
    const pending = knotAuthorStreaming({ signal: new AbortController().signal, expiresAt: Date.now() + 285000, timeoutMs: 60000, request, observed });
    await vi.advanceTimersByTimeAsync(150000);
    expect((await pending).choices[0].message.content).toBe('{"code":"onetwo","final":true}');
    expect(request).toHaveBeenCalledTimes(1);
    expect(observed.mock.calls.at(-1)?.[0]).toMatchObject({ transportCallCount: 1, transportElapsedMs: 150000, transportFirstTokenMs: 0, transportChunkCount: 4, transportMaxIdleMs: 50000, transportStreaming: true, transportOutcome: 'recovered' });
  });
  it('preserves split UTF-8, CRLF and multiline data exactly', async () => {
    const wire = 'data: {"choices":\r\ndata: [{"index":0,"delta":{"role":"assistant","content":"🙂\\nexact"},"finish_reason":"stop"}]}\r\n\r\ndata: [DONE]\r\n\r\n';
    const request = vi.fn(async () => new Response(new ReadableStream({ start(controller) {
      for (const byte of enc.encode(wire)) controller.enqueue(Uint8Array.of(byte));
      controller.close();
    } }), { headers: { 'Content-Type': 'text/event-stream' } }));
    const value = await knotAuthorStreaming({ signal: new AbortController().signal, expiresAt: Date.now() + 285000, timeoutMs: 60000, request, observed: vi.fn() });
    expect(value.choices[0].message.content).toBe('🙂\nexact');
  });
  it('heartbeats, empty deltas and role frames cannot renew first-content timeout', async () => {
    vi.useFakeTimers(); const observed = vi.fn(), cancelled = vi.fn();
    const request = vi.fn(async () => new Response(new ReadableStream({ start(controller) {
      controller.enqueue(enc.encode(': keepalive\n\n' + frame('', null, { role: 'assistant' })));
    }, cancel: cancelled }), { headers: { 'Content-Type': 'text/event-stream' } }));
    const pending = knotAuthorStreaming({ signal: new AbortController().signal, expiresAt: Date.now() + 285000, timeoutMs: 60000, request, observed }).catch(e => e);
    await vi.advanceTimersByTimeAsync(180750);
    expect(await pending).toBeInstanceOf(KnotModelTransportExhausted);
    expect(request).toHaveBeenCalledTimes(3); expect(cancelled).toHaveBeenCalledTimes(3);
    const outcomes = observed.mock.calls.map(call => call[0]);
    expect(outcomes.filter(f => f.transportOutcome === 'retry')).toHaveLength(2);
    expect(outcomes.at(-1)).toMatchObject({ transportCallCount: 3, transportElapsedMs: 60000, transportChunkCount: 0, transportMaxIdleMs: 60000, transportTimeoutKind: 'first_token' });
    expect(outcomes.at(-1)?.transportFirstTokenMs).toBeUndefined();
  });
  it('reports a real content-idle stall and discards its partial program before retry', async () => {
    vi.useFakeTimers(); const observed = vi.fn(), cancel = vi.fn();
    const request = vi.fn().mockImplementationOnce(async () => new Response(new ReadableStream({ start(controller) {
      controller.enqueue(enc.encode(frame('discard this partial code')));
    }, cancel }), { headers: { 'Content-Type': 'text/event-stream' } })).mockResolvedValueOnce(response(frame('exact complete response', 'stop') + done));
    const pending = knotAuthorStreaming({ signal: new AbortController().signal, expiresAt: Date.now() + 285000, timeoutMs: 60000, request, observed });
    await vi.advanceTimersByTimeAsync(60250);
    expect((await pending).choices[0].message.content).toBe('exact complete response');
    expect(cancel).toHaveBeenCalledTimes(1);
    expect(observed.mock.calls.find(c => c[0].transportOutcome === 'retry')?.[0]).toMatchObject({ transportTimeoutKind: 'idle', transportChunkCount: 1, transportElapsedMs: 60000 });
    expect(observed.mock.calls.at(-1)?.[0]).toMatchObject({ transportCallCount: 2, transportChunkCount: 1 });
  });
  it('keeps the original owned deadline authoritative even with healthy chunks', async () => {
    vi.useFakeTimers(); const observed = vi.fn();
    const request = vi.fn(async () => new Response(new ReadableStream({ start(controller) {
      controller.enqueue(enc.encode(frame('prefix')));
      setTimeout(() => controller.enqueue(enc.encode(frame('more content'))), 50000);
    } }), { headers: { 'Content-Type': 'text/event-stream' } }));
    const pending = knotAuthorStreaming({ signal: new AbortController().signal, expiresAt: Date.now() + 90000, timeoutMs: 60000, request, observed }).catch(e => e);
    await vi.advanceTimersByTimeAsync(85000);
    expect(await pending).toBeInstanceOf(KnotModelTransportExhausted); expect(request).toHaveBeenCalledTimes(1);
    expect(observed.mock.calls.at(-1)?.[0]).toMatchObject({ transportTimeoutKind: 'owned_deadline', transportElapsedMs: 85000, transportChunkCount: 2 });
  });
  it('finishes at explicit DONE even when the provider keeps the HTTP body open', async () => {
    const cancel = vi.fn(), request = vi.fn(async () => new Response(new ReadableStream({ start(controller) {
      controller.enqueue(enc.encode(frame('{"code":"complete","final":true}', 'stop') + done));
      // Deliberately no close: DONE is the provider terminal boundary.
    }, cancel }), { headers: { 'Content-Type': 'text/event-stream' } }));
    const result = await knotAuthorStreaming({ signal: new AbortController().signal, expiresAt: Date.now() + 285000, timeoutMs: 60000, request, observed: vi.fn() });
    expect(result.choices[0].message.content).toBe('{"code":"complete","final":true}');
    expect(request).toHaveBeenCalledTimes(1);
    expect(cancel).toHaveBeenCalledTimes(1);
  });
  it('Stop races a request that ignores abort and cancels a late response without adopting it', async () => {
    const aborter = new AbortController(), cancel = vi.fn(); let resolve!: (value: Response) => void;
    const request = vi.fn(() => new Promise<Response>(r => { resolve = r; }));
    const pending = knotAuthorStreaming({ signal: aborter.signal, expiresAt: Date.now() + 285000, timeoutMs: 60000, request, observed: vi.fn() }).catch(e => e);
    aborter.abort(); expect((await pending).name).toBe('AbortError');
    resolve(new Response(new ReadableStream({ cancel }), { headers: { 'Content-Type': 'text/event-stream' } }));
    await Promise.resolve(); await Promise.resolve();
    expect(request).toHaveBeenCalledTimes(1); expect(cancel).toHaveBeenCalledTimes(1);
  });
  it('Stop races an idle body reader and does not request another stream', async () => {
    const aborter = new AbortController(), cancel = vi.fn();
    const request = vi.fn(async () => new Response(new ReadableStream({ start(controller) { controller.enqueue(enc.encode(frame('partial'))); }, cancel }), { headers: { 'Content-Type': 'text/event-stream' } }));
    const pending = knotAuthorStreaming({ signal: aborter.signal, expiresAt: Date.now() + 285000, timeoutMs: 60000, request, observed: vi.fn() }).catch(e => e);
    await Promise.resolve(); await Promise.resolve(); aborter.abort();
    expect((await pending).name).toBe('AbortError'); expect(request).toHaveBeenCalledTimes(1);
    await Promise.resolve(); expect(cancel).toHaveBeenCalledTimes(1);
  });
  it.each([
    ['missing-done', frame('complete', 'stop'), 'provider_stream'],
    ['missing-stop', frame('partial') + done, 'provider_stream'],
    ['partial-final-frame', frame('complete', 'stop') + 'data: [DONE]', 'provider_stream'],
    ['trailing-content', frame('one', 'stop') + done + frame('two'), 'provider_stream'],
    ['duplicate-done', frame('complete', 'stop') + done + done, 'provider_stream'],
    ['duplicate-finish', frame('complete', 'stop') + frame('', 'stop') + done, 'provider_stream'],
    ['empty', frame('', 'stop') + done, 'provider_empty'],
    ['tool-envelope', frame('code', 'stop', { tool_calls: [] }) + done, 'provider_tools'],
    ['function-envelope', frame('code', 'stop', { function_call: {} }) + done, 'provider_tools'],
    ['length', frame('partial', 'length') + done, 'provider_finish'],
    ['multiple-choices', 'data: {"choices":[{"index":0,"delta":{}},{"index":1,"delta":{}}]}\n\n' + done, 'provider_choices'],
    ['wrong-index', 'data: {"choices":[{"index":1,"delta":{"content":"code"},"finish_reason":"stop"}]}\n\n' + done, 'provider_choices'],
    ['malformed-json', 'data: {not JSON}\n\n', 'provider_stream'],
    ['array-content', frame(['not a text delta'], 'stop') + done, 'provider_stream'],
    ['error-envelope', 'data: {"error":{"message":"private"}}\n\n', 'provider_stream'],
  ])('rejects %s without transport retry or partial return', async (_name, wire, check) => {
    const request = vi.fn(async () => response(wire)), observed = vi.fn();
    const failure = await knotAuthorStreaming({ signal: new AbortController().signal, expiresAt: Date.now() + 285000, timeoutMs: 60000, request, observed }).catch(e => e);
    expect(failure).toBeInstanceOf(DocumentProgramRejected); expect(failure.detail.check).toBe(check);
    expect(request).toHaveBeenCalledTimes(1); expect(observed.mock.calls.at(-1)?.[0].transportOutcome).toBe('ended');
  });
  it.each(['refusal', 'content_filter'])('does not retry a %s policy boundary', async kind => {
    const request = vi.fn(async () => response(frame('', kind === 'content_filter' ? kind : 'stop', kind === 'refusal' ? { refusal: 'private refusal' } : {}) + done));
    const failure = await knotAuthorStreaming({ signal: new AbortController().signal, expiresAt: Date.now() + 285000, timeoutMs: 60000, request, observed: vi.fn() }).catch(e => e);
    expect(failure).toBeInstanceOf(KnotAuthorPolicyBoundary); expect(request).toHaveBeenCalledTimes(1);
  });
  it.each(['frame', 'content', 'wire', 'utf8', 'non-sse'])('bounds invalid %s transport', async kind => {
    const request = vi.fn(async () => {
      if (kind === 'non-sse') return Response.json({ choices: [] });
      if (kind === 'utf8') return new Response(Uint8Array.of(255), { headers: { 'Content-Type': 'text/event-stream' } });
      if (kind === 'frame') return response(': ' + 'x'.repeat(330000));
      if (kind === 'wire') return response(': keepalive\n\n'.repeat(400000));
      return response(frame('x'.repeat(160001), 'stop') + done);
    });
    await expect(knotAuthorStreaming({ signal: new AbortController().signal, expiresAt: Date.now() + 285000, timeoutMs: 60000, request, observed: vi.fn() })).rejects.toBeInstanceOf(Error);
    expect(request).toHaveBeenCalledTimes(1);
  });
  it.each([402, 429, 520])('retries only retryable HTTP status %s', async status => {
    vi.useFakeTimers(); const error = Object.assign(new Error('http'), { status });
    const request = vi.fn().mockRejectedValueOnce(error).mockResolvedValueOnce(response(frame('complete', 'stop') + done));
    const pending = knotAuthorStreaming({ signal: new AbortController().signal, expiresAt: Date.now() + 285000, timeoutMs: 60000, request, observed: vi.fn() }).catch(e => e);
    await vi.advanceTimersByTimeAsync(250);
    const result = await pending;
    if (status === 520) { expect(result.choices[0].message.content).toBe('complete'); expect(request).toHaveBeenCalledTimes(2); }
    else { expect(result).toBe(error); expect(request).toHaveBeenCalledTimes(1); }
  });
  it('keeps metrics bounded and content-free through the activity projection', () => {
    const facts = { transportCallCount: 3, transportElapsedMs: 60000, transportFirstTokenMs: 12, transportChunkCount: 40, transportMaxIdleMs: 60000, transportTimeoutKind: 'idle', transportStreaming: true };
    expect(safeKnotActivityDetail({ ...facts, prompt: 'private', partialCode: 'private' })).toEqual(facts);
    expect(safeKnotActivityDetail({ transportCallCount: 4, transportElapsedMs: -1, transportFirstTokenMs: NaN, transportChunkCount: 1000001, transportTimeoutKind: 'private' })).toBeUndefined();
  });
});
