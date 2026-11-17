import { knotDocumentTemplates } from './knot-document-templates';
import type { ShellEvidence, ShellResult } from './knot-shell';
import type { KnotDocument, DocumentManifest } from './knot-documents';
import { rawDocumentFormat, documentFormatIssue } from './knot-document-format';
import { residentDocumentCommand, residentDocumentTransport, verifiedResidentDocumentEvidence, type ResidentDocumentTransport } from './knot-document-resident';

import { documentCodeCharacterLimit, documentArgumentByteLimit, documentCommandByteLimit, documentSizeFacts, type DocumentSizeFacts } from './knot-document-limits';

export type DocumentSource = { path: string; sha256: string; size: number; format: 'md' | 'html' };
export type DocumentInvocation = { stage: 'source' | 'build' | 'existing' | 'final'; interpreter: 'python3' | 'bash' | 'knot-doc'; code: string; path: string; title?: string; deliveryLabel?: string };
export type DocumentExecution = { invocation: DocumentInvocation; source?: DocumentSource; sourceProposalID?: string; resident?: ResidentDocumentTransport };
export const safeDocumentPath = (path: unknown): path is string => typeof path === 'string' && path.length <= 240 && /^[a-zA-Z0-9][a-zA-Z0-9_. /-]*$/.test(path) && path.split('/').every(p => !!p && p !== '.' && p !== '..' && !p.startsWith('.'));
/** A filename from memory/inventory never grants reuse. Archives require their full path. */
export function namedExistingDocument(request: string, path: string, requireRetrieval = false): boolean {
  if (!safeDocumentPath(path)) return false;
  // Fresh workflows require positive retrieval intent; a creation/editing ask or
  // a negative filename mention is never permission to adopt an old final.
  // Historical workflows retain their original admission semantics.
  if (requireRetrieval && /\b(?:create|write|make|produce|generate|convert|rebuild|revise|edit|change|update|correct|rewrite|rework|merge|copy|rename|append|add)\b/i.test(request)) return false;
  const archived = path.split('/').some(part => /^archives?(?:$|[-_ ])/i.test(part));
  const names = archived ? [path] : [...new Set([path, path.split('/').pop()!])];
  return names.some(name => {
    const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const mention = new RegExp('(?:^|[^a-zA-Z0-9_./-])' + escaped + '(?=$|[^a-zA-Z0-9_./-])', 'i').exec(request);
    if (!mention) return false;
    if (!requireRetrieval) return true;
    const before = request.slice(Math.max(0, mention.index - 180), mention.index);
    return /\b(?:retrieve|download|resend|re-send|attach|open|show|fetch|send|return|share|give)\b/i.test(before) && !/\b(?:do not|don['’]t|not|never|without|no)\b/i.test(before);
  });
}
export function workspaceReadPath(command: string): string | undefined {
  const read = /^cat -- (?:'([^'\n]+)'|([a-zA-Z0-9_./-]+))$/.exec(command);
  const path = read?.[1] ?? read?.[2];
  return safeDocumentPath(path) && !/^MEMORY\.md$/i.test(path) ? path : undefined;
}
export class InvalidDocumentInvocation extends Error {
  constructor(readonly fields: string[], readonly sizeFacts?: DocumentSizeFacts) { super('invalid_document_invocation'); }
}
export function sourceWritesDeliverable(code: string): boolean {
  return /^[ \t]*(?:from|import)[ \t]+(?:docx|openpyxl|pptx|reportlab|xlsxwriter|fpdf)\b/m.test(code) || /['"][^'"\n]{0,240}\.(?:docx|xlsx|pptx)['"]/i.test(code);
}
export function validatedDocumentInvocation(value: unknown): DocumentInvocation {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new InvalidDocumentInvocation(['arguments:type']);
  const v = value as Record<string, unknown>, fields: string[] = [];
  if (Object.keys(v).some(key => !['stage', 'interpreter', 'code', 'path', 'title', 'deliveryLabel'].includes(key))) fields.push('arguments:additionalProperties');
  for (const key of ['stage', 'interpreter', 'code', 'path']) if (!Object.hasOwn(v, key)) fields.push('arguments.' + key + ':required');
  for (const [key, limit] of [['title', 120], ['deliveryLabel', 48]] as const) if (v[key] !== undefined) {
    if (typeof v[key] !== 'string') fields.push('arguments.' + key + ':type');
    else {
      if (v[key].length > limit) fields.push('arguments.' + key + ':size');
      if (/[\x00-\x1f\x7f]/.test(v[key])) fields.push('arguments.' + key + ':control');
    }
  }
  if (Object.hasOwn(v, 'stage') && !['source', 'build', 'existing', 'final'].includes(String(v.stage))) fields.push('arguments.stage:enum');
  if (Object.hasOwn(v, 'interpreter') && !['python3', 'bash', 'knot-doc'].includes(String(v.interpreter))) fields.push('arguments.interpreter:enum');
  if (Object.hasOwn(v, 'code')) {
    if (typeof v.code !== 'string') fields.push('arguments.code:type');
    else {
      if (v.code.includes('\u0000')) fields.push('arguments.code:control');
      if (Array.from(v.code).length > documentCodeCharacterLimit) fields.push('arguments.code:size');
      if ((v.interpreter === 'knot-doc' || v.stage === 'existing') && v.code !== '') fields.push('arguments.code:empty');
      if (v.interpreter !== 'knot-doc' && ['build', 'final'].includes(String(v.stage)) && !v.code.trim()) fields.push('arguments.code:nonempty');
      // The source stage measures ONLY the declared Markdown/HTML file. A source
      // program that writes the Office deliverable itself always fails that
      // measurement after running, so reject it before dispatch with a field the
      // selection repair explains.
      if (v.stage === 'source' && sourceWritesDeliverable(v.code)) fields.push('arguments.code:sourceOutput');
    }
  }
  if (v.interpreter === 'knot-doc' && v.stage !== 'build') fields.push('arguments.stage:residentBuild');
  if (Object.hasOwn(v, 'path')) {
    if (typeof v.path !== 'string') fields.push('arguments.path:type');
    else {
      if (v.path.length > 240) fields.push('arguments.path:size');
      if (v.path.length <= 240 && !safeDocumentPath(v.path)) fields.push('arguments.path:format');
      if (v.path.split('/').pop()!.length > 164) fields.push('arguments.path:basenameSize');
      if ((v.stage === 'build' || v.stage === 'final' || v.code !== '') && v.path.includes('/') && !v.path.startsWith('deliverables/')) fields.push('arguments.path:directory');
      if (v.interpreter === 'knot-doc' && !v.path.endsWith('.pdf')) fields.push('arguments.path:residentPDF');
      if (!(v.stage === 'source' ? /\.(?:md|html)$/i : v.stage === 'final' ? /\.(?:txt|md|html|csv|json)$/ : v.stage === 'existing' ? /\.(?:pdf|docx|xlsx|pptx|txt|md|html|csv|json)$/i : /\.(?:pdf|docx|xlsx|pptx)$/i).test(v.path)) fields.push('arguments.path:extension');
    }
  }
  const sizeFacts = documentSizeFacts(v);
  if (sizeFacts.argumentBytes! > documentArgumentByteLimit) fields.push('arguments:size');
  if (fields.length) throw new InvalidDocumentInvocation(fields, fields.some(field => field.endsWith(':size')) ? sizeFacts : undefined);
  return { stage: v.stage, interpreter: v.interpreter, code: v.code, path: v.path, ...(v.title !== undefined ? { title: v.title } : {}), ...(v.deliveryLabel !== undefined ? { deliveryLabel: v.deliveryLabel } : {}) } as DocumentInvocation;
}

/** Task-local declared-input identity. Output naming is transport, not a new
 * build. This does not fingerprint undeclared files, installed packages or the
 * environment, so it is a conservative no-repeat guard, not a global cache. */
export function documentBuildIdentity(invocation: DocumentInvocation, source: DocumentSource, resident?: ResidentDocumentTransport): string {
  if (invocation.stage !== 'build') throw new Error('document_build_required');
  const names = [[invocation.path, 'KNOT_DECLARED_OUTPUT'], [source.path, 'KNOT_MEASURED_SOURCE']] as const;
  // Longest first avoids a source name that is a prefix of the output name.
  const escaped = [...names].sort((a,b) => b[0].length - a[0].length);
  const pattern = new RegExp(escaped.map(([name]) => name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|'), 'g');
  const code = invocation.code.replace(pattern, name => names.find(pair => pair[0] === name)![1]);
  return JSON.stringify({ version: 1, sourceSHA256: source.sha256, sourceBytes: source.size, sourceFormat: source.format,
    format: invocation.path.split('.').pop()!.toLowerCase(), interpreter: invocation.interpreter, code, ...(resident?.template ? { template: resident.template, templateSHA256: knotDocumentTemplates[resident.template] } : {}) });
}

/** Invocation/measurement ONLY. Content, layout and conversion code are supplied
 * live by the agent. No renderer imports, document template or build fallback.
 * JSON is data within a backend-owned heredoc; model code never reaches Bash
 * outside the explicitly selected child interpreter. Not an OS sandbox. */
// Optional timing version preserves byte-identical reconstruction of legacy receipts.
export function documentInvocationCommand(value: DocumentInvocation, source?: DocumentSource, structural = false, resident?: ResidentDocumentTransport, ownedTiming = false, prepareParent = false): string {
  const invocation = validatedDocumentInvocation(value);
  if (invocation.stage === 'final' || invocation.stage === 'existing' && rawDocumentFormat(invocation.path.split('.').pop()?.toLowerCase())) return rawDocumentInvocationCommand(invocation, ownedTiming, prepareParent);
  if (invocation.stage === 'build' && !source) throw new Error('document_source_required');
  if (source && (!safeDocumentPath(source.path) || !/^[a-f0-9]{64}$/.test(source.sha256) || !Number.isSafeInteger(source.size) || source.size < 1 || source.size > 1000000)) throw new Error('invalid_document_source');
  if (invocation.interpreter === 'knot-doc') {
    if (!source || !resident) throw new Error('invalid_document_invocation');
    return residentDocumentCommand(invocation, source, resident, ownedTiming, prepareParent);
  }
  if (resident) throw new Error('invalid_document_invocation');
  const input = { ...invocation, source: invocation.stage === 'build' ? source : undefined };
  const command = `command -p python3 -I - <<'KNOT_DOCUMENT_INVOKE'
from pathlib import Path
import hashlib,json,re,subprocess,sys
c=json.loads(${JSON.stringify(JSON.stringify(input))})
root=Path.cwd().resolve()
env={'PATH':'/usr/bin:/usr/local/bin:/bin','LC_ALL':'C.UTF-8','HOME':str(root)}
def path(value):
    assert isinstance(value,str) and 0<len(value)<=240 and re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_. /-]*',value)
    assert all(p and p not in ('.','..') and not p.startswith('.') for p in value.split('/'))
    p=Path(value)
    assert not p.is_absolute() and all(not Path(*p.parts[:i+1]).is_symlink() for i in range(len(p.parts)))
    assert p.resolve().is_relative_to(root)
    return p
def measured(p,limit):
    assert p.is_file() and 0<p.stat().st_size<=limit
    b=p.read_bytes()
    assert 0<len(b)<=limit
    return b,hashlib.sha256(b).hexdigest()
def check_source():
    s=c.get('source')
    if s:
        b,h=measured(path(s['path']),1000000)
        assert h==s['sha256'] and len(b)==s['size'], 'document_source_changed'
p=path(c['path'])
check_source()
# Reject collisions before any author/build code runs. Empty source code only
# measures an already fully read source; existing final measurement never runs code.
if c['code']: assert not p.exists(), 'document_output_exists'
${prepareParent ? "if c['code']:\n    # output_parent_v1: only the already validated declared parent, never a source/archive.\n    try:\n        p.parent.mkdir(parents=True,exist_ok=True)\n        p=path(c['path'])\n        assert p.parent.is_dir() and not p.exists(), 'document_output_exists'\n    except (OSError,AssertionError):\n        print('KNOT_DOCUMENT_PREPARATION_FAILURE_V1 '+json.dumps(dict(phase='output_parent',noReplay=True),separators=(',',':')),flush=True)\n        raise SystemExit(73)\n" : ''}if c['code']:
    args=[sys.executable,'-I','-c',c['code']] if c['interpreter']=='python3' else ['/bin/bash','--noprofile','--norc','-c',c['code']]
    done=subprocess.run(args,cwd=root,env=env,timeout=${ownedTiming ? 540 : 90})
    if done.returncode: raise SystemExit(done.returncode if done.returncode>0 else 128-done.returncode)
p=path(c['path'])
b,h=measured(p,1000000 if c['stage']=='source' else 50000000)
check_source()
fmt=p.suffix[1:].lower()
if c['stage']=='source':
    text=b.decode('utf-8',errors='strict')
    assert fmt in ('md','html') and text.strip() and '\\x00' not in text
    print('KNOT_DOCUMENT_SOURCE_V1 '+json.dumps(dict(path=c['path'],sha256=h,size=len(b),format=fmt),separators=(',',':')))
else:
    assert fmt in ('pdf','docx','xlsx','pptx')
    pages=0
    if fmt=='pdf':
        assert b.startswith(b'%PDF-') and b'%%EOF' in b[-2048:]
        info=subprocess.run(['/usr/bin/pdfinfo',str(p)],capture_output=True,timeout=${ownedTiming ? 20 : 10},env=env,check=True).stdout.decode('utf-8',errors='replace')
        m=re.search(r'^Pages:\\s+(\\d+)',info,re.M)
        assert m and 1<=int(m[1])<=300
        pages=int(m[1])
        extracted=subprocess.run(['/usr/bin/pdftotext','-enc','UTF-8',str(p),'-'],capture_output=True,timeout=${ownedTiming ? 20 : 10},env=env,check=True).stdout
        assert len(extracted)<=10000000
        plain=extracted.decode('utf-8',errors='strict')
        assert plain.strip(), 'document_text_unreadable'
        assert not re.search(${JSON.stringify(structural && invocation.stage !== 'source' ? documentStructuralMarkupPattern : documentMarkupPattern)},plain,re.I), 'document_literal_markup_detected'
    # Office page counts are measured in the separate independent verifier.
    final,final_hash=measured(path(c['path']),50000000)
    assert h==final_hash and len(b)==len(final), 'document_bytes_changed'
    print('KNOT_DOCUMENT_EXECUTION_V2 '+json.dumps(dict(stage=c['stage'],interpreter=c['interpreter'],sourceSHA256=c.get('source',{}).get('sha256')),separators=(',',':')))
    print('KNOT_DOCUMENT_V1 '+json.dumps(dict(path=c['path'],sha256=h,size=len(b),format=fmt,pages=pages,pagesPending=fmt!='pdf',proofs=[]${invocation.title !== undefined ? ",title=c['title']" : ''}${invocation.deliveryLabel !== undefined ? ",deliveryLabel=c['deliveryLabel']" : ''}),separators=(',',':')))
KNOT_DOCUMENT_INVOKE`;
  if (new TextEncoder().encode(command).length > documentCommandByteLimit) throw new InvalidDocumentInvocation(['arguments:size'], { ...documentSizeFacts(invocation), commandBytes: new TextEncoder().encode(command).length, commandByteLimit: documentCommandByteLimit });
  return command;
}
/** New raw lane only; old source/build/existing-PDF command text is unchanged. */
function rawDocumentInvocationCommand(invocation: DocumentInvocation, ownedTiming = false, prepareParent = false): string {
  const command = `command -p python3 -I - <<'KNOT_RAW_DOCUMENT_INVOKE'
from pathlib import Path
import hashlib,json,subprocess,sys,csv,io
c=json.loads(${JSON.stringify(JSON.stringify(invocation))})
root=Path.cwd().resolve()
def path():
    p=Path(c['path'])
    assert not p.is_absolute() and all(not Path(*p.parts[:i+1]).is_symlink() for i in range(len(p.parts)))
    assert p.resolve().is_relative_to(root)
    return p
p=path()
assert c['stage'] in ('final','existing')
assert (c['stage']=='final' and c['code'].strip() and not p.exists()) or (c['stage']=='existing' and c['code']==''), 'document_output_exists'
${prepareParent ? "if c['stage']=='final':\n    # output_parent_v1: permitted declared output directory only.\n    try:\n        p.parent.mkdir(parents=True,exist_ok=True)\n        p=path()\n        assert p.parent.is_dir() and not p.exists(), 'document_output_exists'\n    except (OSError,AssertionError):\n        print('KNOT_DOCUMENT_PREPARATION_FAILURE_V1 '+json.dumps(dict(phase='output_parent',noReplay=True),separators=(',',':')),flush=True)\n        raise SystemExit(73)\n" : ''}if c['stage']=='final':
    args=[sys.executable,'-I','-c',c['code']] if c['interpreter']=='python3' else ['/bin/bash','--noprofile','--norc','-c',c['code']]
    done=subprocess.run(args,cwd=root,env={'PATH':'/usr/bin:/usr/local/bin:/bin','LC_ALL':'C.UTF-8','HOME':str(root)},timeout=${ownedTiming ? 540 : 90})
    if done.returncode: raise SystemExit(done.returncode if done.returncode>0 else 128-done.returncode)
p=path()
assert p.is_file() and 0<p.stat().st_size<=180000
b=p.read_bytes()
assert 0<len(b)<=180000
text=b.decode('utf-8',errors='strict')
assert text.strip() and '\\x00' not in text
assert not text.lstrip('\\ufeff \\t\\r\\n').startswith('%PDF-'), 'document_output_format_mismatch'
fmt=p.suffix[1:]
assert fmt in ('txt','md','html','csv','json')
if fmt=='json': json.loads(text)
if fmt=='csv':
    rows=list(csv.reader(io.StringIO(text),strict=True))
    assert rows and any(any(cell.strip() for cell in row) for row in rows)
h=hashlib.sha256(b).hexdigest()
assert path().read_bytes()==b, 'document_bytes_changed'
# One logical file, not a rendered-page or visual/factual proof claim.
print('KNOT_DOCUMENT_EXECUTION_V2 '+json.dumps(dict(stage=c['stage'],interpreter=c['interpreter']),separators=(',',':')))
print('KNOT_DOCUMENT_V1 '+json.dumps(dict(path=c['path'],sha256=h,size=len(b),format=fmt,pages=1,proofs=[]${invocation.title !== undefined ? ",title=c['title']" : ''}${invocation.deliveryLabel !== undefined ? ",deliveryLabel=c['deliveryLabel']" : ''}),separators=(',',':')))
KNOT_RAW_DOCUMENT_INVOKE`;
  if (new TextEncoder().encode(command).length > documentCommandByteLimit) throw new InvalidDocumentInvocation(['arguments:size'], { ...documentSizeFacts(invocation), commandBytes: new TextEncoder().encode(command).length, commandByteLimit: documentCommandByteLimit });
  return command;
}
export const documentScriptTool = { type: 'function', function: { name: 'document_script', strict: true,
  description: 'Owned foreground document invocation adapter over the discovered session_input endpoint, NOT an installed droplet tool. Supply live agent-authored code, never interpreter wrappers, heredocs or receipt emitters. The backend selects the declared interpreter, invokes exactly your code and measures saved bytes. For bound TXT/MD/HTML/CSV/JSON output use final: author NEW complete UTF-8 final bytes directly with exactly the bound extension; never convert raw asks into PDF. Backend rehash and independent complete-byte content comparison remain required. PDF/Office default is AUTHOR: read relevant existing source content in full, then author a complete NEW workspace-root source (deliverables/ also allowed). For fresh workflows with documentTemplate, author complete semantic HTML with no authored CSS/style/link/script/presentational attributes; the pinned stylesheet owns design. Use knot-doc build with empty code for that HTML. Historical workflows without template selection retain their authored design route. Markdown is only for an explicitly plain PDF ask. Do not reduce development to headings or one-line restatements. Empty source code is only for an already fully read complete source. build: after its actual source receipt, supply your complete conversion code from the live guide and a NEW final PDF/Office path. existing: empty code is ONLY for a final explicitly named for retrieval in the CURRENT original request, never a remembered/inventory/archive substitute for a new build. Archives require their full path in that request. Complete source-aware text review still runs: positive grounded findings require repair, but two unusable verdicts are nonblocking unconfirmed, not a pass. Backend never chooses a renderer or document content. When owned workflow state explicitly advertises its pinned knot-doc version (fresh 2.0.0; historical 1.0.0 unchanged), prefer build with interpreter=knot-doc, code="" for measured Markdown/HTML source to NEW PDF. This invokes only the pinned mechanical resident transport; author content/layout in source first. It never applies to Office or raw asks and never bypasses independent proof/content/capture. Otherwise supply live-guide conversion code as above. Do not print protocol markers, hashes, sizes or page counts. Never overwrite files, access MEMORY.md, install dependencies, fetch external/local resources from document content, or assume a missing helper. One prepared script per response; wait for its real receipt. Complete code is bounded to 64000 Unicode code points and complete JSON-encoded arguments to 74000 UTF-8 bytes including escaping. Generated invocation framing has its own document-only bound; ordinary session_input commands remain limited to 12000 UTF-8 bytes. Never cut required content to fit or bypass with arbitrary append commands. An oversized complete step stops before dispatch; sliced authoring is not available.',
  parameters: { type: 'object', properties: { title: { type: 'string', maxLength: 120, description: 'Human-readable delivery title, separate from the immutable filename. Empty uses filename fallback.' }, deliveryLabel: { type: 'string', maxLength: 48, description: 'Custom concise document style or purpose, e.g. Event brief, Research report, Budget workbook. Empty uses a format label.' }, stage: { type: 'string', enum: ['source', 'build', 'existing', 'final'] }, interpreter: { type: 'string', enum: ['python3', 'bash', 'knot-doc'] }, code: { type: 'string', maxLength: documentCodeCharacterLimit, description: 'At most 64000 Unicode code points; the complete JSON-encoded arguments must also fit 74000 UTF-8 bytes, including escaping. Supply complete content; never omit required content to fit or use arbitrary append commands. Oversize steps stop before dispatch; a sliced-authoring tool is not available.' }, path: { type: 'string', minLength: 1, maxLength: 240 } }, required: ['stage', 'interpreter', 'code', 'path', 'title', 'deliveryLabel'], additionalProperties: false } } };

export function documentSource(receipt: ShellEvidence, ownedTiming = receipt.workflow?.executionTiming === 'owned_v2', prepareParent = receipt.workflow?.documentDirectoryPolicy === 'output_parent_v1'): DocumentSource | undefined {
  const lines = receipt.stdout.split(/\r?\n/).filter(line => line.startsWith('KNOT_DOCUMENT_SOURCE_V1 '));
  if (!lines.length) return undefined;
  if (!receipt.documentInvocation || receipt.documentInvocation.stage !== 'source' || receipt.reviewedCommand !== documentInvocationCommand(receipt.documentInvocation, undefined, false, undefined, ownedTiming, prepareParent) || lines.length !== 1 || receipt.stdout.includes('KNOT_DOCUMENT_V1 ') || receipt.status !== 'completed' || receipt.exitCode !== 0 || !receipt.sessionID || !receipt.outputComplete || !receipt.terminationConfirmed || receipt.truncated || receipt.contextTruncated) throw new Error('document_source_incomplete');
  const source = JSON.parse(lines[0].slice('KNOT_DOCUMENT_SOURCE_V1 '.length)) as DocumentSource;
  if (!source || source.path !== receipt.documentInvocation.path || !safeDocumentPath(source.path) || !['md', 'html'].includes(source.format) || !source.path.toLowerCase().endsWith('.' + source.format) || !/^[a-f0-9]{64}$/.test(source.sha256) || !Number.isSafeInteger(source.size) || source.size < 1 || source.size > 1000000) throw new Error('invalid_document_source');
  return source;
}
/** Owned invocation provenance. Existing bytes are explicitly inspection-only;
 * build provenance additionally requires the real earlier source measurement. */
export function verifiedDocumentExecution(receipt: ShellEvidence, manifest: DocumentManifest): boolean {
  const execution = receipt.workflow?.documentExecution;
  if (!execution || execution.invocation.stage === 'source') return false;
  if (execution.resident) {
    const expected = residentDocumentTransport(receipt.workflow?.residentDocumentTool, receipt.workflow?.rootID ?? '', execution.source?.format === 'html' ? receipt.workflow?.documentTemplate : undefined, execution.source?.format === 'html' && receipt.workflow?.documentDesignJournal === 'author_css_v1', receipt.workflow?.styleEvidencePolicy, receipt.workflow?.residentFailurePolicy);
    if (!expected || execution.resident.taskID !== expected.taskID || execution.resident.version !== expected.version || execution.resident.template !== expected.template || execution.resident.designJournal !== expected.designJournal || execution.resident.styleEvidencePolicy !== expected.styleEvidencePolicy || execution.resident.failurePolicy !== expected.failurePolicy) return false;
  }
  if ((execution.invocation.interpreter === 'knot-doc') !== !!execution.resident) return false;
  if (documentFormatIssue(receipt.workflow?.documentFormat, manifest.path, manifest.format)) return false;
  if (execution.invocation.stage === 'final' && (!receipt.workflow?.documentFormat || !rawDocumentFormat(manifest.format))) return false;
  if (receipt.workflow?.documentPolicy === 'author_v1' && execution.invocation.stage === 'existing' && !namedExistingDocument(receipt.workflow.originalRequest, execution.invocation.path, !!receipt.workflow.documentFormat)) return false;
  if (receipt.workflow?.pdfRecovery?.phase === 'proving' && !receipt.workflow.pdfRecovery.candidates?.some(candidate => candidate.path === manifest.path && candidate.sha256 === manifest.sha256 && candidate.size === manifest.size && candidate.pages === manifest.pages)) return false;
  const complete = (item: Record<string, unknown>) => item.status === 'completed' && item.exitCode === 0 && item.outputComplete === true && item.terminationConfirmed === true && item.truncated !== true && item.contextTruncated !== true && typeof item.sessionID === 'string';
  if (execution.invocation.stage === 'build' && (!execution.source || !execution.sourceProposalID || !receipt.evidence.some(item => {
    if (item.proposalID !== execution.sourceProposalID || !complete(item)) return false;
    try {
      const actual = documentSource({ ...item, evidence: [] } as unknown as ShellEvidence, receipt.workflow?.executionTiming === 'owned_v2', receipt.workflow?.documentDirectoryPolicy === 'output_parent_v1');
      return !!actual && actual.path === execution.source!.path && actual.sha256 === execution.source!.sha256 && actual.size === execution.source!.size;
    } catch { return false; }
  }))) return false;
  return receipt.evidence.some(item => {
    if (!complete(item) || item.reviewedCommand !== documentInvocationCommand(execution.invocation, execution.source, receipt.workflow?.documentValidation === 'structural_v2', execution.resident, receipt.workflow?.executionTiming === 'owned_v2', receipt.workflow?.documentDirectoryPolicy === 'output_parent_v1') || typeof item.stdout !== 'string') return false;
    const lines = item.stdout.split(/\r?\n/).filter(line => line.startsWith('KNOT_DOCUMENT_V1 '));
    if (lines.length !== 1) return false;
    try {
      const actual = JSON.parse(lines[0].slice('KNOT_DOCUMENT_V1 '.length)) as DocumentManifest;
      if (execution.resident && (!execution.source || !verifiedResidentDocumentEvidence(item.stdout, execution.source, execution.resident, actual))) return false;
      return actual.path === execution.invocation.path && actual.path === manifest.path && actual.sha256 === manifest.sha256 && actual.size === manifest.size && actual.format === manifest.format && (actual.pages === manifest.pages || (actual.pages === 0 && actual.pagesPending === true && manifest.format !== 'pdf'));
    } catch { return false; }
  });
}
// Legacy receipts must regenerate byte-for-byte, including their old broad scan.
// New workflows check whole raw HTML documents mechanically; contextual markup
// (including intentional code/math examples) is judged in complete-text review.
export const documentStructuralMarkupPattern = String.raw`(?is)^\s*(?:<!doctype\s+html[^>]*>\s*)?<html(?:\s[^>]*|)>.*</html>\s*$`;
// Conservative legacy scan, not visual or factual certification.
export const documentMarkupPattern = String.raw`(?m)^\s{0,3}#{1,6}\s+\S|\*\*|__[^_\n]{1,120}__|\x60{3}|<(?:html|body|h[1-6]|p|div|span|table|tr|td|strong|em)(?:\s[^>]*|)>|\[[^\]\n]{1,120}\]\(https?://`;

/** Classify only an exact measured invocation/verifier with a complete receipt. */
export function documentCheckFailure(command: string, receipt: ShellResult, expectedCommand: string | undefined): 'document_literal_markup_detected' | undefined {
  if (!expectedCommand || command !== expectedCommand || receipt.status !== 'failed' || receipt.exitCode === null || receipt.exitCode === 0 || !receipt.sessionID || !receipt.outputComplete || !receipt.terminationConfirmed || receipt.truncated || receipt.contextTruncated) return undefined;
  return /^AssertionError: document_literal_markup_detected\s*$/m.test(receipt.stderr) ? 'document_literal_markup_detected' : undefined;
}

/** Measure final bytes immediately before append; no agent-templated values. */
export function documentMemoryCommand(document: KnotDocument): string {
  const raw = !document.verification && !!document.contentReview && rawDocumentFormat(document.format);
  if ((!document.verification && !raw) || !document.sourcePath || !safeDocumentPath(document.sourcePath) || !/^[a-f0-9]{64}$/.test(document.id)) throw new Error('invalid_document_memory');
  const comparison = document.contentReview?.status === 'pass' ? 'passed' : document.contentReview?.status === 'quality_shortfalls' ? 'quality shortfalls recorded; not a pass' : 'unconfirmed; not a pass';
  const distinctChecks = document.byteFidelity ? '\\nByte fidelity (measured final to immutable capture): passed; bytes rechecked before this memory append.\\nContent quality (complete-text coverage, not factual/safety certification): ' + comparison + '.\\n' : '';
  const input = { path: document.sourcePath, sha256: document.sha256, size: document.size, pages: document.pages, format: document.format, id: document.id };
  return `command -p python3 -I - <<'KNOT_DOCUMENT_MEMORY'
from pathlib import Path
import hashlib,json,subprocess,re,os,datetime,fcntl
c=json.loads(${JSON.stringify(JSON.stringify(input))})
root=Path.cwd().resolve()
p=Path(c['path'])
assert not p.is_absolute() and all(not Path(*p.parts[:i+1]).is_symlink() for i in range(len(p.parts))) and p.resolve().is_relative_to(root)
b=p.read_bytes()
assert len(b)==c['size'] and hashlib.sha256(b).hexdigest()==c['sha256'], 'document_bytes_changed'
pages=c['pages']
if c['format']=='pdf':
    info=subprocess.run(['/usr/bin/pdfinfo',str(p.resolve())],capture_output=True,timeout=15,check=True,env={'PATH':'/usr/bin:/bin','LC_ALL':'C','HOME':str(root)}).stdout.decode('utf-8',errors='replace')
    m=re.search(r'^Pages:\\s+(\\d+)',info,re.M)
    assert m and int(m[1])==pages, 'document_page_count_changed'
    pages=int(m[1])
label=${raw ? "'Logical files (not rendered pages)'" : "'Pages' if c['format']=='pdf' else 'Verified rendered pages'"}
record='\\n'+datetime.datetime.now(datetime.timezone.utc).date().isoformat()+' — Verified private document delivery\\nPath: '+c['path']+'\\nSHA-256: '+hashlib.sha256(b).hexdigest()+'\\nBytes: '+str(len(b))+'\\n'+label+': '+str(pages)+'\\nDelivery ID: '+c['id']+'\\nChecks: ${raw ? 'complete UTF-8 bytes and format; no rendered-page proof' : 'mechanical render/text/format; not visual or factual certification'}.\\nContent comparison: ${comparison}.${distinctChecks}\\n'
assert hashlib.sha256(p.read_bytes()).hexdigest()==c['sha256']
assert not Path('MEMORY.md').is_symlink()
fd=os.open('MEMORY.md',os.O_RDWR|os.O_CREAT|os.O_APPEND|os.O_NOFOLLOW,0o600)
with os.fdopen(fd,'r+b') as f:
    fcntl.flock(f.fileno(),fcntl.LOCK_EX)
    f.seek(0,2)
    assert f.tell()<=1000000, 'memory_capacity'
    payload=record.encode('utf-8')
    assert f.write(payload)==len(payload)
    f.flush(); os.fsync(f.fileno()); f.seek(0)
    saved=f.read()
    assert saved.endswith(payload)
print('KNOT_MEMORY_VERIFIED_V1 '+json.dumps(dict(bytes=len(saved),sha256=hashlib.sha256(saved).hexdigest()),separators=(',',':')))
KNOT_DOCUMENT_MEMORY`;
}
