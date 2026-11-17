import { rawContentSlice } from './knot-document-raw-content';
import { parsedDocumentSlice, validatedSlice } from './knot-document-authoring-parse';
import { validatedStructuredPreparation, initialStructuredState, applyLocalVisualPatch, applyLocalContentPatch, structuredSourceCode, type StructuredState } from './knot-document-structured';
import { rejectDocument } from './knot-document-diagnostics';
import { validatedDocumentInvocation } from './knot-document-build';
import type { DocumentPreparation } from './knot-document-program';

/** Private replay descriptor. Never placed in activity, chat or public delivery.
 * No provider call, command execution, capture or storage mutation occurs here. */
export type DocumentReplayContext = {
  version: 'document_author_replay_v1'; preparation: DocumentPreparation; prefix: string; index: number;
  structured: boolean; rawContent?: boolean; sourceContent?: boolean; localPatch: boolean; contentPatch?: boolean; previous?: StructuredState; targets: string[];
};
export function documentResponseSlice(result: unknown, context: DocumentReplayContext): { code: string; final: boolean } {
  const parsed = parsedDocumentSlice(result, context.structured || context.rawContent || context.sourceContent);
  if (context.rawContent || context.sourceContent) {
    if (context.structured || context.rawContent && context.sourceContent || context.localPatch || context.contentPatch) rejectDocument('raw_content_context', '$', 'initial_raw_content', 'mixed_policy');
    return rawContentSlice(parsed, context.preparation, context.prefix, context.index, context.sourceContent);
  }
  if (!context.structured) return validatedSlice(parsed);
  validatedStructuredPreparation(context.preparation, context.prefix, context.index);
  if (context.localPatch && !context.previous) rejectDocument('patch_previous_missing', '$.state', 'verified_previous_state', 'undefined');
  const state: StructuredState = context.localPatch ? (context.contentPatch ? applyLocalContentPatch(context.previous!, parsed, context.targets) : applyLocalVisualPatch(context.previous!, parsed, context.targets)) : initialStructuredState(parsed);
  return { code: structuredSourceCode(state, context.preparation.path), final: true };
}
export function replayDocumentResponse(result: unknown, context: DocumentReplayContext) {
  const slice = documentResponseSlice(result, context);
  const { authoring: _authoring, ...descriptor } = context.preparation;
  return validatedDocumentInvocation({ ...descriptor, code: context.prefix + slice.code });
}
export type PrivateDocumentResponse = {
  // Reassembled exact model content, not an assertion of original raw wire bytes.
  envelope: unknown; complete: boolean; content: string; finishReason?: string; contentBytes?: number;
};
export const rejectedDocumentRecordByteLimit = 2 * 1024 * 1024;
