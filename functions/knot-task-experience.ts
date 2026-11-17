export const knotTaskModelConsent = 'knot_task_models_v1';
export const knotTaskModels = ['openai/gpt-4o', 'anthropic/claude-haiku-4.5', 'anthropic/claude-sonnet-4.6'] as const;
export type KnotTaskModel = typeof knotTaskModels[number];
/** No arbitrary model override and no cross-provider retry. Older consent stays OpenAI-only. */
export function knotTaskModel(expandedConsent: boolean, task: 'routing' | 'reaction' | 'answer' | 'creation' | 'browser'): KnotTaskModel {
  if (!expandedConsent || task === 'routing') return 'openai/gpt-4o';
  return task === 'creation' || task === 'browser' ? 'anthropic/claude-sonnet-4.6' : 'anthropic/claude-haiku-4.5';
}
/** One prospective plan for original substantial creation, not a progress claim. */
export function knotCreationBriefing(input: { mode: string; workspace: boolean; document: boolean; format?: string }): string | undefined {
  if (input.mode !== 'Create') return undefined;
  if (input.document) return input.format === 'pdf'
    ? 'I’ll create the PDF, then check its content and pages before sharing it.'
    : 'I’ll create the requested file and check it against your request before sharing it.';
  return input.workspace ? 'I’ll build the requested result, then check what actually runs before reporting back.' : undefined;
}
