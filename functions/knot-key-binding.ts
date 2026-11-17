// Operator-authenticated, read-only equality check. Never returns credentials or reusable proofs.
// The route must verify BROADCAST_SECRET before calling this helper.
type KeyEnv = { EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY?: string };
export async function inspectKnotKeyBinding(request: Request, env: KeyEnv): Promise<Response> {
  const nonce = request.headers.get('X-Whisper-Key-Nonce') ?? '';
  const proof = request.headers.get('X-Whisper-Key-Proof') ?? '';
  const headers = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' };
  if (!/^[a-f0-9]{64}$/.test(nonce) || !/^[a-f0-9]{64}$/.test(proof)) {
    return new Response(JSON.stringify({ error: 'invalid_comparison' }), { status: 400, headers });
  }
  // Match the Cloud-only transport: a private override is never selected.
  const token = env.EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY;
  const source = token ? 'managed' : 'missing';
  let credentialMatches = false;
  if (token) {
    const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(token), { name: 'HMAC', hash: 'SHA-256' }, false, ['verify']);
    const signature = Uint8Array.from(proof.match(/../g)!, byte => Number.parseInt(byte, 16));
    credentialMatches = await crypto.subtle.verify('HMAC', key, signature, new TextEncoder().encode('whisper-knot-key-binding-v1:' + nonce));
  }
  return new Response(JSON.stringify({ credentialPresent: !!token, credentialSource: source, credentialMatches, gatewayRequestPerformed: false }), { headers });
}
