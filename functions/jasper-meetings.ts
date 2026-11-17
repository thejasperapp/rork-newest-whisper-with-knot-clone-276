import { workspaceRoute } from './workspace';
import { jasperAnswerInstructions } from './jasper-answer-instructions';
import { validateJasperNoteContext, type JasperNoteContext } from './jasper-meeting-rules';
import { recruiterClientsRoute } from './recruiter-clients';
import { selectedMeetingIDs } from './recruiter-client-rules';
import { rankJasperPassages } from './jasper-ranked-evidence';
import { readJasperSpeech } from './jasper-speech-reader';
import { DurableObject } from 'cloudflare:workers';
import { defaultJasperLibrary, updateJasperLibrary, jasperRetrievalTerms, jasperRecordingEvidence, meetingUUID, validateJasperResult, type JasperLibrary, type JasperEvidence, type JasperResult } from './jasper-meeting-rules';
import { googleCalendarRoute, type GoogleCalendarEnv } from './jasper-google-calendar';

export type JasperEnv = GoogleCalendarEnv & { DO: Fetcher; SUPABASE_SERVICE_ROLE_KEY?: string; OPENAI_API_KEY?: string; /** Optional override for the answer model (defaults to gpt-4o). */ JASPER_ANSWER_MODEL?: string };
type Meeting = { id: string; title: string; host_id: string; created_at: string; ended_at: string | null; status: string };
type Speech = { id: string; meeting_id: string; username: string; text: string; spoken_at: string; kind?: 'speech' | 'summary'; offset?: number };
export type JasperAnswer = { id: string; question: string; generatedAt: string; scope: string; coverage: string; partialEvidence?: boolean; noteContext?: JasperNoteContext; sources: JasperEvidence[]; result: JasperResult; meetingId: string | null };
const DATABASE = 'https://uryyyegnbtlmyhqlgndy.supabase.co';
const headers = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Whisper-Authorization', 'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS' };
export const jasperJSON = (body: unknown, status = 200): Response => new Response(JSON.stringify(body), { status, headers });

async function boundedJSON<T>(source: { body: ReadableStream<Uint8Array> | null }, maximum: number): Promise<T> {
  if (!source.body) throw new Error('invalid_body');
  const reader = source.body.getReader(), decoder = new TextDecoder();
  let size = 0, text = '';
  try {
    for (;;) { const part = await reader.read(); if (part.done) break; size += part.value.byteLength; if (size > maximum) { await reader.cancel(); throw new Error('narrow_search'); } text += decoder.decode(part.value, { stream: true }); }
    text += decoder.decode(); return JSON.parse(text) as T;
  } finally { reader.releaseLock(); }
}

async function readRows<T>(env: JasperEnv, authorization: string, table: string, params: Record<string, string>): Promise<T[]> {
  const url = new URL(`${DATABASE}/rest/v1/${table}`);
  Object.entries(params).forEach(([key, value]) => url.searchParams.set(key, value));
  const response = await fetch(url, { headers: { apikey: env.SUPABASE_SERVICE_ROLE_KEY ?? '', Authorization: authorization }, signal: AbortSignal.timeout(15000) });
  if (!response.ok) throw new Error(response.status === 401 || response.status === 403 ? 'meeting_access_denied' : 'meeting_read_failed');
  const data = await boundedJSON<unknown>(response, 1000000);
  if (!Array.isArray(data)) throw new Error('meeting_read_failed');
  return data as T[];
}
async function pages<T>(env: JasperEnv, auth: string, table: string, params: Record<string, string>, maximum = 10000): Promise<T[]> {
  const rows: T[] = [];
  for (let offset = 0; offset <= maximum; offset += 200) {
    const page = await readRows<T>(env, auth, table, { ...params, limit: '200', offset: String(offset) });
    rows.push(...page);
    if (rows.length > maximum) throw new Error('narrow_search');
    if (page.length < 200) return rows;
  }
  throw new Error('narrow_search');
}
/** Explicit host/member enumeration supplements RLS; folder membership never grants access. */
async function authorizedMeetings(env: JasperEnv, auth: string, owner: string): Promise<Meeting[]> {
  const fields = 'id,title,host_id,created_at,ended_at,status';
  const [hosted, joined] = await Promise.all([
    pages<Meeting>(env, auth, 'whisper_meetings', { select: fields, host_id: `eq.${owner}`, order: 'id.asc' }),
    pages<{ meeting_id: string }>(env, auth, 'whisper_meeting_participants', { select: 'meeting_id', user_id: `eq.${owner}`, order: 'meeting_id.asc' }),
  ]);
  const meetings = new Map(hosted.map((meeting) => [meeting.id, meeting]));
  const ids = [...new Set(joined.map((row) => row.meeting_id))].filter((id) => meetingUUID.test(id) && !meetings.has(id));
  for (let start = 0; start < ids.length; start += 100) {
    const rows = await readRows<Meeting>(env, auth, 'whisper_meetings', { select: fields, id: `in.(${ids.slice(start, start + 100).join(',')})`, limit: '100' });
    rows.forEach((meeting) => meetings.set(meeting.id, meeting));
  }
  return [...meetings.values()].map((meeting) => ({ ...meeting, title: String(meeting.title ?? 'Meeting').slice(0, 160) }));
}

