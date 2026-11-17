import type { DocumentInvocation } from './knot-document-build';
import { rejectDocument, documentShape } from './knot-document-diagnostics';
import type { ShellEvidence, ShellWorkflow } from './knot-shell';

/** Versioned backend-resident content renderer. No model code, CSS or installed
 * utility changes. Old invocations retain their exact original command bytes. */
export type DocumentBlock = { kind: 'paragraph' | 'callout'; text: string } | { kind: 'bullets' | 'steps'; items: string[] } | { kind: 'table'; columns: string[]; rows: string[][] };
export type ContentSection = { id: string; title: string; blocks: DocumentBlock[] };
export type StructuredDocument = { title: string; subtitle: string; sections: ContentSection[] };
export type SectionLayout = 'flow' | 'new_page' | 'compact';
export type StructuredState = { version: 'content_v1'; document: StructuredDocument; layout: Record<string, SectionLayout>; patched: boolean; palette?: 'cream_ink' | 'forest' | 'monochrome' };
const str = { type: 'string', minLength: 1 };
const list = { type: 'array', minItems: 1, items: str };
const block = (properties: Record<string, unknown>) => ({ type: 'object', properties, required: Object.keys(properties), additionalProperties: false });
function contentSchema(tables: boolean) {
  return block({ title: str, subtitle: { type: 'string' }, sections: { type: 'array', minItems: 1, items: block({ id: { type: 'string', pattern: '^[a-z][a-z0-9-]{0,47}$' }, title: str, blocks: { type: 'array', minItems: 1, items: { anyOf: [block({ kind: { type: 'string', enum: ['paragraph', 'callout'] }, text: str }), block({ kind: { type: 'string', enum: ['bullets', 'steps'] }, items: list }), ...(tables ? [block({ kind: { type: 'string', enum: ['table'] }, columns: list, rows: { type: 'array', minItems: 1, items: list } })] : [])] } } }) } });
}
export const structuredDocumentSchema = contentSchema(true);
/** Generation-only narrowing, never a parser repair or a relaxed validator.
 * Ordinary recipes use complete measured lists; an explicitly requested table
 * retains the full table-capable contract. Historic responses are untouched. */
