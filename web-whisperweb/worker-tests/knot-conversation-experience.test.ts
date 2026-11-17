// @vitest-environment node
import { afterEach, describe, expect, it, vi } from 'vitest';
vi.mock('cloudflare:workers', () => ({ DurableObject: class {} }));
import { reactionPreference } from '../../functions/knot-reaction-policy';
import { normalizedKnotReaction } from '../../functions/knot-message-skills';
import { validatedClarification, validatedStoredClarification, validatedClarificationAnswer, clarificationFromQuickActions } from '../../functions/knot-clarification';
import { knotLive } from '../../functions/knot-live';
import { knotTaskModel, knotCreationBriefing } from '../../functions/knot-task-experience';
import { safeKnotActivityDetail } from '../../functions/knot-activity';
import { authorKnotStep } from '../../functions/knot-step-author';
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });
const conversationID = '00000000-0000-4000-8000-000000000001', sourceMessageID = '00000000-0000-4000-8000-000000000002', requestID = '00000000-0000-4000-8000-000000000003';
describe('explicitly consented task models and purposeful plans', () => {
  it('retains OpenAI-only consent for every task and never accepts an arbitrary provider', () => {
    for (const task of ['routing', 'reaction', 'answer', 'creation', 'browser'] as const) expect(knotTaskModel(false, task)).toBe('openai/gpt-4o');
    expect(knotTaskModel(true, 'routing')).toBe('openai/gpt-4o');
    expect(knotTaskModel(true, 'answer')).toBe('anthropic/claude-haiku-4.5');
    expect(knotTaskModel(true, 'reaction')).toBe('anthropic/claude-haiku-4.5');
    expect(knotTaskModel(true, 'creation')).toBe('anthropic/claude-sonnet-4.6');
    expect(knotTaskModel(true, 'browser')).toBe('anthropic/claude-sonnet-4.6');
    expect(safeKnotActivityDetail({ model: 'anthropic/claude-sonnet-4.6' })?.model).toBe('anthropic/claude-sonnet-4.6');
    expect(safeKnotActivityDetail({ model: 'unapproved/model' })).toBeUndefined();
  });
  it('keeps ordinary answers quiet and only gives a prospective creation plan', () => {
    expect(knotCreationBriefing({ mode: 'Answer', workspace: true, document: false })).toBeUndefined();
    expect(knotCreationBriefing({ mode: 'Converse', workspace: false, document: false })).toBeUndefined();
    expect(knotCreationBriefing({ mode: 'Create', workspace: false, document: false })).toBeUndefined();
    expect(knotCreationBriefing({ mode: 'Create', workspace: true, document: true, format: 'pdf' })).toContain('I’ll create the PDF');
    expect(knotCreationBriefing({ mode: 'Create', workspace: true, document: true, format: 'txt' })).not.toContain('PDF');
  });
});
describe('audience-separated step authoring', () => {
  it('never creates chat news without result evidence or for delivery-note authoring', async () => {
    vi.stubGlobal('fetch', vi.fn(async (_url: string, init: RequestInit) => {
      const request = JSON.parse(String(init.body));
      expect(request.response_format.json_schema.schema.required).toContain('chatUpdate');
      expect(request.messages[0].content).toContain('header/Events ONLY, never chat');
      return Response.json({ choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({ label: 'Read dance memory', purpose: 'Read the saved routine.', result: 'Routine retrieved.', chatUpdate: 'Your routine is missing its music track.' }) } }] });
    }));
    const input = { url: 'https://synthetic.invalid', token: 'synthetic-only', signal: new AbortController().signal, taskModelsAllowed: false, request: 'Help with a dance', operation: 'memory_read', purpose: 'Read memory.' };
    expect(await authorKnotStep(input)).not.toHaveProperty('chatUpdate');
    const evidence = { returned: true, observations: [{ missingMusic: true }] };
    expect(await authorKnotStep({ ...input, result: evidence })).toMatchObject({ result: 'Routine retrieved.', chatUpdate: 'Your routine is missing its music track.' });
    expect(await authorKnotStep({ ...input, operation: 'delivery_reply', result: evidence })).not.toHaveProperty('chatUpdate');
  });
});
describe('selective optional reactions', () => {
  it.each(['No emojis please', 'Don’t use emojis', 'Stop reactions', 'Please avoid reactions', 'Do not send any emojis'])('persists an explicit opt-out: %s', text => expect(reactionPreference(text)).toBe('off'));
  it('does not reset a preference from an ordinary follow-up or emoji', () => { expect(reactionPreference('Thanks! 🥳')).toBeUndefined(); expect(reactionPreference('You can use emojis again')).toBe('on'); });
  it('keeps frequency corrections distinct from a global opt-out', () => {
    expect(reactionPreference('Do not react to every message')).toBe('on');
    expect(reactionPreference('Stop reactions. You can use emojis again')).toBe('on');
    expect(reactionPreference('You can use emojis. Stop reactions')).toBe('off');
  });
  it.each(['🥳', '🫶🏽', '👩🏾‍🚀', '🏳️‍🌈', '🪼', '❤️‍🔥'])('preserves unrestricted graphemes unchanged: %s', emoji => expect(normalizedKnotReaction(emoji)).toBe(emoji));
});
describe('source-bound clarification', () => {
  it('binds identity outside the model and rejects malformed/duplicate choices', () => {
    const context = { conversationID, sourceMessageID, bot: 'main' };
    expect(validatedClarification({ question: 'Who is this for?', options: ['Beginners', 'Experienced readers'] }, context)).toMatchObject(context);
    for (const raw of [{ question: 'Who?', options: ['Same', 'same'] }, { question: 'Who?', options: ['One', 'Two'], command: 'not allowed' }, { question: 'Who?\u0000Run this', options: ['One', 'Two'] }, { question: 'Who?', options: ['A', 'B', 'C', 'D', 'E'] }]) expect(() => validatedClarification(raw, context)).toThrow('invalid_clarification');
    expect(() => validatedClarification({ question: 'Who?', options: ['One', 'Two'] }, { bot: 'main' })).toThrow();
    expect(validatedClarification(null, context)).toBeUndefined();
  });
  it('supports natural prose without invented choices and a single concrete next reply', () => {
    const context = { conversationID, sourceMessageID, bot: 'main' };
    const prose = 'I can tailor the guide.\n\nWhat would you like it to cover?';
    const open = validatedClarification({ question: prose, options: [] }, context)!;
    expect(open.options).toEqual([]);
    expect(validatedStoredClarification(open, { conversationID, bot: 'main', role: 'ember', text: prose })).toEqual(open);
    const action = clarificationFromQuickActions('```message\n{"quickActions":["Add a packing list"]}\n```', 'Would you like a packing list?', context)!;
    expect(action).toMatchObject({ ...context, question: 'Would you like a packing list?', options: ['Add a packing list'] });
    expect(action.id).toMatch(/^[a-f0-9-]{36}$/);
    for (const raw of [
      { quickActions: ['Yes'], approvals: ['send'] },
      { quickActions: ['Yes'], shellProposal: { command: 'not allowed' } },
      { quickActions: ['Yes'], sourceMessageID: requestID },
      { quickActions: [] }, { quickActions: ['Same', 'same'] },
    ]) expect(clarificationFromQuickActions('```message\n' + JSON.stringify(raw) + '\n```', prose, context)).toBeUndefined();
    expect(clarificationFromQuickActions('```message\n{"quickActions":["Continue"]}\n```', prose, { bot: 'main' })).toBeUndefined();
  });
  it('keeps operation narration separate from explicit user-facing news', () => {
    expect(safeKnotActivityDetail({ stepID: 'dance-memory', stepPurpose: 'Access dance memory.', stepResult: 'Memory read.' })).not.toHaveProperty('chatUpdate');
    expect(safeKnotActivityDetail({ stepID: 'dance-memory', chatUpdate: 'Your saved routine is missing its music track.' })?.chatUpdate).toBe('Your saved routine is missing its music track.');
    expect(safeKnotActivityDetail({ stepID: 'dance-memory', chatUpdate: '<control>' })).not.toHaveProperty('chatUpdate');
    expect(safeKnotActivityDetail({ chatUpdate: 'Unbound news' })).toBeUndefined();
  });
  it('persists bounded display data without rebinding a card to another conversation or edited text', () => {
    const card = validatedClarification({ question: 'Who is this for?', options: ['Beginners', 'Experienced readers'] }, { conversationID, sourceMessageID, bot: 'main' })!;
    const context = { conversationID, bot: 'main', role: 'ember', text: card.question };
    expect(validatedStoredClarification(card, context)).toEqual(card);
    for (const changed of [{ ...context, conversationID: requestID }, { ...context, bot: 'other' }, { ...context, role: 'user' }, { ...context, text: 'Different question' }]) expect(() => validatedStoredClarification(card, changed)).toThrow();
    expect(() => validatedStoredClarification({ ...card, command: 'not allowed' }, context)).toThrow();
    expect(validatedClarificationAnswer('Beginners', 'user', 'Original request: Create a guide\nClarifying question: Who is this for?\nMy answer: Beginners')).toBe('Beginners');
    expect(() => validatedClarificationAnswer('Beginners', 'user', 'Unrelated source text')).toThrow();
  });
  it('terminates the actual orchestrator with a negotiated card before any proposal or execution', async () => {
    const routes: string[] = [], providerRequests: Record<string, unknown>[] = [];
    const env = { SUPABASE_SERVICE_ROLE_KEY: 'synthetic-only', EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY: 'synthetic-only', EXPO_PUBLIC_TOOLKIT_URL: 'https://synthetic.invalid', DO: { fetch: vi.fn(async (request: Request) => {
      const path = new URL(request.url).pathname; routes.push(path);
      if (path === '/admit' || path === '/activity') return Response.json({ ok: true });
      if (path === '/internal/reactions/begin') return Response.json({ ready: false, suppressed: true });
      if (path === '/internal/reactions/close') return Response.json({ closed: true });
      if (path === '/discovery') return Response.json({ ok: true, service: 'knot-sidecar', tools: [] });
      throw new Error('No execution permitted: ' + path);
    }) } };
    vi.stubGlobal('fetch', vi.fn(async (_url: string, init: RequestInit) => {
      const body = JSON.parse(String(init.body)); providerRequests.push(body);
      if (body.response_format.json_schema.name === 'contextual_step') return Response.json({ choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({ label: 'Clarify the guide audience', purpose: 'Identify the guide audience.', result: '', chatUpdate: '' }) } }] });
      expect(body.response_format.json_schema.name).toBe('work_mode');
      expect(body.response_format.json_schema.schema.required).toContain('clarification');
      return Response.json({ choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({ persona: false, mode: 'Create', workspace: true, document: true, browser: false, browserReview: 'none', ratingRequested: false, liveSource: 'none', resumeReview: false, craftSkills: [], clarification: { question: 'Who should the guide help?', options: ['First-time hikers', 'Experienced hikers'] } }) } }] });
    }));
    let pending: Promise<unknown> | undefined;
    const response = await knotLive(new Request('https://synthetic.invalid/knot/live', { method: 'POST', body: JSON.stringify({ requestID, consentVersion: 'knot_ai_consent_v3', message: 'Create a hiking guide as a PDF', bot: 'main', healthContext: '', history: [], isWebQuery: false, sharedConversation: false, conversationID, sourceMessageID, clarificationVersion: 'knot_clarification_v1' }) }), env, requestID, { waitUntil: task => { pending = task; } });
    const text = await response.text(); await pending;
    expect(providerRequests).toHaveLength(1);
    expect(providerRequests.map(body => (body.response_format as { json_schema: { name: string } }).json_schema.name)).toEqual(['work_mode']);
    expect(routes).not.toContain('/propose'); expect(routes).not.toContain('/dispatch');
    const complete = text.split('\n').filter(line => line.startsWith('data: ')).map(line => JSON.parse(line.slice(6))).find(event => event.type === 'complete');
    expect(complete.clarification).toMatchObject({ conversationID, sourceMessageID, bot: 'main', question: complete.reply, options: ['First-time hikers', 'Experienced hikers'] });
  });
});
