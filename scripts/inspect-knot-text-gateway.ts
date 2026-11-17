// Operator-only deployed diagnostic. Presence-only by default:
// rork env run -- bun scripts/inspect-knot-text-gateway.ts
// A fixed synthetic provider reply (no personal data) with --deployed-transport.
// Managed AI credentials stay in the worker, never in this script's output.
// No member authentication/history, tools, workspace, session or job is used.
const secret = process.env.BROADCAST_SECRET;
if (!secret) throw new Error('Operator configuration missing.');
const transport = process.argv.includes('--deployed-transport');
const response = await fetch('https://uf26aun6d49w1tsjsm2u9-backend.rork.app/admin/' + (transport ? 'knot-text-transport' : 'knot-text-policy'), {
  method: transport ? 'POST' : 'GET',
  headers: { 'X-Whisper-Operator': secret, 'Content-Type': 'application/json' },
  ...(transport ? { body: '{}' } : {}),
  signal: AbortSignal.timeout(35000), redirect: 'error',
});
if (!response.ok) {
  const body = await response.json().catch(() => null) as { error?: unknown } | null;
  console.log(JSON.stringify({ check: 'deployed_route', status: response.status, knownNotFound: body?.error === 'not_found', forbidden: body?.error === 'forbidden' }));
  process.exit(1);
}
const policy = await response.json() as Record<string, unknown>;
const fields = transport
  ? ['configured', 'eventStream', 'terminalFrame', 'normalFinish', 'validReply', 'completed']
  : ['tokenPresent', 'gatewayValid', 'addressOverridePresent', 'signingKeyPresent', 'admissionPresent'];
console.log(JSON.stringify({ check: transport ? 'deployed_provider_stream' : 'deployed_configuration',
  observedAt: new Date().toISOString(),
  ...Object.fromEntries(fields.map(field => [field, policy[field] === true])),
  ...(['openai', 'rork', 'unavailable'].includes(String(policy.provider)) ? { provider: policy.provider } : {}),
  ...(policy.routingPolicy === 'rork_cloud_only_v1' ? { routingPolicy: policy.routingPolicy } : {}),
  ...(['managed', 'missing'].includes(String(policy.credentialSource)) ? { credentialSource: policy.credentialSource } : {}),
  ...(typeof policy.status === 'number' ? { status: policy.status } : {}),
  ...(typeof policy.frames === 'number' ? { frames: policy.frames } : {}),
  ...(policy.diagnostic && typeof policy.diagnostic === 'object' ? { diagnostic: safeDiagnostic(policy.diagnostic as Record<string, unknown>) } : {}),
  ...(['timeout', 'provider_error', 'transport_or_framing_failure'].includes(String(policy.category)) ? { category: policy.category } : {}),
  ...(['provider_request', 'provider_headers', 'provider_frames'].includes(String(policy.stage)) ? { stage: policy.stage } : {}),
  ...(['TypeError', 'SyntaxError', 'Error', 'TimeoutError', 'AbortError', 'unknown'].includes(String(policy.failureName)) ? { failureName: policy.failureName } : {}),
  ...(['invalid_stream', 'incomplete_stream', 'response_limit', 'response_too_large', 'cancelled'].includes(String(policy.knownReason)) ? { knownReason: policy.knownReason } : {}),
}));
if (transport && policy.completed !== true) process.exitCode = 1;
function safeDiagnostic(diagnostic: Record<string, unknown>) {
  return {
    ...(['quota_exhausted', 'rate_limited', 'authentication', 'other_rejection', 'unclassified'].includes(String(diagnostic.category)) ? { category: diagnostic.category } : {}),
    ...(['insufficient_quota', 'INSUFFICIENT_BALANCE', 'rate_limit_exceeded', 'invalid_api_key', 'invalid_key'].includes(String(diagnostic.code)) ? { code: diagnostic.code } : {}),
    ...(typeof diagnostic.retryAfterSeconds === 'number' && Number.isFinite(diagnostic.retryAfterSeconds) && diagnostic.retryAfterSeconds >= 0 && diagnostic.retryAfterSeconds <= 86400 ? { retryAfterSeconds: diagnostic.retryAfterSeconds } : {}),
  };
}
export {};
