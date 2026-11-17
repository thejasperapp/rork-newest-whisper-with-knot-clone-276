import { DocumentProgramRejected } from './knot-document-program';
import { documentShape } from './knot-document-diagnostics';
import type { PrivateDocumentResponse } from './knot-document-replay';
import { documentAuthoringResponseByteLimit } from './knot-document-limits';
import { KnotModelTransportExhausted, type KnotModelTransportFacts } from './knot-model-transport';

export type KnotAuthorTransportVitals = {
  transportCallCount: number; transportElapsedMs: number; transportFirstTokenMs?: number;
  transportChunkCount: number; transportMaxIdleMs: number;
  transportTimeoutKind?: 'first_token' | 'idle' | 'owned_deadline'; transportStreaming: true;
};
export class KnotAuthorPolicyBoundary extends Error {
  constructor(readonly reason: 'model_refusal' | 'provider_content_filter') { super(reason); }
}
function invalid(branch: string, fieldPath: string, expectedShape: string, receivedShape: string, check: 'provider_stream' | 'provider_choices' | 'provider_finish' | 'provider_tools' | 'provider_empty' = 'provider_stream', finishReason?: string): never {
  throw new DocumentProgramRejected('document_program_invalid', { check, branch, fieldPath, expectedShape, receivedShape, unexplained: false, ...(finishReason ? { finishReason } : {}) });
}
const encoder = new TextEncoder();
// Wire overhead is distinct from generated content: thousands of small SSE
// envelopes must fit without raising the existing reassembled response ceiling.
const wireLimit = 4 * 1024 * 1024, frameLimit = documentAuthoringResponseByteLimit * 2 + 4096;
type Envelope = { choices: [{ finish_reason: 'stop'; message: { content: string } }]; usage?: { prompt_tokens?: number; completion_tokens?: number } };

/** Clean EOF may omit the provider's terminal markers only when the entire
 * content is a complete JSON object. The caller must still validate its exact
 * response contract before any slice is committed. No timeout/error salvage.
 * Content deltas measure idle telemetry only; they never reset owned expiry. */
