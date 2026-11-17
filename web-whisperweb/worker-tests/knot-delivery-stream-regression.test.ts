// @vitest-environment node
// Synthetic transport fixtures only; no owner/session/model/browser is invoked.
import { describe, expect, it, vi } from 'vitest';
vi.mock('cloudflare:workers', () => ({ DurableObject: class {} }));
import { knotAuthorStreaming, KnotAuthorPolicyBoundary } from '../../functions/knot-author-streaming';
import { DocumentProgramRejected } from '../../functions/knot-document-program';
import { documentAuthoringResponseFormat } from '../../functions/knot-document-authoring';
const text = JSON.stringify({ code: '# exact complete program 🙂', final: true });
const frame = (content: string, extra: Record<string, unknown> = {}) => 'data: ' + JSON.stringify({ choices: [{ index: 0, delta: { content, ...extra }, finish_reason: null }] });
const stream = (wire: string, signal = new AbortController().signal) => knotAuthorStreaming({ signal, expiresAt: Date.now() + 90000, timeoutMs: 85000, request: async () => new Response(wire, { headers: { 'Content-Type': 'text/event-stream' } }), observed: vi.fn() });
describe('file-delivery complete-response regressions', () => {
  it.each(['', '\n', '\r\n', '\n\n'])('accepts a complete final SSE frame at clean EOF: %j', async ending => {
    const result = await stream(frame(text) + ending);
    expect(result.choices[0].message.content).toBe(text);
  });
  it('accepts a complete final DONE field without a trailing newline', async () => {
    const result = await stream(frame(text) + '\n\ndata: [DONE]');
    expect(result.choices[0].message.content).toBe(text);
  });
  it.each([frame(text).slice(0, -1), frame('{"code":"unfinished'), frame(text) + '\n\ndata: {"choices":'])('never salvages truncated frame or response JSON', async wire => {
    await expect(stream(wire)).rejects.toBeInstanceOf(DocumentProgramRejected);
  });
  it('still enforces refusal in an EOF-terminated final frame', async () => {
    await expect(stream(frame(text) + '\n\n' + frame('', { refusal: 'private' }))).rejects.toBeInstanceOf(KnotAuthorPolicyBoundary);
  });
  it('still enforces Stop before adopting a complete response', async () => {
    const controller = new AbortController(); controller.abort();
    await expect(stream(frame(text), controller.signal)).rejects.toHaveProperty('name', 'AbortError');
  });
  it.each([2000, 4000, 8000])('does not advertise the %s-point authoring target as a hard schema ceiling', target => {
    expect(documentAuthoringResponseFormat(target).json_schema.schema.properties.code).not.toHaveProperty('maxLength');
  });
});
