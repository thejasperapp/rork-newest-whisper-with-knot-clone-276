// Operator-only fixed synthetic gateway diagnostic. Never reads member data,
// starts remote work, prints credentials, or retries/falls back after rejection.
// rork env run -- bun scripts/inspect-knot-gateway-rejection.ts
// Legacy gateway probe, NOT the selected deployed Knot transport. --managed-only
// only skips the private binding; env run cannot certify a protected managed key.
// An inherited process value can be stale after rotation. Prefer the deployed check.
import { knotGatewayBase } from '../functions/knot-gateway';

const privateToken = process.argv.includes('--managed-only') ? undefined : process.env.RORK_TOOLKIT_SECRET_KEY;
const managedToken = process.env.EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY;
const token = privateToken || managedToken;
const base = knotGatewayBase({ EXPO_PUBLIC_TOOLKIT_URL: process.env.EXPO_PUBLIC_TOOLKIT_URL });
if (!token || !base) throw new Error('Gateway configuration missing.');
const signal = AbortSignal.timeout(25000);
const response = await fetch(`${base}/v2/vercel/v1/chat/completions`, {
  method: 'POST', signal, redirect: 'error',
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', 'idempotency-key': crypto.randomUUID() },
  body: JSON.stringify({ model: 'openai/gpt-4o', stream: true, max_tokens: 120,
    messages: [{ role: 'user', content: 'Synthetic transport check, with no personal data. Return a brief greeting as text and empty metadata.' }],
    response_format: { type: 'json_schema', json_schema: { name: 'knot_reply', strict: true,
      schema: { type: 'object', properties: { text: { type: 'string' }, metadata: { type: 'string' } }, required: ['text', 'metadata'], additionalProperties: false } } },
  }),
});
let code: string | undefined;
const codes = new Set(['INSUFFICIENT_BALANCE', 'insufficient_balance', 'insufficient_quota', 'insufficient_credits', 'AI_DISABLED', 'PAYMENT_REQUIRED', 'UNAUTHORIZED', 'unauthorized', 'INVALID_API_KEY', 'invalid_api_key', 'INVALID_KEY', 'invalid_key', 'INVALID_TOKEN', 'invalid_token', 'AUTHENTICATION_ERROR', 'authentication_error', 'FORBIDDEN', 'forbidden', 'API_KEY_REVOKED', 'api_key_revoked']);
let authenticationHint: 'invalid_key' | 'revoked_key' | 'missing_key' | 'unauthorized' | undefined;
if (!response.ok && response.body) {
  const reader = response.body.getReader();
  let size = 0, body = '';
  const decoder = new TextDecoder();
  try {
    for (;;) {
      const part = await reader.read(); if (part.done) break;
      size += part.value.byteLength; if (size > 16000) break;
      body += decoder.decode(part.value, { stream: true });
    }
    if (size <= 16000) {
      try {
        const error = JSON.parse(body + decoder.decode()) as { code?: unknown; message?: unknown; error?: { code?: unknown; message?: unknown } | string };
        const candidate = typeof error.code === 'string' ? error.code : typeof error.error === 'object' && error.error ? error.error.code : undefined;
        if (typeof candidate === 'string' && codes.has(candidate)) code = candidate;
        const message = typeof error.message === 'string' ? error.message : typeof error.error === 'string' ? error.error : typeof error.error?.message === 'string' ? error.error.message : '';
        // Report semantic categories only; never print upstream message text.
        if (/revoked|disabled key|key.*disabled/i.test(message)) authenticationHint = 'revoked_key';
        else if (/invalid.*(?:key|token)|(?:key|token).*invalid|incorrect.*key/i.test(message)) authenticationHint = 'invalid_key';
        else if (/missing.*(?:key|token|authorization)|(?:key|token|authorization).*required/i.test(message)) authenticationHint = 'missing_key';
        else if (/unauthorized|unauthenticated/i.test(message)) authenticationHint = 'unauthorized';
      } catch { /* Never print an upstream body, even when parsing fails. */ }
    }
  } finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
} else await response.body?.cancel();
console.log(JSON.stringify({ check: 'configured_gateway_rejection', observedAt: new Date().toISOString(),
  status: response.status, ...(code ? { code } : {}), ...(authenticationHint ? { authenticationHint } : {}),
  managedRuntimeIdentityVerified: false,
  privateTokenSelected: !!privateToken, managedTokenPresent: !!managedToken,
  selectedMatchesManaged: !!managedToken && token === managedToken,
  defaultGateway: base === 'https://toolkit.rork.com', remoteTaskPerformed: false,
}));
export {};
