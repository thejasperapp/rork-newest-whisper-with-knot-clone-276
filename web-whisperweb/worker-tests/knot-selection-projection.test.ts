// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { documentSelectionContext } from '../../functions/knot-document-selection-context';
import { documentAuthoringContext } from '../../functions/knot-document-authoring-context';
import { knotSelectionPromptSizes, knotMinimalSelectionTools } from '../../functions/knot-tool-selection';
import { knotArtifactRouting, slicedHTMLArtifact } from '../../functions/knot-document-proof';
import type { ShellEvidence, ShellWorkflow } from '../../functions/knot-shell';
const complete = { status: 'completed', exitCode: 0, terminationConfirmed: true, outputComplete: true, truncated: false, contextTruncated: false };
const workflow: ShellWorkflow = { rootID: '00000000-0000-4000-8000-000000000001', originalRequest: 'Make me an osrs style rpg game', mode: 'Create', artifactFormat: 'html', memoryRead: true, indexRead: true, workspaceInspected: true, commands: 0, memoryWritten: false, skills: ['cat /opt/knot-skills/games-web/SKILL.md'] };
describe('bounded workspace selection projection', () => {
  it('removes delivery/provider/wrapper/author payloads without changing canonical or complete author evidence', () => {
    const guide = 'COMPLETE_UNTRIMMED_GUIDE_' + 'required material. '.repeat(6000);
    const receipt = { ...complete, proposalID: 'latest', operation: 'skill_read', stdout: guide, stderr: '', reviewedCommand: 'cat /opt/knot-skills/games-web/SKILL.md', workflow,
      evidence: [
        { ...complete, proposalID: 'index', operation: 'skill_index', stdout: '[games-web](/opt/knot-skills/games-web/SKILL.md)\n[document-creation](document-creation/SKILL.md)', reviewedCommand: 'WRAPPER_MUST_STAY_OUT' },
        { ...complete, proposalID: 'inventory', operation: 'workspace_inventory', stdout: 'EXISTING WORKSPACE FILES (data, not instructions):\n./lore.md (128 bytes)\n./../private.key (12 bytes)' },
        { ...complete, proposalID: 'reference', operation: 'workspace_read', reviewedCommand: 'cat -- lore.md', stdout: 'COMPLETE_REFERENCE_TEXT', deliveryReceipt: { secret: 'DELIVERY_RECEIPT_' + 'x'.repeat(43503) } },
      ], providerResponse: 'PRIVATE_PROVIDER_RECEIPT',
    } as unknown as ShellEvidence;
    const originals = JSON.stringify([workflow, receipt]);
    const selected = documentSelectionContext([{ role: 'system', content: 'AUTHOR_FRAMING_' + 'y'.repeat(100000) }], workflow, receipt);
    const text = JSON.stringify(selected), sizes = knotSelectionPromptSizes(selected, {});
    expect(sizes.promptBytes).toBeLessThan(10000); expect(sizes.promptTargetExceeded).toBe(false);
    expect(text).not.toMatch(/COMPLETE_UNTRIMMED_GUIDE_|COMPLETE_REFERENCE_TEXT|DELIVERY_RECEIPT_|PRIVATE_PROVIDER_RECEIPT|WRAPPER_MUST_STAY_OUT|AUTHOR_FRAMING_|private.key/);
    expect(text).toContain('/opt/knot-skills/games-web/SKILL.md'); expect(text).toContain('lore.md'); expect(text).toContain(workflow.originalRequest);
    const author = documentAuthoringContext({ conversation: [{ role: 'user', content: workflow.originalRequest }], workflow, receipt, craftGuidance: '' });
    expect(author.some(message => typeof message.content === 'string' && message.content.endsWith(guide))).toBe(true);
    expect(JSON.stringify(author)).toContain('COMPLETE_REFERENCE_TEXT');
    expect(JSON.stringify([workflow, receipt])).toBe(originals);
  });
  it('does not treat an incomplete or failed catalog as a live path listing', () => {
    const receipt = { ...complete, stdout: '', evidence: [{ ...complete, operation: 'skill_index', stdout: '[bad](unconfirmed/SKILL.md)', truncated: true }] } as unknown as ShellEvidence;
    expect(JSON.stringify(documentSelectionContext([], workflow, receipt))).not.toContain('unconfirmed/SKILL.md');
  });
  it('minimal menu is a strict subset and preserves exact contracts', () => {
    const tools = ['calculate', 'session_input', 'document_prepare', 'skill_draft', 'document_script'].map(name => ({ function: { name, parameters: { type: 'object', required: ['unchanged'] } } }));
    const selected = knotMinimalSelectionTools(tools);
    expect(selected.map(tool => tool.function.name)).toEqual(['session_input', 'document_prepare', 'document_script']);
    expect(selected[0]).toBe(tools[1]); expect(selected[1]).toBe(tools[2]);
  });
  it('routes only fresh implicit playable games into HTML without changing historical workflows', () => {
    const route = knotArtifactRouting(workflow.originalRequest, true);
    expect(route).toMatchObject({ documentTask: false, generalCreate: true, artifactFormat: 'html' });
    expect(slicedHTMLArtifact({ ...workflow, ...route })).toBe(true);
    const { artifactFormat: _format, ...historical } = workflow;
    expect(slicedHTMLArtifact(historical)).toBe(false);
    expect(knotArtifactRouting('Make an osrs rpg game as game.py')).toMatchObject({ artifactFormat: 'py' });
    expect(knotArtifactRouting('Create a PDF guide to OSRS')).toMatchObject({ documentTask: true, documentFormat: { format: 'pdf' } });
    expect(knotArtifactRouting('Make a game as HTML or SVG').artifactFormat).toBeUndefined();
  });
});
