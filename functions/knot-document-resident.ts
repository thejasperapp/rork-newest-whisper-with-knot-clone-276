import type { DocumentSource, DocumentInvocation } from './knot-document-build';
import { authoredDesignResidentCommand, authoredDesignBindingsValid, verifiedAuthoredDesignEvidence } from './knot-document-design';
import type { DocumentManifest } from './knot-documents';
import { templateResidentCommand, verifiedTemplateEvidence, type KnotDocumentTemplate } from './knot-document-templates';

export type ResidentDocumentTransport = { version: 'knot_doc_1_0_0' | 'knot_doc_2_0_0'; taskID: string; template?: KnotDocumentTemplate; designJournal?: 'author_css_v1'; styleEvidencePolicy?: 'record_v1'; failurePolicy?: 'bounded_v1' };
export const knotDocSHA256 = 'de43a1e516f71d4f694ccc030686c9d8fef2f88941028cb58bb82610d59ebf63';
export const knotDocV2SHA256 = 'd4447d5720521af2e95dcc5b4671f54a7033e14bf2faa3245d0b0b6680e38f78';
function residentProfile(version: ResidentDocumentTransport['version']) {
  if (version === 'knot_doc_1_0_0') return { version: '1.0.0', directory: 'v1', sha256: knotDocSHA256 };
  if (version === 'knot_doc_2_0_0') return { version: '2.0.0', directory: 'v2', sha256: knotDocV2SHA256 };
  throw new Error('invalid_document_invocation');
}
export function residentDocumentTransport(version: unknown, taskID: string, template?: KnotDocumentTemplate, designJournal = false, styleEvidencePolicy?: 'record_v1', failurePolicy?: 'bounded_v1'): ResidentDocumentTransport | undefined {
  return version === '1.0.0' ? { version: 'knot_doc_1_0_0', taskID } : version === '2.0.0' ? { version: 'knot_doc_2_0_0', taskID, ...(failurePolicy === 'bounded_v1' ? { failurePolicy } : {}), ...(styleEvidencePolicy === 'record_v1' ? { styleEvidencePolicy } : {}), ...(template ? { template } : designJournal ? { designJournal: 'author_css_v1' as const } : {}) } : undefined;
}
export const residentDocumentContract = 'Muse reports the exact pinned knot-doc 1.0.0 installed and accepted. In fresh workflows advertising that version, document_script stage=build, interpreter=knot-doc, code="" runs only the pinned mechanical Markdown/HTML-to-PDF transport against the measured source. Author all content/layout in the complete source using the actual live guide first. For a requested PDF, prefer a complete self-contained semantic HTML source with inline print CSS: deliberate typography, spacing, section hierarchy, useful tables/callouts and controlled page breaks/margins. No remote fonts/resources. Plain Markdown-to-PDF is only for an explicitly plain document ask, never the default for a designed guide, report or handout. Develop every requested item with useful explanation, reasoning, worked examples or actionable detail appropriate to the ask; headings and one-line restatements are not coverage. A source-only content pass is not visual certification. This route cannot author content, process raw-format requests, produce Office, adopt historical outputs or waive independent every-page proof, full request/source content comparison and immutable byte capture. Version/hash, task, source, journal inputs/packages and staged file hashes are checked by the fixed adapter; staged evidence is not independent verification. Never invoke knot-doc via model-authored wrappers or install it. Historical workflows without this version keep their original route.';

export function residentDocumentContractFor(version: '1.0.0' | '2.0.0'): string {
  return version === '1.0.0' ? residentDocumentContract : residentDocumentContract.replace('1.0.0', '2.0.0') + ' The v2 Markdown lane adds the operator-owned house-v1 design; HTML remains author-v1, without replacing authored design. The fixed adapter hash-binds design and houseStyleSHA256 in the journal inputs. This does not certify visual quality, make v2 PDF bytes identical to v1, or upgrade existing workflows.';
}

/** A fresh, versioned transport only. Never changes historical command text or
 * executes model conversion code. The resident utility is mechanical staging;
 * its proofs do not replace the separately owned independent verifier/capture. */
