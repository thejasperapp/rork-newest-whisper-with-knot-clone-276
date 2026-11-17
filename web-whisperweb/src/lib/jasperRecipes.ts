/**
 * Saved Sidekick prompts ("recipes"). Each runs through the same consented,
 * cited `/ask` route; nothing here bypasses scope approval or evidence rules.
 */
export type JasperRecipe = {
  id: string;
  title: string;
  hint: string;
  question: string;
  /** Meeting recipes need a current meeting; library recipes run across the chosen scope. */
  scope: 'meeting' | 'library';
  /** Runs the bounded transcript scan instead of an ordinary question. */
  scan?: boolean;
};

export const JASPER_RECIPES: JasperRecipe[] = [
  { id: 'catch-up', title: 'What did I miss?', hint: 'Catch up on the conversation so far', question: 'Catch me up on this meeting so far. What matters now? Distinguish decisions from proposals.', scope: 'meeting' },
  { id: 'decisions', title: 'Decisions so far', hint: 'What was decided vs. still open', question: 'Which decisions were actually made so far, and which questions remain open?', scope: 'meeting' },
  { id: 'sound-smart', title: 'Make me sound smart', hint: 'Two thoughtful contributions', question: 'Suggest two concise, thoughtful contributions I could make right now, grounded in what has been discussed. Distinguish supported facts from suggestions.', scope: 'meeting' },
  { id: 'suggest-questions', title: 'Suggest questions', hint: 'Follow-ups worth asking', question: 'Suggest three useful follow-up questions I could ask, grounded in unresolved points so far. Label them as questions, not meeting facts.', scope: 'meeting' },
  { id: 'explain', title: 'Explain the jargon', hint: 'Terms and concepts, briefly', question: 'Briefly explain any technical terms, acronyms or concepts mentioned in this meeting that someone might not know. Keep meeting facts cited and general explanations labeled.', scope: 'meeting' },
  { id: 'next-steps', title: 'Recap next steps', hint: 'Draft follow-ups for review', question: 'Recap the next steps discussed so far as drafts for review. Do not invent an owner or a due date.', scope: 'meeting' },
  { id: 'follow-up-email', title: 'Draft follow-up email', hint: 'Short, cited, ready to review', question: 'Draft a short follow-up email summarizing the decisions and next steps from this meeting for my review. Cite the discussion and do not invent owners, dates or commitments.', scope: 'meeting' },
  { id: 'organize', title: 'Organize transcript', hint: 'Highlights, decisions, key numbers', question: 'Organize this meeting’s transcript and highlight the decisions, key numbers and follow-ups using my focus preferences.', scope: 'meeting', scan: true },
  { id: 'recent', title: 'Summarize my recent meetings', hint: 'Decisions, open questions, follow-ups', question: 'Summarize my recent meetings: the main decisions, open questions and follow-ups, with dates.', scope: 'library' },
  { id: 'open-loops', title: 'Find my open follow-ups', hint: 'Commitments without a close', question: 'Which follow-ups and commitments from my meetings still look open? Cite where each came from and do not assume anything was completed.', scope: 'library' },
  { id: 'changed', title: "What's changed?", hint: 'Compare across meetings over time', question: 'What changed or conflicts across these meetings over time? Use source dates and do not invent consensus.', scope: 'library' },
];

export function jasperRecipesFor(meeting: boolean): JasperRecipe[] {
  return JASPER_RECIPES.filter((recipe) => recipe.scope === (meeting ? 'meeting' : 'library'));
}

/** Matches the text typed after a leading slash against titles and hints. */
export function filterJasperRecipes(recipes: JasperRecipe[], query: string): JasperRecipe[] {
  const needle = query.trim().toLowerCase();
  if (!needle) return recipes;
  return recipes.filter((recipe) => `${recipe.title} ${recipe.hint}`.toLowerCase().includes(needle));
}
