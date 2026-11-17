import type { ShellEvidence } from './knot-shell';
import type { DocumentManifest } from './knot-documents';
import { rawDocumentFormat, requestedDocumentFormat, documentFormatIssue, officeAliasDocumentRequest, type DocumentFormatBinding } from './knot-document-format';
import { verifiedDocumentExecution, documentMarkupPattern, documentStructuralMarkupPattern } from './knot-document-build';

export type DocumentProof = { version: 'knot_document_proof_v1'; sourceSHA256: string; sourceSize: number; format: string; renderedPages: number; textSHA256: string; markupScan: 'clear'; renderer: 'poppler'; producerChecked: boolean; structureChecked?: true; allPageProofs?: true; textPath?: string; textSize?: number };
export function playableGameRequest(text: string): boolean {
  // An explicit explanatory deliverable still takes its document lane.
  return !/\b(?:pdf|docx|xlsx|pptx|guide|report|document|manual|walkthrough|handout|instructions|tutorial)\b/i.test(text) && /\b(?:game|rpg|role[- ]playing|platformer|playable)\b/i.test(text) && /\b(?:create|make|build|write|generate|produce|develop|code|playable)\b/i.test(text);
}
/** Classification chooses verification/presentation, not whether an owned
 * shell can author an object. Unknown extensions use opaque immutable capture;
 * known PDF/Office/raw deliverables retain their stronger independent gates. */
export function generalArtifactRequest(text: string): boolean {
  const requestedWork = /\b(?:create|make|build|write|generate|produce|develop|code|playable|save|export|convert|deliver)\b/i.test(text);
  if (!requestedWork) return false;
  if (officeAliasDocumentRequest(text)) return false;
  const binding = requestedDocumentFormat(text);
  if (binding.status === 'unsupported') return true;
  if (binding.status === 'bound' && ['pdf', 'docx', 'xlsx', 'pptx', 'txt', 'md', 'csv', 'json'].includes(binding.format) && /\b(?:pdf|docx|xlsx|pptx|txt|md|markdown|plain text|csv|json)\b/i.test(text)) return false;
  const executable = /\b(?:interactive|animated|animation|explorer|game|rpg|role[- ]playing|platformer|playable|app|website)\b/i.test(text);
  const explanatory = /\b(?:write|create|make|produce|generate)\s+(?:(?:me|a|an|the|complete|detailed|research)\s+){0,5}(?:guide|report|document|manual|walkthrough|handout|instructions|tutorial)\s+(?:about|on|for|explaining)\b/i.test(text);
  return executable && !explanatory && /\b(?:create|make|build|write|generate|produce|develop|code|playable)\b/i.test(text);
}
export function knotArtifactRouting(request: string, classifiedDocument = false): { generalCreate: boolean; documentTask: boolean; documentFormat?: DocumentFormatBinding; artifactFormat?: string } {
  const generalCreate = generalArtifactRequest(request);
  const binding = requestedDocumentFormat(request);
  const documentTask = !generalCreate && (classifiedDocument || documentRequest(request));
  // Fresh implicit playable games use the existing separate HTML author lane.
  // Explicit extensions/ambiguous formats win; historical workflows are never
  // rewritten and still require their original artifactFormat to enter it.
  const implicitHTMLGame = generalCreate && playableGameRequest(request) && binding.status === 'bound' && binding.format === 'pdf';
  return { generalCreate, documentTask, ...(documentTask ? { documentFormat: binding } : generalCreate && (binding.status === 'unsupported' || binding.status === 'bound' && binding.format === 'html') ? { artifactFormat: binding.format } : implicitHTMLGame ? { artifactFormat: 'html' } : {}) };
}
/** Shared bounded authoring transport only. A game remains general creation:
 * no document classification, PDF guide, renderer, or page-review semantics. */
