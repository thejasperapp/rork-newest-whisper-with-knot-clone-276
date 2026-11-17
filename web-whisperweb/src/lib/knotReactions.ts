export interface KnotReaction { messageID: string; emoji: string; revision: number; recordedAt: string }
type ReactionFields = { role?: string; reaction?: unknown; reactionRevision?: unknown; reactionRecordedAt?: unknown };

/** Transport validation only; preserve every Unicode scalar unchanged. */
export function normalizedKnotReaction(raw: unknown): string | undefined {
  if (typeof raw !== 'string' || !raw || raw.length > 128) return undefined;
  const Segmenter = (Intl as unknown as { Segmenter?: new (locale: string, options: { granularity: string }) => { segment(value: string): Iterable<unknown> } }).Segmenter;
  if (!Segmenter || [...new Segmenter('und', { granularity: 'grapheme' }).segment(raw)].length !== 1) return undefined;
  const keycap = /^[0-9#*]\uFE0F?\u20E3$/u.test(raw);
  const flag = /^\p{Regional_Indicator}{2}$/u.test(raw);
  const pictograph = /\p{Extended_Pictographic}/u.test(raw) && /^[\p{Extended_Pictographic}\p{Emoji_Modifier}\uFE0F\u200D\u{E0020}-\u{E007F}]+$/u.test(raw);
  return keycap || flag || pictograph ? raw : undefined;
}
export function validKnotReaction(value: unknown): value is KnotReaction {
  const r = value as KnotReaction;
  return !!r && typeof r.messageID === 'string' && /^[0-9a-f-]{36}$/i.test(r.messageID) && typeof r.emoji === 'string' && normalizedKnotReaction(r.emoji) === r.emoji && Number.isSafeInteger(r.revision) && r.revision > 0 && typeof r.recordedAt === 'string' && Number.isFinite(Date.parse(r.recordedAt));
}
export function confirmedKnotReaction(message?: ReactionFields): string | undefined {
  return message?.role === 'user' && typeof message.reactionRevision === 'number' && Number.isSafeInteger(message.reactionRevision) && message.reactionRevision > 0 && typeof message.reactionRecordedAt === 'string' && Number.isFinite(Date.parse(message.reactionRecordedAt)) ? normalizedKnotReaction(message.reaction) : undefined;
}
/** Decoration revisions are independent of text/action modification timestamps. */
export function reconcileKnotReaction<T extends ReactionFields>(winner: T, other?: ReactionFields): T {
  const selected = confirmedKnotReaction(other) && Number(other?.reactionRevision) > (confirmedKnotReaction(winner) ? Number(winner.reactionRevision) : 0) ? other! : winner;
  const reaction = confirmedKnotReaction(selected);
  return { ...winner, reaction, reactionRevision: reaction ? selected.reactionRevision : undefined, reactionRecordedAt: reaction ? selected.reactionRecordedAt : undefined };
}
