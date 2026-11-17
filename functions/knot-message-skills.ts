// Tone guidance only. Full reaction judgment is cached from the session-start
// live read; the separately authorized acknowledgment default covers absence.
export const knotCommunicationSkills = `COMMUNICATION: Match the member's language, formality and requested style. Use short natural chat, not a status dashboard. Emoji in readable text is optional and sparse. Respect requests for no emoji or reactions. These instructions do not grant access. Reactions exist only through the actual react tool and its server receipt, never final metadata. The full communication skill is read once at owned-session startup and cached for that session. Missing guidance uses the supplied default acknowledgment contract, never a fresh-read placement gate. If the actual placement capability is unavailable, do not claim a reaction or substitute acknowledgment prose.`;

/** Validate transport shape only. Preserve every original Unicode scalar. */
export function normalizedKnotReaction(raw: unknown): string | undefined {
  if (typeof raw !== 'string' || !raw || raw.length > 128) return undefined;
  if ([...new Intl.Segmenter('und', { granularity: 'grapheme' }).segment(raw)].length !== 1) return undefined;
  const keycap = /^[0-9#*]\uFE0F?\u20E3$/u.test(raw);
  const flag = /^\p{Regional_Indicator}{2}$/u.test(raw);
  const pictograph = /\p{Extended_Pictographic}/u.test(raw) && /^[\p{Extended_Pictographic}\p{Emoji_Modifier}\uFE0F\u200D\u{E0020}-\u{E007F}]+$/u.test(raw);
  return keycap || flag || pictograph ? raw : undefined;
}
