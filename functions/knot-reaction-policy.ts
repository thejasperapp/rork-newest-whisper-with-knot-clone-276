/** Explicit opt-outs only. The active agent judges relevance and frequency;
 * there is no product cadence or emoji vocabulary gate. */
export function reactionPreference(text: string): 'off' | 'on' | undefined {
  const value = text.normalize('NFKC').toLowerCase().replace(/[’‘]/g, "'");
  const directives: { at: number; preference: 'off' | 'on' }[] = [];
  const negative = /\b(?:no|without|stop|avoid|skip)\s+(?:using\s+|sending\s+|the\s+)?(?:emojis?|reactions?)\b|\b(?:don't|do not|never)\s+(?:use|send|add|give|include|put)\s+(?:me\s+|any\s+)?(?:emojis?|reactions?)\b|\b(?:don't|do not|never|stop)\s+react(?:ing)?\b/g;
  for (const match of value.matchAll(negative)) {
    // A frequency correction is not a global opt-out; semantic judgment remains
    // with the active agent and may abstain on any message.
    const tail = value.slice(match.index! + match[0].length);
    const frequencyOnly = /^\s+(?:(?:on|in|for|to|with)\s+)?(?:every|each|all)\b|^\s+(?:so often|all the time|constantly)\b/.test(tail);
    directives.push({ at: match.index!, preference: frequencyOnly ? 'on' : 'off' });
  }
  const positive = /\b(?:restore|resume|enable)\s+(?:(?:selective|occasional|sparse)\s+)?(?:emojis?|reactions?)\b|\b(?:bring)\s+(?:back\s+(?:(?:selective|occasional)\s+)?(?:emojis?|reactions?)|(?:emojis?|reactions?)\s+back)\b|\b(?:turn|switch)\s+(?:emojis?|reactions?)\s+(?:back\s+)?on\b|\b(?:use|send|add)\s+(?:(?:selective|occasional|sparse)\s+(?:emojis?|reactions?)|(?:emojis?|reactions?)\s+(?:again|now|selectively|occasionally|sparingly|sometimes))\b|\b(?:you can|please|feel free to)\s+(?:use|send|add)\s+(?:emojis?|reactions?)\b|\breact\s+(?:again|selectively|occasionally|sparingly|sometimes)\b/g;
  for (const match of value.matchAll(positive)) {
    if (/\b(?:don't|do not|never|not)\s*$/.test(value.slice(0, match.index))) continue;
    directives.push({ at: match.index!, preference: 'on' });
  }
  // The last explicit instruction wins; a request for sparseness is never a
  // request for more placements. Semantic selection still independently abstains.
  return directives.sort((a, b) => b.at - a.at)[0]?.preference;
}
