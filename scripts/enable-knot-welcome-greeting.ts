// Enable only the maintained SDK's first-message override on the existing
// private Knot agent. No duplicate agent, audio, session or shared-workspace
// mutation. Every existing privacy/auth/no-tools constraint is revalidated.
import { validatedKnotVoiceVersion, validatedKnotVoiceWorkspace } from '../functions/knot-voice-policy';
const key = process.env.ELEVENLABS_API_KEY, id = process.env.ELEVENLABS_AGENT_ID, bridgeSecretID = process.env.ELEVENLABS_KNOT_BRIDGE_SECRET_ID;
if (!key || !id || !bridgeSecretID || !/^agent_[a-zA-Z0-9_-]{5,100}$/.test(id)) throw new Error('Existing private voice configuration is required.');
const headers = { 'xi-api-key': key, 'Content-Type': 'application/json' };
const base = 'https://api.elevenlabs.io/v1/convai';
const url = base + '/agents/' + encodeURIComponent(id);
type Agent = { platform_settings?: { overrides?: { conversation_config_override?: { agent?: Record<string, unknown> } } } };
async function read(url: string): Promise<unknown> {
  const response = await fetch(url, { headers, redirect: 'error', signal: AbortSignal.timeout(15000) });
  if (!response.ok) { await response.body?.cancel(); throw new Error(`Voice policy read failed (${response.status}).`); }
  return response.json();
}
const workspace = await read(base + '/settings');
if (!validatedKnotVoiceWorkspace(workspace)) throw new Error('Workspace privacy gate failed; no change made.');
const raw = await read(url + '?include_procedure_generated_workflow_elements=true');
if (!validatedKnotVoiceVersion(raw, id, undefined, bridgeSecretID)) throw new Error('Existing private-agent policy gate failed; no change made.');
const agent = raw as Agent, overrides = agent.platform_settings?.overrides;
if (!overrides) throw new Error('Missing agent override policy; no change made.');
if (overrides.conversation_config_override?.agent?.first_message !== true) {
  const changed = { ...overrides, conversation_config_override: { ...overrides.conversation_config_override,
    agent: { ...overrides.conversation_config_override?.agent, first_message: true } } };
  const response = await fetch(url, { method: 'PATCH', headers, redirect: 'error', signal: AbortSignal.timeout(15000),
    body: JSON.stringify({ platform_settings: { overrides: changed } }) });
  const status = response.status; await response.body?.cancel();
  if (status < 200 || status >= 300) throw new Error(`Welcome override update not confirmed (${status}); inspect before retrying.`);
}
const verified = await read(url + '?include_procedure_generated_workflow_elements=true');
if (!validatedKnotVoiceVersion(verified, id, undefined, bridgeSecretID) || (verified as Agent).platform_settings?.overrides?.conversation_config_override?.agent?.first_message !== true || !validatedKnotVoiceWorkspace(await read(base + '/settings'))) throw new Error('Updated voice policy not verified. Calling remains gated.');
console.log('Existing private agent verified with first-message override enabled; no session or audio started.');
export {};
