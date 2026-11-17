// Deliberate configuration alignment only. No conversation, token, audio or model probe.
// rork env run -- bun scripts/align-knot-voice-provider.ts
import { spawnSync } from 'node:child_process';
import { knotVoiceCustomLLM, validatedKnotVoiceVersion, validatedKnotVoiceWorkspace, validatedKnotVoiceRelayTool } from '../functions/knot-voice-policy';
import { knotVoiceProviderSecret } from '../functions/knot-voice-bridge';

const key = process.env.ELEVENLABS_API_KEY;
let signing = process.env.KNOT_VOICE_BRIDGE_SIGNING_KEY;
if (!key) throw new Error('The existing private voice configuration is required.');
// Managed gateway and Supabase credentials are runtime-injected, not exported
// by env run. Verify managed status without copying/reading either credential.
const managed = spawnSync('rork', ['ai', 'keys', 'get', '--json'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
if (managed.status !== 0 || JSON.parse(managed.stdout).enabled !== true) throw new Error('Managed Rork AI Cloud must be enabled.');
const api = 'https://api.elevenlabs.io/v1/convai';
const headers = { 'xi-api-key': key, 'Content-Type': 'application/json' };
const object = (v: unknown): Record<string, unknown> => v && typeof v === 'object' && !Array.isArray(v) ? v as Record<string, unknown> : {};
async function call(path: string, method = 'GET', body?: unknown): Promise<Record<string, unknown>> {
  const response = await fetch(api + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body), redirect: 'error', signal: AbortSignal.timeout(20000) });
  if (!response.ok) { await response.body?.cancel(); throw new Error(`Voice configuration ${method} failed (${response.status}); no body logged. Inspect state before any retry.`); }
  return object(await response.json());
}
if (!validatedKnotVoiceWorkspace(await call('/settings'))) throw new Error('Workspace forwarding policy failed; no settings changed.');
let secretID = process.env.ELEVENLABS_KNOT_BRIDGE_SECRET_ID;
const agents: { id: string; toolID?: string; config: Record<string, unknown> }[] = [];
for (const field of ['ELEVENLABS_AGENT_ID', 'ELEVENLABS_RELAY_AGENT_ID']) {
  const id = process.env[field];
  if (!id || !/^agent_[a-zA-Z0-9_-]{5,100}$/.test(id)) throw new Error('Both existing owned voice agents are required; never recreate.');
  const config = await call('/agents/' + id + '?include_procedure_generated_workflow_elements=true');
  let toolID: string | undefined;
  if (field === 'ELEVENLABS_RELAY_AGENT_ID') {
    const ids = object(object(object(config.conversation_config).agent).prompt).tool_ids;
    if (!Array.isArray(ids) || ids.length !== 1 || typeof ids[0] !== 'string') throw new Error('Relay tool policy failed.');
    toolID = ids[0];
    if (!validatedKnotVoiceRelayTool(await call('/tools/' + encodeURIComponent(toolID)))) throw new Error('Relay tool policy failed.');
  }
  if (!validatedKnotVoiceVersion(config, id, toolID) && !(secretID && validatedKnotVoiceVersion(config, id, toolID, secretID))) throw new Error('Existing privacy/auth/tools/workflow policy failed; no migration allowed.');
  agents.push({ id, toolID, config });
}
if (secretID && !signing) throw new Error('Existing bridge reference has no signing key. Inspect state; do not replace it.');
if (!secretID) {
  const name = 'Whisper Knot Rork bridge uf26aun6d49w1tsjsm2u9 v2';
  const existing = await call('/secrets?search=' + encodeURIComponent(name) + '&page_size=100');
  if (!Array.isArray(existing.secrets) || existing.secrets.length !== 0 || existing.next_cursor != null) throw new Error('A prior bridge secret may already exist. Inspect and save its ID privately; do not recreate or adopt it automatically.');
  if (!signing) {
    signing = Array.from(crypto.getRandomValues(new Uint8Array(32)), value => value.toString(16).padStart(2, '0')).join('');
    const savedSigning = spawnSync('rork', ['env', 'set', 'KNOT_VOICE_BRIDGE_SIGNING_KEY', '--secret', '-e', 'all'], { input: signing, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });
    if (savedSigning.status !== 0) throw new Error('Private bridge signing save failed. Inspect state before retry.');
  }
  const created = await call('/secrets', 'POST', { type: 'new', name, value: await knotVoiceProviderSecret(signing) });
  if (typeof created.secret_id !== 'string' || !/^[a-zA-Z0-9_-]{8,120}$/.test(created.secret_id)) throw new Error('Secret creation uncertain; inspect state before retry.');
  secretID = created.secret_id;
  const saved = spawnSync('rork', ['env', 'set', 'ELEVENLABS_KNOT_BRIDGE_SECRET_ID', '--secret', '-e', 'all'], { input: secretID, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });
  if (saved.status !== 0) throw new Error('Bridge reference save failed. Inspect the uniquely named workspace secret and save its ID privately; never recreate.');
}
for (const agent of agents) {
  if (!validatedKnotVoiceVersion(agent.config, agent.id, agent.toolID, secretID)) {
    // Preserve identity, voices, tools, workflow, callbacks, consent and privacy.
    await call('/agents/' + agent.id, 'PATCH', { conversation_config: { agent: { prompt: {
      llm: 'custom-llm', custom_llm: knotVoiceCustomLLM(secretID), backup_llm_config: { preference: 'disabled' },
      ignore_default_personality: true, enable_reasoning_summary: false, enable_parallel_tool_calls: false,
    } } } });
  }
  const readback = await call('/agents/' + agent.id + '?include_procedure_generated_workflow_elements=true');
  if (!validatedKnotVoiceVersion(readback, agent.id, agent.toolID, secretID)) throw new Error('Provider alignment failed strict readback; calls stay disabled. Inspect state before retry.');
}
console.log(JSON.stringify({ agentsAligned: agents.length, privateAuthVerified: true, recordingOff: true, retentionDays: 1, fallbackDisabled: true, answeringProvider: 'rork', modelSource: 'shared_knot_transport', callsStarted: 0, tokensMinted: 0, audioGenerated: false }));
