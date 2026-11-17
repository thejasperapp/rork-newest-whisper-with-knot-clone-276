import type { KnotShellEnv } from './knot-shell';

export type SidecarTool = { name: string; method: string; path: string; purpose: string; request: Record<string, string> | null; returns: string };
export type SidecarCapabilities = {
  ok: true; service: 'knot-sidecar'; server_time: string; principal: 'whisper';
  tools: SidecarTool[]; skills: { location: string; index: string; access: string };
  memory: { file: string; location: string; access: string }; limits: Record<string, unknown>;
};
export const sidecarOrigin = 'https://knot-shell.mydailywhisper.com';
export async function readSidecarBytes(response: Pick<Response, 'body'>, limit: number): Promise<Uint8Array> {
  if (!response.body) throw new Error('empty_provider_response');
  const reader = response.body.getReader(); const chunks: Uint8Array[] = []; let size = 0;
  try {
    for (;;) {
      const part = await reader.read(); if (part.done) break;
      size += part.value.byteLength; if (size > limit) throw new Error('provider_response_limit');
      chunks.push(part.value);
    }
    const data = new Uint8Array(size); let at = 0;
    for (const chunk of chunks) { data.set(chunk, at); at += chunk.byteLength; }
    return data;
  } finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
}
export async function readSidecarText(response: Pick<Response, 'body'>, limit: number): Promise<string> {
  return new TextDecoder('utf-8', { fatal: true, ignoreBOM: false }).decode(await readSidecarBytes(response, limit));
}
export class SidecarHTTPError extends Error {
  constructor(readonly status: number, readonly unknownSession = false) { super('provider_unavailable'); }
}
/** Only a bounded, exact upstream rejection authorizes pre-input recovery. */
export function isUnknownSessionResponse(status: number, text: string): boolean {
  if (status !== 404) return false;
  let value: unknown = text.trim();
  try { value = JSON.parse(text); } catch { /* Plain-text response is supported too. */ }
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    const item = value as Record<string, unknown>;
    value = item.error ?? item.detail ?? item.message;
  }
  return typeof value === 'string' && value.trim().toLowerCase() === 'unknown session';
}
export async function sidecarRequest(env: KnotShellEnv, path: string, method = 'GET', body?: unknown, timeoutMs = 10000, signal?: AbortSignal): Promise<Response> {
  if (!env.SIDECAR_TOKEN_WHISPER) throw new Error('shell_unavailable');
  const response = await fetch(sidecarOrigin + path, { method, redirect: 'manual', headers: {
    Authorization: 'Bearer ' + env.SIDECAR_TOKEN_WHISPER, 'Content-Type': 'application/json',
  }, body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.any([AbortSignal.timeout(timeoutMs), ...(signal ? [signal] : [])]) });
  if (!response.ok) {
    // Allowlisted route class only: never log paths, owned IDs, tokens,
    // query values, request bodies or provider response bodies.
    const operation = path === '/capabilities' ? 'capabilities' : path === '/sessions' ? 'session_open'
      : /^\/sessions\/[^/?]+\/input$/.test(path) ? 'session_input'
      : /^\/sessions\/[^/?]+\/log\?offset=\d+$/.test(path) ? 'session_log'
      : /^\/sessions\/[^/?]+$/.test(path) ? (method === 'DELETE' ? 'session_close' : 'session_status')
      : /^\/browser\/(?:start|navigate|input)$/.test(path) ? 'browser_' + path.split('/').pop()
      : /^\/browser\/(?:state|content|screenshot)\?/.test(path) ? 'browser_' + path.split('/').pop()!.split('?')[0]
      : /^\/browser\/tabs\/activate$/.test(path) ? 'browser_tab_activate'
      : /^\/browser\/tabs(?:\?|$)/.test(path) ? (method === 'GET' ? 'browser_tabs' : method === 'DELETE' ? 'browser_tab_close' : 'browser_tab_open')
      : /^\/browser\/(?:back|forward|find|wait|download|upload)$/.test(path) ? 'browser_' + path.split('/').pop()
      : path.startsWith('/browser?') ? 'browser_stop' : path.startsWith('/files?') ? 'file_read' : 'other';
    console.warn('knot_sidecar_http', JSON.stringify({ operation, method, status: response.status }));
    let unknownSession = false;
    if (response.status === 404 && operation.startsWith('session_')) {
      try { unknownSession = isUnknownSessionResponse(response.status, await readSidecarText(response, 8192)); }
      catch { /* Oversized/unreadable errors never authorize recovery. */ }
    } else { await response.body?.cancel(); }
    throw new SidecarHTTPError(response.status, unknownSession);
  }
  return response;
}
type DiscoverySnapshot = { fingerprint: string; sessionID?: string; capabilities: SidecarCapabilities };
const discoverySnapshots = new Map<string, { expires: number; value: SidecarCapabilities }>();
const discoveryFlights = new Map<string, Promise<SidecarCapabilities>>();
const discoveryStorageKey = 'knot-capabilities-session-v1';
const discoveryLimit = 64;
let activeDiscoveryRequests = 0;
const actorDiscoveryFlights = new WeakMap<DurableObjectState, Map<string, Promise<SidecarCapabilities>>>();
async function discoveryFingerprint(env: KnotShellEnv): Promise<string> {
  if (!env.SIDECAR_TOKEN_WHISPER) throw new Error('shell_unavailable');
  const bytes = new TextEncoder().encode(sidecarOrigin + '\nwhisper\n' + env.SIDECAR_TOKEN_WHISPER);
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map(b => b.toString(16).padStart(2, '0')).join('');
}
function immutableCapabilities(value: SidecarCapabilities): SidecarCapabilities {
  // Callers retain this turn's definitions even if another caller explicitly refreshes.
  const freeze = (object: unknown): void => {
    if (object && typeof object === 'object') { Object.values(object).forEach(freeze); Object.freeze(object); }
  };
  freeze(value); return value;
}
/** A session schema is not evidence of current connectivity. Fresh explicitly
 * verifies THIS call; an actual failed verification never falls back to cache.
 * Actor storage survives eviction and is isolated by the credential fingerprint. */
