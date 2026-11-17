import type { KnotAuthorTransportVitals } from './knot-author-streaming';
import { safeDocumentDiagnostic, type DocumentDiagnostic } from './knot-document-diagnostics';
import { knotCreationTurnMs, type KnotAuthoringVitals } from './knot-turn-economics';
import type { KnotPromptSections } from './knot-tool-selection';
import { documentScriptTool, validatedDocumentInvocation, InvalidDocumentInvocation, type DocumentInvocation } from './knot-document-build';

// Bounded sliced authoring, not unbounded file upload. Final execution retains
// the historical adapter and the independently bounded complete-program lane.
export const documentProgramSliceCharacters = 24000;
export const documentProgramSliceBytes = 24576; // 24 KiB of exact JSON-encoded code; not a model-call ceiling.
export const documentProgramSliceLimit = 32;
export type DocumentPreparation = Omit<DocumentInvocation, 'code'> & { authoring: 'author' | 'measure' };
export type DocumentProgramOwner = { workspace: string; bot: string; conversationID: string; rootID: string; parentID: string; sourceMessageID: string };
export type DocumentProgram = { id: string; owner: DocumentProgramOwner; preparation: DocumentPreparation; expiresAt: number; state: 'authoring' | 'sealed' | 'claimed' | 'cancelled'; prefixSHA256: string; slices: { index: number; code: string; sha256: string; prefixSHA256: string; final: boolean }[]; proposalID?: string };
export const documentProgramChecks = ['program_state', 'program_shape', 'program_expiry', 'receipt_size', 'receipt_parse', 'receipt_shape', 'receipt_binding', 'slice_shape', 'slice_parse', 'slice_limit', 'program_size', 'provider_choices', 'provider_finish', 'provider_tools', 'provider_empty', 'provider_timeout', 'provider_transport', 'provider_stream', 'interpreter_mismatch'] as const;
export type DocumentProgramDetail = KnotAuthoringVitals & Partial<KnotAuthorTransportVitals> & Partial<DocumentDiagnostic> & { rejectionID?: string; rejectedBodySHA256?: string; retentionStatus?: 'retained' | 'failed' | 'not_received'; completionTokens?: number; promptTokens?: number; tokenLimit?: number; promptSections?: KnotPromptSections; programID?: string; sliceCount?: number; programSHA256?: string; check: typeof documentProgramChecks[number]; sliceIndex?: number; attempt?: number; attempts?: number; finishReason?: string; schemaHash?: string; deadlineMs?: number; elapsedMs?: number; promptBytes?: number; contentBytes?: number; argumentBytes?: number; sliceCharacters?: number; sliceCharacterLimit?: number; sliceByteLimit?: number; requestedCharacters?: number; expiresAt?: number; deadlineSource?: 'owned_turn'; model?: string };
export class DocumentProgramRejected extends Error {
  readonly detail: DocumentProgramDetail;
  constructor(readonly reason: 'document_authoring_timeout' | 'document_program_invalid' | 'document_program_owner_mismatch' | 'document_program_closed' | 'document_program_sequence_mismatch' | 'document_program_capacity_exceeded' | 'document_program_changed', detail: DocumentProgramDetail = { check: reason === 'document_program_invalid' ? 'program_shape' : 'program_state' }) {
    super(reason);
    this.detail = { ...detail, ...(safeDocumentDiagnostic(detail) ?? { branch: detail.check, fieldPath: '$', expectedShape: 'validated_contract', receivedShape: 'unclassified_rejection', unexplained: true }) };
  }
}
export function documentPreparationTool(tool: typeof documentScriptTool) {
  const { code: _code, ...properties } = tool.function.parameters.properties;
  return { ...tool, function: { ...tool.function, name: 'document_prepare', description: 'Choose ONLY the next document stage, interpreter, fresh path, title and delivery label, never code. authoring=author requests separate immutable bounded code slices; authoring=measure is empty-code existing-source/final measurement or pinned knot-doc build. Read required originals completely before choosing. No slice executes until the full program is sealed and independently admitted; preparation is not execution or delivery.', parameters: { ...tool.function.parameters, properties: { ...properties, authoring: { type: 'string', enum: ['author', 'measure'] } }, required: ['stage', 'interpreter', 'path', 'title', 'deliveryLabel', 'authoring'] } } };
}
export function validatedDocumentPreparation(value: unknown): DocumentPreparation {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new InvalidDocumentInvocation(['arguments:type']);
  const { authoring, ...descriptor } = value as Record<string, unknown>;
  if (typeof authoring !== 'string' || !['author', 'measure'].includes(authoring) || Object.hasOwn(descriptor, 'code')) throw new InvalidDocumentInvocation(['arguments:additionalProperties']);
  if (authoring === 'author' && (descriptor.interpreter === 'knot-doc' || descriptor.stage === 'existing')) throw new InvalidDocumentInvocation(['arguments.interpreter:enum']);
  // Validate every descriptor constraint through the existing authoritative
  // invocation validator, without inventing executable authoring content.
  const { code: _code, ...valid } = validatedDocumentInvocation({ ...descriptor, code: authoring === 'author' ? '# awaiting complete authored program\n' : '' });
  return { ...valid, authoring: authoring as 'author' | 'measure' };
}
export const documentProgramOwnerMatches = (a: DocumentProgramOwner, b: DocumentProgramOwner) => (['workspace', 'bot', 'conversationID', 'rootID', 'parentID', 'sourceMessageID'] as const).every(key => a[key] === b[key]);
export async function documentProgramSHA256(code: string): Promise<string> {
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(code))), b => b.toString(16).padStart(2, '0')).join('');
}
export function documentProgramCode(program: DocumentProgram): string { return program.slices.map(slice => slice.code).join(''); }
export function activeDocumentProgram(program: DocumentProgram, owner: DocumentProgramOwner, now: number): void {
  if (!documentProgramOwnerMatches(program.owner, owner)) throw new DocumentProgramRejected('document_program_owner_mismatch');
  if (program.expiresAt <= now || program.state === 'cancelled' || program.state === 'claimed') throw new DocumentProgramRejected('document_program_closed');
}
export async function beginDocumentProgram(owner: DocumentProgramOwner, preparation: unknown, expiresAt: number, now: number): Promise<DocumentProgram> {
  const valid = validatedDocumentPreparation(preparation);
  if (valid.authoring !== 'author' || !Number.isFinite(expiresAt) || expiresAt <= now || expiresAt > now + knotCreationTurnMs) throw new DocumentProgramRejected('document_program_invalid', { check: 'program_expiry', expiresAt: Number.isSafeInteger(expiresAt) ? expiresAt : undefined });
  return { id: crypto.randomUUID(), owner: { ...owner }, preparation: valid, expiresAt, state: 'authoring', prefixSHA256: await documentProgramSHA256(''), slices: [] };
}
export async function appendDocumentProgram(program: DocumentProgram, owner: DocumentProgramOwner, value: unknown, now: number): Promise<DocumentProgram> {
  activeDocumentProgram(program, owner, now);
  if (program.state !== 'authoring') throw new DocumentProgramRejected('document_program_closed');
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new DocumentProgramRejected('document_program_invalid', { check: 'slice_shape', sliceIndex: program.slices.length });
  const v = value as Record<string, unknown>;
  if (Object.keys(v).some(key => !['index', 'prefixSHA256', 'code', 'final'].includes(key)) || typeof v.code !== 'string' || !v.code || v.code.includes('\u0000') || /[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/u.test(v.code) || typeof v.final !== 'boolean') throw new DocumentProgramRejected('document_program_invalid', { check: 'slice_shape', sliceIndex: program.slices.length });
  if (v.index !== program.slices.length || v.prefixSHA256 !== program.prefixSHA256) throw new DocumentProgramRejected('document_program_sequence_mismatch');
  if (program.slices.length >= documentProgramSliceLimit || Array.from(v.code).length > documentProgramSliceCharacters || new TextEncoder().encode(JSON.stringify(v.code)).length > documentProgramSliceBytes) throw new DocumentProgramRejected('document_program_capacity_exceeded');
  const code = documentProgramCode(program) + v.code;
  const { authoring: _authoring, ...descriptor } = program.preparation;
  // Apply the unchanged TOTAL Unicode/JSON bounds on every append, never trim.
  try { validatedDocumentInvocation({ ...descriptor, code }); }
  catch (error) {
    if (error instanceof InvalidDocumentInvocation && error.sizeFacts) throw new DocumentProgramRejected('document_program_capacity_exceeded');
    // An unfinished prefix may be whitespace even for build/final. It is data,
    // not yet an executable invocation; all other constraints still apply.
    if (v.final || !(error instanceof InvalidDocumentInvocation) || error.fields.length !== 1 || error.fields[0] !== 'arguments.code:nonempty') throw error;
  }
  if (v.final && !code.trim()) throw new DocumentProgramRejected('document_program_invalid');
  const [sha256, prefixSHA256] = await Promise.all([documentProgramSHA256(v.code), documentProgramSHA256(code)]);
  return { ...program, slices: [...program.slices, { index: program.slices.length, code: v.code, sha256, prefixSHA256, final: v.final }], prefixSHA256, state: v.final ? 'sealed' : 'authoring' };
}
export function documentProgramInvocation(program: DocumentProgram, owner: DocumentProgramOwner, now: number): DocumentInvocation {
  activeDocumentProgram(program, owner, now);
  if (program.state !== 'sealed' || !program.slices.length || !program.slices.at(-1)?.final) throw new DocumentProgramRejected('document_program_closed');
  const { authoring: _authoring, ...descriptor } = program.preparation;
  return validatedDocumentInvocation({ ...descriptor, code: documentProgramCode(program) });
}
export function claimDocumentProgram(program: DocumentProgram, owner: DocumentProgramOwner, invocation: DocumentInvocation, proposalID: string, now: number): DocumentProgram {
  if (JSON.stringify(documentProgramInvocation(program, owner, now)) !== JSON.stringify(validatedDocumentInvocation(invocation))) throw new DocumentProgramRejected('document_program_changed');
  return { ...program, state: 'claimed', proposalID };
}
export function documentProgramReceipt(program: DocumentProgram) {
  return { id: program.id, state: program.state, count: program.slices.length, prefixSHA256: program.prefixSHA256, expiresAt: program.expiresAt, slices: program.slices.map(({ code: _code, ...receipt }) => receipt) };
}