export function residentDocumentCommand(invocation: DocumentInvocation, source: DocumentSource, transport: ResidentDocumentTransport, ownedTiming = false, prepareParent = false): string {
  const profile = residentProfile(transport.version);
  if (transport.styleEvidencePolicy !== undefined && (transport.styleEvidencePolicy !== 'record_v1' || transport.version !== 'knot_doc_2_0_0')) throw new Error('invalid_document_invocation');
  if (transport.designJournal && (transport.version !== 'knot_doc_2_0_0' || source.format !== 'html' || transport.template)) throw new Error('invalid_document_invocation');
  if (transport.template && (transport.version !== 'knot_doc_2_0_0' || source.format !== 'html')) throw new Error('invalid_document_template');
  if (!/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(transport.taskID) || invocation.stage !== 'build' || invocation.interpreter !== 'knot-doc' || invocation.code !== '' || !invocation.path.endsWith('.pdf')) throw new Error('invalid_document_invocation');
  if (transport.failurePolicy !== undefined && (transport.failurePolicy !== 'bounded_v1' || transport.version !== 'knot_doc_2_0_0')) throw new Error('invalid_document_invocation');
  const input = { path: invocation.path, source, taskID: transport.taskID, title: invocation.title, deliveryLabel: invocation.deliveryLabel };
  const command = `command -p python3 -I - <<'KNOT_RESIDENT_DOCUMENT_INVOKE'
from pathlib import Path
import hashlib,json,subprocess,re,time
c=json.loads(${JSON.stringify(JSON.stringify(input))})
root=Path.cwd().resolve()
started=time.monotonic()
env={'PATH':'/usr/local/bin:/usr/bin:/bin','LC_ALL':'C.UTF-8','HOME':str(root)}
tool=Path('/opt/knot-tools/knot-doc/${profile.directory}/knot-doc')
def digest(b): return hashlib.sha256(b).hexdigest()
def pinned():
    assert tool.is_file() and not tool.is_symlink() and digest(tool.read_bytes())=='${profile.sha256}', 'knot_doc_version_unverified'
def path(value,hidden=False):
    assert isinstance(value,str) and 0<len(value)<=240 and re.fullmatch(r'[a-zA-Z0-9_.][a-zA-Z0-9_. /-]*',value)
    assert all(p and p not in ('.','..') and (hidden or not p.startswith('.')) for p in value.split('/'))
    p=Path(value)
    assert not p.is_absolute() and all(not Path(*p.parts[:i+1]).is_symlink() for i in range(len(p.parts))) and p.resolve().is_relative_to(root)
    return p
def measured(value,limit=50000000,hidden=False):
    p=path(value,hidden)
    assert p.is_file() and 0<p.stat().st_size<=limit
    with p.open('rb') as f: b=f.read(limit+1)
    assert 0<len(b)<=limit
    return b
def check_source():
    b=measured(c['source']['path'],1000000)
    assert digest(b)==c['source']['sha256'] and len(b)==c['source']['size'], 'document_source_changed'
def run(args):
    remaining=${ownedTiming ? 540 : 110}-(time.monotonic()-started)
    assert remaining>1
${transport.failurePolicy === 'bounded_v1' ? `    def failure(code,out=b'',err=b''):
        # No raw subprocess text, paths or content escapes this bounded record.
        classes=[v for v in ('FileExistsError','FileNotFoundError','PermissionError','AssertionError','TimeoutExpired','MemoryError','OSError','ValueError') if v.encode() in err[-8192:]]
        print('KNOT_RESIDENT_FAILURE_V1 '+json.dumps(dict(phase='version' if '--version' in args else 'build',exitCode=code,errorClasses=classes,stdoutBytes=len(out),stderrBytes=len(err),stdoutSHA256=digest(out),stderrSHA256=digest(err),noReplay=True),separators=(',',':')),flush=True)
    try:
        result=subprocess.run(args,cwd=root,env=env,capture_output=True,timeout=remaining)
    except subprocess.TimeoutExpired as error:
        failure('timeout',error.stdout or b'',error.stderr or b'')
        raise AssertionError('knot_doc_staging_timeout_no_replay') from None
    if result.returncode!=0: failure(result.returncode,result.stdout,result.stderr)
` : `    result=subprocess.run(args,cwd=root,env=env,capture_output=True,timeout=remaining)
`}    assert result.returncode==0, 'knot_doc_staging_failed_no_replay'
    assert len(result.stdout)<=500000 and len(result.stderr)<=50000
    return result.stdout
pinned()
assert run([str(tool),'--version']).decode('utf-8').strip()=='${profile.version}', 'knot_doc_version_unverified'
check_source()
${prepareParent ? "# output_parent_v1: validated final parent only; proof-root semantics unchanged.\noutput=path(c['path'])\nassert not output.exists(), 'document_output_exists'\ntry:\n    output.parent.mkdir(parents=True,exist_ok=True)\n    output=path(c['path'])\n    assert output.parent.is_dir() and not output.exists(), 'document_output_exists'\nexcept (OSError,AssertionError):\n    print('KNOT_DOCUMENT_PREPARATION_FAILURE_V1 '+json.dumps(dict(phase='output_parent',noReplay=True),separators=(',',':')),flush=True)\n    raise SystemExit(73)\n" : ''}p=path(c['path'])
assert not p.exists() and p.parent.is_dir(), 'document_output_exists'
proof_root='deliverables/knot-resident-'+c['taskID']
# One owned dispatch only. A failure or unknown outcome never retries this tool.
output=run([str(tool),'build',c['source']['path'],'--out',c['path'],'--proof-dir',proof_root,'--task-id',c['taskID']])
lines=output.decode('utf-8',errors='strict').splitlines()
assert len(lines)==1 and lines[0].startswith('KNOT_DOCUMENT_V1 '), 'knot_doc_manifest_invalid'
m=json.loads(lines[0][len('KNOT_DOCUMENT_V1 '):])
assert m['toolVersion']=='${profile.version}' and m['taskID']==c['taskID'] and m['sourceSHA256']==c['source']['sha256']
assert m['path']==c['path'] and m['format']=='pdf' and m['proofStageOnly'] is True and m['independentVerification'] is False
assert re.fullmatch(r'[a-f0-9]{64}',m['inputsSHA256'])
assert type(m['size']) is int and type(m['pages']) is int and 1<=m['pages']<=300
final=measured(c['path'])
assert len(final)==m['size'] and digest(final)==m['sha256'] and final.startswith(b'%PDF-') and b'%%EOF' in final[-2048:], 'document_bytes_changed'
journal_path='.knot-doc/${profile.directory}/'+c['taskID']+'/'+m['inputsSHA256']+'.jsonl'
journal=measured(journal_path,1000000,True)
entries=[json.loads(line) for line in journal.decode('utf-8',errors='strict').splitlines()]
assert len(entries)==2 and entries[0]['state']=='intent' and entries[0]['taskID']==c['taskID'] and entries[0]['output']==c['path']
assert entries[1]['state']=='staged' and entries[1]['manifest']==m
inputs=entries[0]['inputs']
assert digest((json.dumps(inputs,separators=(',',':'))+'\\n').encode('utf-8'))==m['inputsSHA256']
assert inputs['toolVersion']=='${profile.version}' and inputs['sourceSHA256']==c['source']['sha256'] and inputs['sourceBytes']==c['source']['size']
assert inputs['sourceFormat']==c['source']['format'] and inputs['outputFormat']=='pdf' and inputs['resourcePolicy']=='deny-all-v1'
${transport.version === 'knot_doc_2_0_0' ? transport.styleEvidencePolicy === 'record_v1' ? "# record_v1: HTML uses author-v1/null; Markdown uses house-v1/hex.\n# Style schema observations are nonblocking Events, not delivery authority.\n" : "assert inputs['design']==('house-v1' if c['source']['format']=='md' else 'author-v1')\nassert isinstance(inputs['houseStyleSHA256'],str) and re.fullmatch(r'[a-f0-9]{64}',inputs['houseStyleSHA256'])\n" : ''}assert inputs['markdown']=='commonmark-tables-strikethrough-html-v1' and inputs['render']=='scale-to-1400-png-v1'
assert set(inputs['packages'])=={'weasyprint','markdown-it-py'} and all(isinstance(v,str) and 0<len(v)<=100 for v in inputs['packages'].values())
stage=proof_root+'/knot-doc-'+c['taskID']+'-'+m['inputsSHA256']
def staged(item,expected,limit):
    assert item['path']==expected and type(item['size']) is int
    b=measured(expected,limit)
    assert len(b)==item['size'] and digest(b)==item['sha256'], 'knot_doc_stage_changed'
    return b
text=staged(m['textEvidence'],stage+'/text.txt',10000000)
assert text.decode('utf-8',errors='strict').strip()
info=staged(m['pdfInfo'],stage+'/pdfinfo.txt',1000000)
pages=re.search(rb'^Pages:\\s+(\\d+)',info,re.M)
assert pages and int(pages[1])==m['pages']
assert isinstance(m['proofs'],list) and len(m['proofs'])==m['pages']
total=0
for page,item in enumerate(m['proofs'],1):
    assert item['page']==page
    image=staged(item,stage+'/page-'+str(page)+'.png',5000000)
    assert image.startswith(bytes((137,80,78,71,13,10,26,10)))
    total+=len(image)
    assert total<=50000000
check_source()
pinned()
assert measured(c['path'])==final, 'document_bytes_changed'
# Preserve the staged-file references and package-input binding as evidence,
# but expose NO resident proof as independently verified delivery authority.
evidence=dict(version='${transport.version}',toolSHA256='${profile.sha256}',manifest=m,journal=dict(path=journal_path,sha256=digest(journal),size=len(journal)),inputs=inputs)
print('KNOT_RESIDENT_DOCUMENT_V1 '+json.dumps(evidence,separators=(',',':')))
print('KNOT_DOCUMENT_V1 '+json.dumps(dict(path=c['path'],sha256=digest(final),size=len(final),format='pdf',pages=m['pages'],proofs=[]${invocation.title !== undefined ? ",title=c['title']" : ''}${invocation.deliveryLabel !== undefined ? ",deliveryLabel=c['deliveryLabel']" : ''}),separators=(',',':')))
KNOT_RESIDENT_DOCUMENT_INVOKE`;
  if (new TextEncoder().encode(command).length > 12000) throw new Error('invalid_command_size_or_text');
  return transport.template ? templateResidentCommand(command, source, transport.template) : transport.designJournal ? authoredDesignResidentCommand(command, transport.styleEvidencePolicy === 'record_v1') : command;
}

