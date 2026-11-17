import { useEffect, useMemo, useState } from 'react';
import { ArrowLeft, CheckCircle2, Circle, ChevronRight, Clock3, ListChecks, Monitor, RefreshCw, ShieldCheck, Sparkles, MessageCircle, Globe, Terminal } from 'lucide-react';
import { Dialog, DialogContent, DialogDescription, DialogTitle } from '@/components/ui/dialog';
import { KnotPortrait } from '@/components/Knot';
import { KnotBrowserView } from '@/components/KnotBrowserView';
import { knotNames, type KnotBot } from '@/lib/knotService';
import { knotStepStatus, knotTaskStatus, knotWorkspaceTasks, readKnotWorkspace, type KnotWorkspaceRecord, type KnotWorkspaceReplay, type KnotWorkspaceTask } from '@/lib/knotWorkspace';

export type KnotHeaderSection = 'Events' | 'Permissions' | 'Computer' | 'Responsibilities' | 'Skills';
const sections = [
  { title: 'Events', icon: ListChecks }, { title: 'Permissions', icon: ShieldCheck }, { title: 'Computer', icon: Monitor },
  { title: 'Responsibilities', icon: Clock3 }, { title: 'Skills', icon: Sparkles },
] as const;
const buttonStyle = 'min-h-11 rounded-full border border-border px-4 text-sm font-medium transition-colors hover:bg-secondary';

export function KnotWorkspacePreview({ record, onOpen }: { record: KnotWorkspaceRecord; onOpen?: () => void }) {
  const output = (record.result.stdout + '\n' + record.result.stderr).trim();
  return <div className="w-full max-w-lg space-y-4 rounded-3xl border border-border bg-secondary/40 p-4">
    <div className="flex items-center gap-3"><span className="rounded-xl bg-blue-500/10 p-3"><Monitor className="h-5 w-5" /></span><div><p className="text-sm font-semibold">Linux workspace</p><p className="text-xs text-muted-foreground">{knotStepStatus(record)} · recorded shell output</p></div></div>
    <div className="rounded-2xl bg-[#131519] p-4 text-white"><p className="mb-3 font-mono text-xs text-white/60">{record.spec.title}</p><pre className="max-h-40 min-h-24 overflow-auto whitespace-pre-wrap break-words font-mono text-xs leading-relaxed">{output ? output.slice(-1000) : 'No output received.'}</pre></div>
    {onOpen && <button type="button" onClick={onOpen} className={`${buttonStyle} w-full`}>Open workspace</button>}
  </div>;
}

