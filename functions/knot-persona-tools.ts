import { dispatchKnotActor, type KnotShellEnv } from './knot-shell';
import { avatarSharingScope } from './knot-persona';

const tool = (name: string, description: string, properties: Record<string, unknown> = {}, required: string[] = []) => ({ type: 'function' as const, function: { name, description, strict: true, parameters: { type: 'object', properties, required, additionalProperties: false } } });
const prompt = { type: 'string', description: 'Only the requested avatar description or edit; never include chat history, health, profile or workspace data.', maxLength: 1500 };
export const knotPersonaTools = [
  tool('avatar_get', 'Read your actual private persona, saved candidates, avatar sets and generation permission. This is independent of workspace files.'),
  tool('image_generate', 'Create private avatar candidates with centrally routed Nano Banana. Never ask the member to choose a model. If sharing permission is absent, prepares the in-chat permission card. Never selects a master.', { prompt, count: { type: 'integer', minimum: 1, maximum: 4 } }, ['prompt', 'count']),
  tool('image_edit', 'Create edited candidates from the CURRENT selected private master, preserving its identity. Does not replace it until the member taps a candidate.', { instruction: prompt, count: { type: 'integer', minimum: 1, maximum: 4 } }, ['instruction', 'count']),
  tool('persona_rename', 'Save the name explicitly requested by the member. Changes only the name, never avatar, reply style, memory or history.', { name: { type: 'string', minLength: 1, maxLength: 40 } }, ['name']),
  tool('avatar_set', 'Show the private candidate picker. The member must tap an avatar photo; the assistant cannot choose on their behalf.'),
  tool('avatar_revert', 'Show whole avatar-set restoration choices. The member must explicitly tap Restore or Use original Knot; the assistant cannot select a set.'),
];
export const knotPersonaToolContract = 'PRIVATE PERSONA CAPABILITIES are real account-actor tools, independent of shell, workspace files and public image URLs. Use them for explicit avatar/name requests. Read avatar_get for actual state. Never claim no image tools when these are offered. image_generate/image_edit use centrally selected Nano Banana; users never choose models. Missing avatar sharing permission prepares an in-chat permission card; never grant consent on their behalf. Only requested avatar description/instruction and identity reference images go to generation, never other personal context. Generated images/videos and their references go to a separate Google Gemini quality check under explicit versioned permission. Candidates are static WebP with stored visual descriptions and eye/mouth traits; only separately checked output can enter member review. Generation saves candidates, NOT a new master. The actual private candidate picker appears in chat; ask the member to tap an avatar photo. avatar_set and avatar_revert expose choices and NEVER commit a model-made choice. Edits use the current selected master. Choosing a master starts its own call portrait and six fixed-state motion attempts with the permitted provider; the master pick is the only approval for that fixed derived set. Independently checked matching media activates automatically; missing, failed or uncertain states silently use the selected master still. THE RECORD IS NOT UI: descriptions, eye/mouth traits, providers, pipeline details, credits, quality disclaimers and per-state job/status tables are system-facing evidence only. Never print them in chat or request per-piece approvals. Chat is ask, photo candidates, member pick, one short confirmation. When permission is missing the picker has one compact consent control; do not repeat its disclosure in prose. After candidates are saved, say only a short invitation to pick a photo, not counts or bookkeeping. If explicitly asked about animations, read actual state and answer in one human sentence with no table; never claim unconfirmed states succeeded. Rename only when explicitly requested, independently of all other state. Unconfirmed work is not success and must not be replayed. There is no workspace, file capture or memory step for these requests.';

type Snapshot = { version: number; consent: boolean; consentModel: string | null; [key: string]: unknown };
async function readResponse(response: Response): Promise<Record<string, unknown>> {
  const reader = response.body?.getReader(); if (!reader) throw new Error('persona_response_unavailable');
  let text = '', bytes = 0; const decoder = new TextDecoder();
  try { for (;;) { const part = await reader.read(); if (part.done) break; bytes += part.value.byteLength; if (bytes > 100000) throw new Error('persona_response_too_large'); text += decoder.decode(part.value, { stream: true }); } }
  finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
  const value = JSON.parse(text + decoder.decode());
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('persona_response_invalid');
  return { ok: response.ok, ...value };
}
/** Owner, version, model and single-use job IDs come from trusted turn state,
 * never the model. Picks/restores stay explicit native member actions. */
export function knotPersonaToolRunner(env: KnotShellEnv, owner: string, signal: AbortSignal, source?: { bot: string; conversationID?: string; sourceMessageID?: string }) {
  let generationConsumed = false;
  return async (name: string, args: Record<string, unknown>): Promise<string> => {
    const definition = knotPersonaTools.find(t => t.function.name === name);
    if (!definition || Object.keys(args).some(key => !Object.hasOwn(definition.function.parameters.properties, key)) || definition.function.parameters.required.some(key => !Object.hasOwn(args, key))) throw new Error('invalid_persona_arguments');
    if (signal.aborted) throw new Error('cancelled');
    const read = await readResponse(await dispatchKnotActor(env, owner.toLowerCase(), 'persona/read', {}, signal));
    if (!read.ok || !Number.isInteger(read.version)) return JSON.stringify(read);
    const current = read as Snapshot;
    if (name === 'avatar_get') return JSON.stringify(read);
    if (name === 'avatar_set') return JSON.stringify({ ok: true, changed: false, memberChoiceRequired: true, control: 'chat_candidate_picker', persona: read });
    if (name === 'avatar_revert') return JSON.stringify(await readResponse(await dispatchKnotActor(env, owner.toLowerCase(), 'persona/restore-options', { version: current.version, source }, signal)));
    if (name === 'persona_rename') {
      if (typeof args.name !== 'string' || !args.name.trim() || args.name.length > 40) throw new Error('invalid_persona_arguments');
      return JSON.stringify(await readResponse(await dispatchKnotActor(env, owner.toLowerCase(), 'persona/name', { version: current.version, name: args.name }, signal)));
    }
    const instruction = name === 'image_edit' ? args.instruction : args.prompt;
    if (typeof instruction !== 'string' || !instruction.trim() || instruction.length > 1500 || !Number.isInteger(args.count) || Number(args.count) < 1 || Number(args.count) > 4) throw new Error('invalid_persona_arguments');
    if (!current.consent || current.consentScope !== avatarSharingScope) {
      const pending = await readResponse(await dispatchKnotActor(env, owner.toLowerCase(), 'persona/request', { version: current.version, source, prompt: instruction, count: args.count, edit: name === 'image_edit' }, signal));
      return JSON.stringify({ ...pending, generationExecuted: false, memberChoiceRequired: true, control: 'chat_avatar_sharing', note: 'The picker contains the compact sharing-consent control. Do not repeat provider/pipeline disclosures in prose or claim generation started. One short invitation to use the control is enough.' });
    }
    if (generationConsumed) return JSON.stringify({ ok: false, error: 'generation_already_submitted_this_turn', executed: false, note: 'Read saved state; never resubmit an uncertain generation.' });
    generationConsumed = true; // Before I/O, including errors and interrupted responses.
    return JSON.stringify(await readResponse(await dispatchKnotActor(env, owner.toLowerCase(), 'persona/candidates', { version: current.version, source, jobID: crypto.randomUUID(), prompt: instruction, count: args.count, edit: name === 'image_edit' }, signal)));
  };
}
