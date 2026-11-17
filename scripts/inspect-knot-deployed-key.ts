// Operator-only equality check; no AI, member data, workspace or task requests.
// rork env run -- bun scripts/inspect-knot-deployed-key.ts
// Equality is against this process only, not authoritative managed-key identity.
// env run excludes protected managed keys; inherited values may survive rotations.
import { createHmac, randomBytes } from 'node:crypto';
const operator = process.env.BROADCAST_SECRET;
const token = process.env.EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY;
if (!operator || !token) throw new Error('Comparison configuration missing.');
const nonce = randomBytes(32).toString('hex');
try {
  const response = await fetch('https://uf26aun6d49w1tsjsm2u9-backend.rork.app/admin/knot-key-binding', {
    headers: { 'X-Whisper-Operator': operator, 'X-Whisper-Key-Nonce': nonce,
      'X-Whisper-Key-Proof': createHmac('sha256', token).update('whisper-knot-key-binding-v1:' + nonce).digest('hex') },
    signal: AbortSignal.timeout(15000), redirect: 'error',
  });
  if (!response.ok) {
    console.log(JSON.stringify({ check: 'deployed_key_binding', status: response.status, gatewayRequestPerformed: false }));
    process.exitCode = 1;
  } else {
    const result = await response.json() as Record<string, unknown>;
    console.log(JSON.stringify({ check: 'deployed_key_binding', observedAt: new Date().toISOString(),
      credentialPresent: result.credentialPresent === true,
      credentialSource: ['managed', 'missing'].includes(String(result.credentialSource)) ? result.credentialSource : 'unknown',
      credentialMatches: result.credentialMatches === true, managedRuntimeIdentityVerified: false, gatewayRequestPerformed: false }));
    if (result.credentialMatches !== true) process.exitCode = 1;
  }
} catch { throw new Error('Deployed credential comparison unavailable. No credential contents logged.'); }
export {};
