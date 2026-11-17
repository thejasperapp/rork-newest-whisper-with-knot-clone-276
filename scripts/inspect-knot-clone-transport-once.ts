// Exclusive named synthetic checks on this clone only; each scope is single-use.
// rork env run -p mayokn2749ag072e3uvbh -- bun scripts/inspect-knot-clone-transport-once.ts --run-once --scope owner-fix-recheck-01
// No member identity/session, history, workspace, tools, box or configuration writes.
// Credentials remain in the Worker. Never retry this consumed scope, even on timeout.
import { writeFileSync } from 'node:fs';
import { knotBackendIdentity, knotBackendOrigin } from '../functions/knot-backend';
import { knotSourceBuildSHA256 } from '../functions/knot-source-build';

type Obj = Record<string, unknown>;
const object = (value: unknown): Obj => value !== null && typeof value === 'object' && !Array.isArray(value) ? value as Obj : {};
const included = (value: unknown, allowed: readonly string[]) => typeof value === 'string' && allowed.includes(value) ? value : null;
const integer = (value: unknown, max: number) => typeof value === 'number' && Number.isSafeInteger(value) && value >= 0 && value <= max ? value : null;
const uuid = (value: string | null) => value && /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(value) ? value : null;
const hash = (value: string | null) => value && /^[0-9a-f]{64}$/.test(value) ? value : null;
const scopeIndex = process.argv.indexOf('--scope');
const scope = scopeIndex === -1 ? 'post-migration' : process.argv[scopeIndex + 1];
if (scope !== 'post-migration' && scope !== 'rotation-02' && scope !== 'auth-diagnostic-01' && scope !== 'owner-fix-recheck-01') throw new Error('Explicit authorized diagnostic scope required.');
const stem = 'managed-clone-transport-20261114-' + scope;
const evidencePath = new URL('../deliveries/' + stem + '-outcome.json', import.meta.url);
const secret = process.env.BROADCAST_SECRET;
if (!process.argv.includes('--run-once') || !secret) throw new Error('Explicit once flag and operator configuration required; no request made.');
const headers = { 'X-Whisper-Operator': secret, 'Content-Type': 'application/json' };
async function read(response: Response): Promise<Obj> {
  if (!response.ok) { await response.body?.cancel(); throw new Error('Configuration endpoint unavailable; raw response withheld.'); }
  const text = await response.text();
  if (text.length > 16000) throw new Error('Diagnostic response exceeds bound; raw response withheld.');
  try { return object(JSON.parse(text)); } catch { throw new Error('Diagnostic format unavailable; raw response withheld.'); }
}
const ping = await fetch(knotBackendOrigin + '/ping', { redirect: 'error', signal: AbortSignal.timeout(15000) });
const servingBuild = hash(ping.headers.get('X-Knot-Worker-Build'));
const health = await read(ping);
if (health.ok !== true || servingBuild !== knotSourceBuildSHA256) throw new Error('Exact deployed source build required; no AI request made.');
const policy = await read(await fetch(knotBackendOrigin + '/admin/knot-text-policy', { headers, redirect: 'error', signal: AbortSignal.timeout(15000) }));
if (policy.provider !== 'rork' || policy.routingPolicy !== 'rork_cloud_only_v1' || policy.credentialSource !== 'managed' || policy.tokenPresent !== true || policy.gatewayValid !== true || policy.addressOverridePresent !== false) throw new Error('Exact managed Cloud policy required; no AI request made.');
const startedAt = new Date().toISOString(), started = performance.now();
const intent = { title: 'Clone migration — fixed synthetic AI transport check', scope: stem, project: knotBackendIdentity, backend: knotBackendOrigin,
  startedAt, expectedBuild: knotSourceBuildSHA256, method: 'POST', path: '/admin/knot-text-transport',
  reportedManagedKeyID: scope !== 'post-migration' ? 'sk_0gbdem17' : null, reportedKeyIdentityIsNotRuntimeByteProof: true,
  fixedSyntheticGreetingOnly: true, maximumOperatorPosts: 1, automaticRetries: 0, memberDataRead: false,
  usesMemberSession: false, boxCommands: 0, configurationWrites: 0, consumesScopeBeforeRequest: true };
