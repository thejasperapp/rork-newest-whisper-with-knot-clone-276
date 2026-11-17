/** Nonexecuting model requests only. Never wrap actor/shell/browser mutations. */
export type KnotModelTransportFacts = { transportAttempt: number; transportDelayMs: number; transportOutcome: 'attempt' | 'retry' | 'recovered' | 'ended'; status?: number };
export class KnotModelTransportExhausted extends Error {
  constructor(readonly lastError: unknown) { super('model_transport_exhausted'); }
}
const timeout = (error: unknown) => error instanceof Error && ['TimeoutError', 'AbortError'].includes(error.name);
const statusOf = (error: unknown): number | undefined => {
  const status = error && typeof error === 'object' && 'status' in error ? error.status : undefined;
  return typeof status === 'number' && Number.isInteger(status) && status >= 100 && status <= 599 ? status : undefined;
};
function wait(delay: number, signal: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    signal.throwIfAborted();
    const stopped = () => { clearTimeout(timer); signal.removeEventListener('abort', stopped); reject(signal.reason); };
    const timer = setTimeout(() => { signal.removeEventListener('abort', stopped); resolve(); }, delay);
    signal.addEventListener('abort', stopped, { once: true });
  });
}
export async function knotModelTransport<T>(options: {
  signal: AbortSignal; expiresAt: number; timeoutMs: number;
  // File choices may use their admitted stage budget without the ordinary
  // per-attempt 60s cutoff. This never extends stage or owned expiry.
  useStageDeadline?: boolean;
  run: (signal: AbortSignal) => Promise<T>;
  observed: (facts: KnotModelTransportFacts) => void;
}): Promise<T> {
  const { signal, expiresAt } = options;
  // One immutable budget for the entire nonexecuting stage, including retries.
  const stageExpiresAt = Math.min(Date.now() + options.timeoutMs, expiresAt - 5000);
  // Observations cannot cause replay of a successful request.
  const observe = (facts: KnotModelTransportFacts) => { try { options.observed(facts); } catch { /* Non-authoritative diagnostics. */ } };
  for (let attempt = 1; attempt <= 3; attempt++) {
    signal.throwIfAborted();
    const remaining = stageExpiresAt - Date.now();
    if (!Number.isFinite(remaining) || remaining < 1 || !Number.isFinite(options.timeoutMs) || options.timeoutMs < 1) throw new KnotModelTransportExhausted(new DOMException('Owned deadline', 'TimeoutError'));
    const controller = new AbortController(), combined = AbortSignal.any([signal, controller.signal]);
    const timer = setTimeout(() => controller.abort(new DOMException('Model call deadline', 'TimeoutError')), options.useStageDeadline ? remaining : Math.min(60000, remaining));
    observe({ transportAttempt: attempt, transportDelayMs: 0, transportOutcome: 'attempt' });
    let removeAbort = () => {};
    try {
      // Race enforces the deadline even if a stalled body reader ignores abort.
      const aborted = new Promise<never>((_resolve, reject) => {
        const stopped = () => reject(combined.reason);
        combined.addEventListener('abort', stopped, { once: true });
        removeAbort = () => combined.removeEventListener('abort', stopped);
        if (combined.aborted) stopped();
      });
      const value = await Promise.race([options.run(combined), aborted]);
      signal.throwIfAborted();
      if (attempt > 1) observe({ transportAttempt: attempt, transportDelayMs: 0, transportOutcome: 'recovered' });
      return value;
    } catch (error) {
      signal.throwIfAborted();
      const status = statusOf(error), retryable = timeout(error) || status !== undefined && status >= 500;
      if (!retryable) throw error;
      const delay = attempt * 250;
      if (attempt === 3 || stageExpiresAt - Date.now() <= delay || expiresAt - Date.now() - delay < 15000) {
        observe({ transportAttempt: attempt, transportDelayMs: 0, transportOutcome: 'ended', status });
        throw new KnotModelTransportExhausted(error);
      }
      observe({ transportAttempt: attempt, transportDelayMs: delay, transportOutcome: 'retry', status });
      clearTimeout(timer);
      await wait(delay, signal);
      if (Date.now() >= stageExpiresAt || expiresAt - Date.now() < 15000) throw new KnotModelTransportExhausted(error);
    } finally { clearTimeout(timer); removeAbort(); controller.abort(); }
  }
  throw new Error('unreachable_transport_attempt');
}
