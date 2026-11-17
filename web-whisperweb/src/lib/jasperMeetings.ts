import { z } from 'zod';
import { supabase } from './supabase';
import { assertJasperSession, jasperSession } from './jasperSession';
import { timedPassageSchema } from './meetingRecordingModel';
import { isKnowledgeItem } from './jasperAnswerModel';

export const JASPER_MEETINGS_URL = (import.meta.env.VITE_JASPER_MEETINGS_URL as string | undefined) ?? 'https://e1p9ya2tdy09t3sy62x1s-backend.rork.app';
export const jasperLibrarySchema = z.object({ revision: z.number().int().nonnegative(), folders: z.array(z.object({ id: z.string(), name: z.string() })), filings: z.record(z.string()), preferences: z.object({ focus: z.array(z.string()), instructions: z.string() }) });
export type JasperLibrary = z.infer<typeof jasperLibrarySchema>;
const evidenceSchema = z.object({ id: z.string(), meetingId: z.string().uuid(), meetingTitle: z.string(), segmentId: z.string().uuid(), spokenAt: z.string(), speaker: z.string(), text: z.string().max(1200), offset: z.number(), kind: z.enum(['speech', 'summary', 'recording']).optional(), recordingId: z.string().uuid().optional(), position: z.number().finite().nonnegative().optional(), timing: z.enum(['speech', 'chunk']).optional(), revision: z.number().int().optional() });
/** `knowledge` items are Jasper's own general knowledge: uncited, labeled, never a meeting fact. */
export const jasperItemSchema = z.object({ kind: z.enum(['evidence', 'knowledge']).optional(), text: z.string(), sourceIds: z.array(z.string()), noteQuote: z.string().min(3).max(600).optional() });
export const jasperAnswerSchema = z.object({ id: z.string().uuid(), question: z.string(), generatedAt: z.string(), scope: z.string(), coverage: z.string(), partialEvidence: z.boolean().optional(), meetingId: z.string().nullable(), sources: z.array(evidenceSchema).max(160), noteContext: z.object({ title: z.string().max(160), text: z.string().max(8000) }).optional(), result: z.object({ insufficient: z.boolean(), related: z.boolean().optional(), grounding: z.enum(['evidence', 'knowledge', 'mixed']).optional(), followups: z.array(z.string().max(160)).max(4).optional(), sections: z.array(z.object({ title: z.string(), items: z.array(jasperItemSchema) })), actions: z.array(z.object({ title: z.string(), owner: z.string(), when: z.string(), sourceIds: z.array(z.string()) })) }) });
export type JasperAnswer = z.infer<typeof jasperAnswerSchema>;
export type JasperAnswerItem = z.infer<typeof jasperItemSchema>;
export type JasperEvidence = z.infer<typeof evidenceSchema>;
export const jasperRecordingContextSchema = z.object({ id: z.string().uuid(), title: z.string().max(160), revision: z.number().int().nonnegative(), passages: z.array(timedPassageSchema).max(160) });
export type JasperRecordingContext = z.infer<typeof jasperRecordingContextSchema>;
export type JasperCalendarEvent = { id: string; title: string; start: string; end: string; allDay: boolean; link: string; source: string };
const errors: Record<string, string> = {
  workspace_access_denied: 'This workspace item is not available to your account. Ask the owner to review your invitation or team access.',
  invalid_work: 'Check required fields, field lengths, dates and HTTPS links.',
  work_limit: 'This workspace reached its supported capacity. Existing records are unchanged.',
  work_person_missing: 'No exact Whisper username matched. Check the spelling with the person you want to invite.',
  invalid_transition: 'This step is not available. Refresh and check the assigned owner, required dates and current version.',
  confirmation_required: 'Review this content and who can see it before saving.',
  request_cancelled: 'This request was cancelled. Review your context before starting again.',
  invalid_note_context: 'Choose one note excerpt (up to 8,000 characters) and between one and seven meetings for connections.',
  invalid_meeting_scope: 'Choose between one and eight meetings. Other scopes cannot be combined.',
  invalid_client: 'Check your contact details, dates and field lengths, then retry.',
  client_access_denied: 'This private person is not available to your account.',
  team_access_denied: 'Your access to this team is no longer available. Refresh your teams.',
  client_save_failed: 'The update could not be confirmed. Refresh before retrying.',
  client_limit: 'This workspace has reached its supported client or team-card limit.',
  revision_conflict: 'Your organization changed on another device. Refresh and try again; nothing was overwritten.',
  meeting_access_denied: 'You no longer have access to one of these meetings. Refresh your library.',
  meeting_read_failed: 'Meeting transcripts could not load. Reconnect and retry.',
  narrow_search: 'There are too many matches to verify. Choose a folder or ask a more specific question.',
  transcript_too_long: 'This transcript is too long for a single scan. It has not been shortened or sent to AI.',
  google_setup_required: 'Google Calendar needs the app’s Google authorization setup before it can connect.',
  google_reconnect: 'Google Calendar needs you to connect again.',
  account_storage_unavailable: 'Private meeting storage is temporarily unavailable. Your original meetings are unchanged.',
  sign_in_required: 'Sign in again to use your Jasper.',
  ai_not_configured: 'Jasper’s AI connection needs server setup. Your meeting is unchanged.',
  invalid_answer: 'Jasper’s answer could not be verified. Please try again.',
  incomplete_answer: 'Jasper returned an incomplete answer. Please try a narrower question.',
  answer_expired: 'This temporary answer expired. Ask again before saving it.',
  try_again_shortly: 'Please wait a moment before asking again.',
  temporary_answer_limit: 'Temporary answer storage is full. Clear a conversation or wait for temporary answers to expire.',
  saved_answer_limit: 'Saved Jasper answer storage is full. Manage private answers in Personalize Jasper.',
  google_matching_email_required: 'Verify your Whisper email before connecting the Google account with that same email.',
  answer_changed: 'Your private answers were cleared on another device. Please ask again.',
};
/** Every response is bound to the account that initiated the request. */
export async function jasperMeetingRequest<T>(owner: string, path: string, body?: unknown, signal?: AbortSignal): Promise<T> {
  const context = await jasperSession();
  assertJasperSession(context);
  if (context.ownerId !== owner.toLowerCase()) throw new Error('Sign in again to use your Jasper.');
  const response = await fetch(`${JASPER_MEETINGS_URL}/jasper-meetings/${path}`, { method: body === undefined ? 'GET' : 'POST', headers: { Authorization: `Bearer ${context.jwt}`, 'X-Whisper-Authorization': `Bearer ${context.jwt}`, 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.any([context.signal, ...(signal ? [signal] : []), AbortSignal.timeout(90000)]) });
  assertJasperSession(context);
  const result = await response.json() as T & { error?: string };
  assertJasperSession(context);
  const current = await supabase.auth.getSession();
  assertJasperSession(context);
  if (current.data.session?.user.id !== owner) throw new Error('Your account changed. Reopen Jasper.');
  signal?.throwIfAborted();
  if (!response.ok) throw new Error(errors[result.error ?? ''] ?? 'Jasper could not complete this request. Your saved meetings are unchanged. Try again.');
  return result;
}
export async function loadJasperLibrary(owner: string, signal?: AbortSignal): Promise<JasperLibrary> { return jasperLibrarySchema.parse(await jasperMeetingRequest(owner, 'library', undefined, signal)); }
/** `knowledge: false` keeps an answer to meeting evidence only; scans and connections are always evidence-only. */
export async function askJasperMeetings(owner: string, input: { requestId?: string; question: string; meetingId?: string; meetingIds?: string[]; folderId?: string; mode: 'ask' | 'scan' | 'connections'; knowledge?: false; noteContext?: { title: string; text: string }; consent: true; recordingContext?: JasperRecordingContext }, signal: AbortSignal): Promise<JasperAnswer> {
  if (input.recordingContext) {
    jasperRecordingContextSchema.parse(input.recordingContext);
    if (input.recordingContext.passages.reduce((sum, passage) => sum + passage.text.length, 0) > 24000) throw new Error('Choose a shorter recording excerpt: Jasper can read up to 24,000 characters at once.');
  }
  const answer = jasperAnswerSchema.parse(await jasperMeetingRequest(owner, 'ask', input, signal));
  const ids = new Set(answer.sources.map((source) => source.id));
  const items = answer.result.sections.flatMap((section) => section.items);
  const knowledgeAllowed = input.mode === 'ask' && !input.noteContext && input.knowledge !== false;
  if (items.some((item) => isKnowledgeItem(item) && (!knowledgeAllowed || item.sourceIds.length || item.noteQuote !== undefined))) throw new Error('Jasper’s general-knowledge items could not be verified.');
  if (answer.noteContext && items.some((item) => !item.noteQuote || !answer.noteContext!.text.includes(item.noteQuote))) throw new Error('Jasper’s note quotations could not be verified.');
  if (answer.sources.reduce((sum, source) => sum + source.text.length, answer.noteContext?.text.length ?? 0) > 24000 || items.some((item) => !isKnowledgeItem(item) && (!item.sourceIds.length || item.sourceIds.some((id) => !ids.has(id)))) || answer.result.actions.some((action) => !action.sourceIds.length || action.sourceIds.some((id) => !ids.has(id)))) throw new Error('Jasper’s source references could not be verified.');
  return answer;
}
