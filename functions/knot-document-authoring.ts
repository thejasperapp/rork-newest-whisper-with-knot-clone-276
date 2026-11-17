import { dispatchKnotActor, knotWorkspaceID, type KnotShellEnv, type ShellWorkflow } from './knot-shell';
import type { KnotBot } from './knot-agent';
import type { DocumentInvocation } from './knot-document-build';
import { documentCodeCharacterLimit } from './knot-document-limits';
import { validatedDocumentInvocation, InvalidDocumentInvocation } from './knot-document-build';
import { validatedDocumentPreparation, documentProgramSHA256, documentProgramSliceLimit, documentProgramSliceCharacters, documentProgramSliceBytes, DocumentProgramRejected, type DocumentProgramDetail, type DocumentProgramOwner, type DocumentPreparation } from './knot-document-program';
import { validatedSlice } from './knot-document-authoring-parse';
export { parsedDocumentSlice } from './knot-document-authoring-parse';
import { documentDiagnostic } from './knot-document-diagnostics';
import type { DocumentReplayContext, PrivateDocumentResponse } from './knot-document-replay';

// Model authors content, not storage-sized slices. Exact partition follows whole validation.
export { documentAuthoringResponseByteLimit } from './knot-document-limits';
export const documentAuthoringFormat = { type: 'json_schema', json_schema: { name: 'knot_document_slice', strict: true, schema: { type: 'object', properties: { code: { type: 'string', description: 'Nonempty exact executable code continuing the acknowledged prefix. Never raw document text. final=true only when the complete program is finished; otherwise continue in a later response.' }, final: { type: 'boolean' } }, required: ['code', 'final'], additionalProperties: false } } };
export function documentAuthoringResponseFormat(budgetTarget: number) {
  // The model-specific size is a generation/token-budget target, not an
  // integrity bound. A complete legal longer response must not be discarded.
  // Whole-program Unicode/JSON bounds and storage-piece limits remain enforced.
  if (!Number.isSafeInteger(budgetTarget) || budgetTarget < 1 || budgetTarget > documentCodeCharacterLimit) throw new DocumentProgramRejected('document_program_invalid', { check: 'program_shape' });
  return documentAuthoringFormat;
}
export type DocumentSliceRequest = { attempt: number; requestedCharacters: number; repairCheck?: DocumentProgramDetail['check']; schemaHash: string; responseFacts?: Partial<DocumentProgramDetail>; replay?: DocumentReplayContext; privateResponse?: PrivateDocumentResponse };
type Receipt = { id: string; state: 'authoring' | 'sealed'; count: number; prefixSHA256: string; expiresAt: number; slices: { index: number; sha256: string; prefixSHA256: string; final: boolean }[] };
async function receipt(response: Response): Promise<Receipt> {
  const raw = await response.text();
  if (raw.length > 16000) throw new DocumentProgramRejected('document_program_invalid', { check: 'receipt_size' });
  let value: Receipt & { error?: string };
  try { value = JSON.parse(raw); } catch { throw new DocumentProgramRejected('document_program_invalid', { check: 'receipt_parse' }); }
  if (!response.ok) {
    if (value?.error === 'document_program_capacity_exceeded') throw new DocumentProgramRejected(value.error, { check: 'program_size' });
    throw new DocumentProgramRejected('document_program_closed', { check: 'receipt_binding' });
  }
  if (!value || !/^[a-f0-9-]{36}$/.test(value.id) || !Array.isArray(value.slices)) throw new DocumentProgramRejected('document_program_invalid', { check: 'receipt_shape' });
  return value;
}
/** Exact storage partition: no normalization, clipping or semantic boundary. */
function storagePieces(code: string): string[] {
  const pieces: string[] = [];
  let piece = '', points = 0, bytes = 2;
  const encoder = new TextEncoder();
  for (const point of code) {
    const cost = encoder.encode(JSON.stringify(point)).length - 2;
    if (points === documentProgramSliceCharacters || bytes + cost > documentProgramSliceBytes) { pieces.push(piece); piece = ''; points = 0; bytes = 2; }
    piece += point; points++; bytes += cost;
  }
  if (piece) pieces.push(piece);
  return pieces;
}
/** One bounded retry of an uncommitted first author response is safe: no code
 * has reached execution or storage. Actor mutations/uncertain receipts are never
 * retried, and neither policy refusals nor capacity/ownership failures recover. */
