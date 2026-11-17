import type { DocumentSource } from './knot-document-build';

/** Operator-supplied pins, not a claim that this environment inspected or
 * installed these stylesheets. The owned adapter verifies actual bytes. */
export const knotDocumentTemplates = {
  'guide@1.0.0': '5644f23b05dd7db6e4984cf2fc3937ec12597adb2d04097aa2a3ee97d6eeb500',
  'report@1.0.0': '6c17c1dddbfc79c53ac8f85b39740ef6b5c8c0c7fadcd41ffb4068c761868666',
  'letter@1.0.0': '1a5798b5f2c6050cf5a40b4aecc2f28bca2be9c9920c513f32c21847e63235ef',
} as const;
export type KnotDocumentTemplate = keyof typeof knotDocumentTemplates;
export function selectedDocumentTemplate(request: string): KnotDocumentTemplate | undefined {
  // Subject matter is not template consent. Only an explicit house/plain/template
  // request selects this path; retained workflows keep their recorded selection.
  if (/\b(?:not|no|without|rather than)\s+(?:(?:a|an|the|house|plain)\s+)*template\b/i.test(request)) return undefined;
  const pinned = request.match(/\b(guide|report|letter)@1\.0\.0\b/i);
  if (pinned) return (pinned[1].toLowerCase() + '@1.0.0') as KnotDocumentTemplate;
  if (!/\b(?:(?:house|plain)\s+(?:style|template|design)|(?:use|using|with)\s+(?:(?:a|an|the|house|plain|guide|report|letter)\s+)*template)\b/i.test(request)) return undefined;
  return /\b(?:letter|correspondence|cover letter)\b/i.test(request) ? 'letter@1.0.0'
    : /\b(?:report|analysis|findings|brief|research)\b/i.test(request) ? 'report@1.0.0' : 'guide@1.0.0';
}
export const documentTemplateContract = 'FRESH HOUSE-TEMPLATE HTML: the owned workflow explicitly selects guide@1.0.0, report@1.0.0 or letter@1.0.0. Author complete semantic HTML ONLY: html/head/title/body, article/header/main/section/footer, headings, paragraphs, lists, tables, blockquotes and semantic emphasis. Use semantic class names such as guide/report/letter, subtitle, callout, note, recipe, ingredients and steps where appropriate. The installed stylesheet, not agent CSS, owns typography, spacing, colors and page layout. Never include style/link/script/font tags, inline style, font/color/presentational attributes, remote resources or authored CSS. A styled source is rejected and needs a genuinely NEW semantic source; original files are preserved. For HTML-to-PDF select the advertised pinned knot-doc build with empty code. A backend-owned adapter verifies the selected installed CSS hash, applies it inline to a NEW hash-bound prepared HTML file and records a separate template intent/staged journal around the unchanged pinned v2 renderer. This is NOT a new knot-doc flag or a claim that its native journal supports templates. Deny-all remains unchanged. Markdown PDF retains the v2 house path. Raw files and Office never use templates. Independent all-page proof, content/visual review and immutable capture remain mandatory.';

/** Decorate only a newly negotiated v2 HTML transport. Historical commands are
 * never passed here. The original source and the renderer's own journal remain
 * intact; the outer journal binds semantic/CSS/prepared/renderer/final bytes. */
