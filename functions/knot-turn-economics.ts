import { documentArgumentByteLimit } from './knot-document-limits';

/** Historical byte/rate calibration retained for telemetry, not a stage cutoff.
 * Create work shares the platform-bound lifetime below rather than imposing
 * separate authoring/reserve clocks. Neither chunks nor retries renew ownership. */
export const knotTurnEconomics = Object.freeze({
  programByteCeiling: documentArgumentByteLimit,
  calibrationBytes: 31166, calibrationElapsedMs: 151000,
  budgetBytesPerSecond: 200, marginPermille: 1500, completionReserveMs: 360000,
});
/** Classify by the ACTUAL admitted schema/transport, not a guess at content
 * length. PDFs and HTML artifacts retain the full 74KB lane, even for a small
 * ask: assigning them a shorter clock while advertising 74KB is underfunding.
 * Ordinary workspace Create commands have the independent 12KB ceiling. */
export const knotCreationSizeClasses = {
  document_program_74kb: documentArgumentByteLimit,
  workspace_command_12kb: 12000,
} as const;
export type KnotCreationSizeClass = keyof typeof knotCreationSizeClasses;
// A Durable Object alarm is limited to 15 minutes. One shared task deadline
// ends at 14 minutes; the driver gets another 30s to settle receipts/outboxes.
// Per-response authoring/selection must not introduce shorter hidden clocks.
export const knotCreationPlatformBudgetMs = 840000;
export const knotOwnedDriverBudgetMs = 870000;
export const knotFileExecutionBudgetMs = 600000;
export function knotCreationBudget(sizeClass: KnotCreationSizeClass) {
  const programByteCeiling = knotCreationSizeClasses[sizeClass];
  const authoringBudgetMs = Math.ceil(programByteCeiling / knotTurnEconomics.budgetBytesPerSecond * knotTurnEconomics.marginPermille);
  return { ...knotTurnEconomics, sizeClass, programByteCeiling, authoringBudgetMs, turnBudgetMs: knotCreationPlatformBudgetMs };
}
export function knotCreationSizeClass(workflow: { documentTask?: boolean; artifactFormat?: string }): KnotCreationSizeClass {
  return workflow.documentTask || workflow.artifactFormat === 'html' ? 'document_program_74kb' : 'workspace_command_12kb';
}
export const knotCreationBudgetFacts = knotCreationBudget('document_program_74kb');
export const knotAuthoringBudgetMs = knotCreationBudgetFacts.authoringBudgetMs;
export const knotCreationTurnMs = knotCreationBudgetFacts.turnBudgetMs;
export const knotOrdinaryTurnMs = 285000;
export const knotAuthorPromptTargetBytes = 32768;
export type KnotAuthoringVitals = {
  programBytes?: number; modelResponseBytes?: number; authoringResponses?: number; authoringElapsedMs?: number; authoringBytesPerSecond?: number;
  programByteCeiling?: number; budgetBytesPerSecond?: number; marginPermille?: number;
  authoringBudgetMs?: number; completionReserveMs?: number; turnBudgetMs?: number; authoringBasePromptBytes?: number;
  authoringPromptTargetExceeded?: boolean; authoringTotalPromptBytes?: number; authoringPromptOverageBytes?: number;
  authoringReadBytes?: number; authoringDevelopedBytes?: number; authoringDescriptorBytes?: number;
  sizeClass?: KnotCreationSizeClass; turnElapsedMs?: number;
};
