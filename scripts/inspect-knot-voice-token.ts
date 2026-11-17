// Connection-credential diagnostic only. This issues one ephemeral provider
// token after strict policy checks, but never joins a room, captures audio,
// starts a live SDK call or prints tokens, IDs, prompts or provider bodies.
import { validatedKnotVoiceVersion, validatedKnotVoiceWorkspace } from '../functions/knot-voice-policy';
const key = process.env.ELEVENLABS_API_KEY, id = process.env.ELEVENLABS_AGENT_ID, bridgeSecretID = process.env.ELEVENLABS_KNOT_BRIDGE_SECRET_ID;
if (!key || !id || !bridgeSecretID) throw new Error('Private voice configuration is missing.');
const headers = { 'xi-api-key': key };
const [agentResponse, workspaceResponse] = await Promise.all([
  fetch(`https://api.elevenlabs.io/v1/convai/agents/${encodeURIComponent(id)}?include_procedure_generated_workflow_elements=true`, { headers, signal: AbortSignal.timeout(15000), redirect: 'error' }),
  fetch('https://api.elevenlabs.io/v1/convai/settings', { headers, signal: AbortSignal.timeout(15000), redirect: 'error' }),
]);
if (!agentResponse.ok || !workspaceResponse.ok) throw new Error('Policy read failed.');
const [agent, workspace] = await Promise.all([agentResponse.json(), workspaceResponse.json()]);
const version = validatedKnotVoiceVersion(agent, id, undefined, bridgeSecretID);
if (!version || !validatedKnotVoiceWorkspace(workspace)) throw new Error('Strict voice policy check failed.');
const url = new URL('https://api.elevenlabs.io/v1/convai/conversation/token');
url.searchParams.set('agent_id', id); url.searchParams.set('version_id', version);
const response = await fetch(url, { headers, signal: AbortSignal.timeout(20000), redirect: 'error' });
const body = await response.json().catch(() => null) as { token?: unknown; detail?: { status?: unknown; message?: unknown } } | null;
let requiredPermission: string | undefined;
if (typeof body?.detail?.message === 'string') {
  const permission = body.detail.message.match(/\bpermission\s+([a-z_]+)\b/)?.[1];
  if (permission && /^[a-z_]{1,70}$/.test(permission)) requiredPermission = permission;
}
console.log(JSON.stringify({ check: 'private_version_token', http: response.status, validTokenShape: response.ok && typeof body?.token === 'string' && body.token.length >= 20 && body.token.length <= 20000, ...(typeof body?.detail?.status === 'string' && /^[a-z_]{1,70}$/.test(body.detail.status) ? { providerCode: body.detail.status } : {}), ...(requiredPermission ? { requiredPermission } : {}) }));
export {};
