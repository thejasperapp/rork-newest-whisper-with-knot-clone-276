import { validatedDocumentInvocation, type DocumentInvocation } from './knot-document-build';
import { DocumentProgramRejected, type DocumentPreparation } from './knot-document-program';

/** Fresh raw-document policy. The model authors complete final text as data;
 * the only executable bytes are this fixed, exactly reconstructible writer.
 * No renderer, content repair, newline normalization or historical migration. */
export const rawContentResponseFormat = { type: 'json_schema', json_schema: { name: 'document_raw_content', strict: true, schema: {
  type: 'object', additionalProperties: false, required: ['version', 'content'], properties: {
    version: { type: 'string', enum: ['raw_content_v1'] }, content: { type: 'string', minLength: 1 },
  },
} } };
function invalid(): never {
  throw new DocumentProgramRejected('document_program_invalid', { check: 'slice_shape', branch: 'raw_content', fieldPath: '$', expectedShape: 'complete_raw_content_v1_for_initial_python_final', receivedShape: 'invalid_contract', unexplained: false });
}
export function validatedRawPreparation(preparation: DocumentPreparation, prefix = '', index = 0, source = false): void {
  if (prefix !== '' || index !== 0 || preparation.stage !== (source ? 'source' : 'final') || preparation.interpreter !== 'python3' || preparation.authoring !== 'author') invalid();
  // Includes safe path, requested raw extension and existing program-size guards.
  const { authoring: _authoring, ...descriptor } = preparation;
  validatedDocumentInvocation({ ...descriptor, code: '# awaiting complete raw content\n' });
}
function contentString(value: unknown): string {
  if (!value || typeof value !== 'object' || Array.isArray(value)) invalid();
  const v = value as Record<string, unknown>;
  if (Object.keys(v).length !== 2 || v.version !== 'raw_content_v1' || typeof v.content !== 'string' || !v.content.length || /\u0000|[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/u.test(v.content)) invalid();
  return v.content;
}
export function rawContentCode(value: unknown, path: string): string {
  const content = contentString(value);
  let binary = '';
  for (const byte of new TextEncoder().encode(content)) binary += String.fromCharCode(byte);
  return '# KNOT_RAW_CONTENT_V1\nfrom pathlib import Path\nimport base64\nraw_content_b64=' + JSON.stringify(btoa(binary)) + '\nwith Path(' + JSON.stringify(path) + ').open("xb") as f:\n    f.write(base64.b64decode(raw_content_b64,validate=True))\n';
}
export function rawContentSlice(value: unknown, preparation: DocumentPreparation, prefix: string, index: number, source = false): { code: string; final: boolean } {
  validatedRawPreparation(preparation, prefix, index, source);
  const code = rawContentCode(value, preparation.path);
  const { authoring: _authoring, ...descriptor } = preparation;
  validatedDocumentInvocation({ ...descriptor, code }); // Never shorten to fit.
  return { code, final: true };
}
/** Actor admission independently checks exact writer identity, not a marker or
 * model/caller assertion. Decode only for reconstruction, never for execution. */
export function isRawContentInvocation(invocation: DocumentInvocation, source = false): boolean {
  if (invocation.stage !== (source ? 'source' : 'final') || invocation.interpreter !== 'python3') return false;
  const encoded = /^raw_content_b64="([A-Za-z0-9+/]*={0,2})"$/m.exec(invocation.code)?.[1];
  if (!encoded) return false;
  try {
    const binary = atob(encoded), bytes = Uint8Array.from(binary, c => c.charCodeAt(0));
    const content = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes);
    return rawContentCode({ version: 'raw_content_v1', content }, invocation.path) === invocation.code;
  } catch { return false; }
}
export const sourceContentAuthorInstruction = 'SOURCE CONTENT AUTHORING: Return exactly {"version":"raw_content_v1","content":"..."} with the COMPLETE agent-authored Markdown or self-contained HTML SOURCE text for the declared .md/.html path. This is source DATA, not executable Python/Bash, not a code/final object, not the Office/PDF final and not a summary. Use ordinary JSON escaping ONCE. Preserve all requested content and full reference material; no placeholders, truncation, continuation or invented reads. For a PowerPoint source preserve the exact requested slide count and content in clearly separated sections. This source must receive its owned measurement and complete-source comparison before the distinct requested-format build; source bytes alone are not delivery. The backend writes these exact source bytes exclusively. Never embed conversion/writer code in content.';
export const rawContentAuthorInstruction = 'RAW CONTENT AUTHORING raw_content_v1: Return exactly {"version":"raw_content_v1","content":"..."} with the COMPLETE requested final UTF-8 file text in content. This is DATA, never Python/Bash, never a code/final object or a writer program. Use normal JSON string escaping ONCE: actual line breaks are encoded as \\n in the JSON string, not doubled into literal backslash-n sequences. Preserve intentional literal backslashes, quotes, Unicode, CSV CRLF and all requested content. Markdown must remain actual Markdown; JSON final content must itself be the requested complete valid JSON text. Do not wrap the file content in a code fence unless the file itself requires one. No shortening, placeholders, continuation or invented source reads. The backend writes these exact bytes exclusively and independently compares the complete file before capture.';
