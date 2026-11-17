// @vitest-environment node
// Synthetic evidence plus isolated stdlib HTML parser only. Never executes the
// generated transport, installed utility, filesystem writer or any renderer.
import { describe, expect, it } from 'vitest';
import { spawnSync } from 'node:child_process';
import { knotDocumentTemplates, selectedDocumentTemplate, templateResidentCommand, verifiedTemplateEvidence, type KnotDocumentTemplate } from '../../functions/knot-document-templates';
import { documentInvocationCommand, type DocumentSource } from '../../functions/knot-document-build';
import { residentDocumentTransport, verifiedResidentDocumentEvidence, knotDocV2SHA256 } from '../../functions/knot-document-resident';

const taskID = '00000000-0000-4000-8000-000000000001';
const source: DocumentSource = { path: 'semantic.html', sha256: 'a'.repeat(64), size: 100, format: 'html' };
const invocation = { stage: 'build' as const, interpreter: 'knot-doc' as const, code: '', path: 'final.pdf' };
const final = { path: 'final.pdf', sha256: 'b'.repeat(64), size: 200, pages: 1, format: 'pdf', proofs: [] };
const templates = Object.keys(knotDocumentTemplates) as KnotDocumentTemplate[];
function fixture(template: KnotDocumentTemplate) {
  const prepared = { path: 'final.template.html', sha256: 'c'.repeat(64), size: 120, format: 'html' };
  const inputs = { design: 'template', template, templateSHA256: knotDocumentTemplates[template], source, preparedSource: prepared, resourcePolicy: 'deny-all-v1', toolSHA256: knotDocV2SHA256 };
  const value = {
    version: 'knot_doc_2_0_0', toolSHA256: knotDocV2SHA256,
    inputs: { design: 'author-v1', houseStyleSHA256: 'd'.repeat(64), toolVersion: '2.0.0', sourceSHA256: prepared.sha256, sourceBytes: prepared.size, sourceFormat: 'html' },
    manifest: { ...final, taskID, toolVersion: '2.0.0', sourceSHA256: prepared.sha256, inputsSHA256: 'e'.repeat(64), proofStageOnly: true, independentVerification: false },
    journal: { path: '.knot-doc/v2/' + taskID + '/journal.jsonl', sha256: 'f'.repeat(64), size: 300 },
    templateEvidence: {
      inputs,
      entries: [
        { state: 'intent', taskID, output: final.path, inputs },
        { state: 'staged', taskID, output: final.path, rendererInputsSHA256: 'e'.repeat(64), rendererJournalSHA256: 'f'.repeat(64), finalSHA256: final.sha256, finalBytes: final.size },
      ] as any[],
      journal: { path: '.knot-doc/templates/' + taskID + '/' + '1'.repeat(64) + '.jsonl', sha256: '2'.repeat(64), size: 400 },
    },
  };
  return structuredClone(value);
}
describe('fresh pinned semantic templates', () => {
  it.each(['def check_source():', "p=path(c['path'])\nassert not p.exists() and p.parent.is_dir(), 'document_output_exists'", 'check_source()\npinned()', 'evidence=dict(version='])('rejects missing or duplicate required adapter marker: %s', marker => {
    const base = documentInvocationCommand(invocation, source, true, residentDocumentTransport('2.0.0', taskID));
    expect(base.split(marker)).toHaveLength(2);
    expect(() => templateResidentCommand(base.replace(marker, '# missing marker'), source, 'guide@1.0.0')).toThrow('invalid_document_template_adapter');
    expect(() => templateResidentCommand(base + '\n' + marker, source, 'guide@1.0.0')).toThrow('invalid_document_template_adapter');
  });
  it('defaults to authored design, not subject-selected house templates', () => {
    for (const request of ['Create recipes and a guide', 'Write a research report', 'Create a cover letter', 'Make an original PDF, not a house template']) expect(selectedDocumentTemplate(request)).toBeUndefined();
    expect(selectedDocumentTemplate('Create recipes using the house template')).toBe('guide@1.0.0');
    expect(selectedDocumentTemplate('Write a report with the report@1.0.0 template')).toBe('report@1.0.0');
    expect(selectedDocumentTemplate('Create a cover letter using a plain template')).toBe('letter@1.0.0');
    expect(selectedDocumentTemplate('Create a report without a template')).toBeUndefined();
  });
  it.each(templates)('keeps fresh parent preparation within transport limits: %s', template => {
    const transport = residentDocumentTransport('2.0.0', taskID, template, false, 'record_v1', 'bounded_v1')!;
    const command = documentInvocationCommand(invocation, source, true, transport, true, true);
    expect(Buffer.byteLength(command)).toBeLessThanOrEqual(12000);
    expect(command).toContain('output_parent_v1');
    const program = command.split("<<'KNOT_RESIDENT_DOCUMENT_INVOKE'\n")[1].split('\nKNOT_RESIDENT_DOCUMENT_INVOKE')[0];
    const result = spawnSync('python3', ['-I', '-c', `compile(${JSON.stringify(program)},'<fixture>','exec')`], { encoding: 'utf8' });
    expect(result.status, result.stderr).toBe(0);
  });
  it.each(templates)('binds semantic/CSS/prepared/renderer/final identities for %s', template => {
    const value = fixture(template), transport = residentDocumentTransport('2.0.0', taskID, template)!;
    expect(verifiedTemplateEvidence(value, source, template)).toBe(true);
    expect(verifiedResidentDocumentEvidence('KNOT_RESIDENT_DOCUMENT_V1 ' + JSON.stringify(value), source, transport, final)).toBe(true);
    const command = documentInvocationCommand(invocation, source, true, transport);
    expect(Buffer.byteLength(command)).toBeLessThanOrEqual(12000);
    expect(command).toContain(knotDocumentTemplates[template]);
    expect(command).toContain("with target.open('xb')");
    expect(command).toContain("outerEntries[0]==dict(state='intent'");
    expect(command).toContain("outerEntries[1]==dict(state='staged'");
    expect(command).toContain("check_semantic(); template_bytes(); check_source()");
    expect(command).not.toContain('--template');
    expect(verifiedResidentDocumentEvidence('KNOT_RESIDENT_DOCUMENT_V1 ' + JSON.stringify(value), source, { ...transport, template: undefined }, final)).toBe(false);
  });
  it.each(templates)('permits the actual HTML renderer null without weakening template integrity: %s', template => {
    const value = fixture(template), transport = residentDocumentTransport('2.0.0', taskID, template, true, 'record_v1')!;
    Object.assign(value.inputs, { houseStyleSHA256: null });
    const accepts = () => verifiedResidentDocumentEvidence('KNOT_RESIDENT_DOCUMENT_V1 ' + JSON.stringify(value), source, transport, final);
    expect(accepts()).toBe(true);
    expect(Buffer.byteLength(documentInvocationCommand(invocation, source, true, transport))).toBeLessThanOrEqual(12000);
    value.templateEvidence.inputs.templateSHA256 = '0'.repeat(64);
    expect(accepts()).toBe(false);
  });
  it.each(['template-pin','semantic-source','prepared-hash','prepared-path','renderer-input','renderer-journal','final-hash','final-size','task','intent','extra-entry','journal-prefix','journal-suffix','journal-traversal','policy','malformed'] as const)('rejects %s mismatch without throwing', change => {
    const value = fixture('guide@1.0.0');
    if (change === 'template-pin') value.templateEvidence.inputs.templateSHA256 = '0'.repeat(64);
    if (change === 'semantic-source') value.templateEvidence.inputs.source.sha256 = '0'.repeat(64);
    if (change === 'prepared-hash') value.templateEvidence.inputs.preparedSource.sha256 = '0'.repeat(64);
    if (change === 'prepared-path') value.templateEvidence.inputs.preparedSource.path = 'other.html';
    if (change === 'renderer-input') value.templateEvidence.entries[1].rendererInputsSHA256 = '0'.repeat(64);
    if (change === 'renderer-journal') value.templateEvidence.entries[1].rendererJournalSHA256 = '0'.repeat(64);
    if (change === 'final-hash') value.templateEvidence.entries[1].finalSHA256 = '0'.repeat(64);
    if (change === 'final-size') value.templateEvidence.entries[1].finalBytes++;
    if (change === 'task') value.templateEvidence.entries[1].taskID = 'foreign';
    if (change === 'intent') value.templateEvidence.entries[0].inputs = {};
    if (change === 'extra-entry') value.templateEvidence.entries.push({});
    if (change === 'journal-prefix') value.templateEvidence.journal.path = value.templateEvidence.journal.path.replace('.knot-doc', 'xknot-doc');
    if (change === 'journal-suffix') value.templateEvidence.journal.path = value.templateEvidence.journal.path.replace('.jsonl', 'xjsonl');
    if (change === 'journal-traversal') value.templateEvidence.journal.path = value.templateEvidence.journal.path.replace('/' + '1'.repeat(64), '/../' + '1'.repeat(64));
    if (change === 'policy') value.templateEvidence.inputs.resourcePolicy = 'allow';
    if (change === 'malformed') value.templateEvidence.entries[0] = null;
    expect(verifiedTemplateEvidence(value, source, 'guide@1.0.0')).toBe(false);
  });
  it('fails safely on absent/malformed metadata and rejects templates on non-HTML or v1', () => {
    for (const value of [null, {}, { templateEvidence: { inputs: {}, entries: [] } }]) expect(verifiedTemplateEvidence(value, source, 'guide@1.0.0')).toBe(false);
    expect(() => documentInvocationCommand(invocation, { ...source, format: 'md' }, true, residentDocumentTransport('2.0.0', taskID, 'guide@1.0.0'))).toThrow('invalid_document_template');
    expect(() => documentInvocationCommand(invocation, source, true, { version: 'knot_doc_1_0_0', taskID, template: 'guide@1.0.0' })).toThrow('invalid_document_template');
  });
  it('runs only the isolated semantic parser against allowed and styled/active fixtures', () => {
    const command = documentInvocationCommand(invocation, source, true, residentDocumentTransport('2.0.0', taskID, 'guide@1.0.0'));
    const parser = command.slice(command.indexOf('from html.parser import HTMLParser'), command.indexOf('def prepare_template():'));
    expect(parser).toContain('class Semantics(HTMLParser):');
    const allowed = '<html><head><title>Guide</title></head><body><section class="recipe"><h1>Soup</h1><p>Cook.</p></section></body></html>';
    const denied = ['<style>p{color:red}</style>', '<script>alert(1)</script>', '<p style="color:red">text</p>', '<font color="red">text</font>', '<link href="https://fixture.invalid/a.css">', '<p onclick="alert(1)">text</p>', '<img src="file:///secret">'];
    const program = 'import re,json\n' + parser + '\ncases=json.loads(' + JSON.stringify(JSON.stringify([allowed, ...denied])) + ')\nresults=[]\nfor text in cases:\n    try:\n        p=Semantics();p.feed(text);p.close();results.append(True)\n    except AssertionError:\n        results.append(False)\nprint(json.dumps(results))\n';
    const result = spawnSync('python3', ['-I', '-c', program], { encoding: 'utf8' });
    expect(result.status, result.stderr).toBe(0);
    expect(JSON.parse(result.stdout)).toEqual([true, ...denied.map(() => false)]);
  });
});
