/** Document-only budgets. Ordinary shell commands remain at 12000 UTF-8 bytes.
 * Code is counted in Unicode code points (JSON Schema maxLength); the complete
 * encoded arguments have a separate UTF-8 bound, including JSON escaping.
 * Commands retain their historical bytes: only admission/transport bounds grow.
 * This is NOT sliced authoring and grants no execution or source-reuse authority. */
export const documentCodeCharacterLimit = 64000;
export const documentArgumentByteLimit = 74000;
export const documentCommandByteLimit = 160000;
export const documentSelectionResponseByteLimit = 200000;
export const documentAuthoringResponseByteLimit = 160000; // Reassembled model response, never a 16 KiB cap.
export const documentProposalByteLimit = 1000000;
export const documentInputBodyByteLimit = 600000;
export const documentSizeKeys = ['codeCharacters', 'codeCharacterLimit', 'codeBytes', 'argumentBytes', 'argumentByteLimit', 'commandBytes', 'commandByteLimit'] as const;
export type DocumentSizeFacts = Partial<Record<typeof documentSizeKeys[number], number>>;
const bytes = (value: string) => new TextEncoder().encode(value).length;
export function documentSizeFacts(value: unknown, encoded?: string): DocumentSizeFacts {
  const facts: DocumentSizeFacts = { argumentBytes: bytes(encoded ?? JSON.stringify(value) ?? ''), argumentByteLimit: documentArgumentByteLimit };
  if (value && typeof value === 'object' && 'code' in value && typeof value.code === 'string') {
    facts.codeCharacters = Array.from(value.code).length;
    facts.codeBytes = bytes(value.code);
    facts.codeCharacterLimit = documentCodeCharacterLimit;
  }
  return facts;
}
export function safeDocumentSizeFacts(value: unknown): DocumentSizeFacts | undefined {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return;
  const source = value as Record<string, unknown>, facts: DocumentSizeFacts = {};
  for (const key of documentSizeKeys) if (Number.isSafeInteger(source[key]) && (source[key] as number) >= 0 && (source[key] as number) <= 2000000) facts[key] = source[key] as number;
  return Object.keys(facts).length ? facts : undefined;
}
/** Expanded ingress is only a preliminary bound. The actor MUST regenerate the
 * exact invocation from owned workflow state before saving it. No marker, tool
 * name, or model-supplied workflow alone authorizes extended arbitrary commands. */
export function shellCommandWithinBudget(command: unknown, tool: unknown, documentInvocation?: unknown): command is string {
  return typeof command === 'string' && !!command.trim() && !command.includes('\u0000') && bytes(command) <= (tool === 'document_script' && documentInvocation ? documentCommandByteLimit : 12000);
}
