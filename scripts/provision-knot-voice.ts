// Run only after the server-only key is saved:
// rork env run -- bun scripts/provision-knot-voice.ts --create
// Does not start a conversation, synthesize speech or log credentials.
import { privateKnotVoiceAgent, validatedKnotVoiceVersion, validatedKnotVoiceWorkspace, knotVoiceIDs, validatedKnotVoiceRelayTool, knotVoiceEntryWorkflow, validatedKnotVoiceEntry } from '../functions/knot-voice-policy';
import { spawnSync } from 'node:child_process';

const key = process.env.ELEVENLABS_API_KEY, bridgeSecretID = process.env.ELEVENLABS_KNOT_BRIDGE_SECRET_ID;
if (!key || !bridgeSecretID) throw new Error('Configure the existing private voice key and shared Rork bridge first.');
const headers = { 'xi-api-key': key, 'Content-Type': 'application/json' };
const api = 'https://api.elevenlabs.io/v1/convai';
async function read(response: Response): Promise<Record<string, unknown>> {
  if (!response.ok) {
    // Only schema locations/types are safe to report; never log inputs,
    // provider messages, configuration bodies or credentials.
    const body = await response.json().catch(() => null) as { detail?: unknown } | null;
    if (Array.isArray(body?.detail)) {
      const issues = body.detail.slice(0, 20).map((item: { loc?: unknown; type?: unknown; msg?: unknown }) => ({
        path: Array.isArray(item?.loc) ? item.loc.filter(part => typeof part === 'number' || (typeof part === 'string' && /^[a-zA-Z0-9_]{1,100}$/.test(part))) : [],
        type: typeof item?.type === 'string' && /^[a-zA-Z0-9_.]{1,100}$/.test(item.type) ? item.type : 'validation_error',
        modelNames: typeof item?.msg === 'string' ? [...new Set(item.msg.match(/\b(?:gpt|gemini|claude)-[a-z0-9.-]{1,50}\b/g) ?? [])].slice(0, 30) : [],
      }));
      console.error(JSON.stringify({ schemaIssues: issues }));
    }
    throw new Error(`ElevenLabs configuration request failed (${response.status}); no provider body logged.`);
  }
  return await response.json() as Record<string, unknown>;
}
const workspace = await read(await fetch(api + '/settings', { headers, signal: AbortSignal.timeout(15000), redirect: 'error' }));
if (!validatedKnotVoiceWorkspace(workspace)) throw new Error('The ElevenLabs workspace forwards conversation data to webhooks. Use a dedicated workspace without these webhooks before enabling Knot. No shared settings were changed.');
const relay = process.argv.includes('--relay');
const envName = relay ? 'ELEVENLABS_RELAY_AGENT_ID' : 'ELEVENLABS_AGENT_ID';
let id = process.env[envName];
if (!id) {
  if (!process.argv.includes('--create')) throw new Error('No agent configured. Pass --create to provision a private no-tool agent.');
  // Verify both supplied voices are accessible without generating audio.
  for (const voice of Object.values(knotVoiceIDs)) {
    const response = await fetch(`https://api.elevenlabs.io/v1/voices/${voice}`, { headers, signal: AbortSignal.timeout(15000), redirect: 'error' });
    if (!response.ok) { await response.body?.cancel(); throw new Error('A requested voice is unavailable in this ElevenLabs account. Add its licensed voice in ElevenLabs, then retry.'); }
    await response.body?.cancel();
  }
  const created = await read(await fetch(api + '/agents/create', {
    method: 'POST', headers, body: JSON.stringify(privateKnotVoiceAgent(relay, bridgeSecretID)), signal: AbortSignal.timeout(20000), redirect: 'error',
  }));
  if (typeof created.agent_id !== 'string' || !/^agent_[a-zA-Z0-9_-]{5,100}$/.test(created.agent_id)) throw new Error('Agent creation returned no valid ID. Check the ElevenLabs dashboard before retrying.');
  id = created.agent_id;
  // Save the ID immediately, even if the stricter policy check fails, so a
  // rerun inspects this same agent rather than creating duplicate resources.
  const result = spawnSync('rork', ['env', 'set', envName, '--secret', '-e', 'all'], { input: id, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });
  if (result.status !== 0) throw new Error(`Created agent ${id}, but saving its ID failed. Save ELEVENLABS_AGENT_ID privately before retrying. No key logged.`);
}
if (!/^agent_[a-zA-Z0-9_-]{5,100}$/.test(id)) throw new Error('Invalid configured agent ID.');
const url = new URL(api + '/agents/' + encodeURIComponent(id));
url.searchParams.set('include_procedure_generated_workflow_elements', 'true');
let config = await read(await fetch(url, { headers, signal: AbortSignal.timeout(15000), redirect: 'error' }));
let relayToolID: string | undefined;
if (relay) {
  const prompt = (config.conversation_config as { agent?: { prompt?: { tool_ids?: unknown[] } } })?.agent?.prompt;
  if (!Array.isArray(prompt?.tool_ids) || prompt.tool_ids.length !== 1 || typeof prompt.tool_ids[0] !== 'string') throw new Error('Relay must have exactly one registered client tool. Agent ID retained; do not recreate.');
  relayToolID = prompt.tool_ids[0];
  const tool = await read(await fetch(api + '/tools/' + encodeURIComponent(relayToolID), { headers, signal: AbortSignal.timeout(15000), redirect: 'error' }));
  if (!validatedKnotVoiceRelayTool(tool)) throw new Error('Relay client tool did not pass its exact policy. Agent ID retained; do not recreate.');
}
if (!validatedKnotVoiceVersion(config, id, relayToolID, bridgeSecretID)) throw new Error('Agent does not meet Whisper’s no-tools, private-auth, recording-off and one-day retention policy. Calling remains disabled; inspect configuration without relaxing the gate.');
if (process.argv.includes('--repair-entry')) {
  // Only repair an already-policy-verified owned agent; retain its identity,
  // tools, privacy, auth, retention, model and permissions unchanged.
  if (!validatedKnotVoiceEntry(config.workflow)) {
    await read(await fetch(api + '/agents/' + encodeURIComponent(id), {
      method: 'PATCH', headers,
      body: JSON.stringify({ workflow: knotVoiceEntryWorkflow, conversation_config: { agent: { first_message: 'Hi, I’m Knot. What would you like to work on?' } } }),
      signal: AbortSignal.timeout(20000), redirect: 'error',
    }));
    config = await read(await fetch(url, { headers, signal: AbortSignal.timeout(15000), redirect: 'error' }));
  }
  if (!validatedKnotVoiceEntry(config.workflow) || !validatedKnotVoiceVersion(config, id, relayToolID, bridgeSecretID)) throw new Error('Entry repair did not pass strict read-back policy. No call was started.');
  console.log('Explicit inherited voice entry route verified. No new tools, permissions, call or audio started.');
}
console.log(relay ? 'Private native chat relay configured and policy verified. Legacy voice agent unchanged. No call or audio started.' : 'Private Knot agent configured and policy verified. No conversation or audio generation was started.');
