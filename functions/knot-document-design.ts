import type { DocumentSource } from './knot-document-build';

/** Fresh opt-in outer journal only. Never modifies a pinned utility, its native
 * journal, a historical command, source HTML or final PDF. */
export function authoredDesignResidentCommand(base: string, recordOnly = false): string {
  const markers = ['def check_source():', "assert not p.exists() and p.parent.is_dir(), 'document_output_exists'", 'evidence=dict(version='];
  if (markers.some(marker => base.split(marker).length !== 2)) throw new Error('invalid_document_design_adapter');
  const helpers = `
from html.parser import HTMLParser
class DesignStyles(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True); self.records=[]; self.style_index=None
    def handle_starttag(self,tag,attrs):
        if tag=='style': self.style_index=len(self.records); self.records.append(['style',''])
        for key,value in attrs:
            if key=='style': self.records.append(['inline',value or ''])
    def handle_endtag(self,tag):
        if tag=='style': self.style_index=None
    def handle_data(self,data):
        if self.style_index is not None: self.records[self.style_index][1]+=data
def design_inputs():
    original=measured(c['source']['path'],1000000)
    assert digest(original)==c['source']['sha256'] and len(original)==c['source']['size'], 'document_source_changed'
    parser=DesignStyles(); parser.feed(original.decode('utf-8',errors='strict')); parser.close()
    assert parser.records and any(value.strip() for _,value in parser.records), 'document_authored_style_required'
    styles=json.dumps(parser.records,ensure_ascii=False,separators=(',',':')).encode('utf-8')
    return dict(design='authored-inline-v1',styleEncoding='html-parser-style-records-v1',source=dict(c['source']),styleSHA256=digest(styles),styleBytes=len(styles),resourcePolicy='deny-all-v1')
def design_intent():
    inputs=design_inputs()
    payload=(json.dumps(dict(taskID=c['taskID'],output=c['path'],inputs=inputs),separators=(',',':'))+'\\n').encode('utf-8')
    directory=path('.knot-doc/design/'+c['taskID'],True); directory.mkdir(parents=True,exist_ok=True)
    target=directory/(digest(payload)+'.jsonl')
    with target.open('xb') as f: f.write((json.dumps(dict(state='intent',taskID=c['taskID'],output=c['path'],inputs=inputs),separators=(',',':'))+'\\n').encode('utf-8'))
    return inputs,target
`;
  let command = base.replace('def check_source():', helpers + '\ndef check_source():');
  const intent = recordOnly ? `designInputs,designJournal=None,None
try:
    designInputs,designJournal=design_intent()
except (AssertionError,ValueError,UnicodeError,OSError) as error:
    designFailure=dict(phase='intent',reason=type(error).__name__)
` : 'designInputs,designJournal=design_intent()';
  command = command.replace("assert not p.exists() and p.parent.is_dir(), 'document_output_exists'", "assert not p.exists() and p.parent.is_dir(), 'document_output_exists'\n" + intent);
  const staged = `
assert design_inputs()==designInputs, 'document_source_changed'
with designJournal.open('ab') as f: f.write((json.dumps(dict(state='staged',taskID=c['taskID'],output=c['path'],rendererInputsSHA256=m['inputsSHA256'],rendererJournalSHA256=digest(journal),finalSHA256=digest(final),finalBytes=len(final)),separators=(',',':'))+'\\n').encode('utf-8'))
designBytes=measured(str(designJournal),1000000,True)
designEntries=[json.loads(line) for line in designBytes.decode('utf-8',errors='strict').splitlines()]
assert len(designEntries)==2 and designEntries[0]==dict(state='intent',taskID=c['taskID'],output=c['path'],inputs=designInputs)
assert designEntries[1]==dict(state='staged',taskID=c['taskID'],output=c['path'],rendererInputsSHA256=m['inputsSHA256'],rendererJournalSHA256=digest(journal),finalSHA256=digest(final),finalBytes=len(final))
assert measured(c['path'])==final, 'document_bytes_changed'
designEvidence=dict(inputs=designInputs,entries=designEntries,journal=dict(path=str(designJournal),sha256=digest(designBytes),size=len(designBytes)))
`;
  // Only optional CSS extraction/journal availability is advisory. Source/final
  // bytes are checked outside the catch; a readable contradictory journal is
  // still a provenance failure, never relabelled a harmless style gap.
  const recorded = `
check_source()
designEvidence=dict(status='unavailable',failure=designFailure) if designInputs is None else None
if designInputs is not None:
    assert design_inputs()==designInputs, 'document_source_changed'
    try:
        with designJournal.open('ab') as f: f.write((json.dumps(dict(state='staged',taskID=c['taskID'],output=c['path'],rendererInputsSHA256=m['inputsSHA256'],rendererJournalSHA256=digest(journal),finalSHA256=digest(final),finalBytes=len(final)),separators=(',',':'))+'\\n').encode('utf-8'))
        designBytes=measured(str(designJournal),1000000,True)
        designEntries=[json.loads(line) for line in designBytes.decode('utf-8',errors='strict').splitlines()]
    except (AssertionError,ValueError,UnicodeError,OSError) as error:
        designEvidence=dict(status='unavailable',failure=dict(phase='staged',reason=type(error).__name__))
    else:
        assert len(designEntries)==2 and designEntries[0]==dict(state='intent',taskID=c['taskID'],output=c['path'],inputs=designInputs), 'document_design_journal_changed'
        assert designEntries[1]==dict(state='staged',taskID=c['taskID'],output=c['path'],rendererInputsSHA256=m['inputsSHA256'],rendererJournalSHA256=digest(journal),finalSHA256=digest(final),finalBytes=len(final)), 'document_design_journal_changed'
        designEvidence=dict(inputs=designInputs,entries=designEntries,journal=dict(path=str(designJournal),sha256=digest(designBytes),size=len(designBytes)))
check_source()
assert measured(c['path'])==final, 'document_bytes_changed'
`;
  command = command.replace('evidence=dict(version=', (recordOnly ? recorded : staged) + 'evidence=dict(designEvidence=designEvidence,version=');
  if (command === base || new TextEncoder().encode(command).length > 12000) throw new Error('invalid_command_size_or_text');
  return command;
}
/** Optional metadata may be absent, but present contradictory provenance is
 * never admitted by the record-only policy. This is not a style-quality check. */