async function completeAuthorStream(response: Response, signal: AbortSignal, contentReceived: () => void, setReader: (reader: ReadableStreamDefaultReader<Uint8Array>) => void, privateResponse?: (value: PrivateDocumentResponse) => void): Promise<Envelope> {
  if (!response.body) invalid('stream_body', '$.body', 'readable_stream', 'null');
  if (!response.headers.get('content-type')?.toLowerCase().startsWith('text/event-stream')) {
    void response.body!.cancel().catch(() => {});
    invalid('stream_mime', '$.body', 'text_event_stream', 'other_content_type');
  }
  const reader = response.body!.getReader(); setReader(reader);
  const decoder = new TextDecoder('utf-8', { fatal: true, ignoreBOM: false });
  const decode = (bytes?: Uint8Array, stream = false): string => {
    try { return decoder.decode(bytes, { stream }); } catch { return invalid('stream_utf8', '$.stream', 'valid_utf8', 'invalid_utf8'); }
  };
  let buffer = '', pendingCR = false, wireBytes = 0, frameBytes = 0, contentBytes = 0;
  let data: string[] = [], content = '', stopped = false, done = false, complete = false;
  let usage: Envelope['usage'], finishReason: string | undefined;
  const envelope = (): Envelope => ({ choices: [{ finish_reason: 'stop', message: { content } }], ...(usage ? { usage } : {}) });
  const frame = () => {
    if (!data.length) { frameBytes = 0; return; }
    const payload = data.join('\n'); data = []; frameBytes = 0;
    if (done) invalid('stream_after_done', '$.stream', 'no_data_after_done', 'additional_frame');
    if (payload === '[DONE]') {
      // Some compatible providers omit the separate stop frame. Treat DONE as
      // a clean transport end, then require a complete JSON object below.
      done = true; return;
    }
    let value: Record<string, unknown>;
    try { value = JSON.parse(payload); } catch { return invalid('stream_frame_json', '$.stream', 'valid_json_frame', 'invalid_json'); }
    if (!value || typeof value !== 'object' || Array.isArray(value)) invalid('stream_frame_object', '$.stream', 'object', documentShape(value));
    if (value.error) invalid('stream_error_frame', '$.stream', 'successful_frame', 'provider_error_present');
    if (!Array.isArray(value.choices)) invalid('stream_choices_type', '$.choices', 'array', documentShape(value.choices), 'provider_choices');
    const choices = value.choices as unknown[];
    // OpenAI-compatible optional usage-only trailer, not generated content.
    const usageTrailer = !!value.usage && typeof value.usage === 'object' && !Array.isArray(value.usage);
    if (usageTrailer) {
      const raw = value.usage as Record<string, unknown>; usage = {};
      for (const key of ['prompt_tokens', 'completion_tokens'] as const) if (Number.isSafeInteger(raw[key]) && Number(raw[key]) >= 0 && Number(raw[key]) <= 10000000) usage[key] = Number(raw[key]);
    }
    if (choices.length === 0 && usageTrailer) return;
    if (choices.length !== 1) invalid('stream_choices_count', '$.choices', 'array(length=1)', documentShape(choices), 'provider_choices');
    const choice = choices[0] as Record<string, unknown> | null;
    if (!choice || choice.index !== 0) invalid('stream_choice_index', '$.choices[0].index', 'zero', choice ? documentShape(choice.index) + ';not_zero' : 'missing_choice', 'provider_choices');
    const delta = choice.delta as Record<string, unknown> | null;
    if (!delta || typeof delta !== 'object' || Array.isArray(delta)) invalid('stream_delta_type', '$.choices[0].delta', 'object', documentShape(delta));
    if (delta!.refusal) throw new KnotAuthorPolicyBoundary('model_refusal');
    if (choice.finish_reason === 'content_filter') throw new KnotAuthorPolicyBoundary('provider_content_filter');
    if (delta!.tool_calls !== undefined || delta!.function_call !== undefined) invalid('stream_tools', '$.choices[0].delta', 'no_tool_calls', 'tool_fields_present', 'provider_tools');
    if (delta!.role !== undefined && delta!.role !== 'assistant') invalid('stream_role', '$.choices[0].delta.role', 'assistant_or_undefined', 'other_role');
    if (delta!.content !== undefined && delta!.content !== null && typeof delta!.content !== 'string') invalid('stream_content_type', '$.choices[0].delta.content', 'string_or_null_or_undefined', documentShape(delta!.content));
    const text = typeof delta!.content === 'string' ? delta!.content : '';
    if (stopped && (text || choice.finish_reason != null || Object.keys(delta!).length !== 0)) invalid('stream_after_stop', '$.choices[0].delta', 'empty_delta_after_stop', 'additional_data');
    if (text) {
      contentBytes += encoder.encode(text).length;
      content += text;
      privateResponse?.({ envelope: { choices: [{ finish_reason: finishReason ?? null, message: { content } }] }, content, complete: false, finishReason, contentBytes });
      if (contentBytes > documentAuthoringResponseByteLimit) invalid('stream_content_capacity', '$.content', `bytes<=${documentAuthoringResponseByteLimit}`, `bytes=${contentBytes}`);
      contentReceived();
    }
    if (choice.finish_reason != null) {
      finishReason = typeof choice.finish_reason === 'string' && ['stop','length','tool_calls','content_filter','function_call','error'].includes(choice.finish_reason) ? choice.finish_reason : 'unknown';
      if (choice.finish_reason !== 'stop') invalid('stream_finish', '$.choices[0].finish_reason', 'stop', finishReason, 'provider_finish', finishReason);
      stopped = true;
    }
  };
  const consume = (text: string) => {
    if (pendingCR && text.startsWith('\n')) text = text.slice(1);
    pendingCR = text.endsWith('\r');
    buffer += text.replace(/\r\n?/g, '\n');
    let end: number;
    while ((end = buffer.indexOf('\n')) >= 0) {
      const line = buffer.slice(0, end); buffer = buffer.slice(end + 1);
      frameBytes += encoder.encode(line).length + 1;
      if (frameBytes > frameLimit) invalid('stream_frame_capacity', '$.stream', `frame_bytes<=${frameLimit}`, `frame_bytes=${frameBytes}`);
      if (line === '') frame();
      else if (line === 'data' || line.startsWith('data:')) data.push(line === 'data' ? '' : line.slice(5).replace(/^ /, ''));
      else if (!line.startsWith(':') && !/^(event|id|retry):/.test(line)) invalid('stream_line_type', '$.stream', 'sse_field_or_comment', 'unknown_line_type');
    }
    if (frameBytes + encoder.encode(buffer).length > frameLimit) invalid('stream_pending_capacity', '$.stream', `frame_bytes<=${frameLimit}`, 'frame_bytes_exceeded');
  };
  try {
    while (true) {
      signal.throwIfAborted();
      const chunk = await reader.read();
      signal.throwIfAborted();
      if (chunk.done) { consume(decode()); break; }
      wireBytes += chunk.value.byteLength;
      if (wireBytes > wireLimit) invalid('stream_wire_capacity', '$.stream', `wire_bytes<=${wireLimit}`, `wire_bytes=${wireBytes}`);
      consume(decode(chunk.value, true));
      // DONE is the provider's explicit terminal boundary. A healthy upstream
      // may keep its HTTP body open afterward; waiting for reader EOF would
      // turn an already complete response into an owned-deadline failure.
      // consume still validates every frame already received in this chunk.
      if (done) { consume(decode()); break; }
    }
    // At clean reader EOF, providers may omit the final line/blank separator.
    // Parse the exact pending field/frame through the SAME strict validators;
    // never repair JSON, infer code, ignore a refusal, or salvage a thrown read.
    if (buffer.length) consume('\n');
    if (data.length) frame();
    if (buffer.trim()) invalid('stream_eof', '$.stream', 'clean_frame_boundary', `pending_frames=${data.length};pending_chars=${buffer.length}`);
    if (!done || !stopped) {
      // Only a normal reader EOF reaches here. Explicit length/filter/refusal,
      // malformed frames, aborts and transport failures already threw above.
      let parsed: unknown;
      try { parsed = JSON.parse(content); } catch { invalid('stream_eof', '$.content', 'complete_json_object', 'incomplete_json'); }
      if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) invalid('stream_eof', '$.content', 'complete_json_object', documentShape(parsed));
    }
    if (!content.trim()) invalid('stream_empty', '$.content', 'nonblank_string', 'blank_string', 'provider_empty');
    const result = envelope();
    if (encoder.encode(JSON.stringify(result)).length > documentAuthoringResponseByteLimit) invalid('stream_envelope_capacity', '$.envelope', `bytes<=${documentAuthoringResponseByteLimit}`, `bytes=${encoder.encode(JSON.stringify(result)).length}`);
    complete = true;
    return result;
  } finally {
    privateResponse?.({ envelope: complete ? envelope() : { choices: [{ finish_reason: finishReason ?? null, message: { content } }], ...(usage ? { usage } : {}) }, content, complete, finishReason, contentBytes });
  }
}

