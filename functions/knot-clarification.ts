const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const knotClarificationSchema = { anyOf: [{ type: 'null' }, { type: 'object', properties: { question: { type: 'string' }, options: { type: 'array', items: { type: 'string' }, minItems: 0, maxItems: 4 } }, required: ['question', 'options'], additionalProperties: false }] };
export type KnotClarification = { id: string; sourceMessageID: string; conversationID: string; bot: string; question: string; options: string[] };
export function validatedClarification(raw: unknown, context: { sourceMessageID?: string; conversationID?: string; bot: string }): KnotClarification | undefined {
  if (raw === null || raw === undefined) return undefined;
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new Error('invalid_clarification');
  const value = raw as Record<string, unknown>;
  const plain = (s: unknown, max: number): s is string => typeof s === 'string' && s === s.trim() && s.length > 0 && s.length <= max && !/[\x00-\x1f\x7f`]/.test(s);
  if (Object.keys(value).some(key => !['question', 'options'].includes(key)) || !(typeof value.question === 'string' && value.question === value.question.trim() && value.question.length > 0 && value.question.length <= 2400 && !/[\x00-\x09\x0b-\x1f\x7f`]/.test(value.question)) || !Array.isArray(value.options) || value.options.length > 4 || value.options.some(option => !plain(option, 100)) || new Set(value.options.map(option => String(option).toLocaleLowerCase())).size !== value.options.length || !context.sourceMessageID || !uuid.test(context.sourceMessageID) || !context.conversationID || !uuid.test(context.conversationID)) throw new Error('invalid_clarification');
  // Identity comes from this authenticated request, never the model or history.
  return { id: crypto.randomUUID(), sourceMessageID: context.sourceMessageID, conversationID: context.conversationID, bot: context.bot, question: value.question, options: value.options as string[] };
}
/** Optional inline next-message suggestions. Never native actions or approvals.
 * Refuse mixed control metadata rather than hiding an actual review surface. */
export function clarificationFromQuickActions(metadata: string, text: string, context: { sourceMessageID?: string; conversationID?: string; bot: string }): KnotClarification | undefined {
  const match = /^\s*```message\s*\n?([\s\S]*?)```\s*$/.exec(metadata);
  if (!match || metadata.length > 16000) return;
  try {
    const raw = JSON.parse(match[1]);
    if (!raw || typeof raw !== 'object' || Array.isArray(raw) || Object.keys(raw).length !== 1 || !Array.isArray(raw.quickActions) || !raw.quickActions.length) return;
    return validatedClarification({ question: text.trim(), options: raw.quickActions }, context);
  } catch { return; }
}

/** Uploaded/restored display metadata grants no tool or continuation authority. */
export function validatedStoredClarification(raw: unknown, context: { conversationID: string; bot: string; role: string; text: string }): KnotClarification | undefined {
  if (raw === undefined || raw === null) return undefined;
  if (!raw || typeof raw !== 'object' || Array.isArray(raw) || context.role !== 'ember') throw new Error('invalid_clarification');
  const value = raw as Record<string, unknown>;
  if (Object.keys(value).some(key => !['id', 'sourceMessageID', 'conversationID', 'bot', 'question', 'options'].includes(key)) || typeof value.id !== 'string' || !uuid.test(value.id) || typeof value.sourceMessageID !== 'string' || typeof value.conversationID !== 'string' || value.conversationID.toLowerCase() !== context.conversationID.toLowerCase() || value.bot !== context.bot || value.question !== context.text) throw new Error('invalid_clarification');
  const checked = validatedClarification({ question: value.question, options: value.options }, { conversationID: context.conversationID, sourceMessageID: value.sourceMessageID, bot: context.bot })!;
  return { ...checked, id: value.id.toLowerCase(), sourceMessageID: checked.sourceMessageID.toLowerCase(), conversationID: checked.conversationID.toLowerCase() };
}
export function validatedClarificationAnswer(raw: unknown, role: string, text: string): string | undefined {
  if (raw === undefined || raw === null) return undefined;
  if (role !== 'user' || typeof raw !== 'string' || !raw.trim() || raw !== raw.trim() || raw.length > 1000 || !text.startsWith('Original request: ') || !text.includes('\nClarifying question: ') || !text.endsWith('\nMy answer: ' + raw)) throw new Error('invalid_clarification_answer');
  return raw;
}
export const knotClarificationInstruction = '\nCLARIFICATION: return clarification=null unless one missing user preference or detail materially changes the requested output and cannot be safely assumed. Ask one short natural prose question with useful context, in the user’s language. options=[] is the default for an open-ended question: do not invent choices. Supply 2–4 distinct concise answers ONLY for a genuine pick-one decision. Choices supplement the prose, never replace it. Do not ask for shell/workspace/AI permission, approval to send/publish/pay/connect, secrets, or details already explicit. A selection is only a new user message, never approval or execution authority. Do not clarify ordinary questions or ask merely to personalize a clear task. When the latest message includes a prior question and its answer, resolve that ambiguity rather than asking it again.';
