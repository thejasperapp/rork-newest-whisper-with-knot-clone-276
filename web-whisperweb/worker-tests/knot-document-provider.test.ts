// @vitest-environment node
// Synthetic transport only; no real provider, account, actor or shell.
import { describe, expect, it, vi } from 'vitest';
vi.mock('cloudflare:workers', () => ({ DurableObject: class {} }));
import { documentProviderRequest, documentProviderEnvelope, type DocumentProviderMessage } from '../../functions/knot-document-provider';
import { knotAITransport } from '../../functions/knot-ai-transport';
import { documentAuthoringResponseFormat, parsedDocumentSlice } from '../../functions/knot-document-authoring';
const transport = knotAITransport({ EXPO_PUBLIC_TOOLKIT_URL: 'https://synthetic.invalid/prefix', EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY: 'synthetic-key' })!;
const messages: DocumentProviderMessage[] = [
  { role: 'system', content: 'Original author policy' },
  { role: 'user', content: 'Original requested output 🙂\nall bytes' },
  { role: 'assistant', content: null, tool_calls: [{ id: 'owned', type: 'function', function: { name: 'session_read', arguments: '{}' } }] },
  { role: 'tool', tool_call_id: 'owned', content: JSON.stringify({ stdout: 'Complete reference\n'.repeat(1000), evidence: [{ stderr: 'Complete failed ancestor' }], truncated: false }) },
  { role: 'system', content: 'Final slice policy and exact prefix' },
];
describe('provider-native bounded document authoring', () => {
  it('retains the existing GPT-4o request unchanged', () => {
    const format = documentAuthoringResponseFormat(1500);
    const request = documentProviderRequest(transport, 'openai/gpt-4o', messages, 2500, format);
    expect(request.native).toBe(false);
    expect(request.url).toBe('https://synthetic.invalid/prefix/v2/vercel/v1/chat/completions');
    expect(request.body).toEqual({ model: 'openai/gpt-4o', stream: false, max_tokens: 2500, messages, response_format: format });
    expect(request.promptMessages).toEqual(messages);
  });
  it('uses the native Messages output_config schema without altering any evidence bytes', () => {
    const format = documentAuthoringResponseFormat(750);
    const request = documentProviderRequest(transport, 'anthropic/claude-sonnet-4.6', messages, 2000, format);
    expect(request.native).toBe(true);
    expect(request.url).toBe('https://synthetic.invalid/prefix/v2/vercel/v1/messages');
    expect(request.body).toMatchObject({ model: 'anthropic/claude-sonnet-4.6', stream: false, max_tokens: 2000, output_config: { format: { type: 'json_schema', schema: format.json_schema.schema } } });
    expect(request.body).not.toHaveProperty('response_format');
    expect(request.body).not.toHaveProperty('tools');
    const body = request.body as any;
    expect(body.system).toEqual(messages.filter(m => m.role === 'system').map(m => ({ type: 'text', text: m.content })));
    expect(body.messages).toHaveLength(1);
    const data = body.messages[0].content;
    expect(data.startsWith('COMPLETE AUTHORING EVIDENCE')).toBe(true);
    expect(JSON.parse(data.slice(data.indexOf('\n') + 1))).toEqual(messages.filter(m => m.role !== 'system'));
    expect(request.promptMessages).toEqual([...messages.filter(m => m.role === 'system'), { role: 'user', content: data }]);
    expect(JSON.stringify(body)).not.toContain('synthetic-key');
  });
  it('normalizes only complete native text; the same independent slice parser still runs', () => {
    const envelope = { type: 'message', role: 'assistant', stop_reason: 'end_turn', content: [{ type: 'text', text: JSON.stringify({ code: '# next 🙂\n', final: false }) }], usage: { input_tokens: 23, output_tokens: 14 } };
    const normalized = documentProviderEnvelope(envelope, true);
    expect(parsedDocumentSlice(normalized)).toEqual({ code: '# next 🙂\n', final: false });
    expect(normalized).toMatchObject({ usage: { prompt_tokens: 23, completion_tokens: 14 }, choices: [{ finish_reason: 'stop' }] });
    expect(documentProviderEnvelope(normalized, false)).toBe(normalized);
  });
  it.each(['max_tokens', 'tool_use', 'pause_turn', 'stop_sequence', undefined])('does not adopt incomplete native stop reason %s', reason => {
    const normalized = documentProviderEnvelope({ type: 'message', role: 'assistant', stop_reason: reason, content: [{ type: 'text', text: '{"code":"# incomplete","final":true}' }] }, true);
    expect(() => parsedDocumentSlice(normalized)).toThrow('document_program_invalid');
  });
  it('surfaces native refusal without repair or fallback', () => {
    expect(documentProviderEnvelope({ type: 'message', role: 'assistant', stop_reason: 'refusal', content: [{ type: 'text', text: 'Synthetic refusal' }] }, true)).toMatchObject({ choices: [{ message: { refusal: 'provider_refusal' } }] });
  });
  it.each([
    {}, { type: 'message', role: 'user', stop_reason: 'end_turn', content: [] },
    { type: 'message', role: 'assistant', stop_reason: 'end_turn', content: [{ type: 'tool_use', input: {} }] },
    { type: 'message', role: 'assistant', stop_reason: 'end_turn', content: [{ type: 'text', text: '{}' }, { type: 'text', text: '{}' }] },
    { type: 'message', role: 'assistant', stop_reason: 'end_turn', content: [{ type: 'text', text: '{}' }, { type: 'unknown', text: 'do not trust' }] },
  ])('rejects malformed or mixed native envelope %#', value => {
    expect(() => documentProviderEnvelope(value, true)).toThrow('document_program_invalid');
  });
});