/** Called only after exact owned command reconstruction and complete receipts.
 * Independent final byte capture/proof/content checks remain separate gates. */
export function verifiedResidentDocumentEvidence(stdout: string, source: DocumentSource, transport: ResidentDocumentTransport, final: DocumentManifest): boolean {
  try {
    const profile = residentProfile(transport.version);
    const lines = stdout.split(/\r?\n/).filter(line => line.startsWith('KNOT_RESIDENT_DOCUMENT_V1 '));
    if (lines.length !== 1) return false;
    const value = JSON.parse(lines[0].slice('KNOT_RESIDENT_DOCUMENT_V1 '.length));
    const m = value.manifest;
    return (!transport.designJournal || transport.version === 'knot_doc_2_0_0' && !transport.template && (transport.styleEvidencePolicy === 'record_v1' ? authoredDesignBindingsValid(value, source) : verifiedAuthoredDesignEvidence(value, source))) && value.version === transport.version && value.toolSHA256 === profile.sha256 && m.toolVersion === profile.version && m.taskID === transport.taskID &&
      (transport.template ? transport.version === 'knot_doc_2_0_0' && verifiedTemplateEvidence(value, source, transport.template) : m.sourceSHA256 === source.sha256) && m.proofStageOnly === true && m.independentVerification === false && /^[a-f0-9]{64}$/.test(m.inputsSHA256) &&
      (transport.version !== 'knot_doc_2_0_0' || transport.styleEvidencePolicy === 'record_v1' || value.inputs.design === (source.format === 'md' ? 'house-v1' : 'author-v1') && typeof value.inputs.houseStyleSHA256 === 'string' && /^[a-f0-9]{64}$/.test(value.inputs.houseStyleSHA256)) &&
      value.inputs.toolVersion === profile.version && (transport.template ? verifiedTemplateEvidence(value, source, transport.template) : value.inputs.sourceSHA256 === source.sha256 && value.inputs.sourceBytes === source.size && value.inputs.sourceFormat === source.format) &&
      m.path === final.path && m.sha256 === final.sha256 && m.size === final.size && m.pages === final.pages && m.format === final.format;
  } catch { return false; }
}

