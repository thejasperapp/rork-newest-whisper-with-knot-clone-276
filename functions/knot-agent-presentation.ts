/** Display metadata authored by the SAME agent that selects the operation.
 * Never derives copy from tool names, rewrites wording, or grants execution. */
export type KnotAgentActivity = { label: string; purpose: string };
export const knotAgentActivitySchema = {
  type: 'object', properties: {
    label: { type: 'string', minLength: 1, maxLength: 60, description: 'Fresh verb-and-object label specific to this request and the actual selected operation; no generic status or private reasoning.' },
    purpose: { type: 'string', minLength: 1, maxLength: 300, description: 'Brief intended work, not a success claim. Header and Events only, never chat narration.' },
  }, required: ['label', 'purpose'], additionalProperties: false,
};
export const knotAgentPresentationInstruction = 'For each selected work operation author _activity={label,purpose} in the SAME decision. The react tool is not a work operation and accepts only message_id and emoji, with no _activity. Use the user’s language and the concrete subject of THIS request. No canned vocabulary, generic working/processing labels, raw commands, credentials, code or private reasoning. Describe intended work, never pretend it succeeded. These exact strings go only to the activity header and Events. Do not narrate labels or reactions in chat. Tool receipts, not labels, establish outcomes.';
export function validatedKnotAgentActivity(value: unknown): KnotAgentActivity | undefined {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return;
  const v = value as Record<string, unknown>;
  if (Object.keys(v).some(key => !['label', 'purpose'].includes(key))) return;
  const valid = (text: unknown, max: number): text is string => typeof text === 'string' && text.trim().length > 0 && text.length <= max && !/[\x00-\x1f<>`]/.test(text);
  return valid(v.label, 60) && valid(v.purpose, 300) ? { label: v.label, purpose: v.purpose } : undefined;
}
export function knotToolsWithAgentActivity<T extends { function: { parameters: unknown } }>(tools: T[]): T[] {
  return tools.map(tool => {
    const schema = tool.function.parameters as Record<string, unknown>;
    return { ...tool, function: { ...tool.function, parameters: { ...schema,
      properties: { ...(schema.properties as Record<string, unknown>), _activity: knotAgentActivitySchema },
      required: [...(Array.isArray(schema.required) ? schema.required : []), '_activity'],
    } } };
  });
}
