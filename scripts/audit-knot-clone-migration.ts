// Read-only metadata/configuration audit for this clone, never member records.
// rork env run -p mayokn2749ag072e3uvbh -- bun scripts/audit-knot-clone-migration.ts
// Public env values are captured privately and reduced to allowlisted categories.
import { spawnSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { knotBackendIdentity, knotBackendOrigin } from '../functions/knot-backend';
import { knotVoiceBridgeURL } from '../functions/knot-voice-bridge';
import { validatedKnotVoiceVersion, validatedKnotVoiceRelayTool, validatedKnotVoiceWorkspace } from '../functions/knot-voice-policy';

type Obj = Record<string, unknown>;
const object = (value: unknown): Obj => value !== null && typeof value === 'object' && !Array.isArray(value) ? value as Obj : {};
const safeLabel = (value: unknown) => typeof value === 'string' && /^[A-Za-z0-9_.:-]{1,100}$/.test(value) ? value : null;
const rows: unknown[] = [];
const command = spawnSync('rork', ['env', 'ls', '--json', '-p', knotBackendIdentity], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
if (command.status !== 0) throw new Error('Environment metadata unavailable; raw output withheld.');
let parsed: unknown;
try { parsed = JSON.parse(command.stdout); } catch { throw new Error('Environment metadata format unavailable; raw output withheld.'); }
const root = object(parsed);
const entries = Array.isArray(parsed) ? parsed : [root.envs, root.variables, root.items, root.environments].find(Array.isArray);
if (!entries) {
  console.log(JSON.stringify({ metadataStructureOnly: Object.keys(root).filter(k => /^[a-zA-Z_]{1,50}$/.test(k)) }));
  throw new Error('Unknown environment metadata structure; no values printed.');
}
const classifyURL = (value: unknown) => {
  if (typeof value !== 'string') return 'value_not_exposed';
  try {
    const url = new URL(value);
    if (url.origin === knotBackendOrigin) return 'current_clone_backend';
    if (url.origin === 'https://uryyyegnbtlmyhqlgndy.supabase.co') return 'preserved_supabase';
    if (url.origin === 'https://toolkit.rork.com') return 'managed_rork_gateway';
    if (url.origin === 'https://uf26aun6d49w1tsjsm2u9-backend.rork.app') return 'previous_clone_backend';
    if (url.origin === 'https://jasper-backend-staging.yourfriend.workers.dev') return 'parked_staging';
    return 'other_origin_redacted';
  } catch { return 'not_a_url_or_redacted'; }
};
for (const raw of entries) {
  const item = object(raw), name = item.name ?? item.key;
  if (typeof name !== 'string' || !/^[A-Z][A-Z0-9_]{1,100}$/.test(name)) continue;
  rows.push({ name, scope: safeLabel(item.environment ?? item.scope), version: typeof item.version === 'number' ? item.version : null,
    ...(name.endsWith('_URL') || name.endsWith('_ORIGIN') ? { originCategory: classifyURL(item.value) } : {}) });
}
async function read(url: string, headers: Record<string, string> = {}): Promise<{ status: number; value: Obj }> {
  const response = await fetch(url, { method: 'GET', headers, redirect: 'error', signal: AbortSignal.timeout(15000) });
  if (!response.ok) { await response.body?.cancel(); return { status: response.status, value: {} }; }
  const text = await response.text();
  if (text.length > 500000) throw new Error('Configuration response exceeds audit bound.');
  return { status: response.status, value: object(JSON.parse(text)) };
}
const health: unknown[] = [];
for (const [label, origin] of [
  ['backend', knotBackendOrigin],
  ['hosted_web_proxy', 'https://newest-whisper-with-knot-clone-t6ui3ur.rork.app/~api'],
] as const) {
  const response = await fetch(origin + '/ping', { method: 'GET', redirect: 'error', signal: AbortSignal.timeout(15000) });
  const text = await response.text(); let value: Obj = {};
  if (text.length < 20000) { try { value = object(JSON.parse(text)); } catch { /* SPA fallback is not API health. */ } }
  health.push({ label, status: response.status, ok: value.ok === true, sourceBuild: response.headers.get('X-Knot-Worker-Build') });
}
const bridge = await read('https://uryyyegnbtlmyhqlgndy.supabase.co/functions/v1/whisper-knot-contact/health');
health.push({ label: 'shared_notification_bridge', status: bridge.status, ready: bridge.value.ready === true,
  supportsCurrentClone: Array.isArray(bridge.value.backends) && bridge.value.backends.includes(knotBackendIdentity),
  supportsPreviousClone: Array.isArray(bridge.value.backends) && bridge.value.backends.includes('uf26aun6d49w1tsjsm2u9'),
  supportsOriginal: Array.isArray(bridge.value.backends) && bridge.value.backends.includes('spotxaa2tx3bjiagxo5lh') });
const operator = process.env.BROADCAST_SECRET;
let policy: unknown = { available: false };
if (operator) {
  const result = await read(knotBackendOrigin + '/admin/knot-text-policy', { 'X-Whisper-Operator': operator });
  policy = { status: result.status, rorkOnly: result.value.routingPolicy === 'rork_cloud_only_v1' && result.value.provider === 'rork',
    managedCredentialPresent: result.value.tokenPresent === true && result.value.credentialSource === 'managed',
    gatewayValid: result.value.gatewayValid === true, addressOverridePresent: result.value.addressOverridePresent === true,
    signingKeyPresent: result.value.signingKeyPresent === true, admissionPresent: result.value.admissionPresent === true };
}
const voice: unknown[] = [];
const apiKey = process.env.ELEVENLABS_API_KEY, secretID = process.env.ELEVENLABS_KNOT_BRIDGE_SECRET_ID;
if (apiKey) {
  const headers = { 'xi-api-key': apiKey }, api = 'https://api.elevenlabs.io/v1/convai';
  const workspace = await read(api + '/settings', headers);
  voice.push({ role: 'workspace', status: workspace.status, forwardingPolicyValid: validatedKnotVoiceWorkspace(workspace.value) });
  for (const [role, name] of [['voice', 'ELEVENLABS_AGENT_ID'], ['relay', 'ELEVENLABS_RELAY_AGENT_ID']] as const) {
    const id = process.env[name];
    if (!id || !/^agent_[A-Za-z0-9_-]{5,100}$/.test(id)) { voice.push({ role, configured: false }); continue; }
    const config = await read(api + '/agents/' + encodeURIComponent(id) + '?include_procedure_generated_workflow_elements=true', headers);
    const prompt = object(object(object(config.value.conversation_config).agent).prompt);
    const ids = prompt.tool_ids;
    const toolID = role === 'relay' && Array.isArray(ids) && ids.length === 1 && typeof ids[0] === 'string' && /^[A-Za-z0-9_-]{8,120}$/.test(ids[0]) ? ids[0] : undefined;
    const tool = toolID ? await read(api + '/tools/' + encodeURIComponent(toolID), headers) : undefined;
    voice.push({ role, configured: true, status: config.status,
      callbackCategory: classifyURL(object(prompt.custom_llm).url),
      currentCallbackMatches: object(prompt.custom_llm).url === knotVoiceBridgeURL,
      strictCurrentPolicyValid: !!secretID && !!validatedKnotVoiceVersion(config.value, id, toolID, secretID),
      relayToolValid: role !== 'relay' || !!tool && validatedKnotVoiceRelayTool(tool.value),
      sharedAgentOwnershipNotInferred: true });
  }
}
const audit = { title: 'Clone migration — read-only configuration audit', audit: 'clone_migration_configuration', observedAt: new Date().toISOString(), project: knotBackendIdentity,
  environment: rows, health, textPolicy: policy, voice,
  memberDataRead: false, callsStarted: 0, generations: 0, configurationWrites: 0,
  runtimeCredentialIdentityVerified: false, cloudAuthenticationAcceptanceVerified: false,
  historicalDurableStateMigrated: false, deviceOrBrowserInteractionTested: false };
const serialized = JSON.stringify(audit, null, 2) + '\n';
if (process.argv.includes('--record')) {
  // Only sanitized metadata is durable. Never overwrite an earlier observation.
  writeFileSync(new URL('../deliveries/clone-migration-20261114-configuration.json', import.meta.url), serialized, { flag: 'wx' });
}
console.log(serialized);
