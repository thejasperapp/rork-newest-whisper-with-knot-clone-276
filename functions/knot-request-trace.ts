import { knotSourceBuildSHA256 } from './knot-source-build';
export { knotSourceBuildSHA256 };
export type KnotRequestTrace = { requestID: string; workerBuildSHA256: string; actorBuildSHA256?: string; handler?: string };
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
export function knotRequestTrace(request: Request): KnotRequestTrace {
  const id = request.headers.get('X-Knot-Request-ID');
  return { requestID: id && uuid.test(id) ? id : crypto.randomUUID(), workerBuildSHA256: knotSourceBuildSHA256 };
}
export function knotActorTrace(request: Request): KnotRequestTrace {
  const trace = knotRequestTrace(request), worker = request.headers.get('X-Knot-Worker-Build');
  return { ...trace, workerBuildSHA256: worker && /^[a-f0-9]{64}$/.test(worker) ? worker : 'unavailable', actorBuildSHA256: knotSourceBuildSHA256, handler: knotActorHandler(request) };
}
export function knotActorHandler(request: Request): string {
  const path = new URL(request.url).pathname;
  if (path === '/documents/capture-advisory') return 'capture_advisory';
  if (path === '/documents/capture-status') return 'capture_status';
  if (path === '/documents') return 'documents_dispatch';
  if (path === '/documents/capture') return 'capture';
  if (['/status', '/events', '/receipt'].includes(path)) return path.slice(1);
  return 'actor_other';
}
// Never log arbitrary path segments, query strings, bodies, identities, auth or errors.
function safeRoute(request: Request): string {
  const path = new URL(request.url).pathname;
  if (/^\/knot\/shell\/(?:documents(?:\/capture-advisory|\/capture-status)?|status|events|execute|cancel|log|permission|capabilities)$/.test(path)) return path;
  if (path.startsWith('/knot/')) return '/knot/other';
  if (path.startsWith('/jasper-meetings/')) return '/jasper-meetings/other';
  return '/other';
}
export function traceResponse(response: Response, trace: KnotRequestTrace, actor = false): Response {
  // Preserve upgrade socket identity and don't buffer/consume streaming bodies.
  if (response.status === 101) return response;
  const headers = new Headers(response.headers);
  headers.set('X-Knot-Request-ID', trace.requestID);
  headers.set(actor ? 'X-Knot-Actor-Build' : 'X-Knot-Worker-Build', knotSourceBuildSHA256);
  if (trace.handler) headers.set('X-Knot-Handler', trace.handler);
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
}
export async function tracedKnotRequest(request: Request, actor: boolean, serve: (request: Request, trace: KnotRequestTrace) => Promise<Response>): Promise<Response> {
  const trace = actor ? knotActorTrace(request) : { requestID: crypto.randomUUID(), workerBuildSHA256: knotSourceBuildSHA256 };
  const headers = new Headers(request.headers);
  headers.set('X-Knot-Request-ID', trace.requestID);
  headers.set('X-Knot-Worker-Build', trace.workerBuildSHA256);
  const owned = new Request(request, { headers });
  const started = Date.now();
  try {
    const response = traceResponse(await serve(owned, trace), trace, actor);
    console.info('knot_request', JSON.stringify({ layer: actor ? 'actor' : 'worker', ...trace, handler: response.headers.get('X-Knot-Handler') ?? trace.handler, route: actor ? undefined : safeRoute(request), method: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'].includes(request.method) ? request.method : 'OTHER', status: response.status, durationMs: Date.now() - started }));
    return response;
  } catch (error) {
    console.error('knot_request', JSON.stringify({ layer: actor ? 'actor' : 'worker', ...trace, route: actor ? undefined : safeRoute(request), outcome: 'exception', durationMs: Date.now() - started }));
    throw error;
  }
}