/** Private account storage; reached only through the authenticated Worker route below. */
export class JasperMeetingAccount extends DurableObject<JasperEnv> {
  constructor(ctx: DurableObjectState, env: JasperEnv) {
    super(ctx, env);
    this.ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS jasper_values (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated INTEGER NOT NULL)');
  }
  read<T>(key: string): T | undefined {
    const row = this.ctx.storage.sql.exec<{ value: string }>('SELECT value FROM jasper_values WHERE key = ?', key).toArray()[0];
    return row ? JSON.parse(row.value) as T : undefined;
  }
  write(key: string, value: unknown): void { this.ctx.storage.sql.exec('INSERT INTO jasper_values (key,value,updated) VALUES (?,?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated=excluded.updated', key, JSON.stringify(value), Date.now()); }
  remove(key: string): void { this.ctx.storage.sql.exec('DELETE FROM jasper_values WHERE key = ?', key); }
  list<T>(prefix: string): { key: string; value: T }[] {
    const rows = this.ctx.storage.sql.exec<{ key: string; value: string }>('SELECT key,value FROM jasper_values WHERE key LIKE ? LIMIT 1001', `${prefix}%`).toArray();
    if (rows.length > 1000) throw new Error('client_limit');
    return rows.map((row) => ({ key: row.key, value: JSON.parse(row.value) as T }));
  }
  private activeAnswers = new Map<string, AbortController>();
  private clientQueue: Promise<void> = Promise.resolve();
  private expireDrafts(): void { this.ctx.storage.sql.exec("DELETE FROM jasper_values WHERE (key LIKE 'draft:%' OR key LIKE 'request:%') AND updated <= ?", Date.now() - 86400000); }
  private async scheduleExpiry(): Promise<void> {
    const first = this.ctx.storage.sql.exec<{ updated: number }>("SELECT updated FROM jasper_values WHERE key LIKE 'draft:%' OR key LIKE 'request:%' ORDER BY updated ASC LIMIT 1").toArray()[0];
    if (first) await this.ctx.storage.setAlarm(Math.max(Date.now() + 1000, first.updated + 86400000));
  }
  async onAlarm(): Promise<void> { this.expireDrafts(); await this.scheduleExpiry(); }
  override async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const owner = request.headers.get('X-Jasper-Owner') ?? '';
    const isTeam = url.pathname === '/jasper-meetings/clients/team' || url.pathname.startsWith('/jasper-meetings/workspace');
    if (!meetingUUID.test(owner) || (!isTeam && this.ctx.id.name !== owner)) return jasperJSON({ error: 'sign_in_required' }, 401);
    let activeRequestID: string | undefined;
    try {
      if (url.pathname.startsWith('/jasper-meetings/workspace')) {
        const auth = request.headers.get('Authorization') ?? '';
        const operation = this.clientQueue.then(() => workspaceRoute(request, owner, this.ctx.id.name ?? '', this,
          <T>(table: string, params: Record<string, string>, service = false) => readRows<T>(this.env, service ? `Bearer ${this.env.SUPABASE_SERVICE_ROLE_KEY ?? ''}` : auth, table, params),
          () => boundedJSON<Record<string, unknown>>(request, 50000)));
        this.clientQueue = operation.then(() => undefined, () => undefined);
        return jasperJSON(await operation);
      }
      if (url.pathname.startsWith('/jasper-meetings/clients/')) {
        const auth = request.headers.get('Authorization') ?? '';
        const operation = this.clientQueue.then(() => recruiterClientsRoute(request, this.env, owner, this.ctx.id.name ?? '', this,
          <T>(table: string, params: Record<string, string>, service = false) => readRows<T>(this.env, service ? `Bearer ${this.env.SUPABASE_SERVICE_ROLE_KEY ?? ''}` : auth, table, params),
          () => boundedJSON<Record<string, unknown>>(request, 16000), () => authorizedMeetings(this.env, auth, owner)));
        this.clientQueue = operation.then(() => undefined, () => undefined);
        return jasperJSON(await operation);
      }
      this.expireDrafts();
      const answerEpoch = this.read<number>('answer_epoch') ?? 0;
      if (url.pathname.includes('/google/')) return await googleCalendarRoute(request, this.env, this);
      const library = this.read<JasperLibrary>('library') ?? defaultJasperLibrary();
      const auth = request.headers.get('Authorization') ?? '';
      if (url.pathname.endsWith('/library')) {
        if (request.method === 'GET') return jasperJSON(library);
        if (request.method !== 'POST') return jasperJSON({ error: 'method_not_allowed' }, 405);
        const input = await boundedJSON<Record<string, unknown>>(request, 8192);
        if (input.action === 'file') {
          const accessible = await authorizedMeetings(this.env, auth, owner);
          if (!accessible.some((meeting) => meeting.id === input.meetingId)) return jasperJSON({ error: 'meeting_access_denied' }, 403);
        }
        // Re-read after asynchronous authorization so revision checks are atomic with the write.
        const updated = updateJasperLibrary(this.read<JasperLibrary>('library') ?? defaultJasperLibrary(), input);
        this.write('library', updated);
        return jasperJSON(updated);
      }
      if (url.pathname.endsWith('/cancel') && request.method === 'POST') {
        const { id } = await boundedJSON<{ id: string }>(request, 1024);
        if (!meetingUUID.test(id ?? '')) throw new Error('invalid_answer');
        if (!this.read(`request:${id}`) && this.list('request:').length >= 500) throw new Error('temporary_answer_limit');
        this.write(`request:${id}`, { cancelled: true });
        this.activeAnswers.get(id)?.abort();
        this.remove(`draft:${id}`);
        await this.scheduleExpiry();
        return jasperJSON({ cancelled: true });
      }
      if (request.method === 'POST' && ['/jasper-meetings/clear', '/jasper-meetings/forget', '/jasper-meetings/erase-answers'].includes(url.pathname)) {
        const input = await boundedJSON<{ ids?: string[]; id?: string; meetingId?: string; confirm?: boolean }>(request, 8192);
        if (url.pathname.endsWith('/erase-answers')) {
          if (input.confirm !== true) return jasperJSON({ error: 'confirmation_required' }, 400);
          this.ctx.storage.sql.exec("DELETE FROM jasper_values WHERE key LIKE 'draft:%' OR key LIKE 'kept:%'");
        } else if (url.pathname.endsWith('/forget')) {
          if (!meetingUUID.test(input.id ?? '') || !meetingUUID.test(input.meetingId ?? '')) return jasperJSON({ error: 'invalid_meeting' }, 400);
          this.remove(`kept:${input.meetingId}:${input.id}`); this.remove(`draft:${input.id}`);
        } else {
          if (!Array.isArray(input.ids) || input.ids.length > 100 || input.ids.some((id) => !meetingUUID.test(id))) return jasperJSON({ error: 'invalid_answer' }, 400);
          input.ids.forEach((id) => this.remove(`draft:${id}`));
        }
        this.write('answer_epoch', (this.read<number>('answer_epoch') ?? 0) + 1);
        return jasperJSON({ cleared: true });
      }
      if (url.pathname.endsWith('/history') && request.method === 'GET') {
        const meetingId = url.searchParams.get('meetingId') ?? '';
        if (!meetingUUID.test(meetingId)) return jasperJSON({ error: 'invalid_meeting' }, 400);
        const permitted = new Set((await authorizedMeetings(this.env, auth, owner)).map((meeting) => meeting.id));
        if (!permitted.has(meetingId)) return jasperJSON({ error: 'meeting_access_denied' }, 403);
        const rows = this.ctx.storage.sql.exec<{ value: string }>('SELECT value FROM jasper_values WHERE key LIKE ? ORDER BY updated DESC LIMIT 100', `kept:${meetingId}:%`).toArray();
        const answers = rows.map((row) => JSON.parse(row.value) as JasperAnswer).filter((answer) => answer.sources.every((source) => permitted.has(source.meetingId)));
        return jasperJSON({ answers });
      }
      if (url.pathname.endsWith('/keep') && request.method === 'POST') {
        const { id, meetingId } = await boundedJSON<{ id: string; meetingId: string }>(request, 1024);
        if (!meetingUUID.test(id ?? '') || !meetingUUID.test(meetingId ?? '')) return jasperJSON({ error: 'invalid_meeting' }, 400);
        const answer = this.read<JasperAnswer>(`draft:${id}`) ?? this.read<JasperAnswer>(`kept:${meetingId}:${id}`);
        if (!answer) return jasperJSON({ error: 'answer_expired' }, 409);
        const permitted = new Set((await authorizedMeetings(this.env, auth, owner)).map((meeting) => meeting.id));
        if (!permitted.has(meetingId) || answer.sources.some((source) => !permitted.has(source.meetingId))) return jasperJSON({ error: 'meeting_access_denied' }, 403);
        const count = this.ctx.storage.sql.exec<{ count: number }>('SELECT COUNT(*) AS count FROM jasper_values WHERE key LIKE ?', `kept:${meetingId}:%`).toArray()[0]?.count ?? 0;
        const total = this.ctx.storage.sql.exec<{ count: number }>("SELECT COUNT(*) AS count FROM jasper_values WHERE key LIKE 'kept:%'").toArray()[0]?.count ?? 0;
        if (answerEpoch !== (this.read<number>('answer_epoch') ?? 0) || this.read<{ cancelled: boolean }>(`request:${id}`)?.cancelled) throw new Error('answer_changed');
        if ((count >= 100 || total >= 1000) && !this.read(`kept:${meetingId}:${id}`)) return jasperJSON({ error: 'saved_answer_limit' }, 409);
        this.write(`kept:${meetingId}:${id}`, { ...answer, meetingId }); this.remove(`draft:${id}`);
        return jasperJSON({ saved: true });
      }
      if (url.pathname.endsWith('/ask') && request.method === 'POST') {
        const input = await boundedJSON<{ requestId?: string; question: string; meetingId?: string; meetingIds?: string[]; folderId?: string; mode?: string; consent?: boolean; knowledge?: boolean; recordingContext?: unknown; noteContext?: unknown }>(request, 200000);
        request.signal.throwIfAborted();
        if (input.requestId !== undefined && !meetingUUID.test(input.requestId)) throw new Error('invalid_answer');
        const requestID = input.requestId ?? crypto.randomUUID();
        if (this.read(`request:${requestID}`)) throw new Error('answer_changed');
        if (this.list('request:').length >= 500) throw new Error('temporary_answer_limit');
        this.write(`request:${requestID}`, { cancelled: false });
        activeRequestID = requestID;
        const cancellation = new AbortController();
        this.activeAnswers.set(requestID, cancellation);
        const checkRequest = (): void => {
          request.signal.throwIfAborted();
          if (this.read<{ cancelled: boolean }>(`request:${requestID}`)?.cancelled) throw new Error('request_cancelled');
          if (answerEpoch !== (this.read<number>('answer_epoch') ?? 0)) throw new Error('answer_changed');
        };
        await this.scheduleExpiry();
        const draftCount = this.ctx.storage.sql.exec<{ count: number }>("SELECT COUNT(*) AS count FROM jasper_values WHERE key LIKE 'draft:%'").toArray()[0]?.count ?? 0;
        if (draftCount >= 100) return jasperJSON({ error: 'temporary_answer_limit' }, 409);
        if (input.consent !== true) return jasperJSON({ error: 'consent_required' }, 400);
        if (typeof input.question !== 'string' || !input.question.trim() || input.question.length > 600 || (input.meetingId && !meetingUUID.test(input.meetingId))) return jasperJSON({ error: 'invalid_question' }, 400);
        const last = this.read<number>('last_request') ?? 0;
        if (Date.now() - last < 3000) return jasperJSON({ error: 'try_again_shortly' }, 429);
        this.write('last_request', Date.now());
        const chosen = input.meetingIds === undefined ? undefined : selectedMeetingIDs(input.meetingIds);
        if (chosen && (input.meetingId || input.folderId || input.recordingContext)) throw new Error('invalid_meeting_scope');
        const noteContext = input.noteContext === undefined ? undefined : validateJasperNoteContext(input.noteContext, chosen, input.mode);
        if (input.mode === 'connections' && !noteContext) throw new Error('invalid_note_context');
        const meetings = await authorizedMeetings(this.env, auth, owner);
        if (chosen?.some((id) => !meetings.some((m) => m.id === id))) throw new Error('meeting_access_denied');
        const scope = meetings.filter((meeting) => chosen ? chosen.includes(meeting.id) : input.meetingId ? meeting.id === input.meetingId : input.folderId ? library.filings[meeting.id] === input.folderId : true);
        if (input.meetingId && !scope.length) return jasperJSON({ error: 'meeting_access_denied' }, 403);
        if (input.folderId && !library.folders.some((folder) => folder.id === input.folderId)) return jasperJSON({ error: 'invalid_folder' }, 400);
        const scanning = input.mode === 'scan';
        if (scanning && !input.meetingId) return jasperJSON({ error: 'choose_meeting_to_scan' }, 400);
        // General knowledge is an ordinary-question feature only; scans and note connections stay evidence-only. Callers may opt out.
        const knowledgeAllowed = !scanning && input.mode !== 'connections' && !noteContext && input.knowledge !== false;
        if (input.recordingContext && !input.meetingId) throw new Error('invalid_recording_context');
        const terms = jasperRetrievalTerms(input.question, !!input.meetingId || !!chosen, scanning);
        const speech: Speech[] = [];
        for (let offset = 0; !input.recordingContext && offset < scope.length; offset += 100) {
          const params: Record<string, string> = { select: 'id,meeting_id,username,text,spoken_at', meeting_id: `in.(${scope.slice(offset, offset + 100).map((meeting) => meeting.id).join(',')})`, order: 'spoken_at.desc,id.desc' };
          if (terms.length) params.or = `(${terms.flatMap((term) => [`text.ilike.*${term}*`, `username.ilike.*${term}*`]).join(',')})`;
          speech.push(...await readJasperSpeech<Speech>((query) => readRows<Speech>(this.env, auth, 'whisper_meeting_transcripts', query), params));
          if (speech.length > 2000) throw new Error('narrow_search');
        }
        if (!scanning && !input.recordingContext) {
          let noteCharacters = 0;
          // Summaries are separate evidence, not invented verbatim transcript rows.
          for (let offset = 0; offset < scope.length; offset += 100) {
            const notes = await pages<{ id: string; summary: string | null }>(this.env, auth, 'whisper_meetings', { select: 'id,summary', id: `in.(${scope.slice(offset, offset + 100).map((m) => m.id).join(',')})`, order: 'id.asc' }, 100);
            for (const note of notes) {
              const meeting = scope.find((m) => m.id === note.id);
              if (!meeting || !note.summary?.trim()) continue;
              noteCharacters += note.summary.length;
              if (noteCharacters > 1000000 || speech.length >= 2000) throw new Error('narrow_search');
              if (terms.length && !terms.some((term) => `${note.summary} ${meeting.title}`.toLowerCase().includes(term))) continue;
              speech.push({ id: note.id, meeting_id: note.id, username: 'Original meeting notes · summary, not verbatim speech', text: note.summary, spoken_at: meeting.ended_at ?? meeting.created_at, kind: 'summary' });
            }
          }
        }
        const ranked = rankJasperPassages(speech, noteContext?.text ?? input.question, scanning, { characters: 24000 - (noteContext?.text.length ?? 0), passages: 160 - (noteContext ? Math.ceil(noteContext.text.length / 1100) : 0) });
        const excerpted = ranked.excerpted;
        speech.splice(0, speech.length, ...ranked.rows);
        const selectedMeetings = new Set<string>(); let characters = noteContext?.text.length ?? 0; let omitted = 0;
        const notePassages = noteContext ? Math.ceil(noteContext.text.length / 1100) : 0;
        const sources: JasperEvidence[] = input.recordingContext ? jasperRecordingEvidence(input.recordingContext, scope[0].id, scope[0].title, scope[0].created_at) : [];
        for (const row of speech) {
          const meeting = scope.find((item) => item.id === row.meeting_id); if (!meeting) throw new Error('meeting_access_denied');
          if (!selectedMeetings.has(row.meeting_id) && selectedMeetings.size >= 8) { omitted++; continue; }
          for (let offset = 0; offset < row.text.length; offset += 1100) {
            const text = row.text.slice(offset, offset + 1100);
            if (sources.length + notePassages >= 160 || characters + text.length > 24000) { omitted++; continue; }
            sources.push({ id: `S${sources.length + 1}`, meetingId: row.meeting_id, meetingTitle: meeting.title, segmentId: row.id, spokenAt: row.spoken_at, speaker: String(row.username ?? 'Speaker').slice(0, 80), text, offset: (row.offset ?? 0) + offset, kind: row.kind ?? 'speech' }); characters += text.length; selectedMeetings.add(row.meeting_id);
          }
        }
        if (scanning && omitted) throw new Error('transcript_too_long');
        const knowledgeNote = knowledgeAllowed ? ' General-knowledge items, when present, come from Jasper itself and are labeled; they are not meeting facts.' : '';
        const coverage = (input.recordingContext ? 'User-selected private recording transcript snapshot. Times are relative to that recording, not the meeting clock. Speaker identity and completeness are not verified. No shared transcript or other recording was included.' : (excerpted || omitted) ? `Ranked excerpts from ${scope.length} accessible selected/search-scope meetings. ${sources.length} source excerpts included; other passages omitted. Later corrections and adjacent context prioritized where available, not guaranteed complete. Repeated mentions are not new people. This cannot verify exhaustive totals or absence. Pending or uncaptured speech is excluded.` : (scanning || input.meetingId || chosen) ? (speech.length ? `Saved meeting snapshot · ${speech.length} passages, including separately labeled original notes when available. No question-keyword filtering. Uncaptured, pending or later-arriving speech cannot be included.` : 'No saved speech or original notes were available for this meeting yet. Uncaptured, pending or later-arriving speech cannot be included.') : sources.length ? `Searched saved transcript text, speaker names and original meeting notes in ${scope.length} accessible meetings. Using ${sources.length} matching excerpts from ${selectedMeetings.size} meetings${omitted ? '; some matches were not included' : ''}. This is an excerpt search, not proof of a complete monthly total.` : `Searched saved transcript text, speaker names and original meeting notes in ${scope.length} accessible meetings. No matching excerpts were found; that is not proof the topic was never discussed.`) + knowledgeNote;
        let result: JasperResult = { insufficient: true, sections: [], actions: [], grounding: 'evidence', followups: [] };
        if (sources.length || knowledgeAllowed) {
          if (!this.env.OPENAI_API_KEY) throw new Error('ai_not_configured');
          checkRequest();
          const response = await fetch('https://api.openai.com/v1/chat/completions', { method: 'POST', signal: AbortSignal.any([AbortSignal.timeout(45000), request.signal, cancellation.signal]), headers: { Authorization: `Bearer ${this.env.OPENAI_API_KEY}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ model: this.env.JASPER_ANSWER_MODEL?.trim() || 'gpt-4o', max_tokens: 2400, temperature: 0.2, response_format: { type: 'json_object' }, messages: [
            { role: 'system', content: jasperAnswerInstructions },
            { role: 'user', content: JSON.stringify({ question: input.question, mode: noteContext ? 'connections' : scanning ? 'scan' : 'ask', knowledgeAllowed, noteContext, currentDate: new Date().toISOString(), preferences: library.preferences, coverage, sources }) },
          ] }) });
          if (!response.ok) throw new Error('ai_unavailable');
          const completion = await boundedJSON<{ choices?: { finish_reason?: string; message?: { content?: string } }[] }>(response, 100000);
          if (completion.choices?.[0]?.finish_reason !== 'stop') throw new Error('incomplete_answer');
          result = validateJasperResult(JSON.parse(completion.choices[0].message?.content ?? '{}'), sources, noteContext, { allowKnowledge: knowledgeAllowed });
        }
        // Recheck access after generation before returning or retaining evidence.
        const stillAccessible = new Set((await authorizedMeetings(this.env, auth, owner)).map((meeting) => meeting.id));
        if (sources.some((source) => !stillAccessible.has(source.meetingId))) throw new Error('meeting_access_denied');
        checkRequest();
        const answer: JasperAnswer = { id: requestID, question: input.question, generatedAt: new Date().toISOString(), scope: chosen ? `${noteContext ? 'Private note + ' : ''}${chosen.length} selected meetings` : input.meetingId ? scope[0]?.title ?? 'This meeting' : input.folderId ? library.folders.find((folder) => folder.id === input.folderId)?.name ?? 'Folder' : 'All my meetings', coverage: noteContext ? `One explicitly supplied private writing snapshot; its submission date is not the date of its claims. ${coverage}` : coverage, noteContext, partialEvidence: sources.length > 0 && (excerpted || omitted > 0 || terms.length > 0 || !!input.recordingContext), sources, result, meetingId: input.meetingId ?? null };
        this.ctx.storage.sql.exec("DELETE FROM jasper_values WHERE key LIKE 'draft:%' AND updated < ?", Date.now() - 86400000);
        const drafts = this.ctx.storage.sql.exec<{ count: number }>("SELECT COUNT(*) AS count FROM jasper_values WHERE key LIKE 'draft:%'").toArray()[0]?.count ?? 0;
        if (drafts >= 100) throw new Error('temporary_answer_limit');
        if (answerEpoch !== (this.read<number>('answer_epoch') ?? 0)) throw new Error('answer_changed');
        this.write(`draft:${answer.id}`, answer);
        try { await this.scheduleExpiry(); } catch { this.remove(`draft:${answer.id}`); throw new Error('request_failed'); }
        return jasperJSON(answer);
      }
      return jasperJSON({ error: 'not_found' }, 404);
    } catch (error) {
      const code = error instanceof Error ? error.message : 'request_failed';
      const allowed = ['workspace_access_denied','invalid_work','work_limit','work_person_missing','invalid_transition','client_access_denied','team_access_denied','invalid_client','client_save_failed','client_limit','confirmation_required','invalid_meeting_scope','revision_conflict','invalid_folder','folder_limit','invalid_meeting','invalid_preferences','invalid_action','filing_limit','meeting_access_denied','meeting_read_failed','narrow_search','transcript_too_long','ai_not_configured','ai_unavailable','invalid_answer','incomplete_answer','temporary_answer_limit','answer_changed','invalid_recording_context','invalid_note_context','request_cancelled'];
      return jasperJSON({ error: allowed.includes(code) ? code : 'request_failed' }, code === 'revision_conflict' ? 409 : code.endsWith('access_denied') ? 403 : 422);
    } finally {
      if (activeRequestID) this.activeAnswers.delete(activeRequestID);
    }
  }
}

export async function routeJasperMeetings(request: Request, env: JasperEnv, owner: string, email?: string | null): Promise<Response> {
  if (!env.DO) return jasperJSON({ error: 'account_storage_unavailable' }, 503);
  const wrapped = new Request(request.url, request);
  wrapped.headers.set('X-Jasper-Owner', owner);
  if (email !== undefined) wrapped.headers.set('X-Jasper-Email', email ?? '');
  const url = new URL(request.url);
  const target = url.pathname.startsWith('/jasper-meetings/workspace') ? (url.searchParams.get('space') ?? owner).toLowerCase() : url.pathname === '/jasper-meetings/clients/team' ? url.searchParams.get('businessId') ?? '' : owner;
  if (!meetingUUID.test(target)) return jasperJSON({ error: 'team_access_denied' }, 403);
  wrapped.headers.set('X-Rork-DO-Class', 'JasperMeetingAccount'); wrapped.headers.set('X-Rork-DO-Id', target);
  return env.DO.fetch(wrapped);
}
