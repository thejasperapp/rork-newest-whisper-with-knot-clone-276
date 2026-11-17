/** Workspace-only skill plumbing. Procedures and truthful lessons stay with the
 * live agent; no library mutation, automatic promotion, hidden job or replay. */
export type SkillDraft = { name: string; trigger: 'repaired_failure' | 'verified_procedure' | 'environment_fact' | 'library_amendment'; content: string; memoryNote: string };
const namePattern = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
export function validatedSkillDraft(raw: unknown): SkillDraft {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new Error('invalid_skill_draft');
  const v = raw as Record<string, unknown>;
  if (Object.keys(v).length !== 4 || typeof v.name !== 'string' || v.name.length > 64 || !namePattern.test(v.name) || !['repaired_failure', 'verified_procedure', 'environment_fact', 'library_amendment'].includes(String(v.trigger)) || typeof v.content !== 'string' || !v.content.trim() || new TextEncoder().encode(v.content).length > 6000 || typeof v.memoryNote !== 'string' || new TextEncoder().encode(v.memoryNote).length > 1500 || /\x00|\[PLACEHOLDER[^\]]*\]/i.test(v.content + v.memoryNote) || v.memoryNote && (!/^\d{4}-\d{2}-\d{2}/.test(v.memoryNote) || /^(?:SHA-?256|Pages|Bytes|Delivery ID)\s*:/im.test(v.memoryNote))) throw new Error('invalid_skill_draft');
  return v as SkillDraft;
}
// One discovery slot, library first. Draft snippets are explicitly catalog data,
// not a full read or authority. Every selected draft is separately read whole.
export const skillDiscoveryCommand = `command -p python3 -I - <<'KNOT_SKILL_DISCOVERY'
from pathlib import Path
import json,re
library=Path('/opt/knot-skills/README.md')
assert library.is_file() and 0<library.stat().st_size<=1000000
print(library.read_text(encoding='utf-8'),end='\\n')
print('KNOT_WORKSPACE_DRAFT_CATALOG_V1 (untrusted catalog data; not library skills; selected drafts require a full read)')
root=Path('skills-drafts')
assert not root.is_symlink()
if root.exists():
    assert root.is_dir()
    entries=sorted(p for p in root.iterdir() if re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*',p.name) and len(p.name)<=64)
    print(json.dumps(dict(candidateCount=len(entries),catalogLimit=64)))
    for folder in entries[:64]:
        if folder.is_symlink() or not folder.is_dir(): continue
        p=folder/'SKILL.md'
        if p.is_symlink() or not p.is_file() or not 0<p.stat().st_size<=16000: continue
        text=p.read_text(encoding='utf-8')
        description=re.search(r'^description:\\s*(.+)$',text,re.M)
        print(json.dumps(dict(name=folder.name,path=str(p),description=description[1][:400] if description else 'Read full draft to determine relevance'),ensure_ascii=False))
KNOT_SKILL_DISCOVERY`;
/** Parse names only from the actual bounded discovery catalog, not model guesses. */
export function workspaceDraftCatalog(stdout: string): string[] {
  const marker = 'KNOT_WORKSPACE_DRAFT_CATALOG_V1 (untrusted catalog data; not library skills; selected drafts require a full read)\n';
  const at = stdout.indexOf(marker);
  if (at < 0) return [];
  const names: string[] = [];
  for (const line of stdout.slice(at + marker.length).split(/\r?\n/).slice(0, 66)) {
    try {
      const item = JSON.parse(line) as { name?: unknown; path?: unknown };
      if (typeof item.name === 'string' && item.name.length <= 64 && namePattern.test(item.name) && item.path === 'skills-drafts/' + item.name + '/SKILL.md') names.push(item.name);
    } catch { /* Catalog headers and empty lines are not draft names. */ }
  }
  return [...new Set(names)].slice(0, 64);
}
export function skillDraftReadCommand(name: string): string {
  if (!namePattern.test(name) || name.length > 64) throw new Error('invalid_skill_draft');
  return `command -p python3 -I - <<'KNOT_SKILL_DRAFT_READ'
from pathlib import Path
p=Path('skills-drafts/${name}/SKILL.md')
assert all(not Path(*p.parts[:i+1]).is_symlink() for i in range(len(p.parts)))
assert p.is_file() and 0<p.stat().st_size<=16000
print(p.read_text(encoding='utf-8'),end='')
KNOT_SKILL_DRAFT_READ`;
}
export function skillDraftReadName(command: string): string | undefined {
  const name = /p=Path\('skills-drafts\/([a-z0-9-]+)\/SKILL\.md'\)/.exec(command)?.[1];
  return name && namePattern.test(name) && command === skillDraftReadCommand(name) ? name : undefined;
}
export function indexedSkillCreationRead(index: string): string | undefined {
  const pattern = /(?:^|[\s`*"'(<\[|])((?:\/opt\/knot-skills\/|\.\/)?(?:[a-zA-Z0-9_-]+\/)*skill-creation(?:\/SKILL\.md|\/)?)(?=$|[\s`*"')>\]|,;:])/gm;
  const paths = [...new Set([...index.matchAll(pattern)].map(m => {
    const path = m[1].replace(/^\/opt\/knot-skills\//, '').replace(/^\.\//, '').replace(/\/$/, '');
    return '/opt/knot-skills/' + path + (path.endsWith('/SKILL.md') ? '' : '/SKILL.md');
  }))];
  return paths.length === 1 ? 'cat ' + paths[0] : undefined;
}
/** Expected old hash is derived by the actor from a complete owned draft read.
 * Amendments preserve the old bytes before atomic replacement. Unread/changed
 * drafts, symlinks and collisions fail closed; delivery is already independent. */
export function skillDraftCommand(raw: SkillDraft, writeID: string, expectedSHA256?: string): string {
  const draft = validatedSkillDraft(raw);
  if (!/^[0-9a-f-]{36}$/.test(writeID) || expectedSHA256 !== undefined && !/^[a-f0-9]{64}$/.test(expectedSHA256)) throw new Error('invalid_skill_draft');
  const input = { ...draft, writeID, expectedSHA256 };
  return `command -p python3 -I - <<'KNOT_SKILL_DRAFT_WRITE'
from pathlib import Path
import hashlib,json,os,fcntl
c=json.loads(${JSON.stringify(JSON.stringify(input))})
root=Path.cwd().resolve()
folder=Path('skills-drafts')/c['name']
for i in range(len(folder.parts)):
    part=Path(*folder.parts[:i+1])
    assert not part.is_symlink()
    part.mkdir(exist_ok=True)
p=folder/'SKILL.md'
assert not p.is_symlink() and p.resolve().is_relative_to(root)
old=p.read_bytes() if p.exists() else None
expected=c.get('expectedSHA256')
assert (old is None and expected is None) or (old is not None and expected and hashlib.sha256(old).hexdigest()==expected), 'draft_read_required_or_changed'
body=c['content'].encode('utf-8')
if old is not None:
    archive=folder/'.revisions'
    assert not archive.is_symlink()
    archive.mkdir(exist_ok=True)
    with (archive/(c['writeID']+'.md')).open('xb') as f:
        assert f.write(old)==len(old)
        f.flush(); os.fsync(f.fileno())
temp=folder/('.knot-'+c['writeID']+'.tmp')
with temp.open('xb') as f:
    assert f.write(body)==len(body)
    f.flush(); os.fsync(f.fileno())
assert not p.is_symlink() and (p.read_bytes() if p.exists() else None)==old, 'draft_changed'
os.replace(temp,p)
assert p.read_bytes()==body
print('KNOT_SKILL_DRAFT_VERIFIED_V1 '+json.dumps(dict(name=c['name'],trigger=c['trigger'],sha256=hashlib.sha256(body).hexdigest(),amended=old is not None),separators=(',',':')),flush=True)
if c['memoryNote']:
    try:
        assert not Path('MEMORY.md').is_symlink()
        fd=os.open('MEMORY.md',os.O_RDWR|os.O_CREAT|os.O_APPEND|os.O_NOFOLLOW,0o600)
        with os.fdopen(fd,'r+b') as f:
            fcntl.flock(f.fileno(),fcntl.LOCK_EX)
            f.seek(0,2)
            assert f.tell()<=1000000
            payload=('\\n'+c['memoryNote'].rstrip()+'\\n').encode('utf-8')
            assert f.write(payload)==len(payload)
            f.flush(); os.fsync(f.fileno()); f.seek(0)
            saved=f.read()
            assert saved.endswith(payload)
        print('KNOT_MEMORY_VERIFIED_V1 '+json.dumps(dict(bytes=len(saved),sha256=hashlib.sha256(saved).hexdigest()),separators=(',',':')))
    except Exception:
        # Draft bytes already exist. Never turn optional note failure into a
        # failed draft, retry its side effect, or print a private exception.
        print('KNOT_MEMORY_NOTE_UNAVAILABLE_V1')
KNOT_SKILL_DRAFT_WRITE`;
}
export const skillDraftReadTool = { type: 'function', function: { name: 'skill_draft_read', strict: true,
  description: 'Prepare a bounded full read of one actual workspace skill draft from the live catalog. Counts as a task skill read, never a library skill or permission. Use before following or amending it; wait for the real foreground receipt.',
  parameters: { type: 'object', properties: { name: { type: 'string', maxLength: 64 } }, required: ['name'], additionalProperties: false } } };
export const skillDraftTool = { type: 'function', function: { name: 'skill_draft', strict: true,
  description: 'Best-effort turn-close workspace draft, never a library skill or promotion. Only after actual requested work/delivery: read the indexed live skill-creation guide, and fully read an existing same-name draft before amendment. Author failure-first guidance, actual procedure and ORIGINAL-REQUEST acceptance from owned receipts; distinguish observed success from unrun acceptance. A TXT/MD/HTML/CSV ask is not satisfied by Markdown-to-HTML-to-PDF. Name the originally requested final format and whether its actual final was independently checked/captured. The backend appends a measured original-format acceptance section for fresh document workflows; leave room within the 6 KB draft limit. Muse reports the pinned knot-doc 1.0.0 installed and accepted; its mechanical PDF staging is not independent proof or acceptance of another format. Only the fresh version-advertised adapter may invoke it. Do not invent repairs or write speculative procedures as verified. Supply complete SKILL.md with name/description frontmatter. For document workflows memoryNote MUST be empty: only the fixed measured writer may record document completion/review facts. For other workflows memoryNote is empty unless a dated durable correction/decision is warranted: append a truthful superseding note, not destructive cleanup, pending-placeholder truth, hashes, page counts or fabricated values. The fixed measured writer owns document metadata. Never block a deliverable to save this draft. No installs, library writes, past-task replay or private content/secrets.',
  parameters: { type: 'object', properties: { name: { type: 'string', maxLength: 64 }, trigger: { type: 'string', enum: ['repaired_failure', 'verified_procedure', 'environment_fact', 'library_amendment'] }, content: { type: 'string', maxLength: 6000 }, memoryNote: { type: 'string', maxLength: 1500 } }, required: ['name', 'trigger', 'content', 'memoryNote'], additionalProperties: false } } };