const recipeListOnly = (request: string) => /\brecipes?\b/i.test(request) && !/\b(?:tables?|tabular|columns?|spreadsheets?|matrix)\b/i.test(request);
export function structuredContentSchema(request = '') {
  return block({ version: { type: 'string', enum: ['content_layout_v2'] }, palette: { type: 'string', enum: ['cream_ink', 'forest', 'monochrome'] }, document: recipeListOnly(request) ? contentSchema(false) : structuredDocumentSchema, layout: { type: 'array', items: block({ sectionID: { type: 'string', pattern: '^[a-z][a-z0-9-]{0,47}$' }, layout: { type: 'string', enum: ['flow', 'new_page', 'compact'] } }) } });
}
export const localVisualPatchSchema = block({ patches: { type: 'array', minItems: 1, maxItems: 8, items: block({ sectionID: { type: 'string', pattern: '^[a-z][a-z0-9-]{0,47}$' }, layout: { type: 'string', enum: ['flow', 'new_page', 'compact'] } }) } });
export const localContentPatchSchema = block({ patches: { type: 'array', minItems: 1, maxItems: 8, items: block({ sectionID: { type: 'string', pattern: '^[a-z][a-z0-9-]{0,47}$' }, paragraphs: { type: 'array', minItems: 1, maxItems: 3, items: { type: 'string', minLength: 1, maxLength: 1800 } } }) } });
export function structuredResponseFormat(patch: boolean | 'content', request?: string) { return { type: 'json_schema', json_schema: { name: patch === 'content' ? 'document_section_content_patch' : patch ? 'document_section_layout_patch' : 'document_content', strict: true, schema: patch === 'content' ? localContentPatchSchema : patch ? localVisualPatchSchema : structuredContentSchema(request) } }; }
const object = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object' && !Array.isArray(v);
function keys(v: Record<string, unknown>, expected: string[], path = '$') {
  for (const key of expected) if (!Object.hasOwn(v, key)) rejectDocument('object_required', path + '.' + key, 'required_field', 'undefined');
  if (Object.keys(v).length !== expected.length) rejectDocument('object_keys', path, 'exact_fields(' + expected.join(',') + ')', documentShape(v) + ';unexpected_fields');
}
function text(v: unknown, empty = false, path = '$'): asserts v is string {
  if (typeof v !== 'string') rejectDocument('text_type', path, 'string', documentShape(v));
  if (!empty && !v.trim()) rejectDocument('text_nonblank', path, 'nonblank_string', 'blank_string');
  if (/\u0000|[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/u.test(v)) rejectDocument('text_unicode', path, 'unicode_without_nul', 'invalid_unicode_or_nul');
}
function strings(v: unknown, path = '$'): asserts v is string[] {
  if (!Array.isArray(v) || !v.length) rejectDocument('list_nonempty', path, 'nonempty_array', documentShape(v));
  v.forEach((s, i) => text(s, false, `${path}[${i}]`));
}
export function validatedStructuredPreparation(preparation: { interpreter: string; path: string; stage: string; authoring: string }, prefix = '', index = 0): void {
  if (preparation.stage !== 'source') rejectDocument('structured_stage', '$.preparation.stage', 'source', 'other_stage');
  if (preparation.authoring !== 'author') rejectDocument('structured_authoring', '$.preparation.authoring', 'author', 'other_authoring');
  if (preparation.interpreter !== 'python3') rejectDocument('structured_interpreter', '$.preparation.interpreter', 'python3', 'other_interpreter');
  if (!preparation.path.endsWith('.html')) rejectDocument('structured_path', '$.preparation.path', 'html_extension', 'other_extension');
  if (prefix || index) rejectDocument('structured_prefix', '$.prefix', 'empty_prefix_at_index_zero', 'nonempty_prefix_or_index');
}
export function validatedStructuredDocument(value: unknown): StructuredDocument {
  if (!object(value)) rejectDocument('document_type', '$', 'object', documentShape(value));
  keys(value, ['title', 'subtitle', 'sections']); text(value.title, false, '$.title'); text(value.subtitle, true, '$.subtitle');
  if (!Array.isArray(value.sections) || !value.sections.length) rejectDocument('sections_nonempty', '$.sections', 'nonempty_array', documentShape(value.sections));
  const ids = new Set<string>();
  for (const [i, section] of value.sections.entries()) {
    const path = `$.sections[${i}]`;
    if (!object(section)) rejectDocument('section_type', path, 'object', documentShape(section));
    keys(section, ['id', 'title', 'blocks'], path); text(section.id, false, path + '.id'); text(section.title, false, path + '.title');
    if (!/^[a-z][a-z0-9-]{0,47}$/.test(section.id)) rejectDocument('section_id_format', path + '.id', 'kebab_identifier_1_to_48', 'string_invalid_identifier');
    if (ids.has(section.id)) rejectDocument('section_id_unique', path + '.id', 'unique_identifier', 'duplicate_identifier');
    if (!Array.isArray(section.blocks) || !section.blocks.length) rejectDocument('blocks_nonempty', path + '.blocks', 'nonempty_array', documentShape(section.blocks));
    ids.add(section.id);
    for (const [j, b] of section.blocks.entries()) {
      const bp = `${path}.blocks[${j}]`;
      if (!object(b)) rejectDocument('block_type', bp, 'object', documentShape(b));
      if (b.kind === 'paragraph' || b.kind === 'callout') { keys(b, ['kind', 'text'], bp); text(b.text, false, bp + '.text'); }
      else if (b.kind === 'bullets' || b.kind === 'steps') { keys(b, ['kind', 'items'], bp); strings(b.items, bp + '.items'); }
      else if (b.kind === 'table') {
        keys(b, ['kind', 'columns', 'rows'], bp); strings(b.columns, bp + '.columns');
        if (!Array.isArray(b.rows) || !b.rows.length) rejectDocument('table_rows_nonempty', bp + '.rows', 'nonempty_array', documentShape(b.rows));
        for (const [k, row] of b.rows.entries()) { strings(row, `${bp}.rows[${k}]`); if (row.length !== b.columns.length) rejectDocument('table_row_width', `${bp}.rows[${k}]`, `array(length=${b.columns.length})`, documentShape(row)); }
      } else rejectDocument('block_kind', bp + '.kind', 'paragraph|callout|bullets|steps|table', typeof b.kind === 'string' ? 'string_outside_enum' : documentShape(b.kind));
    }
  }
  return value as unknown as StructuredDocument;
}
/** Fresh content_layout_v2 adds bounded layout vocabulary to initial authoring.
 * Legacy flat content and its deterministic source bytes remain unchanged. */
export function initialStructuredState(value: unknown): StructuredState {
  if (!object(value) || !Object.hasOwn(value, 'version')) return { version: 'content_v1', document: validatedStructuredDocument(value), layout: {}, patched: false };
  keys(value, ['version', 'palette', 'document', 'layout']);
  if (!['cream_ink', 'forest', 'monochrome'].includes(String(value.palette))) rejectDocument('initial_palette_enum', '$.palette', 'cream_ink|forest|monochrome', documentShape(value.palette));
  if (value.version !== 'content_layout_v2') rejectDocument('initial_layout_version', '$.version', 'content_layout_v2', documentShape(value.version));
  const document = validatedStructuredDocument(value.document);
  if (!Array.isArray(value.layout) || value.layout.length > document.sections.length) rejectDocument('initial_layout_count', '$.layout', 'array_up_to_section_count', documentShape(value.layout));
  const layout: Record<string, SectionLayout> = Object.create(null);
  for (const [i, item] of value.layout.entries()) {
    const path = `$.layout[${i}]`;
    if (!object(item)) rejectDocument('initial_layout_type', path, 'object', documentShape(item));
    keys(item, ['sectionID', 'layout'], path);
    if (typeof item.sectionID !== 'string' || !document.sections.some(s => s.id === item.sectionID) || Object.hasOwn(layout, item.sectionID)) rejectDocument('initial_layout_target', path + '.sectionID', 'unique_existing_section', documentShape(item.sectionID));
    if (typeof item.layout !== 'string' || !['flow', 'new_page', 'compact'].includes(item.layout)) rejectDocument('initial_layout_enum', path + '.layout', 'flow|new_page|compact', documentShape(item.layout));
    layout[item.sectionID] = item.layout as SectionLayout;
  }
  return { version: 'content_v1', document, layout, patched: false, palette: value.palette as StructuredState['palette'] };
}
const sectionLayout = (layout: Record<string, SectionLayout>, id: string): SectionLayout => Object.hasOwn(layout, id) ? layout[id] : 'flow';
const escape = (s: string) => s.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);
// Fixed hierarchy; avoid whole-recipe keep-together (the old 17-page failure).
// Headings stay with their first block; long sections/lists/tables may flow.
export const residentContentCSS = `@page{size:A4;margin:19mm 18mm 20mm;@bottom-right{content:counter(page);font:9pt sans-serif;color:#6b7067}}*{box-sizing:border-box}body{font:10.5pt/1.5 Georgia,serif;color:#222b24;background:#fff}header{border-top:7px solid #315744;border-bottom:1px solid #b9c7b7;padding:14pt 0 16pt;margin-bottom:22pt}h1{font-size:30pt;line-height:1.12;margin:0 0 10pt;color:#244632}header p{font:11pt/1.45 sans-serif;color:#576350;margin:0}section{margin:0 0 22pt;break-inside:auto}h2{font:700 19pt/1.2 Georgia,serif;color:#315744;margin:0 0 10pt;break-after:avoid}p{margin:0 0 9pt;orphans:3;widows:3}h2+*{break-before:avoid}ul,ol{margin:0 0 12pt;padding-left:18pt}li{padding-left:3pt;margin:0 0 5pt;orphans:2;widows:2}table{width:100%;border-collapse:collapse;margin:0 0 12pt;font:9.5pt/1.4 sans-serif;table-layout:fixed}thead{display:table-header-group}th,td{text-align:left;vertical-align:top;padding:7pt;border-bottom:1px solid #cdd5ca;overflow-wrap:anywhere}th{background:#edf1e9;color:#315744}tr{break-inside:avoid}.callout{border-left:3px solid #ae853c;background:#f5f2e9;padding:9pt 12pt}.new_page{break-before:page}.compact{margin-bottom:14pt}.compact p,.compact li{margin-bottom:5pt}.compact table th,.compact table td{padding:5pt}`;
function structuredCSS(state: StructuredState): string {
  // Optional fresh-contract palette; absent legacy states keep exact old bytes.
  if (state.palette === 'cream_ink') return residentContentCSS + '@page{background:#fbf5e9}body{background:#fbf5e9;color:#242322}header{border-top-color:#242322;border-bottom-color:#c9bfac}h1,h2,th{color:#242322}th{background:#eee5d4}.callout{background:#eee5d4;border-left-color:#887251}';
  if (state.palette === 'monochrome') return residentContentCSS + 'body,h1,h2,th{color:#222}header{border-top-color:#222;border-bottom-color:#bbb}th,.callout{background:#f3f3f3}.callout{border-left-color:#777}';
  return residentContentCSS;
}
export function renderStructuredDocument(state: StructuredState): string {
  const d = validatedStructuredDocument(state.document);
  const render = (b: DocumentBlock): string => 'text' in b ? `<p${b.kind === 'callout' ? ' class="callout"' : ''}>${escape(b.text)}</p>` : 'items' in b ? `<${b.kind === 'steps' ? 'ol' : 'ul'}>${b.items.map(s => `<li>${escape(s)}</li>`).join('')}</${b.kind === 'steps' ? 'ol' : 'ul'}>` : `<table><thead><tr>${b.columns.map(c => `<th>${escape(c)}</th>`).join('')}</tr></thead><tbody>${b.rows.map(r => `<tr>${r.map(c => `<td>${escape(c)}</td>`).join('')}</tr>`).join('')}</tbody></table>`;
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>${escape(d.title)}</title><style>${structuredCSS(state)}</style></head><body><header><h1>${escape(d.title)}</h1><p>${escape(d.subtitle)}</p></header><main>${d.sections.map(s => `<section id="${s.id}" class="${sectionLayout(state.layout, s.id)}"><h2>${escape(s.title)}</h2>${s.blocks.map(render).join('')}</section>`).join('')}</main></body></html>`;
}
const prefix = '# KNOT_RESIDENT_CONTENT_V1\nfrom pathlib import Path\nimport json\ns=json.loads(';
/** Deterministic writer: the model never outputs Python/HTML/CSS. Content JSON
 * is retained in the immutable invocation for preservation and local patches. */
export function structuredSourceCode(state: StructuredState, path: string): string {
  validatedStructuredDocument(state.document);
  // Content is serialized ONCE. Fixed resident code renders it on execution;
  // generated HTML/code size is never reported as model-generated bytes.
  return prefix + JSON.stringify(JSON.stringify(state)) + `)
