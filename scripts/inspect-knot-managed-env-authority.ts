// Supported, project-scoped managed-store inspection; credentials stay in memory.
// No generation, override, key rotation, member session, workspace or box access.
// Run with rork env run -p mayokn2749ag072e3uvbh -- bun scripts/inspect-knot-managed-env-authority.ts
import { execFileSync } from 'node:child_process';
import { createHmac, randomBytes } from 'node:crypto';
import { existsSync, writeFileSync } from 'node:fs';

const project = 'mayokn2749ag072e3uvbh';
const backend = 'https://newest-whisper-with-knot-clone-t6ui3ur-backend.rork.app';
const name = 'EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY';
const path = new URL('../deliveries/clone-managed-store-authority-20261114.json', import.meta.url);
if (existsSync(path)) throw new Error('Immutable inspection already recorded; no requests made.');
const operator = process.env.BROADCAST_SECRET;
if (!operator) throw new Error('Operator configuration unavailable; no requests made.');
type Obj = Record<string, unknown>;
const obj = (v: unknown): Obj => v !== null && typeof v === 'object' && !Array.isArray(v) ? v as Obj : {};
const observations: Obj[] = [];
for (const environment of ['development', 'production']) {
  let output: string;
  try {
    // Explicit reveal is audited by the supported store. Never inherit/copy a
    // stale CLI value, print output/stderr, or write credentials to disk.
    output = execFileSync('rork', ['env', 'get', name, '-p', project, '-e', environment, '--reveal', '--json'], {
      encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 30000, maxBuffer: 131072,
    });
  } catch (error) {
    const failure = error as { stdout?: unknown; stderr?: unknown };
    const text = [failure.stdout, failure.stderr].map(v => typeof v === 'string' ? v : Buffer.isBuffer(v) ? v.toString('utf8') : '').join('\n');
    const denied = /\b403\b|forbidden|protected|cannot.*reveal|not.*allowed/i.test(text);
    observations.push({ environment, supportedGetSucceeded: false, denied, candidateAvailable: false, runtimeComparison: null });
    // A protected/denied result is final; do not try pull or another export path.
    if (denied) break;
    continue;
  }
  let data: Obj;
  try { data = obj(JSON.parse(output)); } catch {
    observations.push({ environment, supportedGetSucceeded: true, recognizedResponse: false, candidateAvailable: false, runtimeComparison: null });
    continue;
  }
  const nested = obj(data.variable);
  const candidate = typeof data.value === 'string' ? data.value : typeof nested.value === 'string' ? nested.value : null;
  const marker = candidate !== null && /placeholder|redacted|delegated|__rork|^\*+$/i.test(candidate);
  const usable = candidate !== null && candidate.length > 0 && !marker;
  const observation: Obj = { environment, supportedGetSucceeded: true, recognizedResponse: candidate !== null,
    candidateAvailable: usable, empty: candidate === '', explicitPlaceholderMarker: marker, runtimeComparison: null };
  if (usable) {
    const nonce = randomBytes(32).toString('hex');
    try {
      const response = await fetch(backend + '/admin/knot-key-binding', { redirect: 'error', signal: AbortSignal.timeout(15000),
        headers: { 'X-Whisper-Operator': operator, 'X-Whisper-Key-Nonce': nonce,
          'X-Whisper-Key-Proof': createHmac('sha256', candidate!).update('whisper-knot-key-binding-v1:' + nonce).digest('hex') } });
      if (!response.ok) { await response.body?.cancel(); observation.runtimeComparison = { status: response.status, verified: false }; }
      else {
        const result = obj(await response.json());
        observation.runtimeComparison = { status: response.status, credentialPresent: result.credentialPresent === true,
          credentialSource: result.credentialSource === 'managed' ? 'managed' : 'unavailable', matchesAuthoritativeStore: result.credentialMatches === true };
      }
    } catch { observation.runtimeComparison = { unavailable: true }; }
  }
  observations.push(observation);
}
const evidence = { check: 'supported_managed_environment_store_authority', project, backend, observedAt: new Date().toISOString(), observations,
  gatewayRequestPerformed: false, generationPerformed: false, rawCredentialLoggedOrPersisted: false,
  credentialConfigurationWritten: false, memberSessionUsed: false, originalBackendsCalled: false, billingAssociationVerified: false };
const serialized = JSON.stringify(evidence, null, 2) + '\n';
writeFileSync(path, serialized, { flag: 'wx' });
console.log(serialized);
export {};