export function slicedHTMLArtifact(workflow: { mode: string; originalRequest: string; documentTask?: boolean; artifactFormat?: string } | undefined): boolean {
  if (!workflow || workflow.mode !== 'Create' || workflow.documentTask || workflow.artifactFormat !== 'html') return false;
  const route = knotArtifactRouting(workflow.originalRequest);
  return route.generalCreate && route.artifactFormat === 'html';
}
export function documentRequest(text: string): boolean {
  if (generalArtifactRequest(text)) return false;
  if (officeAliasDocumentRequest(text)) return true;
  return /\b(?:pdf|docx|xlsx|pptx|document|report|manuscript|brochure|résumé|resume|spreadsheet|presentation|handout)\b/i.test(text) || /\b(?:write|save|export|deliver|send|share|produce|generate|convert|rebuild|make|create)\s+(?:(?:me|it|this|that|a|an|the|raw|final|as|in|to|into|complete)\s+){0,7}(?:markdown|plain text|txt|md|html|csv|json)\b(?!\s+(?:parser|renderer|editor|syntax|highlighter|serializer|validator|library|compiler|tokenizer|processor|game|app|website|page|component|tool|button|canvas)\b)/i.test(text) || /\b(?:write|save|export|deliver|send|share|produce|generate|convert|rebuild|make|create)\b[^\n]{0,150}\b(?:as|in|into|to)\s+(?:(?:a|an|the|raw|final|native|actual)\s+)*(?:markdown|plain text|txt|md|html|csv|json)\b/i.test(text) || /\b(?:create|write|save|export|deliver|send|make|produce|generate|convert|rebuild)\b[^\n]{0,150}(?:\b(?:txt|md|markdown|plain text|html|csv|json|rtf|odt|epub)\b[^\n]{0,30}\b(?:file|format|document)\b|\bfile\b[^\n]{0,30}\b(?:txt|md|markdown|plain text|html|csv|json)\b)/i.test(text) || /\b(?:create|write|save|export|deliver|send|make|produce|generate|convert|rebuild)\b[^\n]{0,150}\b[a-z0-9_-]+\.(?:txt|md|html|csv|json|rtf|odt|epub)(?=$|[\s,;:!?"'`)\]])/i.test(text) || /\b(?:convert|rebuild|export)\b[^\n]{0,100}\b(?:markdown|html|word|excel|slides)\b/i.test(text);
}
export function needsDocumentProof(manifest: DocumentManifest, documentTask = false, binding?: DocumentFormatBinding): boolean {
  if (binding && !documentFormatIssue(binding, manifest.path, manifest.format) && rawDocumentFormat(binding.format)) return false;
  return ['pdf', 'docx', 'xlsx', 'pptx'].includes(manifest.format) || documentTask;
}
// Accept the actual index's Markdown file link, directory link or catalog
// token. Boundaries exclude traversal, foreign absolute paths and URL suffixes.
const indexedDocumentPath = String.raw`(?:^|[\s\x60*"'(<\[|])((?:/opt/knot-skills/|\./)?(?:[a-zA-Z0-9_-]+/)*document-creation(?:/SKILL\.md|/)?)(?=$|[\s\x60*"')>\]|,;:])`;
export function indexedDocumentSkill(index: string): string | undefined { return indexedSkill(index, indexedDocumentPath); }
/** games-web is an actual entry in the observed live catalog, not bundled
 * guidance. Only a complete successful index receipt chooses its read path. */
export function indexedHTMLGameSkill(index: string, request: string): string | undefined {
  // Use the already-established general-create semantics. A game's explicit
  // "not a guide" requirement must not suppress its real indexed skill read.
  return generalArtifactRequest(request) && /\b(?:game|rpg|role[- ]playing|platformer|playable)\b/i.test(request) ? indexedSkill(index, indexedDocumentPath.replace('document-creation', 'games-web')) : undefined;
}
function indexedSkill(index: string, pattern: string): string | undefined {
  const candidates = [...index.matchAll(new RegExp(pattern, 'gm'))].map(match => match[1]);
  const paths = [...new Set(candidates.map(path => {
    const relative = path.replace(/^\/opt\/knot-skills\//, '').replace(/^\.\//, '').replace(/\/$/, '');
    return '/opt/knot-skills/' + relative + (relative.endsWith('/SKILL.md') ? '' : '/SKILL.md');
  }))];
  return paths.length === 1 ? 'cat ' + paths[0] : undefined;
}

/** A missing parsed path is a read step, not a premature tool rejection.
 * Resolve against the live index in the owned shell; read no unindexed guide.
 * This fixed read advances the prerequisite only on a complete successful
 * command receipt, just like an explicit indexed cat. No workspace file writes. */
export const documentSkillReadCommand = `command -p python3 -I - <<'KNOT_DOCUMENT_GUIDE'
from pathlib import Path
import re
root=Path('/opt/knot-skills')
index=(root/'README.md').read_text(encoding='utf-8')
pattern=${JSON.stringify(indexedDocumentPath)}
paths=set()
for match in re.finditer(pattern,index,re.M):
    path=match[1]
    path=re.sub(r'^/opt/knot-skills/|^\\./','',path).rstrip('/')
    if not path.endswith('/SKILL.md'): path+='/SKILL.md'
    paths.add(path)
assert len(paths)==1, 'document_skill_index_unresolved'
relative=Path(next(iter(paths)))
assert not relative.is_absolute() and all(part not in ('.','..') for part in relative.parts)
skill=root/relative
assert skill.resolve(strict=True).is_relative_to(root.resolve(strict=True))
assert skill.is_file() and 0<skill.stat().st_size<=1000000
text=skill.read_text(encoding='utf-8')
assert text.strip(), 'document_skill_empty'
print(text,end='')
KNOT_DOCUMENT_GUIDE`;

/** Fixed verification, NOT authoring or regeneration. It runs only as a new
 * owned foreground executor step; the source is never rewritten. All input
 * paths/hashes came from the successful parent receipt and are rechecked.
 * Unsupported formats/tools or bounded-out checks fail closed, preserving bytes. */
export function documentProofCommand(manifest: DocumentManifest, sourceProposalID: string, contentEvidence = false, structural = false, allPages = false, ownedTiming = false): string {
  if (!/^[0-9a-f-]{36}$/.test(sourceProposalID)) throw new Error('invalid_document_proof');
  const input = JSON.stringify({ path: manifest.path, sha256: manifest.sha256, size: manifest.size, format: manifest.format, pages: manifest.pages, pagesPending: manifest.pagesPending, bundle: manifest.bundle, ...(manifest.title !== undefined ? { title: manifest.title } : {}), ...(manifest.deliveryLabel !== undefined ? { deliveryLabel: manifest.deliveryLabel } : {}) });
  return `command -p python3 -I - <<'KNOT_FINAL_FILE_PROOF'
from pathlib import Path
import hashlib,json,os,re,subprocess,time,zipfile,struct
c=json.loads(${JSON.stringify(input)})
root=Path.cwd().resolve()
started=time.monotonic()
env={'PATH':'/usr/bin:/usr/local/bin:/bin','LC_ALL':'C','HOME':str(root)}
def source():
    p=Path(c['path'])
    assert not p.is_absolute() and all(not Path(*p.parts[:i+1]).is_symlink() for i in range(len(p.parts)))
    assert p.resolve().is_relative_to(root) and p.is_file() and p.stat().st_size==c['size']
    b=p.read_bytes()
    assert len(b)==c['size'] and hashlib.sha256(b).hexdigest()==c['sha256']
    return p,b
def run(args,output):
    remaining=${ownedTiming ? 540 : 100}-(time.monotonic()-started)
    assert remaining>1
    with output.open('xb') as out:
        done=subprocess.run(args,stdout=out,stderr=subprocess.DEVNULL,timeout=${ownedTiming ? 'remaining' : 'min(remaining,35)'},env=env,check=True)
    assert output.stat().st_size<=10000000
    return output.read_bytes()
p,b=source()
assert c['format'] in ('pdf','docx','xlsx','pptx'), 'document_proof_format_unsupported'
proofdir=root/'deliverables'/'knot-proof-${sourceProposalID}'
assert not (root/'deliverables').is_symlink()
proofdir.mkdir(parents=True,exist_ok=False)
pdf=p.resolve()
if c['format']!='pdf':
    with zipfile.ZipFile(p) as z:
        names=z.namelist()
        required={'docx':'word/document.xml','xlsx':'xl/workbook.xml','pptx':'ppt/presentation.xml'}[c['format']]
        assert required in names and '[Content_Types].xml' in names
        assert len(names)<=5000 and sum(x.file_size for x in z.infolist())<=200000000
        assert not any('vbaProject' in n or n.endswith('.bin') or '/embeddings/' in n for n in names)
    # Render an EXISTING Office final into a separate proof directory only.
    # An isolated LibreOffice profile avoids touching the user's browser/session.
    run(['/usr/bin/libreoffice','-env:UserInstallation='+ (proofdir/'office-profile').as_uri(),'--headless','--convert-to','pdf','--outdir',str(proofdir),str(p.resolve())],proofdir/'conversion.log')
    pdf=proofdir/(p.stem+'.pdf')
    assert pdf.is_file() and 0<pdf.stat().st_size<=50000000
render_bytes=pdf.read_bytes()
assert render_bytes.startswith(b'%PDF-') and b'%%EOF' in render_bytes[-2048:]
info=run(['/usr/bin/pdfinfo',str(pdf)],proofdir/'info.txt').decode('utf-8',errors='replace')
match=re.search(r'^Pages:\\s+(\\d+)',info,re.M)
assert match
pages=int(match[1])
assert 1<=pages<=300 and (pages==c['pages'] or (c.get('pagesPending') is True and c['format']!='pdf' and c['pages']==0))
${structural ? '# Producer metadata is informational, not a renderer brand allowlist.\n# Independent structure, text, every-page render and immutable-byte checks remain mandatory.' : "producer=re.search(r'^Producer:\\s+(.+)',info,re.M)\nassert producer and re.search(r'WeasyPrint|LibreOffice',producer[1],re.I), 'document_producer_unverified'\n# This is a metadata/format check, not cryptographic proof of original authorship."}
text=run(['/usr/bin/pdftotext','-enc','UTF-8',str(pdf),'-'],proofdir/'text.txt')
t=text.decode('utf-8',errors='strict')
assert t.strip(), 'document_text_unreadable'
markup=${JSON.stringify(structural ? documentStructuralMarkupPattern : documentMarkupPattern)}
assert not re.search(markup,t,re.I), 'document_literal_markup_detected'
sampled=${allPages ? 'list(range(1,pages+1))' : 'list(range(1,pages+1)) if pages<=12 else sorted(set((1,(pages+1)//2,pages)))'}
proofs=[]
total=0
for page in range(1,pages+1):
    assert time.monotonic()-started<${ownedTiming ? 540 : 100}
    prefix=proofdir/('page-'+str(page))
    run(['/usr/bin/pdftoppm','-f',str(page),'-l',str(page),'-singlefile','-scale-to','900','-png',str(pdf),str(prefix)],proofdir/('render-'+str(page)+'.log'))
    image=prefix.with_suffix('.png')
    assert image.is_file() and 33<=image.stat().st_size<=1800000
    png=image.read_bytes()
    assert png[:8]==bytes((137,80,78,71,13,10,26,10)) and png[12:16]==b'IHDR'
    width,height=struct.unpack('>II',png[16:24])
    assert 320<=width<=2200 and 320<=height<=2200 and width*height<=4000000
    if page in sampled:
        total+=len(png)
        assert total<=${allPages ? '50000000' : '2800000'}
        proofs.append(dict(path=image.relative_to(root).as_posix(),sha256=hashlib.sha256(png).hexdigest(),page=page,sourceSHA256=c['sha256']))
    else:
        # Only this verifier's own disposable render, never the shipped file.
        image.unlink()
source()
verification=dict(version='knot_document_proof_v1',sourceSHA256=c['sha256'],sourceSize=c['size'],format=c['format'],renderedPages=pages,textSHA256=hashlib.sha256(text).hexdigest(),markupScan='clear',renderer='poppler',producerChecked=${structural ? 'False,structureChecked=True' : 'True'}${allPages ? ',allPageProofs=True' : ''}${contentEvidence ? ",textPath=(proofdir/'text.txt').relative_to(root).as_posix(),textSize=len(text)" : ''})
result=dict(path=c['path'],sha256=c['sha256'],size=c['size'],format=c['format'],pages=pages,proofs=proofs,verification=verification${manifest.title !== undefined ? ",title=c['title']" : ''}${manifest.deliveryLabel !== undefined ? ",deliveryLabel=c['deliveryLabel']" : ''})
print('KNOT_DOCUMENT_V1 '+json.dumps(result,separators=(',',':')))
KNOT_FINAL_FILE_PROOF`;
}

/** A model's own pass:true, stdout, proof filename or sourceSHA256 declaration
 * is never sufficient. Exact server-derived command + owned complete receipt
 * + final-byte capture + independently read PNG hashes are required. */
export function verifiedDocumentProof(receipt: ShellEvidence, manifest: DocumentManifest): DocumentProof | undefined {
  const prepared = receipt.workflow?.documentProof;
  const v = manifest.verification;
  // Exact agent-code invocation + measured source/final receipts, not a printed
  // converter name or producer metadata alone. No backend-authored build exists.
  if (!verifiedDocumentExecution(receipt, manifest)) return undefined;
  if (!prepared || receipt.reviewedCommand !== documentProofCommand(prepared.manifest, prepared.sourceProposalID, receipt.workflow?.documentPolicy === 'author_v1', receipt.workflow?.documentValidation === 'structural_v2', receipt.workflow?.documentQuality === 'quality_v1', receipt.workflow?.executionTiming === 'owned_v2') ||
      receipt.status !== 'completed' || receipt.exitCode !== 0 || !receipt.sessionID || !receipt.outputComplete || !receipt.terminationConfirmed || receipt.truncated || receipt.contextTruncated ||
      !v || v.version !== 'knot_document_proof_v1' || v.sourceSHA256 !== manifest.sha256 || v.sourceSize !== manifest.size || v.format !== manifest.format ||
      v.renderedPages !== manifest.pages || v.markupScan !== 'clear' || v.renderer !== 'poppler' || (receipt.workflow?.documentValidation === 'structural_v2' ? v.structureChecked !== true || v.producerChecked !== false : v.producerChecked !== true) || !/^[a-f0-9]{64}$/.test(v.textSHA256) ||
      manifest.sha256 !== prepared.manifest.sha256 || manifest.path !== prepared.manifest.path || manifest.format !== prepared.manifest.format || manifest.size !== prepared.manifest.size || (manifest.pages !== prepared.manifest.pages && !(prepared.manifest.pagesPending === true && prepared.manifest.pages === 0 && manifest.format !== 'pdf')) || manifest.pagesPending || manifest.proofIssue) return undefined;
  if (receipt.workflow?.documentPolicy === 'author_v1' && (v.textPath !== 'deliverables/knot-proof-' + prepared.sourceProposalID + '/text.txt' || !Number.isSafeInteger(v.textSize) || v.textSize! < 1 || v.textSize! > 10000000)) return undefined;
  if (receipt.workflow?.documentQuality === 'quality_v1' && (v.allPageProofs !== true || manifest.proofs.length !== manifest.pages)) return undefined;
  const required = receipt.workflow?.documentQuality === 'quality_v1' || manifest.pages <= 12 ? Array.from({ length: manifest.pages }, (_, i) => i + 1) : [1, Math.ceil(manifest.pages / 2), manifest.pages];
  return required.every(page => manifest.proofs.some(p => p.page === page)) ? v : undefined;
}
