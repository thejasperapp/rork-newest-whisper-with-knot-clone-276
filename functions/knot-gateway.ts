type GatewayEnv = { EXPO_PUBLIC_TOOLKIT_URL?: string };

/** An omitted optional address uses the same gateway as Whisper's other AI routes.
 * Explicit overrides retain their path prefix; invalid overrides fail closed. */
export function knotGatewayBase(env: GatewayEnv): string | null {
  const configured = env.EXPO_PUBLIC_TOOLKIT_URL?.trim();
  try {
    const url = new URL(configured || 'https://toolkit.rork.com');
    if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash) return null;
    return url.toString().replace(/\/+$/, '');
  } catch { return null; }
}
