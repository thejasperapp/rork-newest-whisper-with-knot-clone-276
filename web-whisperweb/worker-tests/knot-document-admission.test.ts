// @vitest-environment node
import { describe, expect, it, vi } from 'vitest';
vi.mock('cloudflare:workers', () => ({ DurableObject: class {} }));
import { knotDocumentAuthoringReady } from '../../functions/knot-document-admission';
import { documentSkillReadCommand } from '../../functions/knot-document-proof';
import type { ShellWorkflow } from '../../functions/knot-shell';

describe('document authoring prerequisite projection', () => {
  const ready: ShellWorkflow = { parentID: crypto.randomUUID(), rootID: crypto.randomUUID(), sourceMessageID: crypto.randomUUID(), originalRequest: 'Create a PDF', mode: 'Create', documentTask: true, memoryRead: true, indexRead: true, workspaceInspected: true, skills: [documentSkillReadCommand], documentSkillCommand: documentSkillReadCommand, commands: 4, memoryWritten: false };
  it('offers authoring only after a receipt-bound complete prerequisite chain', () => { expect(knotDocumentAuthoringReady(ready)).toBe(true); });
  it.each(['parentID', 'sourceMessageID', 'memoryRead', 'indexRead', 'workspaceInspected', 'skills'] as const)('withholds authoring before %s, without creating an owner or replay', key => {
    const incomplete = { ...ready, [key]: key === 'skills' ? [] : undefined };
    expect(knotDocumentAuthoringReady(incomplete as ShellWorkflow)).toBe(false);
  });
});
