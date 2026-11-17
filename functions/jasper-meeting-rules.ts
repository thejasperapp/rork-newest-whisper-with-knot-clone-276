/** Shared, bounded contracts for meeting retrieval. No client-selected identity grants access. */
export type JasperFolder = { id: string; name: string };
export type JasperLibrary = { revision: number; folders: JasperFolder[]; filings: Record<string, string>; preferences: { focus: string[]; instructions: string } };
export type JasperEvidence = { id: string; meetingId: string; meetingTitle: string; segmentId: string; spokenAt: string; speaker: string; text: string; offset: number; kind?: 'speech' | 'summary' | 'recording'; recordingId?: string; position?: number; timing?: 'speech' | 'chunk'; revision?: number };
export type JasperNoteContext = { title: string; text: string };
/** `knowledge` items are Jasper's own general knowledge: never cited, never meeting facts. */
export type JasperItemKind = 'evidence' | 'knowledge';
export type JasperGrounding = 'evidence' | 'knowledge' | 'mixed';
export type JasperResult = { insufficient: boolean; related?: boolean; grounding?: JasperGrounding; followups?: string[]; sections: { title: string; items: { kind?: JasperItemKind; text: string; sourceIds: string[]; noteQuote?: string }[] }[]; actions: { title: string; owner: string; when: string; sourceIds: string[] }[] };
export type JasperResultOptions = { allowKnowledge?: boolean };
export const meetingUUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const defaultJasperLibrary = (): JasperLibrary => ({ revision: 0, folders: [{ id: 'creators', name: 'Creators' }, { id: 'coaches', name: 'Coaches' }, { id: 'team', name: 'Team' }], filings: {}, preferences: { focus: ['Decisions', 'Client numbers', 'Next steps'], instructions: '' } });
const stopWords = new Set('a an the is are was were be have has had do does did can could would should how what when where which who why many much me my you your our all of in on at to for from with and or last month this that meetings meeting transcript tell about please compare summarize'.split(' '));
/** Search terms are query data, never PostgREST operators or executable instructions. */
export function jasperSearchTerms(question: string): string[] {
  return [...new Set((question.toLowerCase().match(/[\p{L}\p{N}]{2,40}/gu) ?? []).filter((word) => !stopWords.has(word)))].slice(0, 12);
}
/** Current-meeting questions must not require their wording to appear verbatim in speech. */
export function jasperRetrievalTerms(question: string, currentMeeting: boolean, scanning: boolean): string[] {
  if (currentMeeting || scanning || /^(summari[sz]e|recap|catch me up|what did i miss|generate notes)/i.test(question.trim())) return [];
  return jasperSearchTerms(question);
}

