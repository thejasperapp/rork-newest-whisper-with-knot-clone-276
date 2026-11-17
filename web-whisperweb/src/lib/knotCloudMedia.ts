// Dedicated Knot media calls use Rork AI Cloud only, never the shared legacy
// /ai/chat or /ai/image routes. Browser authentication is delegated by Rork's
// runtime; do not embed or forward a managed/server/provider credential here.

type MediaTurn = {
  assertCurrent: () => void;
  signal: AbortSignal;
};

function cloudOrigin(): string {
  const configured = (
    (import.meta.env.EXPO_PUBLIC_TOOLKIT_URL as string | undefined) ??
    (import.meta.env.VITE_TOOLKIT_URL as string | undefined) ??
    'https://toolkit.rork.com'
  ).trim();
  const url = new URL(configured);
  if (url.origin !== 'https://toolkit.rork.com' || url.username || url.password ||
      url.pathname !== '/' || url.search || url.hash) {
    throw new Error('Knot Cloud configuration unavailable');
  }
  return url.origin;
}

async function cloudJSON(
  path: '/v2/vercel/v1/chat/completions' | '/v2/vercel/v3/ai/image-model',
  body: Record<string, unknown>,
  turn: MediaTurn,
  timeoutMs: number,
  extraHeaders: Record<string, string> = {},
): Promise<unknown> {
  // The caller's captured guard checks account, visible turn and current AI
  // consent. Recheck before transmission and after every network/body await.
  turn.assertCurrent();
  turn.signal.throwIfAborted();
  const response = await fetch(`${cloudOrigin()}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...extraHeaders },
    body: JSON.stringify(body),
    signal: AbortSignal.any([turn.signal, AbortSignal.timeout(timeoutMs)]),
    redirect: 'error',
    credentials: 'omit',
    cache: 'no-store',
  });
  turn.assertCurrent();
  turn.signal.throwIfAborted();
  if (!response.ok) {
    await response.body?.cancel();
    throw new Error('Knot Cloud request rejected');
  }
  const result: unknown = await response.json();
  turn.assertCurrent();
  turn.signal.throwIfAborted();
  return result;
}

export async function knotConverseWithImage(
  history: { role: 'user' | 'assistant'; content: string }[],
  imageUrl: string,
  caption: string,
  turn: MediaTurn & { system: string },
): Promise<string> {
  const result = await cloudJSON('/v2/vercel/v1/chat/completions', {
    // Same Cloud vision model as native Knot; provider prefix is a model ID,
    // not permission to contact the provider's API directly.
    model: 'openai/gpt-4o',
    max_tokens: 600,
    messages: [
      { role: 'system', content: turn.system },
      ...history.slice(0, -1),
      { role: 'user', content: [
        { type: 'text', text: caption.trim() || 'What do you see in this image?' },
        { type: 'image_url', image_url: { url: imageUrl } },
      ] },
    ],
  }, turn, 30000) as {
    choices?: { finish_reason?: string; message?: { content?: unknown } }[];
  } | null;
  const choice = result?.choices?.[0];
  const content = choice?.message?.content;
  if ((choice?.finish_reason && choice.finish_reason !== 'stop') ||
      typeof content !== 'string' || !content.trim()) {
    throw new Error('Knot Cloud image analysis incomplete');
  }
  return content.trim();
}

export async function knotImagine(
  prompt: string,
  assertCurrent: () => void,
  signal: AbortSignal,
): Promise<string | null> {
  assertCurrent();
  signal.throwIfAborted();
  if (!prompt.trim()) return null;
  // Retain native Knot's primary image model, confirmed in the live catalogue.
  // One Cloud request only; rejection never triggers another transport/model.
  const model = 'openai/gpt-image-2';
  const result = await cloudJSON('/v2/vercel/v3/ai/image-model', {
    model, prompt: prompt.trim(), n: 1, size: '1024x1024', providerOptions: {},
  }, { assertCurrent, signal }, 120000, {
    'ai-gateway-protocol-version': '0.0.1',
    'ai-image-model-specification-version': '4',
    'ai-model-id': model,
  }) as { images?: unknown[] } | null;
  const image = result?.images?.[0];
  return typeof image === 'string' && image.length > 0
    ? `data:image/png;base64,${image}`
    : null;
}