from html import escape as e
def render(b):
 if b['kind'] in ('paragraph','callout'):
  return '<p'+(' class="callout"' if b['kind']=='callout' else '')+'>'+e(b['text'])+'</p>'
 if b['kind'] in ('bullets','steps'):
  tag='ol' if b['kind']=='steps' else 'ul'
  return '<'+tag+'>'+''.join('<li>'+e(t)+'</li>' for t in b['items'])+'</'+tag+'>'
 return '<table><thead><tr>'+''.join('<th>'+e(c)+'</th>' for c in b['columns'])+'</tr></thead><tbody>'+''.join('<tr>'+''.join('<td>'+e(c)+'</td>' for c in row)+'</tr>' for row in b['rows'])+'</tbody></table>'
d=s['document']
out='<!doctype html><html lang="en"><head><meta charset="utf-8"><title>'+e(d['title'])+'</title><style>'+${JSON.stringify(structuredCSS(state))}+'</style></head><body><header><h1>'+e(d['title'])+'</h1><p>'+e(d['subtitle'])+'</p></header><main>'
for section in d['sections']:
 out+='<section id="'+section['id']+'" class="'+s['layout'].get(section['id'],'flow')+'"><h2>'+e(section['title'])+'</h2>'+''.join(render(b) for b in section['blocks'])+'</section>'