export async function authorKnotDocumentProgram(options: {
  env: KnotShellEnv; userID: string; bot: KnotBot; conversationID: string; workflow: ShellWorkflow;
  preparation: unknown; expiresAt: number; signal: AbortSignal; wholeResponseCapacity?: boolean; responseSchema?: unknown;
  next: (preparation: DocumentPreparation, prefix: string, index: number, deadlineMs: number, request: DocumentSliceRequest) => Promise<unknown>;
  // Keep policy/provider boundaries terminal with their original safe reason.
  isTerminalError?: (error: unknown) => boolean;
  observed: (kind: 'document_program_started' | 'document_program_slice' | 'document_program_sealed' | 'document_program_retry' | 'document_program_attempt', facts: { programID: string; sliceCount: number; programSHA256: string } & Partial<DocumentProgramDetail>) => void;
}): Promise<{ invocation: DocumentInvocation; documentProgramID?: string }> {
  const { env, userID, bot, conversationID, workflow, signal } = options;
  const preparation = validatedDocumentPreparation(options.preparation);
  const { authoring: _authoring, ...descriptor } = preparation;
  if (preparation.authoring === 'measure') return { invocation: validatedDocumentInvocation({ ...descriptor, code: '' }) };
  if (workflow.documentRepairPolicy === 'single_patch_v1' && workflow.documentSource && (preparation.stage !== 'source' || workflow.documentRepairClosed || !workflow.documentContentFinding?.sectionIDs?.length)) throw new DocumentProgramRejected('document_program_closed');
  if (!workflow.parentID || !workflow.sourceMessageID) throw new DocumentProgramRejected('document_program_owner_mismatch');
  const requestedCharacters = options.responseSchema ? documentCodeCharacterLimit : options.wholeResponseCapacity ? 8000 : 2000;
  let schema = options.responseSchema ?? documentAuthoringResponseFormat(requestedCharacters).json_schema.schema;
  let schemaHash = await documentProgramSHA256(JSON.stringify(schema));
  const authoringStarted = Date.now(); let authoringResponses = 0, modelResponseBytes = 0, prefix = '';
  const vitals = () => {
    const authoringElapsedMs = Math.max(1, Date.now() - authoringStarted), programBytes = new TextEncoder().encode(prefix).length;
    return { programBytes, modelResponseBytes, authoringResponses, authoringElapsedMs, authoringBytesPerSecond: Math.floor(programBytes * 1000 / authoringElapsedMs) };
  };
  const workspace = await knotWorkspaceID(env, userID, bot, conversationID, signal);
  const owner: DocumentProgramOwner = { workspace, bot, conversationID, rootID: workflow.rootID, parentID: workflow.parentID, sourceMessageID: workflow.sourceMessageID };
  let responseRetryUsed = false;
  let id: string | undefined, handedOff = false, pending: DocumentSliceRequest | undefined, sourceOutputRepair: 'unused' | 'pending' | 'spent' = 'unused';
  let facts: Partial<DocumentProgramDetail> = { schemaHash, expiresAt: options.expiresAt, deadlineSource: 'owned_turn' };
  const check = () => { if (signal.aborted || !Number.isFinite(options.expiresAt) || Date.now() >= options.expiresAt - 5000) throw new DocumentProgramRejected('document_program_closed', { check: 'program_expiry', ...facts }); };
  try {
    check();
    // begin reserves private rejection capacity before any provider request.
    let saved = await receipt(await dispatchKnotActor(env, userID, 'document-program/begin', { owner, preparation, expiresAt: options.expiresAt }, signal));
    id = saved.id;
    let acknowledged = { programID: id, sliceCount: 0, programSHA256: await documentProgramSHA256('') };
    facts = { ...facts, ...acknowledged };
    if (saved.count !== 0 || saved.slices.length !== 0 || saved.state !== 'authoring' || saved.expiresAt !== options.expiresAt || saved.prefixSHA256 !== await documentProgramSHA256('')) throw new DocumentProgramRejected('document_program_changed', { check: 'receipt_binding' });
    const observed = (kind: Parameters<typeof options.observed>[0], detail: Partial<DocumentProgramDetail> = {}) => options.observed(kind, { ...facts, ...detail, programID: id!, sliceCount: saved.count, programSHA256: saved.prefixSHA256, sliceCharacterLimit: documentProgramSliceCharacters, sliceByteLimit: documentProgramSliceBytes, ...vitals() });
    observed('document_program_started');
    while (saved.count < documentProgramSliceLimit) {
      const index = saved.count;
      schema = options.responseSchema ?? documentAuthoringResponseFormat(requestedCharacters).json_schema.schema;
      schemaHash = await documentProgramSHA256(JSON.stringify(schema));
      facts = { schemaHash, ...acknowledged, expiresAt: options.expiresAt, deadlineSource: 'owned_turn', sliceIndex: index, attempt: 1, attempts: 1, requestedCharacters };
      check();
      // Size/rate calibration is telemetry, not an authoring stopwatch. A live
      // response can use the remaining owned lifetime; Stop/expiry/no-replay
      // remain authoritative and never renew on content or retries.
      const deadlineMs = options.expiresAt - Date.now() - 5000;
      if (deadlineMs < 10000) throw new DocumentProgramRejected('document_program_closed', { check: 'program_expiry', ...facts, deadlineMs });
      const started = Date.now(); facts = { ...facts, deadlineMs }; observed('document_program_attempt');
      pending = { attempt: sourceOutputRepair === 'pending' ? 2 : 1, requestedCharacters, schemaHash, ...(sourceOutputRepair === 'pending' ? { repairCheck: 'interpreter_mismatch' as const } : {}) };
      if (sourceOutputRepair === 'pending') sourceOutputRepair = 'spent';
      authoringResponses++;
      let value: unknown;
      try {
        value = await options.next(preparation, prefix, index, deadlineMs, pending);
        // Local response-shape checks belong to the same uncommitted-response
        // retry boundary as transport parsing, never actor append/admission.
        validatedSlice(value);
      }
      catch (error) {
        const safeResponseFailure = error instanceof DocumentProgramRejected && (error.reason === 'document_authoring_timeout' || error.reason === 'document_program_invalid' && ['provider_stream', 'provider_timeout', 'provider_transport', 'slice_parse', 'slice_shape'].includes(String(error.detail?.check)));
        if (saved.count !== 0 || responseRetryUsed || signal.aborted || options.isTerminalError?.(error) || !safeResponseFailure || options.expiresAt - Date.now() < 20000) throw error;
        responseRetryUsed = true;
        // Preserve first-attempt diagnostics before replacing its request. Raw
        // rejected bodies remain private and never enter activity observations.
        modelResponseBytes += pending.responseFacts?.contentBytes ?? 0;
        observed('document_program_retry', { ...pending.responseFacts, ...error.detail, attempt: 2 });
        // Structured content keeps its exact schema; code responses can become
        // smaller continuations, never shorter substantive content.
        const retryCharacters = options.responseSchema ? requestedCharacters : Math.min(requestedCharacters, 4000);
        schema = options.responseSchema ?? documentAuthoringResponseFormat(retryCharacters).json_schema.schema;
        schemaHash = await documentProgramSHA256(JSON.stringify(schema));
        facts = { ...facts, schemaHash, requestedCharacters: retryCharacters, attempt: 2, attempts: 2 };
        pending = { attempt: 2, requestedCharacters: retryCharacters, schemaHash, repairCheck: 'slice_parse' };
        authoringResponses++;
        value = await options.next(preparation, prefix, index, options.expiresAt - Date.now() - 5000, pending);
      }
      finally { facts = { ...facts, ...pending.responseFacts, elapsedMs: Date.now() - started }; modelResponseBytes += pending.responseFacts?.contentBytes ?? 0; }
      check();
      const slice = validatedSlice(value);
      if (index === 0 && /^(?:<!doctype\s+html\b|<html\b)/i.test(slice.code.trimStart())) throw new DocumentProgramRejected('document_program_invalid', { check: 'interpreter_mismatch', branch: 'code_interpreter', fieldPath: '$.code', expectedShape: 'executable_code', receivedShape: 'raw_html', unexplained: false });
      const complete = prefix + slice.code;
      try { validatedDocumentInvocation({ ...descriptor, code: complete }); }
      catch (error) {
        if (error instanceof InvalidDocumentInvocation && error.sizeFacts) throw new DocumentProgramRejected('document_program_capacity_exceeded', { check: 'program_size', ...facts, argumentBytes: error.sizeFacts.argumentBytes, branch: 'invocation_size', fieldPath: '$.arguments', expectedShape: 'bounded_invocation', receivedShape: 'capacity_exceeded', unexplained: false });
        // A source program that writes the Office deliverable itself can never
        // pass source measurement. Nothing was appended yet, so allow exactly one
        // uncommitted re-author of the first response with an explicit correction.
        if (error instanceof InvalidDocumentInvocation && error.fields.includes('arguments.code:sourceOutput')) {
          if (saved.count === 0 && sourceOutputRepair === 'unused') { sourceOutputRepair = 'pending'; pending = undefined; observed('document_program_attempt', { check: 'interpreter_mismatch', branch: 'source_output', expectedShape: 'markdown_or_html_source_writer', receivedShape: 'office_writer', unexplained: false }); continue; }
          throw new DocumentProgramRejected('document_program_invalid', { check: 'interpreter_mismatch', ...facts, branch: 'source_output', fieldPath: '$.code', expectedShape: 'markdown_or_html_source_writer', receivedShape: 'office_writer', unexplained: false });
        }
        if (slice.final || !(error instanceof InvalidDocumentInvocation) || error.fields.length !== 1 || error.fields[0] !== 'arguments.code:nonempty') throw error;
      }
      const pieces = storagePieces(slice.code);
      if (saved.count + pieces.length > documentProgramSliceLimit || !slice.final && saved.count + pieces.length === documentProgramSliceLimit) throw new DocumentProgramRejected('document_program_capacity_exceeded', { check: 'slice_limit', ...facts });
      // Author response accepted. Subsequent failures are actor failures, not body rejections.
      pending = undefined;
      for (const [pieceIndex, code] of pieces.entries()) {
        const storageIndex = saved.count, final = slice.final && pieceIndex === pieces.length - 1, nextPrefix = prefix + code;
        const [prefixSHA256, sha256] = await Promise.all([documentProgramSHA256(nextPrefix), documentProgramSHA256(code)]);
        check();
        const next = await receipt(await dispatchKnotActor(env, userID, 'document-program/append', { owner, id, slice: { index: storageIndex, prefixSHA256: saved.prefixSHA256, code, final } }, signal));
        check();
        if (next.id !== id || next.expiresAt !== options.expiresAt || next.count !== storageIndex + 1 || next.prefixSHA256 !== prefixSHA256 || next.state !== (final ? 'sealed' : 'authoring') || next.slices.length !== storageIndex + 1 || JSON.stringify(next.slices.slice(0, storageIndex)) !== JSON.stringify(saved.slices) || JSON.stringify(next.slices[storageIndex]) !== JSON.stringify({ index: storageIndex, sha256, prefixSHA256, final })) throw new DocumentProgramRejected('document_program_changed', { check: 'receipt_binding' });
        saved = next; prefix = nextPrefix; acknowledged = { programID: id, sliceCount: saved.count, programSHA256: saved.prefixSHA256 }; facts = { ...facts, ...acknowledged, sliceIndex: storageIndex };
        observed(final ? 'document_program_sealed' : 'document_program_slice');
      }
      if (slice.final) { handedOff = true; return { invocation: validatedDocumentInvocation({ ...descriptor, code: prefix }), documentProgramID: id }; }
    }
    throw new DocumentProgramRejected('document_program_capacity_exceeded', { check: 'slice_limit' });
  } catch (error) {
    const rejected = error instanceof DocumentProgramRejected ? error : new DocumentProgramRejected('document_program_invalid', { check: 'slice_shape', ...documentDiagnostic(error, 'author_contract') });
    let retention: Partial<DocumentProgramDetail> = {};
    if (pending) {
      retention = { retentionStatus: pending.privateResponse ? 'failed' : 'not_received' };
      if (id && pending.privateResponse && pending.replay && !signal.aborted) {
        const rejectedBodySHA256 = await documentProgramSHA256(pending.privateResponse.content);
        retention.rejectedBodySHA256 = rejectedBodySHA256;
        try {
          // One immutable mutation only. No uncertain-write retry. The actor
          // rechecks Stop/deletion after hashing; bodies never enter observations.
          const response = await dispatchKnotActor(env, userID, 'document-program/reject', { owner, id, record: { version: 'document_author_rejection_v1', response: pending.privateResponse, context: pending.replay, schema, schemaHash, diagnostic: rejected.detail, facts, rejectedBodySHA256 } }, AbortSignal.any([signal, AbortSignal.timeout(5000)]));
          const saved = await response.json() as { id?: string; rejectedBodySHA256?: string };
          if (response.ok && saved.id === id && saved.rejectedBodySHA256 === rejectedBodySHA256) retention = { rejectionID: id, rejectedBodySHA256, retentionStatus: 'retained' };
        } catch { /* Fail closed; never retry authoring or retention mutation. */ }
      }
    }
    if (options.isTerminalError?.(error)) throw error;
    throw new DocumentProgramRejected(rejected.reason, { ...facts, ...rejected.detail, ...retention, ...vitals() });
  } finally {
    if (id && !handedOff) {
      try { const stopped = await dispatchKnotActor(env, userID, 'document-program/cancel', { owner, id }, AbortSignal.timeout(5000)); await stopped.body?.cancel(); } catch { /* Expiry still prohibits sealing/claiming. */ }
    }
  }
}
