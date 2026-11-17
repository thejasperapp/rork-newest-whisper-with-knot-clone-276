// Read-only deployed voice policy diagnostic. Never starts a call or prints
// credentials, provider bodies, agent identifiers or conversation context.
const secret = process.env.BROADCAST_SECRET;
if (!secret) throw new Error('Operator configuration missing.');
const response = await fetch('https://uf26aun6d49w1tsjsm2u9-backend.rork.app/admin/knot-voice-policy', {
  headers: { 'X-Whisper-Operator': secret }, signal: AbortSignal.timeout(15000), redirect: 'error',
});
if (!response.ok) { await response.body?.cancel(); throw new Error(`Policy inspection unavailable (${response.status}).`); }
const result = await response.json() as { configured?: boolean; checks?: { scope?: string; http?: number; valid?: boolean; failure?: string }[] };
console.log(JSON.stringify({ configured: result.configured, checks: result.checks?.map(check => ({
  scope: ['agent', 'workspace'].includes(check.scope ?? '') ? check.scope : 'unknown',
  http: check.http, valid: check.valid,
  failure: ['TypeError', 'SyntaxError', 'TimeoutError', 'AbortError', 'read_failed'].includes(check.failure ?? '') ? check.failure : undefined,
})) }));
export {};