/** Allowlisted metadata only, after the exact owned command and core evidence
 * passed. No CSS, arbitrary journal contents, exception text or secrets enter
 * Events. Oversize strings/structured values are described, never dumped. */
export function residentDocumentStyleObservation(stdout: string, source: DocumentSource, transport: ResidentDocumentTransport, final: DocumentManifest): Record<string, unknown> | undefined {
  if (transport.styleEvidencePolicy !== 'record_v1' || !verifiedResidentDocumentEvidence(stdout, source, transport, final)) return undefined;
  const line = stdout.split(/\r?\n/).find(value => value.startsWith('KNOT_RESIDENT_DOCUMENT_V1 '))!;
  const value = JSON.parse(line.slice('KNOT_RESIDENT_DOCUMENT_V1 '.length));
  const hash = (v: unknown) => typeof v === 'string' && /^[a-f0-9]{64}$/.test(v);
  const observed = (v: unknown) => {
    if (v === undefined) return { type: 'missing' };
    if (v === null) return { type: 'null', value: null };
    if (typeof v === 'string') return v.length <= 160 ? { type: 'string', value: v } : { type: 'string', length: v.length, valueOmitted: true };
    if (typeof v === 'number' || typeof v === 'boolean') return { type: typeof v, value: v };
    return { type: Array.isArray(v) ? 'array' : typeof v, valueOmitted: true };
  };
  const inputs = value.inputs;
  const issues: string[] = [];
  if (inputs.design !== (source.format === 'md' ? 'house-v1' : 'author-v1')) issues.push('renderer_design_metadata');
  if (source.format === 'md' ? !hash(inputs.houseStyleSHA256) : inputs.houseStyleSHA256 !== null) issues.push('renderer_house_style_metadata');
  if (transport.designJournal && !verifiedAuthoredDesignEvidence(value, source)) issues.push('authored_css_evidence_unavailable_or_malformed');
  const style = value.designEvidence?.inputs;
  const failure = value.designEvidence?.failure;
  return { policy: 'record_v1', sourceFormat: source.format, sourceSHA256: source.sha256, finalSHA256: final.sha256, blocking: false,
    status: issues.length ? 'advisory' : 'recorded', issues, rendererDesign: observed(inputs.design), houseStyleSHA256: observed(inputs.houseStyleSHA256),
    ...(transport.template ? { template: transport.template, templateSHA256: value.templateEvidence.inputs.templateSHA256 } : {}),
    ...(transport.designJournal ? { authoredDesign: observed(style?.design), styleSHA256: observed(style?.styleSHA256), styleBytes: observed(style?.styleBytes),
      ...(failure && ['intent', 'staged'].includes(failure.phase) && ['AssertionError', 'ValueError', 'UnicodeDecodeError', 'UnicodeEncodeError', 'FileExistsError', 'FileNotFoundError', 'PermissionError', 'OSError', 'JSONDecodeError'].includes(failure.reason) ? { recordingFailure: { phase: failure.phase, reason: failure.reason } } : {}) } : {}),
    note: 'Style metadata observation only; not visual certification, independent proof or delivery.' };
}