export function templateResidentCommand(base: string, source: DocumentSource, template: KnotDocumentTemplate): string {
  const sha256 = Object.hasOwn(knotDocumentTemplates, template) ? knotDocumentTemplates[template] : undefined;
  if (!sha256 || source.format !== 'html') throw new Error('invalid_document_template');
  const markers = ['def check_source():', "p=path(c['path'])\nassert not p.exists() and p.parent.is_dir(), 'document_output_exists'", 'check_source()\npinned()', 'evidence=dict(version='];
  if (markers.some(marker => base.split(marker).length !== 2)) throw new Error('invalid_document_template_adapter');
  const helpers = `
semantic=dict(c['source'])
template=${JSON.stringify(template)}
templateSHA256='${sha256}'
style=Path('/opt/knot-tools/templates/'+template+'.css')
def template_bytes():
    assert all(not parent.is_symlink() for parent in [style,*style.parents]), 'document_template_unverified'
    assert style.is_file() and 0<style.stat().st_size<=100000, 'document_template_unverified'
    b=style.read_bytes()
    assert digest(b)==templateSHA256, 'document_template_unverified'
    return b
def check_semantic():
    b=measured(semantic['path'],1000000)
    assert digest(b)==semantic['sha256'] and len(b)==semantic['size'], 'document_source_changed'
    return b
from html.parser import HTMLParser
class Semantics(HTMLParser):
    def handle_starttag(self,tag,attrs):
        assert tag in 'html head title meta body article header main section footer h1 h2 h3 h4 h5 h6 p ul ol li table thead tbody tfoot tr th td caption colgroup col div span strong em b i code pre blockquote dl dt dd br hr small sup sub a time figure figcaption'.split(), 'document_template_semantics_required'
        for key,value in attrs:
            assert key in 'class id lang dir title charset name content datetime colspan rowspan scope headers href'.split(), 'document_template_semantics_required'
            assert key!='href' or value and (value.startswith('#') or re.match(r'https?://',value)), 'document_template_semantics_required'
        assert tag!='meta' or all(key!='http-equiv' for key,_ in attrs), 'document_template_semantics_required'
    def handle_startendtag(self,tag,attrs): self.handle_starttag(tag,attrs)
def prepare_template():
    original=check_semantic().decode('utf-8',errors='strict')
    parser=Semantics(convert_charrefs=True); parser.feed(original); parser.close()
    assert re.search(r'<html(?:\\s[^>]*|)>',original,re.I) and re.search(r'<head(?:\\s[^>]*|)>',original,re.I) and re.search(r'</head\\s*>',original,re.I) and re.search(r'<body(?:\\s[^>]*|)>',original,re.I), 'document_template_semantics_required'
    css=template_bytes().decode('utf-8',errors='strict')
    assert '</style' not in css.lower(), 'document_template_unverified'
    prepared=re.sub(r'</head\\s*>',lambda _: '<style>'+css+'</style></head>',original,count=1,flags=re.I).encode('utf-8')
    assert len(prepared)<=1000000
    target=path(c['path'][:-4]+'.template.html')
    with target.open('xb') as f: assert f.write(prepared)==len(prepared)
    c['source']=dict(path=str(target),sha256=digest(prepared),size=len(prepared),format='html')
    inputs=dict(design='template',template=template,templateSHA256=templateSHA256,source=semantic,preparedSource=c['source'],resourcePolicy='deny-all-v1',toolSHA256='d4447d5720521af2e95dcc5b4671f54a7033e14bf2faa3245d0b0b6680e38f78')
    payload=(json.dumps(inputs,separators=(',',':'))+'\\n').encode('utf-8')
    directory=path('.knot-doc/templates/'+c['taskID'],True); directory.mkdir(parents=True,exist_ok=True)
    journal=directory/(digest(payload)+'.jsonl')
    with journal.open('xb') as f: f.write((json.dumps(dict(state='intent',taskID=c['taskID'],output=c['path'],inputs=inputs),separators=(',',':'))+'\\n').encode('utf-8'))
    return inputs,journal
`;
  let command = base.replace('def check_source():', helpers + '\ndef check_source():');
  command = command.replace("p=path(c['path'])\nassert not p.exists() and p.parent.is_dir(), 'document_output_exists'", "p=path(c['path'])\nassert not p.exists() and p.parent.is_dir(), 'document_output_exists'\ntemplateInputs,templateJournal=prepare_template()\ncheck_source()");
  command = command.replace("check_source()\npinned()", "check_source()\ncheck_semantic()\ntemplate_bytes()\npinned()");
  const journal = `
with templateJournal.open('ab') as f: f.write((json.dumps(dict(state='staged',taskID=c['taskID'],output=c['path'],rendererInputsSHA256=m['inputsSHA256'],rendererJournalSHA256=digest(journal),finalSHA256=digest(final),finalBytes=len(final)),separators=(',',':'))+'\\n').encode('utf-8'))
outer=measured(str(templateJournal),1000000,True)
outerEntries=[json.loads(line) for line in outer.decode('utf-8',errors='strict').splitlines()]
assert len(outerEntries)==2 and outerEntries[0]==dict(state='intent',taskID=c['taskID'],output=c['path'],inputs=templateInputs)
assert outerEntries[1]==dict(state='staged',taskID=c['taskID'],output=c['path'],rendererInputsSHA256=m['inputsSHA256'],rendererJournalSHA256=digest(journal),finalSHA256=digest(final),finalBytes=len(final))
assert templateJournal.name==digest((json.dumps(templateInputs,separators=(',',':'))+'\\n').encode('utf-8'))+'.jsonl'
check_semantic(); template_bytes(); check_source()
assert measured(c['path'])==final, 'document_bytes_changed'
templateEvidence=dict(inputs=templateInputs,entries=outerEntries,journal=dict(path=str(templateJournal),sha256=digest(outer),size=len(outer)))
`;
  command = command.replace("evidence=dict(version=", journal + "evidence=dict(templateEvidence=templateEvidence,version=");
  if (command === base || new TextEncoder().encode(command).length > 12000) throw new Error('invalid_command_size_or_text');
  return command;
}