export function authoredDesignBindingsValid(value: any, source: DocumentSource): boolean {
  const evidence = value?.designEvidence, m = value?.manifest;
  const matches = (actual: unknown, expected: unknown) => actual === undefined || actual === expected;
  const original = evidence?.inputs?.source;
  if (original !== undefined && (!original || typeof original !== 'object' || !matches(original.path, source.path) || !matches(original.sha256, source.sha256) || !matches(original.size, source.size) || !matches(original.format, source.format))) return false;
  if (Array.isArray(evidence?.entries)) for (const entry of evidence.entries) {
    if (!entry || typeof entry !== 'object') continue;
    if (!matches(entry.taskID, m?.taskID) || !matches(entry.output, m?.path)) return false;
    if (entry.state === 'staged' && (!matches(entry.rendererInputsSHA256, m?.inputsSHA256) || !matches(entry.rendererJournalSHA256, value?.journal?.sha256) || !matches(entry.finalSHA256, m?.sha256) || !matches(entry.finalBytes, m?.size))) return false;
    const bound = entry.inputs?.source;
    if (bound !== undefined && (!bound || !matches(bound.path, source.path) || !matches(bound.sha256, source.sha256) || !matches(bound.size, source.size) || !matches(bound.format, source.format))) return false;
  }
  if (typeof evidence?.journal?.path === 'string' && !evidence.journal.path.startsWith('.knot-doc/design/' + m?.taskID + '/')) return false;
  return true;
}
export function verifiedAuthoredDesignEvidence(value: any, source: DocumentSource): boolean {
  try {
    const evidence = value?.designEvidence, inputs = evidence?.inputs;
    const intent = evidence?.entries?.[0], staged = evidence?.entries?.[1], m = value?.manifest;
    const hash = (v: unknown) => typeof v === 'string' && /^[a-f0-9]{64}$/.test(v);
    return source.format === 'html' && inputs?.design === 'authored-inline-v1' && inputs.styleEncoding === 'html-parser-style-records-v1' &&
      inputs.resourcePolicy === 'deny-all-v1' && hash(inputs.styleSHA256) && Number.isSafeInteger(inputs.styleBytes) && inputs.styleBytes > 0 && inputs.styleBytes <= 1000000 &&
      inputs.source?.path === source.path && inputs.source?.sha256 === source.sha256 && inputs.source?.size === source.size && inputs.source?.format === 'html' &&
      Array.isArray(evidence.entries) && evidence.entries.length === 2 && intent.state === 'intent' && intent.taskID === m.taskID && intent.output === m.path && JSON.stringify(intent.inputs) === JSON.stringify(inputs) &&
      staged.state === 'staged' && staged.taskID === m.taskID && staged.output === m.path && staged.rendererInputsSHA256 === m.inputsSHA256 && staged.rendererJournalSHA256 === value.journal.sha256 && staged.finalSHA256 === m.sha256 && staged.finalBytes === m.size &&
      typeof evidence.journal?.path === 'string' && evidence.journal.path.startsWith('.knot-doc/design/' + m.taskID + '/') && /^[a-f0-9]{64}\.jsonl$/.test(evidence.journal.path.slice(('.knot-doc/design/' + m.taskID + '/').length)) && hash(evidence.journal.sha256) && Number.isSafeInteger(evidence.journal.size) && evidence.journal.size > 0 && evidence.journal.size <= 1000000;
  } catch { return false; }
}
