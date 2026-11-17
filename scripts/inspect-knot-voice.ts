// Read-only provider configuration diagnostics. Never prints credentials,
// provider bodies, voice previews or conversation content; starts no calls.
const key = process.env.ELEVENLABS_API_KEY;
if (!key) throw new Error('ELEVENLABS_API_KEY is not configured.');
console.log(JSON.stringify({ keyPresent: true, outerWhitespace: key !== key.trim(), wrappedInQuotes: /^("|').*\1$/.test(key), hasBearerPrefix: /^Bearer\s/i.test(key), agentConfigured: Boolean(process.env.ELEVENLABS_AGENT_ID) }));
const targets = [
  ['workspace_settings', '/v1/convai/settings'],
  ['boy_voice', '/v1/voices/UgBBYS2sOqTuMpoF3BR0'],
  ['girl_voice', '/v1/voices/DODLEQrClDo8wCz460ld'],
] as const;
await Promise.all(targets.map(async ([name, path]) => {
  try {
    const response = await fetch('https://api.elevenlabs.io' + path, { headers: { 'xi-api-key': key }, signal: AbortSignal.timeout(15000), redirect: 'error' });
    let providerCode: string | undefined;
    let requiredPermission: string | undefined;
    if (!response.ok) {
      const body = await response.json().catch(() => null) as { detail?: { status?: unknown; message?: unknown } } | null;
      const status = body?.detail?.status;
      if (typeof status === 'string' && /^[a-z_]{1,60}$/.test(status)) providerCode = status;
      const message = body?.detail?.message;
      if (typeof message === 'string') {
        const match = message.match(/\bpermission\s+([a-z_]+)\b/);
        if (match && ['voices_read', 'convai_read', 'convai_write', 'workspace_read', 'conversation_privacy_manage'].includes(match[1])) requiredPermission = match[1];
      }
    } else { await response.body?.cancel(); }
    console.log(JSON.stringify({ check: name, http: response.status, ...(providerCode ? { providerCode } : {}), ...(requiredPermission ? { requiredPermission } : {}) }));
  } catch { console.log(JSON.stringify({ check: name, error: 'request_failed' })); }
}));
