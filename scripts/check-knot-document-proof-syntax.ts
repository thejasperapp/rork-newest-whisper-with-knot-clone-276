// Static-only validation: compile generated Python without executing any of it.
// No network, model calls, member files, droplet operations or behavior tests.
import { attachedShellInput } from '../functions/knot-shell-protocol';
import { validatedDocumentInvocation } from '../functions/knot-document-build';
import { knotDocumentTemplates } from '../functions/knot-document-templates';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { documentProofCommand, documentSkillReadCommand } from '../functions/knot-document-proof';
import { documentInvocationCommand, documentMemoryCommand } from '../functions/knot-document-build';
import { skillDiscoveryCommand, skillDraftReadCommand, skillDraftCommand } from '../functions/knot-skill-drafts';
import type { KnotDocument } from '../functions/knot-documents';
const commands = [
  ...(['md', 'html'] as const).map(format => ['record-only v2 ' + format + ' PDF transport', documentInvocationCommand({ stage: 'build', interpreter: 'knot-doc', code: '', path: 'syntax-record.pdf', title: 'Café — "Notes"', deliveryLabel: 'Recorded style evidence' }, { path: 'syntax-record.' + format, sha256: 'a'.repeat(64), size: 1, format }, true, { version: 'knot_doc_2_0_0', taskID: '00000000-0000-4000-8000-000000000001', styleEvidencePolicy: 'record_v1', ...(format === 'html' ? { designJournal: 'author_css_v1' as const } : {}) })] as const),
  ...Object.keys(knotDocumentTemplates).map(template => ['record-only ' + template + ' template transport', documentInvocationCommand({ stage: 'build', interpreter: 'knot-doc', code: '', path: 'syntax-template.pdf', title: 'Café — "Notes"', deliveryLabel: 'Research report' }, { path: 'syntax-semantic.html', sha256: 'a'.repeat(64), size: 1, format: 'html' }, true, { version: 'knot_doc_2_0_0', taskID: '00000000-0000-4000-8000-000000000001', styleEvidencePolicy: 'record_v1', template: template as keyof typeof knotDocumentTemplates })] as const),
  ['fresh authored CSS journal transport', documentInvocationCommand({ stage: 'build', interpreter: 'knot-doc', code: '', path: 'syntax-authored.pdf', title: 'Café — "Notes"', deliveryLabel: 'Authored report' }, { path: 'syntax-authored.html', sha256: 'a'.repeat(64), size: 1, format: 'html' }, true, { version: 'knot_doc_2_0_0', taskID: '00000000-0000-4000-8000-000000000001', designJournal: 'author_css_v1' })],
  ...Object.keys(knotDocumentTemplates).map(template => ['pinned ' + template + ' template transport', documentInvocationCommand({ stage: 'build', interpreter: 'knot-doc', code: '', path: 'syntax-template.pdf', title: 'Café — "Notes"', deliveryLabel: 'Research report' }, { path: 'syntax-semantic.html', sha256: 'a'.repeat(64), size: 1, format: 'html' }, true, { version: 'knot_doc_2_0_0', taskID: '00000000-0000-4000-8000-000000000001', template: template as keyof typeof knotDocumentTemplates })] as const),
  ['pinned resident PDF transport', documentInvocationCommand({ stage: 'build', interpreter: 'knot-doc', code: '', path: 'syntax-reference.pdf', title: 'Café — "Notes"', deliveryLabel: 'Research report' }, { path: 'syntax-reference.md', sha256: 'a'.repeat(64), size: 1, format: 'md' }, true, { version: 'knot_doc_1_0_0', taskID: '00000000-0000-4000-8000-000000000001' })],
  ...(['md', 'html'] as const).map(format => ['pinned v2 ' + format + ' PDF transport', documentInvocationCommand({ stage: 'build', interpreter: 'knot-doc', code: '', path: 'syntax-v2.pdf', title: 'Café — "Notes"', deliveryLabel: 'Research report' }, { path: 'syntax-v2.' + format, sha256: 'a'.repeat(64), size: 1, format }, true, { version: 'knot_doc_2_0_0', taskID: '00000000-0000-4000-8000-000000000001' })] as const),
  ...(['txt', 'md', 'html', 'csv', 'json'] as const).map(format => ['raw ' + format + ' final framing', documentInvocationCommand({ stage: 'final', interpreter: 'python3', code: '# Static syntax only; never executed.\n', path: 'syntax-reference.' + format, title: 'Café — "Notes"', deliveryLabel: 'Original-format file' })] as const),
  ['raw existing measurement framing', documentInvocationCommand({ stage: 'existing', interpreter: 'python3', code: '', path: 'syntax-reference.md' })],
  ['raw measured completion framing', documentMemoryCommand({ id: 'a'.repeat(64), sourcePath: 'syntax-reference.md', sha256: 'b'.repeat(64), size: 1, pages: 1, format: 'md', contentReview: { status: 'pass' } } as KnotDocument)],
  ['library-first draft discovery', skillDiscoveryCommand],
  ['whole workspace draft read', skillDraftReadCommand('syntax-reference')],
  ['workspace draft create', skillDraftCommand({ name: 'syntax-reference', trigger: 'verified_procedure', content: '---\nname: syntax-reference\ndescription: Static syntax framing only\n---\nNever executed.', memoryNote: '' }, '00000000-0000-4000-8000-000000000001')],
  ['workspace draft amend and note', skillDraftCommand({ name: 'syntax-reference', trigger: 'repaired_failure', content: '---\nname: syntax-reference\ndescription: Static quoted Unicode framing\n---\ncafé — "data" \\ end', memoryNote: '2026-11-11 Static syntax reference only; never executed.' }, '00000000-0000-4000-8000-000000000001', 'a'.repeat(64))],
  ['structured source invocation', documentInvocationCommand({ stage: 'source', interpreter: 'python3', code: '# Syntax reference only; never executed.\n', path: 'deliverables/syntax-reference.md' })],
  ['quoted Unicode source framing', documentInvocationCommand({ stage: 'source', interpreter: 'python3', code: "# Syntax reference only; never executed.\ntext = '''\nKNOT_DOCUMENT_INVOKE\ncafé — quoted \"data\", $(), backslash \\\\n'''\n", path: 'deliverables/syntax-quoted.md' })],
  ['existing final measurement', documentInvocationCommand({ stage: 'existing', interpreter: 'python3', code: '', path: 'deliverables/syntax-reference.pdf' })],
  ['verifier', documentProofCommand({ path: 'deliverables/syntax-reference.pdf', sha256: 'a'.repeat(64), size: 1, format: 'pdf', pages: 1, proofs: [] }, '00000000-0000-4000-8000-000000000001')],
  ['source-aware verifier evidence', documentProofCommand({ path: 'syntax-reference.pdf', sha256: 'a'.repeat(64), size: 1, format: 'pdf', pages: 1, proofs: [] }, '00000000-0000-4000-8000-000000000001', true)],
  ['fresh all-page quality verifier', documentProofCommand({ path: 'syntax-all-pages.pdf', sha256: 'a'.repeat(64), size: 1, format: 'pdf', pages: 25, proofs: [] }, '00000000-0000-4000-8000-000000000001', true, true, true)],
  ['document guide read', documentSkillReadCommand],
  ['agent build invocation', documentInvocationCommand({ stage: 'build', interpreter: 'bash', code: '# Syntax reference only; never executed.\n', path: 'deliverables/syntax-reference.pdf' }, { path: 'deliverables/syntax-reference.md', sha256: 'a'.repeat(64), size: 1, format: 'md' })],
  ['measured document memory', documentMemoryCommand({ id: 'a'.repeat(64), sourcePath: 'deliverables/syntax-reference.pdf', sha256: 'b'.repeat(64), size: 1, pages: 1, format: 'pdf', verification: {} } as KnotDocument)],
  ['structural source with custom labels', documentInvocationCommand({ stage: 'source', interpreter: 'python3', code: '# Syntax reference only; never executed.\n', path: 'syntax-reference.md', title: 'Café — "Notes"', deliveryLabel: 'Research report' }, undefined, true)],
  ['structural build with custom labels', documentInvocationCommand({ stage: 'build', interpreter: 'bash', code: '# Syntax reference only; never executed.\n', path: 'syntax-reference.pdf', title: 'Café — "Notes"', deliveryLabel: 'Research report' }, { path: 'syntax-reference.md', sha256: 'a'.repeat(64), size: 1, format: 'md' }, true)],
  ['structural existing final', documentInvocationCommand({ stage: 'existing', interpreter: 'python3', code: '', path: 'syntax-reference.pdf', title: '', deliveryLabel: '' }, undefined, true)],
  ['structural source-aware labeled verifier', documentProofCommand({ path: 'syntax-reference.pdf', sha256: 'a'.repeat(64), size: 1, format: 'pdf', pages: 1, proofs: [], title: 'Café — "Notes"', deliveryLabel: 'Research report' }, '00000000-0000-4000-8000-000000000001', true, true)],
] as const;
for (const [label, command] of commands) {
  const source = command.slice(command.indexOf('\n') + 1, command.lastIndexOf('\n'));
  const result = spawnSync('python3', ['-I', '-c', 'import ast,sys; ast.parse(sys.stdin.read())'], { input: source, encoding: 'utf-8' });
  if (result.status !== 0) { console.error('Generated ' + label + ' Python syntax: invalid'); process.exit(1); }
  if (new TextEncoder().encode(command).length > 12000) { console.error('Generated ' + label + ' exceeds command budget'); process.exit(1); }
  console.log('Generated ' + label + ' Python syntax and command budget: valid (not executed).');
}
// Full-size programs: compile only the unchanged adapter and measure every
// local encoded hop. Neither authored code nor adapter is executed here.
for (const stage of ['source', 'final'] as const) for (const code of ['#'.repeat(64000), "'".repeat(64000), '🪢'.repeat(17000), '"\\\n'.repeat(10000), '\u0001'.repeat(12000)]) {
  const invocation = validatedDocumentInvocation({ stage, interpreter: 'python3', code, path: 'syntax-full-source.html', title: '', deliveryLabel: '' });
  const command = documentInvocationCommand(invocation);
  const source = command.slice(command.indexOf('\n') + 1, command.lastIndexOf('\n'));
  const syntax = spawnSync('python3', ['-I', '-c', 'import ast,sys; ast.parse(sys.stdin.read())'], { input: source, encoding: 'utf-8' });
  const bytes = (value: string) => new TextEncoder().encode(value).length;
  const proposal = { command, documentInvocation: invocation };
  const reply = '```message\n' + JSON.stringify({ shellProposal: proposal }) + '\n```';
  const sizes = { code: bytes(code), arguments: bytes(JSON.stringify(invocation)), command: bytes(command), input: bytes(JSON.stringify({ data: attachedShellInput(command, 120000, 'a'.repeat(32), true) })), proposal: bytes(JSON.stringify({ proposal })), reply: bytes(reply), frame: bytes('data: ' + JSON.stringify({ type: 'complete', reply }) + '\n\n') };
  if (syntax.status !== 0 || sizes.arguments > 74000 || sizes.command > 160000 || sizes.input > 600000 || sizes.proposal > 1000000 || sizes.frame > 800000) throw new Error('Full-size document transport exceeds supported bound');
  console.log('Full-size ' + stage + ' document adapter syntax/local UTF-8 sizes (not executed): ' + JSON.stringify(sizes));
}
const residentSource = readFileSync(new URL('../tools/knot-doc/v1/knot-doc', import.meta.url), 'utf-8');
const resident = spawnSync('python3', ['-I', '-c', 'import ast,sys; ast.parse(sys.stdin.read())'], { input: residentSource, encoding: 'utf-8' });
if (resident.status !== 0) { console.error('Resident document utility Python syntax: invalid'); process.exit(1); }
console.log('Resident document utility Python syntax: valid (not executed here; on-box installation/acceptance is operator-reported).');