export async function discoverKnotShell(env: KnotShellEnv, options: { fresh?: boolean; state?: DurableObjectState; sessionID?: string } = {}): Promise<SidecarCapabilities> {
  if (!options.state || options.fresh) return discoverSessionSchema(env, options);
  let flights = actorDiscoveryFlights.get(options.state);
  if (!flights) { flights = new Map(); actorDiscoveryFlights.set(options.state, flights); }
  const key = options.sessionID ?? 'current';
  const existing = flights.get(key);
  if (existing) return existing;
  const flight = discoverSessionSchema(env, options);
  flights.set(key, flight);
  try { return await flight; }
  finally { if (flights.get(key) === flight) flights.delete(key); }
}
async function discoverSessionSchema(env: KnotShellEnv, options: { fresh?: boolean; state?: DurableObjectState; sessionID?: string }): Promise<SidecarCapabilities> {
  const fingerprint = await discoveryFingerprint(env);
  const saved = options.state ? await options.state.storage.get<DiscoverySnapshot>(discoveryStorageKey) : undefined;
  const sessionChanged = !!options.sessionID && !!saved?.sessionID && options.sessionID !== saved.sessionID;
  const fresh = options.fresh || sessionChanged;
  const persist = async (capabilities: SidecarCapabilities) => {
    if (options.state) await options.state.storage.transaction(async storage => {
      const current = await storage.get<DiscoverySnapshot>(discoveryStorageKey);
      // A delayed discovery/bind cannot replace a newer verified schema, a
      // concurrently rebound session, or a different newly installed credential.
      if (current?.fingerprint === fingerprint && (Date.parse(current.capabilities.server_time) > Date.parse(capabilities.server_time) ||
          (options.sessionID && current.sessionID && current.sessionID !== saved?.sessionID && current.sessionID !== options.sessionID))) return;
      if (current && current.fingerprint !== fingerprint && current.fingerprint !== saved?.fingerprint) return;
      await storage.put(discoveryStorageKey, { fingerprint, capabilities, sessionID: options.sessionID ?? current?.sessionID });
    });
    return capabilities;
  };
  if (!fresh && saved?.fingerprint === fingerprint) {
    const value = immutableCapabilities(saved.capabilities);
    return options.sessionID && !saved.sessionID ? persist(value) : value;
  };
  if (!fresh) {
    const cached = discoverySnapshots.get(fingerprint);
    if (cached && cached.expires > Date.now()) {
      return persist(cached.value);
    }
  }
  // In-flight sharing is for schema reuse only: a fresh verification must start
  // its own request, not inherit evidence from a previous turn.
  let flight = fresh ? undefined : discoveryFlights.get(fingerprint);
  if (!flight) {
    if (activeDiscoveryRequests >= discoveryLimit) throw new Error('discovery_capacity');
    activeDiscoveryRequests++;
    flight = fetchKnotCapabilities(env).then(value => {
      const frozen = immutableCapabilities(value);
      for (const [key, entry] of discoverySnapshots) if (entry.expires <= Date.now()) discoverySnapshots.delete(key);
      const current = discoverySnapshots.get(fingerprint);
      if (!current || Date.parse(current.value.server_time) <= Date.parse(frozen.server_time)) {
        if (!current && discoverySnapshots.size >= discoveryLimit) discoverySnapshots.delete(discoverySnapshots.keys().next().value!);
        discoverySnapshots.set(fingerprint, { expires: Date.now() + 1800000, value: frozen });
      }
      return frozen;
    // A failed fresh call still rejects this caller. It is not permitted to
    // erase another call's verified schema or turn schema reuse into liveness.
    }).finally(() => { activeDiscoveryRequests--; });
    if (!fresh) discoveryFlights.set(fingerprint, flight);
  }
  try {
    const capabilities = await flight;
    return await persist(capabilities);
  } finally { if (discoveryFlights.get(fingerprint) === flight) discoveryFlights.delete(fingerprint); }
}
async function fetchKnotCapabilities(env: KnotShellEnv): Promise<SidecarCapabilities> {
  const raw = JSON.parse(await readSidecarText(await sidecarRequest(env, '/capabilities'), 100000)) as SidecarCapabilities;
  if (!raw || raw.ok !== true || raw.service !== 'knot-sidecar' || raw.principal !== 'whisper' ||
      !Number.isFinite(Date.parse(raw.server_time)) || !Array.isArray(raw.tools) || raw.tools.length > 64 ||
      raw.skills?.location !== '/opt/knot-skills' || raw.skills.index !== '/opt/knot-skills/README.md' || raw.memory?.file !== 'MEMORY.md' ||
      !raw.limits || typeof raw.limits !== 'object') throw new Error('invalid_live_capabilities');
  const names = new Set<string>();
  for (const tool of raw.tools) {
    if (!tool || !/^[a-z][a-z0-9_]{0,63}$/.test(tool.name) || names.has(tool.name) ||
        !['GET', 'POST', 'DELETE'].includes(tool.method) || typeof tool.path !== 'string' || tool.path.length > 256 ||
        !tool.path.startsWith('/') || typeof tool.purpose !== 'string' || tool.purpose.length > 2000 ||
        typeof tool.returns !== 'string' || tool.returns.length > 3000 ||
        !(tool.request === null || (typeof tool.request === 'object' && !Array.isArray(tool.request) &&
          Object.entries(tool.request).every(([key, value]) => /^[a-z_]{1,64}$/.test(key) && typeof value === 'string' && value.length < 1000)))) throw new Error('invalid_live_tool');
    names.add(tool.name);
  }
  return raw;
}
export function endpoint(capabilities: SidecarCapabilities, name: string, method: string, path: string): SidecarTool | undefined {
  return capabilities.tools.find(tool => tool.name === name && tool.method === method && tool.path === path);
}
/** Least privilege projection of live endpoints. Global lists/jobs/files and unowned IDs are deliberately not offered.
 * The foreground executor owns session creation, identity, time bound and termination; the model supplies command text only. */
