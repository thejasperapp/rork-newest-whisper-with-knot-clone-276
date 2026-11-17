import { knotAITransport, type KnotAIEnv } from './knot-ai-transport';
import { knotTaskModel } from './knot-task-experience';
import { documentProviderRequest, documentProviderEnvelope } from './knot-document-provider';
import { documentAuthoringResponseFormat, parsedDocumentSlice } from './knot-document-authoring';
import { documentSliceTokenLimit } from './knot-document-authoring-context';
import { documentProgramSHA256, DocumentProgramRejected } from './knot-document-program';
import { knotUpstreamDiagnostic } from './knot-upstream-error';

/** Existing OPERATOR-authenticated diagnostic only. Fixed synthetic prompt and
 * model; accepts no prompt/schema/key/context from the request. No actor, member
 * history, session, shell, retry or cross-provider fallback. Secrets remain in
 * the worker. Only numeric/hash/category observations leave this function. */
export async function inspectKnotDocumentTransport(env: KnotAIEnv, check: 'authoring-chat' | 'authoring-messages' | 'authoring-bound' | 'authoring-beta' | 'authoring-beta-bound'): Promise<Record<string, unknown>> {
  const transport = knotAITransport(env);
  if (!transport) return { configured: false, completed: false };


  const native = check !== 'authoring-chat', beta = check === 'authoring-beta' || check === 'authoring-beta-bound', large = check === 'authoring-bound' || check === 'authoring-beta-bound', started = Date.now();
  const model = knotTaskModel(true, 'creation');
  const base = documentAuthoringResponseFormat(3000);
  const format = { ...base, json_schema: { ...base.json_schema, schema: { ...base.json_schema.schema, properties: { ...base.json_schema.schema.properties, code: { ...base.json_schema.schema.properties.code, pattern: large ? '^[\\s\\S]{1,3000}$' : '^[A-Z]{1,8}$' } } } } };
  const schemaHash = await documentProgramSHA256(JSON.stringify(format.json_schema.schema));
  const prompt = large
    ? 'Synthetic output-format test, no personal data or execution. Return ONLY JSON with code and final. Author a substantive Python program that would write a fictional meal-planning Markdown guide to synthetic.md. At most 3000 Unicode code points of code in THIS response; use bounded continuation, final=false if more remains. Stop inside the writer string if needed: only the outer JSON must close. Nothing will execute. No tool calls.'
    : 'Synthetic schema enforcement test. Return ONLY JSON with code and final. Put the complete uppercase English alphabet ABCDEFGHIJKLMNOPQRSTUVWXYZ in code and final=true. Obey the response schema when this conflicts with its code pattern. No tool or actual execution.';
  const messages = [{ role: 'user' as const, content: prompt }], tokenLimit = large ? documentSliceTokenLimit(3000) : 256;
  const request = native ? documentProviderRequest(transport, model, messages, tokenLimit, format) : { native: false, url: transport.chatURL, body: { model, stream: false, max_tokens: tokenLimit, response_format: format, messages } };
  // Documented pre-GA schema wire form, fixed operator probe only. Do not send
  // both schema fields or infer that the gateway forwards either correctly.
  const { output_config: _gaFormat, ...betaBody } = request.body as typeof request.body & { output_config?: unknown };
  const body = beta ? { ...betaBody, output_format: { type: 'json_schema', schema: format.json_schema.schema } } : request.body;
  const common = { configured: true, check, model, schemaHash, tokenLimit, structuredOutputMode: 'outputFormat', schemaWire: beta ? 'beta_output_format' : native ? 'output_config' : 'response_format', noPersonalData: true, remoteMutationPerformed: false, noAutomaticRetry: true };
  let status: number | undefined;
  try {
    const response = await fetch(request.url, { method: 'POST', redirect: 'manual', headers: { Authorization: 'Bearer ' + transport.token, 'Content-Type': 'application/json', ...(native ? { 'anthropic-version': '2023-06-01' } : {}), ...(beta ? { 'anthropic-beta': 'structured-outputs-2025-11-13' } : {}) }, body: JSON.stringify({ ...body, providerOptions: { anthropic: { structuredOutputMode: 'outputFormat' } } }), signal: AbortSignal.timeout(60000) });
    status = response.status;
    if (!response.ok) return { ...common, status, elapsedMs: Date.now() - started, completed: false, diagnostic: await knotUpstreamDiagnostic(response) };
    if (!response.body) throw new Error('empty');
    const reader = response.body.getReader(), decoder = new TextDecoder(); let raw = '', size = 0;
    try { for (;;) { const chunk = await reader.read(); if (chunk.done) break; size += chunk.value.byteLength; if (size > 50000) throw new Error('size'); raw += decoder.decode(chunk.value, { stream: true }); } raw += decoder.decode(); }
    finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
    const result = documentProviderEnvelope(JSON.parse(raw), native) as { choices?: { finish_reason?: string; message?: { refusal?: string; content?: string } }[]; usage?: { prompt_tokens?: number; completion_tokens?: number } };
    const choice = result.choices?.[0];
    const finishReason = ['stop', 'length', 'tool_calls', 'content_filter', 'unknown'].includes(choice?.finish_reason ?? '') ? choice!.finish_reason : 'unknown';
    const facts = { ...common, status, elapsedMs: Date.now() - started, finishReason, contentBytes: typeof choice?.message?.content === 'string' ? new TextEncoder().encode(choice.message.content).length : 0, ...(Number.isSafeInteger(result.usage?.prompt_tokens) ? { inputTokens: result.usage!.prompt_tokens } : {}), ...(Number.isSafeInteger(result.usage?.completion_tokens) ? { outputTokens: result.usage!.completion_tokens } : {}) };
    if (choice?.message?.refusal) return { ...facts, completed: false, reason: 'model_refusal' };
    let slice;
    try { slice = parsedDocumentSlice(result) as { code?: unknown; final?: unknown }; }
    catch (error) { return { ...facts, completed: false, checkFailure: error instanceof DocumentProgramRejected ? error.detail.check : 'slice_parse' }; }
    const codeCharacters = typeof slice?.code === 'string' ? Array.from(slice.code).length : 0;
    const matchesPattern = typeof slice?.code === 'string' && new RegExp(format.json_schema.schema.properties.code.pattern, 'u').test(slice.code);
    return { ...facts, codeCharacters, matchesPattern, completed: matchesPattern && typeof slice.final === 'boolean' };
  } catch (error) {
    return { ...common, status, elapsedMs: Date.now() - started, completed: false, failureName: error instanceof Error && ['TypeError', 'SyntaxError', 'Error', 'TimeoutError', 'AbortError'].includes(error.name) ? error.name : 'unknown', reason: error instanceof Error && ['TimeoutError', 'AbortError'].includes(error.name) ? 'provider_timeout' : 'transport_or_schema_failure' };
  }
}
