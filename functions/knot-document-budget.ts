import type { ShellWorkflow } from './knot-shell';
import type { DocumentInvocation } from './knot-document-build';
import { rawDocumentFormat } from './knot-document-format';
import { documentQualityShortfallsEligible } from './knot-document-development';
import { remainingShellCommands } from './knot-work-budget';

export function documentSourceApproved(workflow: ShellWorkflow): boolean {
  const source = workflow.documentSource, check = workflow.documentSourceCheck;
  return !!source && (!workflow.documentSourceReview || !!check && check.sourceProposalID === source.proposalID && check.sourceSHA256 === source.source.sha256 && check.verdict === 'pass' && !check.issue && check.observations.length === 0);
}
/** A bounded absent quality verdict is not approval, but cannot block build or
 * original-build continuation. Only this exact measured source's actor-owned
 * two-attempt result qualifies; old opaque errors and absent checks do not. */
export function documentSourceContinuationAllowed(workflow: ShellWorkflow): boolean {
  if (documentSourceApproved(workflow)) return true;
  const source = workflow.documentSource, check = workflow.documentSourceCheck;
  return !!source && !!check && check.sourceProposalID === source.proposalID && check.sourceSHA256 === source.source.sha256 &&
    check.verdict === 'unconfirmed' && !check.issue && check.observations.length === 0 &&
    check.contentCheckAttempts?.length === 2 && check.contentCheckAttempts.every(attempt => attempt.outcome === 'unconfirmed');
}
/** Exhaustion is derived from the owned counter, not a model's request to skip
 * repair. This permits completion with recorded shortfalls, never approval. */
export function documentSourceBuildEligible(workflow: ShellWorkflow): boolean {
  if (documentSourceContinuationAllowed(workflow)) return true;
  const source = workflow.documentSource, check = workflow.documentSourceCheck;
  return workflow.documentQuality === 'quality_v1' && remainingShellCommands(workflow.commands) >= 1 && (workflow.documentRepairPolicy === 'single_patch_v1' && workflow.documentRepairClosed || remainingShellCommands(workflow.commands) <= 2) && !workflow.documentExecution && !workflow.documentProof && !workflow.recovery &&
    !!source && !!check && check.sourceProposalID === source.proposalID && check.sourceSHA256 === source.source.sha256 && documentQualityShortfallsEligible(check);
}
/** A measured source may only be replaced for an actual owned finding or an
 * inspected confirmed failure. A missing verdict is not a reason to re-author. */
export function documentSourceReplacementAllowed(workflow: ShellWorkflow): boolean {
  if (!workflow.documentSource) return true;
  const finding = workflow.documentContentFinding;
  if (workflow.documentRepairPolicy === 'single_patch_v1') return !workflow.documentRepairClosed && !!finding?.sectionIDs?.length && ['document_content_incomplete', 'document_visual_incomplete'].includes(finding.issue);
  return (!!finding && ['document_content_incomplete', 'document_visual_incomplete'].includes(finding.issue) && finding.observations.length > 0) || workflow.recovery?.phase === 'inspected';
}
/** Reserve one complete corrective attempt as well as the normal completion
 * chain. Indispensable complete references can still be read while the minimum
 * completion chain fits; optional learning never spends this reserve. */
export function documentCompletionBudget(workflow: ShellWorkflow) {
  const remaining = remainingShellCommands(workflow.commands);
  const active = workflow.documentPolicy === 'author_v1' && workflow.documentTask === true;
  const raw = !!workflow.documentFormat && workflow.documentFormat.status === 'bound' && rawDocumentFormat(workflow.documentFormat.format);
  const buildReady = !raw && documentSourceBuildEligible(workflow) && !workflow.documentExecution && !workflow.documentProof && !workflow.recovery;
  const requiredSteps = raw ? 1 : buildReady ? 2 : 3;
  const repairReserve = raw ? 1 : 3;
  const repairing = !!workflow.documentContentFinding;
  const canReadReference = remaining > requiredSteps;
  const reserved = active && (repairing || remaining <= requiredSteps + repairReserve);
  const stages: DocumentInvocation['stage'][] = [];
  if (raw) {
    if (remaining >= 1) {
      stages.push('final');
      if (/\.(?:txt|md|html|csv|json)(?=$|[^a-zA-Z0-9_.\/-])/i.test(workflow.originalRequest)) stages.push('existing');
    }
  } else {
    // Projection must not refuse an affordable stage just because later work
    // may not fit. This never waives independent proof or immutable capture.
    // An inspected failure (e.g. a build crash) leaves the approved measured
    // source intact: offer a corrected build instead of forcing a full source
    // rewrite each time (live Excel regression). Admission gates are unchanged.
    const buildRetryReady = !raw && workflow.recovery?.phase === 'inspected' && !!workflow.documentSource && documentSourceBuildEligible(workflow) && !workflow.documentExecution && !workflow.documentProof;
    // A pure build-program crash over that intact source is repaired in the
    // build program; re-authoring the unchanged source only burns the turn.
    const buildCrashOnly = buildRetryReady && workflow.recovery?.failedStage === 'build' && !workflow.documentContentFinding;
    if (remaining >= 1 && !buildCrashOnly && documentSourceReplacementAllowed(workflow)) stages.push('source');
    if (remaining >= 1 && (buildReady || buildRetryReady)) stages.push('build');
    if (remaining >= 2 && !workflow.documentExecution && /\.(?:pdf|docx|xlsx|pptx)(?=$|[^a-zA-Z0-9_.\/-])/i.test(workflow.originalRequest)) stages.push('existing');
  }
  return { remaining, active, reserved, repairing, requiredSteps, repairReserve, canReadReference, stages };
}
/** Admission and projection share the same exception: only an actual full
 * workspace reference read, never optional skill/learning or arbitrary work. */
export function documentReferenceReadAllowed(budget: ReturnType<typeof documentCompletionBudget>, operation: string): boolean {
  return operation === 'workspace_read' && budget.canReadReference;
}
