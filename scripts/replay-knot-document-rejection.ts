// Local-only diagnostic replay. Never calls a provider, shell, capture or API.
// Usage: bun scripts/replay-knot-document-rejection.ts --replay <private-export.json>
// --self-check uses explicitly synthetic data, NOT historical acceptance.
import { readFileSync, statSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { documentResponseSlice, replayDocumentResponse, rejectedDocumentRecordByteLimit, type DocumentReplayContext, type PrivateDocumentResponse } from '../functions/knot-document-replay';
import { documentDiagnostic, safeDocumentDiagnostic } from '../functions/knot-document-diagnostics';
import { knotAuthorStreaming } from '../functions/knot-author-streaming';
const hash = (value: string) => createHash('sha256').update(value).digest('hex');
const bytes = (value: string) => new TextEncoder().encode(value).length;
function requireFact(value: unknown, cause: string): asserts value { if (!value) throw new Error(cause); }
const context: DocumentReplayContext = { version: 'document_author_replay_v1', preparation: { stage: 'source', interpreter: 'python3', path: 'deliverables/offline-source.html', authoring: 'author' }, prefix: '', index: 0, structured: true, localPatch: false, targets: [] };
function documentBody(length: number) {
  const d = { title: 'Synthetic transport check', subtitle: '', sections: [{ id: 'section-one', title: 'Synthetic section', blocks: [{ kind: 'paragraph', text: 'x' }] }] };
  const base = JSON.stringify(d); d.sections[0].blocks[0].text += 'x'.repeat(length - bytes(base));
  const body = JSON.stringify(d); requireFact(bytes(body) === length, 'synthetic_size'); return body;
}
async function stream(content: string) {
  const frames: string[] = [];
  for (let i = 0; i < content.length; i += 113) frames.push('data: ' + JSON.stringify({ choices: [{ index: 0, delta: { content: content.slice(i, i + 113) }, finish_reason: null }] }) + '\r\n\r\n');
  frames.push('data: ' + JSON.stringify({ choices: [{ index: 0, delta: {}, finish_reason: 'stop' }] }) + '\n\n');
  frames.push('data: ' + JSON.stringify({ choices: [], usage: { prompt_tokens: 12, completion_tokens: 34 } }) + '\n\n', 'data: [DONE]\n\n');
  const wire = new TextEncoder().encode(frames.join(''));
  let requests = 0, offset = 0, captured: PrivateDocumentResponse | undefined;
  const result = await knotAuthorStreaming({ signal: new AbortController().signal, expiresAt: Date.now() + 30000, timeoutMs: 10000, observed: () => {}, privateResponse: value => { captured = value; }, request: async () => {
    requests++;
    return new Response(new ReadableStream<Uint8Array>({ pull(controller) { if (offset >= wire.length) { controller.close(); return; } controller.enqueue(wire.slice(offset, offset + 137)); offset += 137; } }), { headers: { 'Content-Type': 'text/event-stream' } });
  } });
  requireFact(requests === 1 && captured?.complete && captured.content === content && result.choices[0].message.content === content && result.usage?.completion_tokens === 34, 'synthetic_stream_roundtrip');
  return result;
}
async function selfCheck() {
  const sizes = [15248, 15975, 16062, 16384, 21975, 32768];
  for (const size of sizes) {
    const result = await stream(documentBody(size));
    const invocation = replayDocumentResponse(result, context);
    requireFact(invocation.code.includes('KNOT_RESIDENT_CONTENT_V1'), 'synthetic_adapter');
  }
  await stream('é'.repeat(10000)); // Byte boundaries split multibyte UTF-8 too.
  const malformed = { title: 'Synthetic', subtitle: '', sections: [{ id: 'one', title: 'One', blocks: [{ kind: 'table', columns: ['A', 'B'], rows: [['one']] }] }] };
  let diagnostic;
  try { documentResponseSlice(await stream(JSON.stringify(malformed)), context); }
  catch (error) { diagnostic = documentDiagnostic(error, 'offline_replay'); }
  requireFact(diagnostic?.branch === 'table_row_width' && diagnostic.fieldPath === '$.sections[0].blocks[0].rows[0]' && diagnostic.expectedShape === 'array(length=2)' && diagnostic.receivedShape === 'array(length=1)' && !diagnostic.unexplained, 'synthetic_precise_diagnostic');
  // Exercise rejection paths through the actual production transport, not a
  // second parser. Every request below is an injected in-memory Response.
  const frame = (value: unknown) => 'data: ' + JSON.stringify(value) + '\n\n';
  const partialContent = 'Synthetic partial response—not executable';
  const prefix = frame({ choices: [{ index: 0, delta: { content: partialContent }, finish_reason: null }] });
  const stop = frame({ choices: [{ index: 0, delta: {}, finish_reason: 'stop' }] });
  const done = 'data: [DONE]\n\n';
  const encode = (wire: string) => new TextEncoder().encode(wire);
  const usage = frame({ choices: [], usage: { prompt_tokens: 12, completion_tokens: 34 } });
  const negativeCases: { branch: string; wire: Uint8Array }[] = [
    { branch: 'stream_frame_json', wire: encode(prefix + 'data: {broken}\n\n') },
    { branch: 'stream_done_order', wire: encode(prefix + done) },
    { branch: 'stream_after_done', wire: encode(prefix + stop + done + prefix) },
    { branch: 'stream_after_stop', wire: encode(prefix + stop + prefix) },
    { branch: 'stream_eof', wire: encode(prefix + stop) },
    { branch: 'stream_utf8', wire: new Uint8Array([...encode(prefix), 0xff, 10, 10]) },
    { branch: 'stream_finish', wire: encode(prefix + frame({ choices: [{ index: 0, delta: {}, finish_reason: 'length' }] }) + done) },
    // A previous valid usage trailer must not authorize a later empty choice
    // frame without its own valid object-shaped usage payload.
    { branch: 'stream_choices_count', wire: encode(prefix + usage + frame({ choices: [] }) + stop + done) },
    { branch: 'stream_choices_count', wire: encode(prefix + frame({ choices: [], usage: [] }) + stop + done) },
  ];
  for (const scenario of negativeCases) {
    let requests = 0, captured: PrivateDocumentResponse | undefined, rejected: unknown;
    const outcomes: string[] = [], completeness: boolean[] = [];
    try {
      await knotAuthorStreaming({ signal: new AbortController().signal, expiresAt: Date.now() + 30000, timeoutMs: 10000,
        observed: value => { outcomes.push(value.transportOutcome); },
        privateResponse: value => { captured = value; completeness.push(value.complete); },
        request: async () => {
          requests++;
          // Deliver the valid prefix separately so the invalid-UTF8 case also
          // verifies retention of content received before the malformed chunk.
          const boundary = encode(prefix).length;
          return new Response(new ReadableStream<Uint8Array>({ start(controller) {
            controller.enqueue(scenario.wire.slice(0, boundary));
            controller.enqueue(scenario.wire.slice(boundary));
            controller.close();
          } }), { headers: { 'Content-Type': 'text/event-stream' } });
        },
      });
    } catch (error) { rejected = error; }
    requireFact(rejected !== undefined && documentDiagnostic(rejected, 'offline_replay').branch === scenario.branch, 'synthetic_stream_rejection_branch');
    requireFact(requests === 1 && outcomes.join(',') === 'attempt,ended', 'synthetic_stream_terminal_without_retry');
    requireFact(captured?.content === partialContent && captured.complete === false && completeness.length >= 2 && completeness.every(value => value === false), 'synthetic_partial_never_complete');
  }
  let calls = 0, transportThrew = false;
  try { await knotAuthorStreaming({ signal: new AbortController().signal, expiresAt: Date.now() + 30000, timeoutMs: 10000, observed: () => {}, request: async () => { calls++; throw Object.assign(new Error('synthetic'), { status: 503 }); } }); }
  catch { transportThrew = true; }
  requireFact(transportThrew && calls === 1, 'synthetic_zero_transport_retry');
  console.log(JSON.stringify({ mode: 'synthetic_supplemental_only', success: true, exactContentByteSizes: sizes, multiByteUTF8: true, usagePreserved: true, preciseDiagnostic: diagnostic, negativeStreamCases: negativeCases.map(value => value.branch), partialResponsesNeverComplete: true, terminalTransportFailure: true, automaticTransportRetries: 0, historicalActualBodyAcceptance: 'blocked_original_bodies_not_retained', providerCalls: 0, commandsExecuted: 0 }));
}
function replay(path: string) {
  requireFact(statSync(path).isFile() && statSync(path).size <= rejectedDocumentRecordByteLimit, 'private_record_size');
  const record = JSON.parse(readFileSync(path, 'utf8')) as { version: string; response: PrivateDocumentResponse; context: DocumentReplayContext; rejectedBodySHA256: string; schemaHash: string; schema: unknown; diagnostic: unknown };
  requireFact(record.version === 'document_author_rejection_v1' && record.context?.version === 'document_author_replay_v1' && typeof record.response?.content === 'string', 'private_record_version');
  requireFact(hash(record.response.content) === record.rejectedBodySHA256 && hash(JSON.stringify(record.schema)) === record.schemaHash, 'private_record_hash_binding');
  const original = safeDocumentDiagnostic(record.diagnostic); requireFact(original, 'private_record_diagnostic');
  const observed = record.response.envelope as { choices?: { message?: { content?: unknown } }[] };
  requireFact(observed?.choices?.[0]?.message?.content === record.response.content, 'private_record_envelope_binding');
  if (!record.response.complete) {
    console.log(JSON.stringify({ mode: 'retained_partial_body', replayed: false, bodyHashVerified: true, originalDiagnostic: original, reason: 'incomplete_stream_is_not_a_complete_response', providerCalls: 0, commandsExecuted: 0 })); return;
  }
  let current;
  try { replayDocumentResponse(record.response.envelope, record.context); }
  catch (error) { current = documentDiagnostic(error, 'offline_replay'); }
  const diagnosticMatches = !!current && JSON.stringify(current) === JSON.stringify(original);
  console.log(JSON.stringify({ mode: 'retained_actual_body', bodyHashVerified: true, schemaHashVerified: true, rejectedAgain: !!current, diagnosticMatches, originalDiagnostic: original, replayDiagnostic: current, providerCalls: 0, commandsExecuted: 0 }));
  requireFact(diagnosticMatches, 'retained_replay_diagnostic_mismatch');
}
const [mode, path] = process.argv.slice(2);
try {
  if (mode === '--self-check' && !path) await selfCheck();
  else if (mode === '--replay' && path && process.argv.length === 4) replay(path);
  else throw new Error('explicit_local_mode_required');
} catch (error) { console.error(error instanceof Error && /^[a-z_]+$/.test(error.message) ? error.message : 'local_replay_failed'); process.exitCode = 1; }
