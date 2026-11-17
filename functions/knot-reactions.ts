import type { KnotBot } from './knot-agent';
import type { KnotShellEnv } from './knot-shell';
import { dispatchKnotActor, knotWorkspaceID } from './knot-shell';
import { normalizedKnotReaction } from './knot-message-skills';

export type KnotReaction = { messageID: string; emoji: string; revision: number; recordedAt: string };
export const reactionTool = { type: 'function', function: { name: 'react', description: 'Attach one Unicode emoji unchanged to the current user message, immediately. Choose at most one semantic reaction per source message; a different second choice is rejected. The runtime alone supplies any long-work acknowledgment. Not a reply, push, approval or delivery receipt. Follow the session-cached communication guide or supplied default contract; never announce a reaction in prose.', strict: true,
  parameters: { type: 'object', properties: { message_id: { type: 'string' }, emoji: { type: 'string', description: 'Exactly one Unicode emoji grapheme, unchanged. No enum or substitutions.' } }, required: ['message_id', 'emoji'], additionalProperties: false } } };

export async function reactionActor(env: KnotShellEnv, owner: string, action: 'begin' | 'apply' | 'close' | 'events', data: unknown): Promise<Response> {
  owner = owner.toLowerCase();
  return env.DO.fetch(new Request('https://internal/internal/reactions/' + action, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Knot-Owner': owner, 'X-Rork-DO-Class': 'KnotConversationAccount', 'X-Rork-DO-Id': owner }, body: JSON.stringify(data) }));
}

// Fixed session-start communication read only: no user paths/commands. The
// executor caches its complete receipt in the SAME owned account session.
// Reading this skill is never a prerequisite for placing a reaction.
const guideRead = "python3 - <<'KNOT_COMMUNICATION'\nfrom pathlib import Path\nindex = Path('/opt/knot-skills/README.md').read_text()\nassert 'message-reactions' in index\nguide = Path('/opt/knot-skills/message-reactions/SKILL.md').read_text()\nassert 'name: message-reactions' in guide\nprint(guide, end='')\nKNOT_COMMUNICATION";
// The addendum explicitly authorizes this default, not a bundled copy of the
// live skill. Optional/no-reaction and member tone preferences still apply.
export const defaultReactionContract = 'SESSION REACTION DEFAULT: Guidance is absent. When a reaction genuinely fits, choose one Unicode emoji that matches the specific message and tone. Preserve its exact grapheme, including skin tone, variation selectors and joined sequences. There is no default emoji and no fixed emoji list. A reaction is optional, not mandatory on every message. Do not react to an ordinary quick question when a short answer suffices. Respect the member’s no-emoji/no-reaction preference, including supplied recent thread context. Do not use an acknowledgment gesture for distress or a safety disclosure. Never substitute acknowledgment prose or claim placement without the actual react receipt.';

/** Storage lookup only. No discovery, provider fetch, session creation or input.
 * Missing/unavailable cache uses the default; it never disables placement. */
export async function readCachedReactionGuide(env: KnotShellEnv, owner: string, bot: KnotBot, conversationID: string, signal: AbortSignal): Promise<string | undefined> {
  const workspace = await knotWorkspaceID(env, owner.toLowerCase(), bot, conversationID, signal);
  const response = await dispatchKnotActor(env, owner, 'reaction-guide', { workspace }, signal);
  const value = await response.json() as { guide?: unknown };
  if (!response.ok || signal.aborted) throw new Error('reaction_cache_unavailable');
  return typeof value.guide === 'string' && value.guide.includes('name: message-reactions') && new TextEncoder().encode(value.guide).byteLength <= 64000 ? value.guide : undefined;
}
export function validReaction(value: unknown): value is KnotReaction {
  const r = value as KnotReaction;
  return !!r && typeof r.messageID === 'string' && typeof r.emoji === 'string' && normalizedKnotReaction(r.emoji) === r.emoji && Number.isSafeInteger(r.revision) && r.revision > 0 && typeof r.recordedAt === 'string' && Number.isFinite(Date.parse(r.recordedAt));
}
export { guideRead as reactionGuideReadCommand };