/** AUTHOR ONLY. Zero automatic transport retries. Selection keeps its separate
 * policy. Partial content can be retained privately, never executed or resumed. */
export async function knotAuthorStreaming(options: {
  signal: AbortSignal; expiresAt: number; timeoutMs: number;
  request: (signal: AbortSignal) => Promise<Response>;
  // Pure request-budget calibration only, before attempt diagnostics/fetch.
  prepareAttempt?: (timeoutRetries: number) => void;
  observed: (facts: KnotModelTransportFacts & KnotAuthorTransportVitals) => void;
  privateResponse?: (value: PrivateDocumentResponse) => void;
}): Promise<Envelope> {
  const { signal } = options;
  // Reserve final admission time; no retry or first-content event renews this.
  const deadline = Math.min(options.expiresAt - 5000, Date.now() + options.timeoutMs);
  if (!Number.isFinite(deadline) || !Number.isFinite(options.timeoutMs) || options.timeoutMs < 1) throw new KnotModelTransportExhausted(new DOMException('Owned deadline', 'TimeoutError'));
  // A provider may reason silently before emitting the complete structured
  // file. Do not kill it at 60 seconds or treat SSE comments as file progress.
  // Only the admitted owned deadline and explicit Stop end a pending stream.
  // Retain genuine content-idle measurements for diagnostics, not cancellation.
  const timeoutRetries = 0;
  for (let attempt = 1; attempt <= 1; attempt++) {
    signal.throwIfAborted();
    if (deadline - Date.now() < 1000) throw new KnotModelTransportExhausted(new DOMException('Owned deadline', 'TimeoutError'));
    options.prepareAttempt?.(timeoutRetries);
    const started = Date.now(), controller = new AbortController(), combined = AbortSignal.any([signal, controller.signal]);
    let first: number | undefined, last = started, chunks = 0, maxIdle = 0;
    let timeoutKind: KnotAuthorTransportVitals['transportTimeoutKind'];
    let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
    const expire = (kind: NonNullable<typeof timeoutKind>) => {
      timeoutKind = Date.now() >= deadline ? 'owned_deadline' : kind;
      controller.abort(new DOMException('Author stream deadline', 'TimeoutError'));
    };
    const ownedTimer = setTimeout(() => expire('owned_deadline'), Math.max(0, deadline - started));
    const vitals = (): KnotAuthorTransportVitals => ({ transportCallCount: attempt, transportElapsedMs: Math.min(1200000, Math.max(0, Date.now() - started)), transportFirstTokenMs: first, transportChunkCount: chunks, transportMaxIdleMs: Math.min(1200000, Math.max(maxIdle, Date.now() - last)), transportTimeoutKind: timeoutKind, transportStreaming: true });
    const observe = (transportOutcome: KnotModelTransportFacts['transportOutcome'], transportDelayMs = 0, status?: number) => {
      try { options.observed({ transportAttempt: attempt, transportDelayMs, transportOutcome, status, ...vitals() }); } catch { /* Observation cannot replay a successful stream. */ }
    };
    observe('attempt');
    let removeAbort = () => {};
    try {
      const aborted = new Promise<never>((_resolve, reject) => {
        const stopped = () => reject(combined.reason);
        combined.addEventListener('abort', stopped, { once: true }); removeAbort = () => combined.removeEventListener('abort', stopped);
        if (combined.aborted) stopped();
      });
      const run = async () => {
        const response = await options.request(combined);
        if (combined.aborted) { void response.body?.cancel().catch(() => {}); combined.throwIfAborted(); }
        return completeAuthorStream(response, combined, () => {
          const now = Date.now(); maxIdle = Math.max(maxIdle, now - last); last = now;
          if (first === undefined) first = now - started;
          chunks++;
        }, value => { reader = value; }, options.privateResponse);
      };
      const result = await Promise.race([run(), aborted]);
      combined.throwIfAborted();
      observe('recovered');
      return result;
    } catch (error) {
      if (signal.aborted) { observe('ended'); signal.throwIfAborted(); }
      const status = error && typeof error === 'object' && 'status' in error && Number.isInteger(error.status) ? Number(error.status) : undefined;
      const isTimeout = error instanceof Error && ['TimeoutError', 'AbortError'].includes(error.name);
      const retryable = isTimeout || status !== undefined && status >= 500 && status <= 599;
      observe('ended', 0, status);
      if (retryable) throw new KnotModelTransportExhausted(error);
      throw error;
    } finally {
      clearTimeout(ownedTimer); removeAbort(); controller.abort();
      if (reader) { const old = reader; void old.cancel().catch(() => {}).finally(() => { try { old.releaseLock(); } catch { /* Pending read. */ } }); }
    }
  }
  throw new Error('unreachable_author_stream_attempt');
}
