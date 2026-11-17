import { knotGatewayBase } from './knot-gateway';

export type KnotAIEnv = {
  EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY?: string;
  EXPO_PUBLIC_TOOLKIT_URL?: string;
};

/** Rork AI Cloud only. Never reads direct-provider credentials, legacy private
 * overrides or transport-selection settings, even if they drift at runtime.
 * Missing/invalid managed configuration fails closed without fallback or replay. */
export function knotAITransport(env: KnotAIEnv) {
  const token = env.EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY;
  const base = knotGatewayBase(env);
  if (!token || !base) return null;
  return { provider: 'rork' as const, token, model: 'openai/gpt-4o',
    chatURL: `${base}/v2/vercel/v1/chat/completions`, responsesURL: `${base}/v2/vercel/v1/responses`, messagesURL: `${base}/v2/vercel/v1/messages` };
}