out+='</main></body></html>'
p=Path(${JSON.stringify(path)})
with p.open("xb") as f:
 f.write(out.encode("utf-8"))
`;
}
export function structuredState(invocation: Pick<DocumentInvocation, 'code' | 'path' | 'stage' | 'interpreter'> | undefined): StructuredState | undefined {
  try {
    if (!invocation || invocation.stage !== 'source' || invocation.interpreter !== 'python3' || !invocation.path.endsWith('.html') || !invocation.code.startsWith(prefix)) return undefined;
    const line = invocation.code.slice(prefix.length).split('\n')[0];
    if (!line.endsWith(')')) return undefined;
    const state: unknown = JSON.parse(JSON.parse(line.slice(0, -1)));
    if (!object(state)) return undefined; keys(state, ['version', 'document', 'layout', 'patched', ...(Object.hasOwn(state, 'palette') ? ['palette'] : [])]);
    if (Object.hasOwn(state, 'palette') && !['cream_ink', 'forest', 'monochrome'].includes(String(state.palette))) return undefined;
    if (state.version !== 'content_v1' || typeof state.patched !== 'boolean' || !object(state.layout)) return undefined;
    const doc = validatedStructuredDocument(state.document);
    if (Object.entries(state.layout).some(([id, layout]) => !doc.sections.some(s => s.id === id) || !['flow', 'new_page', 'compact'].includes(String(layout)))) return undefined;
    return structuredSourceCode(state as unknown as StructuredState, invocation.path) === invocation.code ? state as unknown as StructuredState : undefined;
  } catch { return undefined; }
}
export function latestStructuredState(receipt: ShellEvidence | null): StructuredState | undefined {
  if (!receipt) return undefined;
  const id = receipt.workflow?.documentSource?.proposalID;
  const source = [...receipt.evidence, receipt as unknown as Record<string, unknown>].find(item => item.proposalID === id && item.status === 'completed' && item.exitCode === 0);
  return structuredState(source?.documentInvocation as DocumentInvocation | undefined);
}
export function applyLocalVisualPatch(state: StructuredState, value: unknown, targets: string[]): StructuredState {
  if (state.patched) rejectDocument('patch_already_used', '$.state.patched', 'false', 'true');
  if (!object(value)) rejectDocument('patch_type', '$', 'object', documentShape(value)); keys(value, ['patches']);
  if (!Array.isArray(value.patches) || !value.patches.length || value.patches.length > 8) rejectDocument('patch_count', '$.patches', 'array(length=1_to_8)', documentShape(value.patches));
  const layout = { ...state.layout }, seen = new Set<string>();
  for (const [i, p] of value.patches.entries()) {
    const path = `$.patches[${i}]`;
    if (!object(p)) rejectDocument('patch_item_type', path, 'object', documentShape(p)); keys(p, ['sectionID', 'layout'], path);
    if (typeof p.sectionID !== 'string') rejectDocument('patch_target_type', path + '.sectionID', 'string', documentShape(p.sectionID));
    if (!targets.includes(p.sectionID)) rejectDocument('patch_target_allowed', path + '.sectionID', 'allowed_target', 'unmapped_target');
    if (seen.has(p.sectionID)) rejectDocument('patch_target_unique', path + '.sectionID', 'unique_target', 'duplicate_target');
    if (typeof p.layout !== 'string' || !['flow', 'new_page', 'compact'].includes(p.layout)) rejectDocument('patch_layout_enum', path + '.layout', 'flow|new_page|compact', typeof p.layout === 'string' ? 'string_outside_enum' : documentShape(p.layout));
    if (sectionLayout(layout, p.sectionID) === p.layout) rejectDocument('patch_layout_changed', path + '.layout', 'different_layout', 'unchanged_layout');
    seen.add(p.sectionID); layout[p.sectionID] = p.layout as SectionLayout;
  }
  return { ...state, layout, patched: true };
}
export function validLocalVisualSuccessor(before: StructuredState, after: StructuredState, targets: string[]): boolean {
  if (before.palette !== after.palette || before.patched || !after.patched || JSON.stringify(before.document) !== JSON.stringify(after.document)) return false;
  const changed = after.document.sections.filter(s => sectionLayout(before.layout, s.id) !== sectionLayout(after.layout, s.id)).map(s => s.id);
  return changed.length > 0 && changed.length <= 8 && changed.every(id => targets.includes(id));
}
/** Additive only: old titles, blocks, ordering and layout remain byte-for-byte
 * identical. A patch is at most eight exact sections and 12 KiB, never a file. */
export function applyLocalContentPatch(state: StructuredState, value: unknown, targets: string[]): StructuredState {
  if (state.patched) rejectDocument('patch_already_used', '$.state.patched', 'false', 'true');
  if (!object(value)) rejectDocument('patch_type', '$', 'object', documentShape(value)); keys(value, ['patches']);
  if (new TextEncoder().encode(JSON.stringify(value)).length > 12288) rejectDocument('patch_size', '$', 'at_most_12288_bytes', 'oversized_patch');
  if (!Array.isArray(value.patches) || !value.patches.length || value.patches.length > 8) rejectDocument('patch_count', '$.patches', 'array(length=1_to_8)', documentShape(value.patches));
  const additions = new Map<string, DocumentBlock[]>();
  for (const [i, p] of value.patches.entries()) {
    const path = `$.patches[${i}]`;
    if (!object(p)) rejectDocument('patch_item_type', path, 'object', documentShape(p)); keys(p, ['sectionID', 'paragraphs'], path);
    if (typeof p.sectionID !== 'string' || !targets.includes(p.sectionID) || !state.document.sections.some(s => s.id === p.sectionID) || additions.has(p.sectionID)) rejectDocument('patch_target_allowed', path + '.sectionID', 'unique_allowed_section', 'unmapped_or_duplicate_target');
    strings(p.paragraphs, path + '.paragraphs');
    if (p.paragraphs.length > 3 || p.paragraphs.some(p => p.length > 1800)) rejectDocument('patch_size', path, 'one_to_three_paragraphs_up_to_1800_chars', 'oversized_patch');
    additions.set(p.sectionID, p.paragraphs.map(text => ({ kind: 'paragraph', text })));
  }
  return { ...state, patched: true, document: { ...state.document, sections: state.document.sections.map(s => additions.has(s.id) ? { ...s, blocks: [...s.blocks, ...additions.get(s.id)!] } : s) } };
}
export function validLocalContentSuccessor(before: StructuredState, after: StructuredState, targets: string[]): boolean {
  if (before.palette !== after.palette || before.patched || !after.patched || before.document.title !== after.document.title || before.document.subtitle !== after.document.subtitle || JSON.stringify(before.layout) !== JSON.stringify(after.layout) || before.document.sections.length !== after.document.sections.length) return false;
  const patches: { sectionID: string; paragraphs: string[] }[] = [];
  for (const [i, section] of before.document.sections.entries()) {
    const next = after.document.sections[i];
    if (next.id !== section.id || next.title !== section.title || JSON.stringify(next.blocks.slice(0, section.blocks.length)) !== JSON.stringify(section.blocks)) return false;
    const added = next.blocks.slice(section.blocks.length);
    if (added.some(b => b.kind !== 'paragraph')) return false;
    if (added.length) patches.push({ sectionID: section.id, paragraphs: added.map(b => (b as { text: string }).text) });
  }
  try { return JSON.stringify(applyLocalContentPatch(before, { patches }, targets)) === JSON.stringify(after); } catch { return false; }
}
export function contentSectionTargets(state: StructuredState | undefined, orders: { section: string }[]): string[] {
  if (!state || state.patched || !orders.length) return [];
  const normalize = (s: string) => s.normalize('NFKC').replace(/\s+/g, ' ').trim().toLowerCase();
  const targets = new Set<string>();
  for (const order of orders) {
    const matches = state.document.sections.filter(s => normalize(s.id) === normalize(order.section) || normalize(s.title) === normalize(order.section));
    if (matches.length !== 1) return [];
    targets.add(matches[0].id);
  }
  return targets.size <= 8 ? [...targets] : [];
}
/** Fail closed on ambiguous heading/page association: no guessed patch target.
 * Exact extraction (all pages) is independently hash checked by the caller. */
export function visualSectionTargets(state: StructuredState, finalText: string, issuePages: number[]): string[] {
  if (state.patched || !issuePages.length) return [];
  const pages = finalText.split('\f'), normalize = (s: string) => s.replace(/\s+/g, ' ').trim();
  const headings = state.document.sections.map(s => ({ id: s.id, title: normalize(s.title) }));
  if (new Set(headings.map(s => s.title)).size !== headings.length) return [];
  const normalized = pages.map(normalize);
  // Require every heading exactly once and in document order. A coincidental
  // mention, repeated title or extraction ambiguity must not authorize a patch.
  const located = headings.map(h => ({ ...h, hits: normalized.flatMap((page, i) => {
    const first = page.indexOf(h.title);
    return first < 0 ? [] : [{ page: i + 1, index: first, repeated: page.indexOf(h.title, first + 1) >= 0 }];
  }) }));
  if (located.some(h => h.hits.length !== 1 || h.hits[0].repeated)) return [];
  for (let i = 1; i < located.length; i++) {
    const a = located[i - 1].hits[0], b = located[i].hits[0];
    if (a.page > b.page || a.page === b.page && a.index >= b.index) return [];
  }
  const targets = new Set<string>(); let active: string | undefined;
  for (let i = 0; i < pages.length; i++) {
    const starts = located.filter(h => h.hits[0].page === i + 1);
    if (issuePages.includes(i + 1)) {
      const carries = active && (!starts.length || normalized[i].slice(0, starts[0].hits[0].index).replace(/\d|\s/g, ''));
      if (carries) targets.add(active!);
      starts.forEach(h => targets.add(h.id));
      if (!carries && !starts.length) return [];
    }
    if (starts.length) active = starts[starts.length - 1].id;
  }
  if (issuePages.some(p => !Number.isInteger(p) || p < 1 || p > pages.length) || targets.size > 8) return [];
  return [...targets];
}
export const structuredDocumentContract = 'RESIDENT CONTENT/LAYOUT CONTRACT content_layout_v2 (resident state content_v1) — overrides ALL earlier model-code, authored-CSS, complete-source visual-repair and template-selection directions for this fresh PDF. Select document_prepare stage=source interpreter=python3 authoring=author path=a NEW .html file; the author outputs ONLY structured content JSON, never code, markup or CSS. The versioned resident renderer owns typography, layout and deterministic new source bytes; the pinned knot-doc 2 build consumes that measured HTML using interpreter=knot-doc authoring=measure. Develop every original requested item, measured ingredients, timings, servings, ordered technique, nutrition estimates and useful explanations where relevant; no transport-driven shortening. For visual findings use ONLY the section-layout patch contract, never re-author content or a complete source. At most one local patch; if unpatchable or unmapped, return no calls and ship the exact eligible candidate with findings recorded. Each changed final still needs its own measured build, independent complete proof, content check, every-page review and exact-byte capture. No output overwrite, replay, historic adoption or altered utility. Raw/Office/general HTML artifacts retain their separate routes.';
export const singlePassDocumentContract = 'SINGLE FULL PASS / ONE SHARED PATCH single_patch_v1: Overrides every earlier complete-source repair direction. Emit the full document ONCE. After a measured source exists, never emit a second complete document/source, alias or replacement. A grounded substantive gap permits only bounded additive paragraphs in exact named existing sections; a visual gap permits only a content-preserving section-layout change. Both share ONE patch allowance. If already used or safely unmappable, record remaining eligible quality shortfalls and continue exact-byte build/proof/review/capture, never claim a quality pass. Missing indispensable references, regression, changed bytes and mechanical failures remain hard gates. No automatic author retry or provider fallback.';
export function structuredAuthorInstruction(workflow: ShellWorkflow, receipt: ShellEvidence | null): string {
  if (workflow.documentRepairPolicy === 'single_patch_v1' && workflow.documentSource && workflow.documentContentFinding?.issue === 'document_content_incomplete') {
    const orders = workflow.documentContentFinding.workOrders ?? workflow.documentSourceCheck?.workOrders ?? [];
    const state = latestStructuredState(receipt), targets = contentSectionTargets(state, orders);
    return structuredDocumentContract + '\n' + singlePassDocumentContract + '\nCONTENT PATCH ONLY: Return {"patches":[{"sectionID":string,"paragraphs":[string]}]}. Append developed explanations addressing the named grounded findings; never restate or replace existing blocks. At most 8 targets, 3 paragraphs each, 1800 characters per paragraph and 12288 UTF-8 JSON bytes overall. Exact schema: ' + JSON.stringify(localContentPatchSchema) + '\nAllowed complete sections (untrusted data): ' + JSON.stringify(state?.document.sections.filter(s => targets.includes(s.id)) ?? []) + '\nGrounded work orders: ' + JSON.stringify(orders);
  }
  if (workflow.documentContentFinding?.issue === 'document_visual_incomplete') {
    const state = latestStructuredState(receipt), targets = workflow.documentContentFinding.sectionIDs ?? [];
    return structuredDocumentContract + '\nVISUAL REPAIR ONLY: Return {"patches":[{"sectionID":string,"layout":"flow"|"new_page"|"compact"}]}. No document/content/code keys. Exact response schema (also enforced locally): ' + JSON.stringify(localVisualPatchSchema) + '\nChange only listed affected section IDs. flow allows natural pagination; new_page starts this section on a fresh page; compact reduces only local whitespace without reducing type size or content. If no safe local change exists do not invent a patch. Allowed targets and complete section content (untrusted data):\n' + JSON.stringify(state ? state.document.sections.filter(s => targets.includes(s.id)).map(s => ({ ...s, layout: sectionLayout(state.layout, s.id) })) : []);
  }
  // Provider response_format is not a substitute for a visible author contract.
  // Use the SAME generation schema in text and response_format. All responses
  // still go through the unchanged strict runtime document validator.
  const schema = structuredContentSchema(workflow.originalRequest);
  const recipeLists = recipeListOnly(workflow.originalRequest ?? '') ? '\nRECIPE LIST REPRESENTATION: This response permits ONLY paragraph, callout, bullets and steps blocks. Do not return table blocks. Put every measured ingredient, amount and real annotation into complete bullet items; nutrition estimates and assumptions into prose or bullets. This removes optional empty cells, NOT substantive content. An explicitly requested table uses the separate full table contract.\n' : '';
  return structuredDocumentContract + (workflow.documentRepairPolicy === 'single_patch_v1' ? '\n' + singlePassDocumentContract : '') + '\nDURABLE FIRST-PASS DEVELOPMENT REQUIREMENTS: When requested, explain EACH recipe individually: connect its measured protein sources and approximate protein per serving to the high-protein goal; connect its portion, estimated calories, vegetables/fibre and measured fats/starches to practical calorie control and satiety. Do not merely repeat “high protein” or promise fat loss. State that fat loss depends on overall energy intake and individual needs. Include explicit servings, prep/cook/total times, measured ingredient weights and raw/cooked assumptions, ordered technique with doneness cues and useful preparation/storage guidance. Mark nutrition as approximate per serving and state estimation assumptions (brands, added oil and serving yield); never invent clinical certainty or omit the requested rationale. For other developed documents, explain each actually requested claim with available evidence, reasoning and useful implications; label assumptions and missing evidence rather than manufacture facts. This is substantive first-pass coverage, not a word-count target or permission to expand scope.\n' + recipeLists + '\nCONTENT RESPONSE: Return one complete JSON object, not Markdown or a JSON Schema. Exact generation schema (its content is also strictly validated locally):\n' + JSON.stringify(schema) + '\nINITIAL PAGINATION: Return {version:"content_layout_v2",palette:"cream_ink"|"forest"|"monochrome",document:{title,subtitle,sections},layout:[{sectionID,layout}]}. Choose the palette matching the actual request: cream_ink supplies warm cream paper with dark ink; forest uses green accents on white; monochrome uses black/gray on white. No invented custom CSS. The layout array may be empty; each entry names one unique existing section. The title header already occupies page one. Keep the FIRST section flow (or omit its layout entry), unless the user explicitly requests a separate cover page. Do NOT put new_page on page-one content: it would strand the title on its own page. flow means natural pagination; new_page starts that section on a fresh page; compact reduces local spacing only. Honor explicit requested page assignments in the FIRST PASS with new_page on the first section of each requested later page; never rely on accidental overflow or defer requested pagination to a repair. Keep content concise when requested, but never omit requirements to meet a page count. This initial layout does not consume the one shared patch allowance. Separate headings into sections, keep all required substantive prose/values. STRICT CONTENT SHAPE: Every table row must have exactly the same number of cells as columns. Every column heading and every cell must contain non-whitespace plain text, never an empty string or whitespace-only padding. If an optional annotation has no useful value for some rows, omit an optional column and preserve its substantive notes in the ingredient text or a separate paragraph; alternatively use complete bullet items. Never invent a value or insert a meaningless placeholder to satisfy this rule. Keep every measured ingredient, quantity and substantive note. All paragraph/callout text and list items must also be nonblank; section IDs must be unique stable kebab-case. Before returning, check every row width and every text field, including the last cell of each row. Plain text is escaped by the resident renderer, not interpreted as markup. Complete content in one response; never substitute an outline or shorten to meet a speed goal.\nMEASURED INGREDIENT LISTS: Use complete bullet items rather than a sparse ingredient/amount/optional-notes table unless the member explicitly requests a table. Combine the measured amount, ingredient and any actual annotation in the same item; preserve every quantity and useful preparation note. Example block: ' + JSON.stringify({ kind: 'bullets', items: ['200 g chicken breast — raw weight; diced', '60 g spinach — washed', '5 ml olive oil'] }) + '. This is a representation example, not a recipe to copy or a content limit. Keep full cooking steps, timings, servings, calorie/protein estimates and explanations in their appropriate blocks. For any other optional table field, fold the real annotation into an existing nonblank cell rather than emitting an empty cell.';
}