/** Client-selected private evidence is labeled as supplied, not server-verified shared speech. */
export function jasperRecordingEvidence(raw: unknown, meetingId: string, meetingTitle: string, date: string): JasperEvidence[] {
  const value = raw as { id: string; title: string; revision: number; passages: { id: string; text: string; start: number; end: number; timing: 'speech' | 'chunk'; speakerName?: string }[] };
  if (!value || !meetingUUID.test(value.id ?? '') || typeof value.title !== 'string' || value.title.length > 160 || !Number.isInteger(value.revision) || value.revision < 0 || !Array.isArray(value.passages) || !value.passages.length || value.passages.length > 160) throw new Error('invalid_recording_context');
  if (value.passages.some((p) => !p || typeof p.id !== 'string' || p.id.length > 80 || typeof p.text !== 'string' || !p.text.trim() || p.text.length > 12000 || !Number.isFinite(p.start) || !Number.isFinite(p.end) || p.start < 0 || p.end < p.start || p.end > 86400 || !['speech','chunk'].includes(p.timing) || (p.speakerName !== undefined && (typeof p.speakerName !== 'string' || p.speakerName.length > 160))) || value.passages.reduce((sum, p) => sum + p.text.length, 0) > 24000) throw new Error('transcript_too_long');
  const sources: JasperEvidence[] = [];
  for (const p of value.passages) for (let offset = 0; offset < p.text.length; offset += 1100) {
    if (sources.length >= 160) throw new Error('transcript_too_long');
    sources.push({ id: `S${sources.length + 1}`, meetingId, meetingTitle, segmentId: crypto.randomUUID(), spokenAt: date, speaker: p.speakerName?.trim() ? `${p.speakerName.trim()} · supplied recording source label` : 'Private recording · speaker not identified', text: p.text.slice(offset, offset + 1100), offset, kind: 'recording', recordingId: value.id, position: p.start, timing: p.timing, revision: value.revision });
  }
  return sources;
}
/** A supplied writing snapshot never grants meeting access or impersonates meeting speech. */
export function validateJasperNoteContext(raw: unknown, meetingIDs: string[] | undefined, mode: string | undefined): JasperNoteContext {
  const note = raw as JasperNoteContext;
  if (!note || typeof note.title !== 'string' || !note.title.trim() || note.title.length > 160 || typeof note.text !== 'string' || !note.text.trim() || note.text.length > 8000 || !meetingIDs?.length || meetingIDs.length > 7 || mode !== 'connections') throw new Error('invalid_note_context');
  return { title: note.title.trim(), text: note.text };
}
/** Knowledge items are only accepted where the caller allows them, never in scan or connections; actions stay evidence-cited. */
export function validateJasperResult(value: unknown, sources: JasperEvidence[], note?: JasperNoteContext, options: JasperResultOptions = {}): JasperResult {
  const result = value as JasperResult;
  const ids = new Set(sources.map((source) => source.id));
  const allowKnowledge = options.allowKnowledge === true && !note;
  const validIDs = (references: unknown): references is string[] => Array.isArray(references) && references.length > 0 && references.length <= 8 && references.every((id) => typeof id === 'string' && ids.has(id));
  const isKnowledge = (item: { kind?: unknown }): boolean => item.kind === 'knowledge';
  if (!result || typeof result.insufficient !== 'boolean' || !Array.isArray(result.sections) || !Array.isArray(result.actions) || result.sections.length > 6 || result.actions.length > 8) throw new Error('invalid_answer');
  if (result.sections.some((section) => typeof section.title !== 'string' || section.title.length > 100 || !Array.isArray(section.items) || section.items.length > 8 || section.items.some((item) => typeof item.text !== 'string' || !item.text.trim() || item.text.length > 1200 || (item.kind !== undefined && item.kind !== 'evidence' && item.kind !== 'knowledge')))) throw new Error('invalid_answer');
  for (const item of result.sections.flatMap((section) => section.items)) {
    if (isKnowledge(item)) { if (!allowKnowledge || !Array.isArray(item.sourceIds) || item.sourceIds.length !== 0 || item.noteQuote !== undefined) throw new Error('invalid_answer'); }
    else if (!validIDs(item.sourceIds)) throw new Error('invalid_answer');
  }
  if (result.actions.some((action) => typeof action.title !== 'string' || !action.title.trim() || action.title.length > 300 || typeof action.owner !== 'string' || action.owner.length > 100 || typeof action.when !== 'string' || action.when.length > 100 || !validIDs(action.sourceIds))) throw new Error('invalid_answer');
  if (result.related !== undefined && typeof result.related !== 'boolean') throw new Error('invalid_answer');
  if (result.related && result.insufficient) throw new Error('invalid_answer');
  if (result.grounding !== undefined && !['evidence', 'knowledge', 'mixed'].includes(String(result.grounding))) throw new Error('invalid_answer');
  if (result.followups !== undefined && (!Array.isArray(result.followups) || result.followups.length > 4 || result.followups.some((item) => typeof item !== 'string' || item.length > 160))) throw new Error('invalid_answer');
  for (const item of result.sections.flatMap((section) => section.items)) {
    if (isKnowledge(item)) continue;
    if (note ? typeof item.noteQuote !== 'string' || item.noteQuote.trim().length < 3 || item.noteQuote.length > 600 || !note.text.includes(item.noteQuote) : item.noteQuote !== undefined) throw new Error('invalid_answer');
  }
  if (note && (result.actions.length || result.sections.flatMap((section) => section.items).length > 5)) throw new Error('invalid_answer');
  const items = result.sections.flatMap((section) => section.items);
  const evidenceCount = items.filter((item) => !isKnowledge(item)).length + result.actions.length;
  const knowledgeCount = items.length - items.filter((item) => !isKnowledge(item)).length;
  if (result.related && evidenceCount === 0) throw new Error('invalid_answer');
  const count = items.length + result.actions.length;
  if (result.insufficient ? count !== 0 : count === 0) throw new Error('invalid_answer');
  const followups = result.insufficient ? [] : [...new Set((result.followups ?? []).map((item) => item.trim()).filter((item) => item.length >= 3))].slice(0, 3);
  const grounding: JasperGrounding = knowledgeCount > 0 && evidenceCount > 0 ? 'mixed' : knowledgeCount > 0 ? 'knowledge' : 'evidence';
  return { ...result, grounding, followups, sections: result.sections.map((section) => ({ title: section.title, items: section.items.map((item) => ({ ...item, kind: isKnowledge(item) ? 'knowledge' : 'evidence', sourceIds: isKnowledge(item) ? [] : item.sourceIds })) })) };
}
export function updateJasperLibrary(current: JasperLibrary, input: Record<string, unknown>): JasperLibrary {
  if (input.revision !== current.revision) throw new Error('revision_conflict');
  const next = structuredClone(current);
  const action = input.action;
  if (action === 'folder.create' || action === 'folder.rename') {
    const name = typeof input.name === 'string' ? input.name.trim() : '';
    if (!name || name.length > 60 || next.folders.some((folder) => folder.id !== input.id && folder.name.toLowerCase() === name.toLowerCase())) throw new Error('invalid_folder');
    if (action === 'folder.create') { if (next.folders.length >= 50) throw new Error('folder_limit'); next.folders.push({ id: crypto.randomUUID(), name }); }
    else { const folder = next.folders.find((folder) => folder.id === input.id); if (!folder) throw new Error('invalid_folder'); folder.name = name; }
  } else if (action === 'folder.remove') {
    next.folders = next.folders.filter((folder) => folder.id !== input.id);
    next.filings = Object.fromEntries(Object.entries(next.filings).filter(([, folder]) => folder !== input.id));
  } else if (action === 'file') {
    if (typeof input.meetingId !== 'string' || !meetingUUID.test(input.meetingId)) throw new Error('invalid_meeting');
    if (Object.prototype.hasOwnProperty.call(input, 'expectedFolder') && (current.filings[input.meetingId] ?? null) !== input.expectedFolder) throw new Error('revision_conflict');
    if (input.folderId === null || input.folderId === '') delete next.filings[input.meetingId];
    else if (typeof input.folderId === 'string' && next.folders.some((folder) => folder.id === input.folderId)) next.filings[input.meetingId] = input.folderId;
    else throw new Error('invalid_folder');
    if (Object.keys(next.filings).length > 10000) throw new Error('filing_limit');
  } else if (action === 'preferences') {
    if (!Array.isArray(input.focus) || input.focus.length > 12 || input.focus.some((item) => typeof item !== 'string' || !item.trim() || item.length > 80) || typeof input.instructions !== 'string' || input.instructions.length > 600) throw new Error('invalid_preferences');
    next.preferences = { focus: [...new Set(input.focus as string[])], instructions: input.instructions.trim() };
  } else throw new Error('invalid_action');
  next.revision++;
  return next;
}
