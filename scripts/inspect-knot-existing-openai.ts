// Fixed non-personal verification of the server credential already used by Whisper's /ai/chat.
// No member authentication/data, workspace/task calls, key output or automatic retry.
// env -u EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY -u RORK_TOOLKIT_SECRET_KEY rork env run -- bun scripts/inspect-knot-existing-openai.ts
import { knotUpstreamDiagnostic } from '../functions/knot-upstream-error';
const key = process.env.OPENAI_API_KEY;
if (!key) {
  console.log(JSON.stringify({ check: 'existing_openai_stream', configured: false, completed: false }));
  process.exit(1);
}
try {
  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST', signal: AbortSignal.timeout(25000), redirect: 'error',
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: 'gpt-4o', stream: true, max_tokens: 120,
      messages: [{ role: 'user', content: 'Synthetic transport check, with no personal data. Return a brief greeting as text and empty metadata.' }],
      response_format: { type: 'json_schema', json_schema: { name: 'knot_reply', strict: true,
        schema: { type: 'object', properties: { text: { type: 'string' }, metadata: { type: 'string' } }, required: ['text', 'metadata'], additionalProperties: false } } },
    }),
  });
  if (!response.ok) {
    const diagnostic = await knotUpstreamDiagnostic(response);
    console.log(JSON.stringify({ check: 'existing_openai_stream', observedAt: new Date().toISOString(), configured: true, status: response.status, completed: false, diagnostic }));
    process.exitCode = 1;
  } else {
    const text = await response.text();
    if (text.length > 100000) throw new Error('Response limit');
    let raw = '', frames = 0, terminalFrame = false, normalFinish = false;
    for (const line of text.split('\n')) {
      if (!line.startsWith('data:')) continue;
      const data = line.slice(5).trim(); frames++;
      if (data === '[DONE]') { terminalFrame = true; break; }
      const parsed = JSON.parse(data) as { error?: unknown; choices?: { delta?: { content?: string }; finish_reason?: string }[] };
      if (parsed.error) throw new Error('Stream error');
      raw += parsed.choices?.[0]?.delta?.content ?? '';
      if (parsed.choices?.[0]?.finish_reason === 'stop') normalFinish = true;
    }
    const result = JSON.parse(raw) as { text?: unknown; metadata?: unknown };
    const validReply = typeof result.text === 'string' && !!result.text.trim() && typeof result.metadata === 'string';
    const completed = terminalFrame && normalFinish && validReply;
    console.log(JSON.stringify({ check: 'existing_openai_stream', observedAt: new Date().toISOString(), configured: true,
      status: response.status, frames, terminalFrame, normalFinish, validReply, completed }));
    if (!completed) process.exitCode = 1;
  }
} catch { console.log(JSON.stringify({ check: 'existing_openai_stream', configured: true, completed: false, category: 'transport_or_framing_failure' })); process.exitCode = 1; }
export {};
