import { knotSourceBuildSHA256 } from './knot-source-build';

type CallIdentity = {
  requestID: string; taskID: string; servingRequestID: string | null;
  phase: 'classification' | 'selection' | 'answer'; model: string;
};
// Only fixed metadata fields are retained. Never prompts, output, arbitrary
// headers, error bodies, reasoning, account IDs or credentials.
const label = (value: unknown): string | null => typeof value === 'string' && /^[a-zA-Z0-9][a-zA-Z0-9_.:/;-]{0,199}$/.test(value) ? value : null;
export class KnotModelCallTrace {
  private readonly callID = crypto.randomUUID();
  private readonly started = Date.now();
  private headersMs: number | null = null;
  private firstContentMs: number | null = null;
  private status: number | null = null;
  private returnedModel: string | null = null;
  private responseID: string | null = null;
  private reportedProvider: string | null = null;
  private readonly responseHeaders: Record<string, string> = {};
  private finished = false;
  constructor(private readonly identity: CallIdentity, private readonly url: string) {}
  response(response: Response): void {
    this.headersMs = Date.now() - this.started; this.status = response.status;
    for (const name of ['x-request-id', 'x-vercel-id', 'x-ai-gateway-request-id', 'x-vercel-ai-gateway-request-id', 'x-vercel-ai-provider', 'x-ai-gateway-provider', 'openai-processing-ms']) {
      const value = label(response.headers.get(name));
      if (value) this.responseHeaders[name] = value;
    }
    this.reportedProvider = this.responseHeaders['x-vercel-ai-provider'] ?? this.responseHeaders['x-ai-gateway-provider'] ?? null;
  }
  payload(value: unknown, content = false): void {
    if (value && typeof value === 'object') {
      const data = value as Record<string, unknown>;
      this.returnedModel = label(data.model) ?? this.returnedModel;
      this.responseID = label(data.id) ?? this.responseID;
      this.reportedProvider = label(data.provider) ?? this.reportedProvider;
    }
    if (content && this.firstContentMs === null) this.firstContentMs = Date.now() - this.started;
  }
  finish(outcome: 'completed' | 'failed' | 'aborted'): void {
    if (this.finished) return;
    this.finished = true;
    console.info('knot_model_call', JSON.stringify({
      ...this.identity, requestedModel: this.identity.model, model: undefined,
      callID: this.callID, workerBuildSHA256: knotSourceBuildSHA256,
      transport: 'rork', endpointHost: new URL(this.url).hostname,
      endpointPath: new URL(this.url).pathname, reportedProvider: this.reportedProvider,
      returnedModel: this.returnedModel, responseID: this.responseID,
      responseHeaders: this.responseHeaders, httpStatus: this.status,
      startedAt: new Date(this.started).toISOString(), endedAt: new Date().toISOString(),
      headersMs: this.headersMs, firstContentMs: this.firstContentMs,
      elapsedMs: Date.now() - this.started, outcome,
      timingSource: 'worker_wall_clock', upstreamInternalTiming: 'unavailable_unless_response_header_supplied',
    }));
  }
}
export async function tracedKnotModelJSON(identity: CallIdentity, url: string, init: RequestInit, read: (response: Response) => Promise<unknown>): Promise<unknown> {
  const trace = new KnotModelCallTrace(identity, url);
  try {
    const response = await fetch(url, init); trace.response(response);
    const result = await read(response); trace.payload(result); trace.finish('completed');
    return result;
  } catch (error) {
    trace.finish(init.signal?.aborted ? 'aborted' : 'failed'); throw error;
  }
}
