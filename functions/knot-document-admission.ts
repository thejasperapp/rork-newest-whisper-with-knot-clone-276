import { requiredKnotShellRead, type ShellWorkflow } from './knot-shell';

/** Projection only; the actor independently revalidates the exact owner and receipts. */
export function knotDocumentAuthoringReady(workflow: ShellWorkflow | undefined): boolean {
  return !!workflow?.parentID && !!workflow.sourceMessageID && workflow.memoryRead === true && workflow.indexRead === true && workflow.workspaceInspected === true && workflow.skills.length > 0 && !requiredKnotShellRead(workflow);
}