// Exclusive, durable latch before the only non-idempotent network call.
writeFileSync(new URL('../deliveries/' + stem + '-intent.json', import.meta.url), JSON.stringify(intent, null, 2) + '\n', { flag: 'wx' });
let outcome: Obj;
try {
  const response = await fetch(knotBackendOrigin + '/admin/knot-text-transport', {
    method: 'POST', headers, body: '{}', redirect: 'error', signal: AbortSignal.timeout(35000),
  });
  const routeStatus = response.status, responseBuild = hash(response.headers.get('X-Knot-Worker-Build'));
  const servingRequestID = uuid(response.headers.get('X-Knot-Request-ID'));
  const result = await read(response), diagnostic = object(result.diagnostic);
  const exactServingBuild = responseBuild === knotSourceBuildSHA256;
  const completed = routeStatus === 200 && exactServingBuild && result.provider === 'rork' && result.status === 200 &&
    result.eventStream === true && result.terminalFrame === true && result.normalFinish === true && result.validReply === true && result.completed === true;
  outcome = { routeStatus, servingBuild: responseBuild, servingRequestID, exactServingBuild,
    provider: included(result.provider, ['rork', 'unavailable']), configured: result.configured === true,
    upstreamStatus: integer(result.status, 599), eventStream: result.eventStream === true,
    frames: integer(result.frames, 10000), terminalFrame: result.terminalFrame === true,
    normalFinish: result.normalFinish === true, validReply: result.validReply === true, completed,
    diagnostic: { category: included(diagnostic.category, ['quota_exhausted', 'rate_limited', 'authentication', 'other_rejection', 'unclassified']),
      code: included(diagnostic.code, ['insufficient_quota', 'INSUFFICIENT_BALANCE', 'rate_limit_exceeded', 'invalid_api_key', 'invalid_key', 'authentication_error', 'UNAUTHORIZED', 'unauthorized', 'INVALID_API_KEY', 'INVALID_TOKEN', 'invalid_token', 'API_KEY_REVOKED']),
      authenticationHint: included(diagnostic.authenticationHint, ['invalid_key', 'revoked_key', 'missing_key', 'unauthorized', 'authentication_failed']),
      retryAfterSeconds: integer(diagnostic.retryAfterSeconds, 86400) },
    category: included(result.category, ['timeout', 'provider_error', 'transport_or_framing_failure']),
    stage: included(result.stage, ['provider_request', 'provider_headers', 'provider_frames']),
    runtimeCredentialIdentityVerified: false, billingAssociationVerified: false,
    memberTurnOrBoxAcceptanceVerified: false, observedUpstreamModel: null, upstreamProviderIdentity: null,
    uncertaintyRequiresReconciliationNotReplay: false };
} catch {
  outcome = { completed: false, upstreamStatus: null, category: 'operator_transport_or_diagnostic_unavailable',
    uncertaintyRequiresReconciliationNotReplay: true, runtimeCredentialIdentityVerified: false,
    billingAssociationVerified: false, memberTurnOrBoxAcceptanceVerified: false };
}
const evidence = { intent, endedAt: new Date().toISOString(), clientElapsedMs: Math.round(performance.now() - started),
  operatorPostsAttempted: 1, automaticRetries: 0, outcome,
  memberDataRead: false, callsStarted: 0, boxCommands: 0, configurationWrites: 0,
  priorPrimeScopesReused: false, originalBackendsCalled: false,
  timingScope: 'operator_client_round_trip_not_gateway_or_provider_generation_time' };
writeFileSync(evidencePath, JSON.stringify(evidence, null, 2) + '\n', { flag: 'wx' });
console.log(JSON.stringify({ ...evidence, evidence: 'deliveries/' + stem + '-outcome.json' }, null, 2));
if (outcome.completed !== true) process.exitCode = 1;