export function KnotWorkspaceDialog({ open, onClose, owner, bot, conversationID, messages, section, onSection, working, replay, loading, issue, onRefresh, onPrivacy, onResponsibilities, onSkills, onProfile, onTune, onVoice, onHistory }: {
  open: boolean; onClose: () => void; owner: string; bot: KnotBot; conversationID: string;
  messages: { id: string; createdAt?: number; role: 'user' | 'ember'; text: string }[];
  section: KnotHeaderSection; onSection: (section: KnotHeaderSection) => void; working: boolean;
  replay: KnotWorkspaceReplay | null; loading: boolean; issue: string | null; onRefresh: () => void;
  onPrivacy: () => void; onResponsibilities: () => void; onSkills: () => void; onProfile: () => void; onTune: () => void; onVoice: () => void; onHistory: () => void;
}) {
  const [taskID, setTaskID] = useState<string | null>(null);
  const tasks = useMemo(() => knotWorkspaceTasks(replay?.records ?? [], replay?.activities ?? [], messages.filter(message => message.text.trim())), [replay, messages]);
  const entries = useMemo(() => tasks.map(task => ({ id: task.id, date: task.date, title: task.title, subtitle: knotTaskStatus(task), kind: task.activities.some(a => a.kind.startsWith('browser_')) ? 'browser' : task.records.length ? 'command' : 'message', target: task.id })), [tasks]);
  const selected = tasks.find(task => task.id === taskID);
  const latest = [...(replay?.records ?? [])].sort((a,b) => b.spec.expiresAt - a.spec.expiresAt).find(record => record.result.sessionID && (record.operation === 'work' || (!record.operation && !/MEMORY\.md|\/opt\/knot-skills\//.test(record.spec.command))));
  useEffect(() => { if (!open) { setTaskID(null); } }, [open]);
  const navigate = (action: () => void) => { onClose(); action(); };
  return <Dialog open={open} onOpenChange={value => { if (!value) onClose(); }}><DialogContent className="max-h-[92dvh] w-[calc(100%-24px)] overflow-y-auto rounded-[28px] bg-background p-5 sm:max-w-xl sm:rounded-[28px] sm:p-7">
    <div className="flex flex-col items-center gap-2 pb-2 pt-3"><KnotPortrait size={112} expression={working ? 'thinking' : 'calm'} /><DialogTitle className="mt-2 text-3xl tracking-tight">{knotNames[bot]}</DialogTitle><DialogDescription>{working ? 'Responding in this conversation' : 'Your AI specialist in Whisper'}</DialogDescription></div>
    <div role="group" aria-label="Knot header sections" className="grid grid-cols-5 gap-1 rounded-full bg-secondary p-1.5">{sections.map(item => <button key={item.title} type="button" title={item.title} aria-label={item.title} aria-pressed={section === item.title} onClick={() => { setTaskID(null); onSection(item.title); }} className={`flex min-h-12 items-center justify-center rounded-full transition-colors ${section === item.title ? 'bg-background shadow-sm' : 'text-muted-foreground hover:bg-background/50'}`}><item.icon className="h-5 w-5" /></button>)}</div>
    {section === 'Events' && (selected ? <TaskDetail key={selected.id} task={selected} owner={owner} bot={bot} conversationID={conversationID} onBack={() => setTaskID(null)} /> : <section className="space-y-5" aria-label="Events">
      <div className="flex items-center justify-between"><h2 className="text-xl font-semibold">Events</h2><button type="button" onClick={onRefresh} disabled={loading} aria-label="Refresh Events" className="flex h-11 w-11 items-center justify-center rounded-full hover:bg-secondary"><RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin motion-reduce:animate-none' : ''}`} /></button></div>
      {issue && <p role="status" className="text-sm text-muted-foreground">{issue}</p>}
      {!entries.length && <div className="py-8 text-center"><ListChecks className="mx-auto mb-4 h-8 w-8 text-muted-foreground/60" /><p className="font-medium">{loading ? 'Loading Events…' : 'A quieter conversation'}</p><p className="mx-auto mt-2 max-w-xs text-sm leading-relaxed text-muted-foreground">One entry per task. Open it to see the conversation, recorded steps and receipts.</p></div>}
      {entries.map((entry, index) => {
        const date = eventDay(entry.date), previous = index ? eventDay(entries[index - 1].date) : null;
        const Icon = entry.kind === 'command' ? Terminal : entry.kind === 'message' ? MessageCircle : entry.kind === 'browser' ? Globe : Circle;
        const row = <><span className="rounded-full bg-secondary p-3"><Icon className="h-4 w-4" /></span><span className="min-w-0 flex-1"><strong className="line-clamp-2 block break-words text-sm font-medium">{entry.title}</strong><span className="mt-1 block text-xs text-muted-foreground">{entry.subtitle}</span>{entry.date > 0 && <time className="mt-1 block text-xs text-muted-foreground/80">{new Date(entry.date).toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })}</time>}</span>{entry.target && <ChevronRight className="mt-3 h-4 w-4 shrink-0 text-muted-foreground" />}</>;
        const style = 'flex min-h-20 w-full items-start gap-3 rounded-2xl py-3 text-left';
        return <div key={entry.id}>{date !== previous && <h3 className="mb-3 text-xs font-medium text-muted-foreground">{date}</h3>}{entry.target ? <button type="button" onClick={() => setTaskID(entry.target)} className={`${style} hover:bg-secondary/50`}>{row}</button> : <div className={style}>{row}</div>}</div>;
      })}
      {!!entries.length && <p className="text-xs leading-relaxed text-muted-foreground">Each task holds its recorded steps. Conversation text follows chat history; execution details are retained for 24 hours. A finished step isn’t proof the whole task is complete. Web does not run or replay shell commands.</p>}
    </section>)}
    {section === 'Computer' && <Computer key={`${owner}:${bot}:${conversationID}`} owner={owner} bot={bot} conversationID={conversationID} latest={latest} onRefresh={onRefresh} />}
    {section === 'Permissions' && <section className="space-y-4 py-2"><h2 className="text-xl font-semibold">Permissions</h2><p className="text-sm leading-relaxed text-muted-foreground">Workspace commands are automatic in the native app. Personal-product access stays separate; account actions and Responsibilities keep their own native approvals. Web is read-only for workspace evidence.</p><button type="button" className={buttonStyle} onClick={() => navigate(onPrivacy)}>Privacy & sharing</button></section>}
    {section === 'Responsibilities' && <section className="space-y-4 py-2"><h2 className="text-xl font-semibold">Responsibilities</h2><p className="text-sm leading-relaxed text-muted-foreground">See approved recurring checks, their actual outcomes and their next scheduled times. Pause or delete a rule here; new approvals and resume stay in the native app.</p><button type="button" className={buttonStyle} onClick={() => navigate(onResponsibilities)}>Manage responsibilities</button></section>}
    {section === 'Skills' && <section className="space-y-4 py-2"><h2 className="text-xl font-semibold">Skills</h2><p className="text-sm leading-relaxed text-muted-foreground">Writing, research and practical plans—plus built-in Emoji & tone and Message reactions. Communication skills need no workspace guide; task guides are read live when needed in native.</p><button type="button" className={buttonStyle} onClick={() => navigate(onSkills)}>Explore skills & tools</button></section>}
    <details className="border-t border-border pt-4"><summary className="min-h-11 cursor-pointer py-3 text-sm font-medium">Conversation options</summary><div className="grid grid-cols-2 gap-2 pt-2">{[{ title: 'About this Knot', action: onProfile }, { title: 'Tune replies', action: onTune }, { title: 'Talk to Knot', action: onVoice }, { title: 'Chat history', action: onHistory }].map(item => <button type="button" key={item.title} className={buttonStyle} onClick={() => navigate(item.action)}>{item.title}</button>)}</div></details>
  </DialogContent></Dialog>;
}

function eventDay(timestamp: number): string {
  if (timestamp <= 0) return 'Earlier · date unavailable';
  const date = new Date(timestamp), today = new Date(), yesterday = new Date(); yesterday.setDate(today.getDate() - 1);
  if (date.toDateString() === today.toDateString()) return 'Today';
  if (date.toDateString() === yesterday.toDateString()) return 'Yesterday';
  return date.toLocaleDateString(undefined, { month: 'long', day: 'numeric', year: 'numeric' });
}

function TaskDetail({ task, owner, bot, conversationID, onBack }: { task: KnotWorkspaceTask; owner: string; bot: KnotBot; conversationID: string; onBack: () => void }) {
  const steps: { id: string; date: number; record?: KnotWorkspaceRecord; activity?: KnotWorkspaceTask['activities'][number] }[] = [
    ...task.records.map(record => ({ id: 'command:' + record.spec.id, date: record.spec.expiresAt - 600000, record })),
    ...task.activities.map(activity => ({ id: 'stage:' + activity.id, date: Date.parse(activity.recordedAt), activity })),
  ];
  steps.sort((a,b) => a.date - b.date || a.id.localeCompare(b.id));
  return <section className="space-y-5" aria-label="Task details">
    <button type="button" className="flex min-h-11 items-center gap-2 text-sm" onClick={onBack}><ArrowLeft className="h-4 w-4" />Events</button>
    <span className="inline-block rounded-full bg-secondary px-3 py-1.5 text-xs">{knotTaskStatus(task)}</span>
    <h2 className="text-xl font-semibold">{task.title}</h2>
    <p className="text-xs text-muted-foreground">{task.date > 0 ? new Date(task.date).toLocaleString() : 'Earlier · date unavailable'}</p>
    {task.messages.map(message => <div key={message.id} className="space-y-2"><h3 className="text-xs font-medium text-muted-foreground">{message.role === 'user' ? 'You' : knotNames[bot]}</h3><p className="whitespace-pre-wrap break-words text-sm leading-relaxed">{message.text}</p></div>)}
    {!!steps.length && <h3 className="font-semibold">Recorded steps</h3>}
    {steps.map(step => step.activity ? <div key={step.id} className="flex items-start gap-3 text-sm"><Circle className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" /><div className="min-w-0 flex-1"><span>{step.activity.label}</span>{step.activity.messageID && step.activity.emoji && <div className="mt-1 space-y-1"><p className="text-lg">{step.activity.emoji}</p><p className="break-all text-xs text-muted-foreground">Message · {step.activity.messageID}</p><p className="text-xs text-muted-foreground">{step.activity.recordedAt}</p></div>}</div><time className="text-xs text-muted-foreground">{new Date(step.date).toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })}</time></div> : step.record ? <TaskCommand key={step.id} record={step.record} owner={owner} bot={bot} conversationID={conversationID} /> : null)}
    <p className="text-xs leading-relaxed text-muted-foreground">This is recorded execution evidence, not permission to repeat it. Continue or stop an owned task in the native app.</p>
  </section>;
}

function TaskCommand({ record, owner, bot, conversationID }: { record: KnotWorkspaceRecord; owner: string; bot: KnotBot; conversationID: string }) {
  return <div className="space-y-3 rounded-2xl bg-secondary/50 p-4"><div className="flex gap-3">{knotStepStatus(record) === 'Step finished' ? <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600 dark:text-emerald-400" /> : <Circle className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />}<div><h3 className="text-sm font-medium">{record.spec.title}</h3><p className="mt-1 text-xs text-muted-foreground">{knotStepStatus(record)}</p></div></div><p className="text-xs leading-relaxed text-muted-foreground">{record.result.reason}</p><details><summary className="min-h-11 cursor-pointer py-3 text-xs font-medium">Command, receipt & provider log</summary><StepEvidence record={record} owner={owner} bot={bot} conversationID={conversationID} /></details></div>;
}

function StepEvidence({ record, owner, bot, conversationID }: { record: KnotWorkspaceRecord; owner: string; bot: KnotBot; conversationID: string }) {
  const [events, setEvents] = useState<unknown[] | null>(null), [log, setLog] = useState<unknown>(null), [issue, setIssue] = useState<string | null>(null), [request, setRequest] = useState<'events' | 'log' | null>(null);
  useEffect(() => {
    if (!request) return;
    const controller = new AbortController(); let disposed = false;
    void readKnotWorkspace(owner, request, bot, conversationID, controller.signal, record.spec.id).then(value => { if (!disposed) { if (request === 'events') setEvents((value as KnotWorkspaceReplay).events); else setLog(value); setIssue(null); } }).catch(() => { if (!disposed) setIssue('Couldn’t read the retained evidence. Nothing was run again.'); }).finally(() => { if (!disposed) setRequest(null); });
    return () => { disposed = true; controller.abort(); };
  }, [request, owner, bot, conversationID, record.spec.id]);
  const pre = 'max-h-64 overflow-auto whitespace-pre-wrap break-words rounded-xl border border-border bg-background p-3 font-mono text-xs';
  return <div className="space-y-3"><h4 className="text-xs font-medium">Exact command</h4><pre className={pre}>{record.spec.command}</pre><p className="text-xs text-muted-foreground">Timeout {record.spec.timeoutMs} ms · Exit {record.result.exitCode ?? 'not recorded'}</p><details><summary className="cursor-pointer py-3 text-xs">Recorded result & preview limits</summary><pre className={pre}>{JSON.stringify({ result: record.result, receiptOutputComplete: record.receiptOutputComplete, receiptTruncated: record.receiptTruncated }, null, 2)}</pre></details><button type="button" className={buttonStyle} disabled={request !== null} onClick={() => setRequest('events')}>Read executor events</button>{events && <><ExecutorFindings events={events} /><details><summary className="min-h-11 cursor-pointer py-3 text-xs">Exact recorded events</summary><pre className={pre}>{JSON.stringify(events, null, 2)}</pre></details></>}{record.result.sessionID && <button type="button" className={buttonStyle} disabled={request !== null} onClick={() => setRequest('log')}>Read retained provider log</button>}{log !== null && <pre className={pre}>{JSON.stringify(log, null, 2)}</pre>}{issue && <p role="status" className="text-xs text-muted-foreground">{issue}</p>}</div>;
}

function ExecutorFindings({ events }: { events: unknown[] }) {
  const labels: Record<string, string> = { document_content_check_attempt: 'Document content checker run recorded', document_source_unconfirmed: 'Source quality verdict unconfirmed; nonblocking', document_content_unconfirmed: 'Content verdict unconfirmed; not a pass', document_source_blocked: 'Source content or evidence needs attention', document_content_blocked: 'Document content check blocked delivery', document_content_qualified: 'Content captured with checked shortfalls; not a pass', document_visual_reviewed: 'Every rendered page passed visual AI review', document_visual_qualified: 'Every page reviewed; visual shortfalls retained', document_visual_blocked: 'All-page visual review blocked delivery', document_quality_shortfalls: 'Delivered with remaining quality shortfalls', skill_draft_written: 'Workspace skill draft saved', skill_draft_amended: 'Workspace skill draft amended', document_build_latched: 'Original build retained; no repeat execution', document_build_continued: 'Continuing checks on the original successful build' };
  const findings = events.flatMap((raw, index) => {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return [];
    const event = raw as Record<string, unknown>;
    if (typeof event.kind !== 'string' || !labels[event.kind]) return [];
    const observations = Array.isArray(event.observations) ? event.observations.filter((value): value is string => typeof value === 'string') : [];
    return [{ id: index, title: labels[event.kind], observations, name: typeof event.name === 'string' ? event.name : undefined }];
  });
  if (!findings.length) return null;
  return <div className="space-y-3" aria-label="Recorded findings">{findings.map(item => <section key={item.id} className="space-y-2 rounded-xl border border-border bg-background p-3"><h4 className="text-sm font-medium">{item.title}</h4>{item.name && <p className="break-words text-xs text-muted-foreground">{item.name} · workspace only; not promoted</p>}{item.observations.length > 0 && <ul className="list-disc space-y-2 pl-4 text-sm">{item.observations.map((text, index) => <li key={index} className="whitespace-pre-wrap break-words">{text}</li>)}</ul>}</section>)}</div>;
}

function Computer({ owner, bot, conversationID, latest, onRefresh }: { owner: string; bot: KnotBot; conversationID: string; latest?: KnotWorkspaceRecord; onRefresh: () => void }) {
  const [connection, setConnection] = useState('Checking shell connection…'), [revision, setRevision] = useState(0);
  useEffect(() => {
    const controller = new AbortController(); let disposed = false;
    void readKnotWorkspace(owner, 'capabilities', bot, conversationID, controller.signal).then(value => { const result = value as { ok?: boolean; service?: string }; if (!disposed) setConnection(result.ok && result.service === 'knot-sidecar' ? 'Shell connected' : 'Shell connection unavailable'); }).catch(() => { if (!disposed) setConnection('Shell connection unavailable'); });
    return () => { disposed = true; controller.abort(); };
  }, [owner, bot, conversationID, revision]);
  return <section className="space-y-5 py-2"><h2 className="text-xl font-semibold">Computer</h2><p className="flex items-center gap-2 text-sm text-muted-foreground"><Terminal className="h-4 w-4" />{connection}</p>{latest && <KnotWorkspacePreview record={latest} />}<KnotBrowserView owner={owner} bot={bot} conversationID={conversationID} /><button type="button" className={buttonStyle} onClick={() => { setRevision(value => value + 1); onRefresh(); }}>Refresh connection</button></section>;
}
