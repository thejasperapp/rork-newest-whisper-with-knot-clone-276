import { DocumentProgramRejected } from './knot-document-program';
import { documentShape, type DocumentDiagnostic } from './knot-document-diagnostics';
function invalid(check: 'slice_parse' | 'slice_shape' | 'provider_choices' | 'provider_finish' | 'provider_tools' | 'provider_empty', branch: string, fieldPath: string, expectedShape: string, receivedShape: string, facts: Record<string, number | string> = {}): never {
  const diagnostic: DocumentDiagnostic = { branch, fieldPath, expectedShape, receivedShape, unexplained: false };
  throw new DocumentProgramRejected('document_program_invalid', { check, ...facts, ...diagnostic });
}
function sliceJSON(content: string): unknown {
  try { return JSON.parse(content); } catch { /* Historical code lane permits one unambiguous wrapper. */ }
  const candidates: string[] = [];
  let start = -1, depth = 0, quoted = false, escaped = false;
  for (let i = 0; i < content.length; i++) {
    const c = content[i];
    if (start < 0) { if (c === '{') { start = i; depth = 1; } continue; }
    if (quoted) { if (escaped) escaped = false; else if (c === '\\') escaped = true; else if (c === '"') quoted = false; continue; }
    if (c === '"') quoted = true;
    else if (c === '{') depth++;
    else if (c === '}' && --depth === 0) { candidates.push(content.slice(start, i + 1)); start = -1; }
  }
  if (start >= 0 || candidates.length !== 1) invalid('slice_parse', 'json_wrapper', '$.message.content', 'one_complete_json_object', `complete_objects=${candidates.length};unfinished=${start >= 0 ? 1 : 0}`);
  try { return JSON.parse(candidates[0]); } catch { return invalid('slice_parse', 'json_syntax', '$.message.content', 'valid_json', 'invalid_json'); }
}
export function parsedDocumentSlice(result: unknown, strictWholeJSON = false): unknown {
  const choices = (result as { choices?: { finish_reason?: unknown; message?: { content?: unknown; tool_calls?: unknown } }[] } | null)?.choices;
  if (!Array.isArray(choices) || choices.length !== 1) invalid('provider_choices', 'envelope_choices', '$.choices', 'array(length=1)', documentShape(choices));
  const choice = choices[0], rawFinish = choice?.finish_reason;
  const finishReason = typeof rawFinish === 'string' && ['stop','length','tool_calls','content_filter','function_call','error'].includes(rawFinish) ? rawFinish : rawFinish === undefined ? 'missing' : 'unknown';
  const content = choice?.message?.content;
  const facts = { finishReason, contentBytes: typeof content === 'string' ? new TextEncoder().encode(content).length : 0 };
  if (rawFinish !== 'stop') invalid('provider_finish', 'envelope_finish', '$.choices[0].finish_reason', 'stop', finishReason, facts);
  if (choice?.message?.tool_calls !== undefined) invalid('provider_tools', 'envelope_tools', '$.choices[0].message.tool_calls', 'undefined', documentShape(choice.message.tool_calls), facts);
  if (typeof content !== 'string' || !content.trim()) invalid('provider_empty', 'envelope_content', '$.choices[0].message.content', 'nonblank_string', documentShape(content), facts);
  try {
    if (!strictWholeJSON) return sliceJSON(content);
    const trimmed = content.trim(), fence = /^```(?:json)?\r?\n([\s\S]*?)\r?\n```$/.exec(trimmed);
    try { return JSON.parse(fence ? fence[1] : trimmed); }
    catch { return invalid('slice_parse', 'strict_json_syntax', '$.choices[0].message.content', 'whole_json_or_single_json_fence', 'invalid_json_or_decoration'); }
  } catch (error) {
    if (error instanceof DocumentProgramRejected) throw new DocumentProgramRejected(error.reason, { ...facts, ...error.detail });
    throw error;
  }
}
export function validatedSlice(value: unknown): { code: string; final: boolean } {
  if (!value || typeof value !== 'object' || Array.isArray(value)) invalid('slice_shape', 'slice_object', '$', 'object(code,final)', documentShape(value));
  const slice = value as Record<string, unknown>;
  if (Object.keys(slice).some(key => !['code','final'].includes(key))) invalid('slice_shape', 'slice_keys', '$', 'exact_fields(code,final)', 'unexpected_fields');
  if (typeof slice.code !== 'string' || !slice.code) invalid('slice_shape', 'slice_code', '$.code', 'nonempty_string', documentShape(slice.code));
  if (/\u0000|[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/u.test(slice.code)) invalid('slice_shape', 'slice_unicode', '$.code', 'unicode_without_nul', 'invalid_unicode_or_nul');
  if (typeof slice.final !== 'boolean') invalid('slice_shape', 'slice_final', '$.final', 'boolean', documentShape(slice.final));
  return { code: slice.code, final: slice.final };
}