export function liveShellTools(capabilities: SidecarCapabilities, canPropose: boolean, hasReceipt: boolean, documentTask = false) {
  return capabilities.tools.flatMap(tool => {
    let properties: Record<string, unknown> = {}, required: string[] = [], policy = '';
    if (tool.name === 'session_input' && canPropose && endpoint(capabilities, 'session_input', 'POST', '/sessions/:id/input') &&
        endpoint(capabilities, 'session_open', 'POST', '/sessions') && endpoint(capabilities, 'session_status', 'GET', '/sessions/:id') &&
        endpoint(capabilities, 'session_read', 'GET', '/sessions/:id/log?offset=N') && endpoint(capabilities, 'session_close', 'DELETE', '/sessions/:id') &&
        tool.request && Object.keys(tool.request).length === 1 && typeof tool.request.data === 'string') {
      properties = Object.fromEntries(Object.entries(tool.request).map(([name, description]) => [name, { type: 'string', description }]));
      required = Object.keys(properties);
      policy = documentTask ? 'Document workflow READ adapter only. data is an exact indexed skill-read command or cat -- followed by a single quoted relative workspace file path. No authoring, Python, heredoc, rendering or receipt-emitter code is accepted here. Use the separately advertised backend document_script adapter with interpreter plus pure code for document work. Prerequisite reads are backend-prepared. Foreground ownership, Stop, 120 seconds and real receipts remain mandatory; no IDs, approval or enabling step.' : 'Foreground workspace adapter: data is the EXACT Bash command, without a trailing newline. This call saves a command only; it does NOT write stdin. Native automatically dispatches fresh commands into the current owned create-or-attach shell, with harness-owned per-command stream boundaries and a 120-second bound, for this account/Knot/conversation with nothing to enable. There is no shell-sharing toggle or command approval. Permissions apply separately to personal-product reads/writes, which this offline shell cannot perform. No IDs, workspace selection, webhook or background permission. Prefer python3 for Python scripts; do not depend on a python alias. Include complete source in a quoted heredoc, preferably python3 - <<\'KNOT_SOURCE\', rather than invoking an assumed create_pdf.py or build.py. Existing task scripts require an actual successful source-writing receipt. Commands are at most 12 KB; never replace required source with a filename or placeholder. At most one command per response.';
    } else if (hasReceipt && ['session_status', 'session_read', 'session_close'].includes(tool.name) &&
        ((tool.name === 'session_status' && tool.method === 'GET' && tool.path === '/sessions/:id') ||
         (tool.name === 'session_read' && tool.method === 'GET' && tool.path === '/sessions/:id/log?offset=N') ||
         (tool.name === 'session_close' && tool.method === 'DELETE' && tool.path === '/sessions/:id'))) {
      policy = 'Only the current server-resolved owned execution. No model-selected session ID. Read/status/close return stored evidence only and never dispatch again. Close reports foreground termination separately from the provider session; it does not send Stop or imply a retained shell is dead.';
    } else if (tool.name === 'capabilities' && tool.method === 'GET' && tool.path === '/capabilities') {
      policy = 'Return the validated discovery snapshot for this attached session. It describes supported endpoints, not current reachability. No workspace mutation.';
    } else return [];
    return [{ type: 'function', function: { name: tool.name, description: `${tool.purpose}\n${tool.method} ${tool.path}\nReturns: ${tool.returns}\n${policy}`, strict: true,
      parameters: { type: 'object', properties, required, additionalProperties: false } } }];
  });
}