export function verifiedTemplateEvidence(value: any, source: DocumentSource, template: KnotDocumentTemplate): boolean {
  try {
    if (!Object.hasOwn(knotDocumentTemplates, template) || source.format !== 'html') return false;
    const evidence = value?.templateEvidence, inputs = evidence?.inputs, prepared = inputs?.preparedSource;
    const intent = evidence?.entries?.[0], staged = evidence?.entries?.[1], m = value?.manifest;
    const hash = (v: unknown) => typeof v === 'string' && /^[a-f0-9]{64}$/.test(v);
    return !!inputs && inputs.design === 'template' && inputs.template === template && inputs.templateSHA256 === knotDocumentTemplates[template] &&
      inputs.resourcePolicy === 'deny-all-v1' && inputs.toolSHA256 === 'd4447d5720521af2e95dcc5b4671f54a7033e14bf2faa3245d0b0b6680e38f78' && inputs.toolSHA256 === value.toolSHA256 &&
      inputs.source?.path === source.path && inputs.source?.sha256 === source.sha256 && inputs.source?.size === source.size && inputs.source?.format === 'html' &&
      prepared?.path === m.path.replace(/\.pdf$/, '.template.html') && hash(prepared.sha256) && Number.isSafeInteger(prepared.size) && prepared.size > 0 && prepared.size <= 1000000 && prepared.format === 'html' &&
      m.sourceSHA256 === prepared.sha256 && value.inputs.sourceSHA256 === prepared.sha256 && value.inputs.sourceBytes === prepared.size && value.inputs.sourceFormat === 'html' &&
      Array.isArray(evidence.entries) && evidence.entries.length === 2 && intent.state === 'intent' && intent.taskID === m.taskID && intent.output === m.path && JSON.stringify(intent.inputs) === JSON.stringify(inputs) &&
      staged.state === 'staged' && staged.taskID === m.taskID && staged.output === m.path && staged.rendererInputsSHA256 === m.inputsSHA256 && staged.rendererJournalSHA256 === value.journal.sha256 && staged.finalSHA256 === m.sha256 && staged.finalBytes === m.size &&
      typeof evidence.journal?.path === 'string' && evidence.journal.path.startsWith('.knot-doc/templates/' + m.taskID + '/') && /^[a-f0-9]{64}\.jsonl$/.test(evidence.journal.path.slice(('.knot-doc/templates/' + m.taskID + '/').length)) && hash(evidence.journal.sha256) && Number.isSafeInteger(evidence.journal.size) && evidence.journal.size > 0 && evidence.journal.size <= 1000000;
  } catch { return false; }
}
