// @vitest-environment node
// Synthetic author-contract regressions only. No provider, shell or capture.
import { describe, expect, it } from 'vitest';
import { documentDiagnostic } from '../../functions/knot-document-diagnostics';
import { structuredAuthorInstruction, structuredDocumentSchema, localVisualPatchSchema, validatedStructuredDocument, renderStructuredDocument, structuredSourceCode, structuredState, type StructuredDocument } from '../../functions/knot-document-structured';
import type { ShellWorkflow, ShellEvidence } from '../../functions/knot-shell';
import { documentResponseSlice } from '../../functions/knot-document-replay';
import { documentInvocationCommand } from '../../functions/knot-document-build';
const fixture = (): StructuredDocument => ({ title: 'Practical meals', subtitle: '', sections: [{ id: 'meal-one', title: 'Lentil bowl', blocks: [{ kind: 'table', columns: ['Ingredient', 'Amount'], rows: [['Lentils, cooked', '150 g'], ['Spinach', '60 g']] }, { kind: 'steps', items: ['Heat the lentils, then stir in the spinach.'] }] }] });
function rejected(value: unknown) {
  try { validatedStructuredDocument(value); } catch (error) { return documentDiagnostic(error, 'test_unclassified'); }
  throw new Error('expected_strict_rejection');
}
describe('structured content author contract', () => {
  it('retains explicit first-pass section page boundaries without consuming a patch', () => {
    const document = fixture();
    document.sections.push({ id: 'schedule', title: 'Weekend schedule', blocks: [{ kind: 'paragraph', text: 'Friday, Saturday and Sunday.' }] });
    const response = { version: 'content_layout_v2', palette: 'cream_ink', document, layout: [{ sectionID: 'schedule', layout: 'new_page' }] };
    const slice = documentResponseSlice({ choices: [{ finish_reason: 'stop', message: { content: JSON.stringify(response) } }] }, { version: 'document_author_replay_v1', preparation: { stage: 'source', interpreter: 'python3', path: 'fresh.html', authoring: 'author' }, prefix: '', index: 0, structured: true, localPatch: false, targets: [] });
    const state = structuredState({ ...slice, stage: 'source', interpreter: 'python3', path: 'fresh.html' })!;
    expect(state.layout).toEqual({ schedule: 'new_page' }); expect(state.patched).toBe(false);
    expect(state.palette).toBe('cream_ink');
    expect(renderStructuredDocument(state)).toContain('@page{background:#fbf5e9}');
    expect(structuredAuthorInstruction({} as ShellWorkflow, null)).toContain('Do NOT put new_page on page-one content');
    expect(renderStructuredDocument(state)).toContain('id="schedule" class="new_page"');
  });
  it('does not authorize palette changes through the single visual patch', async () => {
    const { validLocalVisualSuccessor } = await import('../../functions/knot-document-structured');
    const before = { version: 'content_v1' as const, document: fixture(), layout: {}, patched: false, palette: 'cream_ink' as const };
    const after = { ...before, patched: true, palette: 'monochrome' as const, layout: { 'meal-one': 'compact' as const } };
    expect(validLocalVisualSuccessor(before, after, ['meal-one'])).toBe(false);
  });
  it.each([
    [{ sectionID: 'missing', layout: 'new_page' }],
    [{ sectionID: 'meal-one', layout: 'new_page' }, { sectionID: 'meal-one', layout: 'flow' }],
    [{ sectionID: 'meal-one', layout: 'arbitrary_css' }],
  ])('rejects invalid first-pass layout rather than repairing it', layout => {
    expect(() => documentResponseSlice({ choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({ version: 'content_layout_v2', palette: 'cream_ink', document: fixture(), layout }) } }] }, { version: 'document_author_replay_v1', preparation: { stage: 'source', interpreter: 'python3', path: 'fresh.html', authoring: 'author' }, prefix: '', index: 0, structured: true, localPatch: false, targets: [] })).toThrow();
  });
  it('tells the author the existing strict table constraints before generation', () => {
    const instruction = structuredAuthorInstruction({} as ShellWorkflow, null);
    expect(instruction).toContain('Every table row must have exactly the same number of cells as columns');
    expect(instruction).toContain('Every column heading and every cell must contain non-whitespace plain text');
    expect(instruction).toContain('omit an optional column');
    expect(instruction).toContain('Never invent a value');
    expect(instruction).toContain('no transport-driven shortening');
    expect(instruction).toContain('all required substantive prose/values');
  });
  it('makes the exact full schema visible in author text independently of gateway enforcement', () => {
    const instruction = structuredAuthorInstruction({} as ShellWorkflow, null);
    expect(instruction).toContain(JSON.stringify(structuredDocumentSchema));
    expect(instruction).toContain('MEASURED INGREDIENT LISTS');
    expect(instruction).toContain('Use complete bullet items');
    expect(instruction).toContain('200 g chicken breast — raw weight; diced');
    expect(instruction).toContain('preserve every quantity and useful preparation note');
  });
  it('makes the patch schema visible without inviting content reauthoring', () => {
    const instruction = structuredAuthorInstruction({ documentContentFinding: { issue: 'document_visual_incomplete', sectionIDs: [] } } as unknown as ShellWorkflow, null);
    expect(instruction).toContain(JSON.stringify(localVisualPatchSchema));
    expect(instruction).not.toContain(JSON.stringify(structuredDocumentSchema));
    expect(instruction).toContain('No document/content/code keys');
  });
  it('uses final work orders and the exact owned sections, not stale source orders or supplied target IDs', () => {
    const document = fixture();
    document.sections.push({ id: 'unaffected', title: 'Unchanged serving notes', blocks: [{ kind: 'paragraph', text: 'Retain this exact unaffected content.' }] });
    const state = { version: 'content_v1' as const, document, layout: {}, patched: false };
    const invocation = { stage: 'source' as const, interpreter: 'python3' as const, path: 'owned.html', code: structuredSourceCode(state, 'owned.html') };
    const workflow = { documentRepairPolicy: 'single_patch_v1', documentSource: { source: { path: 'owned.html' }, proposalID: 'owned-source' }, documentSourceCheck: { workOrders: [{ section: 'unaffected', requirements: 'STALE_SOURCE_REPAIR' }] }, documentContentFinding: { issue: 'document_content_incomplete', sectionIDs: ['unaffected'], workOrders: [{ item: 'Lentil explanation', section: 'Lentil bowl', action: 'expand', requirements: 'FINAL_GROUNDED_REPAIR', preserve: [] }] } } as unknown as ShellWorkflow;
    const receipt = { workflow, evidence: [{ proposalID: 'owned-source', status: 'completed', exitCode: 0, outputComplete: true, terminationConfirmed: true, truncated: false, contextTruncated: false, reviewedCommand: documentInvocationCommand(invocation), documentInvocation: invocation, stdout: 'KNOT_DOCUMENT_SOURCE_V1 ' + JSON.stringify({ path: 'owned.html', sha256: 'a'.repeat(64), size: 100, format: 'html' }) }] } as unknown as ShellEvidence;
    const instruction = structuredAuthorInstruction(workflow, receipt);
    expect(instruction).toContain('CONTENT PATCH ONLY'); expect(instruction).toContain('FINAL_GROUNDED_REPAIR');
    expect(instruction).toContain(JSON.stringify(document.sections[0]));
    expect(instruction).not.toContain('STALE_SOURCE_REPAIR'); expect(instruction).not.toContain('Retain this exact unaffected content.');
    expect(instruction).toContain('Missing indispensable references, regression, changed bytes and mechanical failures remain hard gates');
    workflow.documentContentFinding!.workOrders = [];
    expect(structuredAuthorInstruction(workflow, receipt)).toContain('Allowed complete sections (untrusted data): []');
  });
  it.each(['', ' ', '\t\n', '\u00a0', '\u2003'])('still rejects a blank cell %j with its exact path', cell => {
    const value = fixture();
    const table = value.sections[0].blocks[0];
    if (table.kind !== 'table') throw new Error('fixture_table');
    table.rows[1][1] = cell;
    expect(rejected(value)).toEqual({ branch: 'text_nonblank', fieldPath: '$.sections[0].blocks[0].rows[1][1]', expectedShape: 'nonblank_string', receivedShape: 'blank_string', unexplained: false });
  });
  it('still rejects a missing cell instead of silently padding or dropping data', () => {
    const value = fixture(), table = value.sections[0].blocks[0];
    if (table.kind !== 'table') throw new Error('fixture_table');
    table.rows[0].pop();
    expect(rejected(value)).toMatchObject({ branch: 'table_row_width', fieldPath: '$.sections[0].blocks[0].rows[0]', expectedShape: 'array(length=2)', receivedShape: 'array(length=1)' });
  });
  it('preserves a valid complete table through resident source serialization', () => {
    const document = fixture(), before = JSON.stringify(document), state = { version: 'content_v1' as const, document, layout: {}, patched: false };
    expect(validatedStructuredDocument(document)).toBe(document);
    const code = structuredSourceCode(state, 'new-owned.html');
    expect(structuredState({ code, path: 'new-owned.html', stage: 'source', interpreter: 'python3' })?.document).toEqual(document);
    expect(renderStructuredDocument(state)).toContain('<td>150 g</td>');
    expect(JSON.stringify(document)).toBe(before);
  });
});
