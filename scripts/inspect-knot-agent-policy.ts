// Read-only policy diagnostics. Only booleans, collection shapes and a small
// allowlist of configuration enums are printed. No tokens, IDs or prompts.
import { validatedKnotVoiceVersion } from '../functions/knot-voice-policy';
const key = process.env.ELEVENLABS_API_KEY, id = process.env[process.argv.includes('--relay') ? 'ELEVENLABS_RELAY_AGENT_ID' : 'ELEVENLABS_AGENT_ID'];
if (!key || !id) throw new Error('Private voice configuration is incomplete.');
const response = await fetch(`https://api.elevenlabs.io/v1/convai/agents/${encodeURIComponent(id)}?include_procedure_generated_workflow_elements=true`, { headers: { 'xi-api-key': key }, signal: AbortSignal.timeout(15000), redirect: 'error' });
if (!response.ok) { await response.body?.cancel(); throw new Error(`Configuration read failed (${response.status}).`); }
const raw = await response.json() as Record<string, any>;
const allowed = new Set(['gpt-4o', 'gpt-6.1-terra', 'disabled', 'default', 'none', 'start', 'override_agent', 'auto', 'unconditional', 'start_node', 'conversation_node', 'start_to_conversation', 'Knot']);
function shape(value: unknown, path = ''): unknown {
  if (value === undefined) return 'absent';
  if (value === null || typeof value === 'boolean' || typeof value === 'number') return value;
  if (typeof value === 'string') return allowed.has(value) ? value : { stringLength: value.length };
  if (Array.isArray(value)) return { arrayLength: value.length };
  if (typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([key, child]) => [key, shape(child, path + '.' + key)]));
  return typeof value;
}
console.log(JSON.stringify({ valid: Boolean(process.env.ELEVENLABS_KNOT_BRIDGE_SECRET_ID && validatedKnotVoiceVersion(raw, id, process.argv.includes('--relay') && Array.isArray(raw.conversation_config?.agent?.prompt?.tool_ids) && raw.conversation_config.agent.prompt.tool_ids.length === 1 ? raw.conversation_config.agent.prompt.tool_ids[0] : undefined, process.env.ELEVENLABS_KNOT_BRIDGE_SECRET_ID)), agentIDMatches: raw.agent_id === id, versionPresent: typeof raw.version_id === 'string', versionFormatValid: typeof raw.version_id === 'string' && /^[a-zA-Z0-9_-]{8,120}$/.test(raw.version_id) }));
for (const [name, value] of Object.entries({ prompt: raw.conversation_config?.agent?.prompt, auth: raw.platform_settings?.auth, privacy: raw.platform_settings?.privacy, workflow: raw.workflow, procedures: raw.procedures, languagePresets: raw.conversation_config?.language_presets, conversation: raw.conversation_config?.conversation, settings: Object.fromEntries(Object.entries(raw.platform_settings ?? {}).filter(([key]) => ['analysis_llm', 'evaluation', 'data_collection', 'data_collection_scopes', 'auto_translate_transcript_to_app_language', 'workspace_overrides', 'alerting', 'analysis_items', 'overrides'].includes(key))) })) console.log(JSON.stringify({ section: name, shape: shape(value) }));
export {};
