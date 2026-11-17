/** Content-free diagnostics only. Never return/log the provider message, IDs,
 * prompt, raw body, organization, project, credential or arbitrary error fields. */
export type KnotUpstreamDiagnostic = {
  category: 'quota_exhausted' | 'rate_limited' | 'authentication' | 'other_rejection' | 'unclassified';
  code?: 'insufficient_quota' | 'INSUFFICIENT_BALANCE' | 'rate_limit_exceeded' | 'invalid_api_key' | 'invalid_key' | 'authentication_error' | 'UNAUTHORIZED' | 'unauthorized' | 'INVALID_API_KEY' | 'INVALID_TOKEN' | 'invalid_token' | 'API_KEY_REVOKED';
  authenticationHint?: 'invalid_key' | 'revoked_key' | 'missing_key' | 'unauthorized' | 'authentication_failed';
  retryAfterSeconds?: number;
};
export async function knotUpstreamDiagnostic(response: Response): Promise<KnotUpstreamDiagnostic> {
  const result: KnotUpstreamDiagnostic = { category: response.status === 401 ? 'authentication' : 'unclassified' };
  const retry = response.headers.get('retry-after');
  const seconds = retry && /^\d+(?:\.\d+)?$/.test(retry) ? Math.ceil(Number(retry))
    : retry ? Math.ceil((Date.parse(retry) - Date.now()) / 1000) : NaN;
  if (Number.isFinite(seconds) && seconds >= 0 && seconds <= 86400) result.retryAfterSeconds = seconds;
  const reader = response.body?.getReader();
  if (!reader) return result;
  try {
    const chunks: Uint8Array[] = []; let size = 0;
    for (;;) {
      const read = await reader.read(); if (read.done) break;
      size += read.value.length; if (size > 16384) return result;
      chunks.push(read.value);
    }
    const bytes = new Uint8Array(size); let at = 0;
    for (const chunk of chunks) { bytes.set(chunk, at); at += chunk.length; }
    const parsed: unknown = JSON.parse(new TextDecoder().decode(bytes));
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return result;
    const data = parsed as { code?: unknown; message?: unknown; error?: { code?: unknown; type?: unknown; message?: unknown } | string };
    const error = data.error && typeof data.error === 'object' ? data.error : undefined;
    const authenticationCodes = ['invalid_api_key', 'invalid_key', 'authentication_error', 'UNAUTHORIZED', 'unauthorized', 'INVALID_API_KEY', 'INVALID_TOKEN', 'invalid_token', 'API_KEY_REVOKED'] as const;
    const codes = ['insufficient_quota', 'INSUFFICIENT_BALANCE', 'rate_limit_exceeded', ...authenticationCodes] as const;
    const code = codes.find(value => data.code === value || error?.code === value || error?.type === value);
    if (code) result.code = code;
    // HTTP 401 is authoritative even when the JSON body has no allowlisted code.
    // These diagnostics never identify the rejecting service or account binding.
    result.category = response.status === 401 || authenticationCodes.some(value => value === code) ? 'authentication'
      : code === 'insufficient_quota' || code === 'INSUFFICIENT_BALANCE' ? 'quota_exhausted'
      : code === 'rate_limit_exceeded' ? 'rate_limited' : 'other_rejection';
    if (result.category === 'authentication') {
      const message = typeof error?.message === 'string' ? error.message : typeof data.error === 'string' ? data.error : typeof data.message === 'string' ? data.message : '';
      // Collapse bounded text to fixed semantic hints only. Never return text,
      // arbitrary fields, IDs, key bytes, project or billing conclusions.
      if (/revoked|disabled key|key.*disabled/i.test(message)) result.authenticationHint = 'revoked_key';
      else if (/invalid.*(?:key|token)|(?:key|token).*invalid|incorrect.*key/i.test(message)) result.authenticationHint = 'invalid_key';
      else if (/missing.*(?:key|token|authorization)|(?:key|token|authorization).*required/i.test(message)) result.authenticationHint = 'missing_key';
      else if (/unauthorized|unauthenticated/i.test(message)) result.authenticationHint = 'unauthorized';
      else if (/authentication (?:failed|failure)/i.test(message)) result.authenticationHint = 'authentication_failed';
    }
  } catch { /* An unparseable rejection remains unclassified, not presumed throttling. */ }
  finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
  return result;
}
