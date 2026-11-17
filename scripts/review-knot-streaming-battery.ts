// Read-only, local evidence review. No network, execution, token reads or task replay.
// Usage: bun scripts/review-knot-streaming-battery.ts battery-<UTC timestamp> [--session <exact observed owned session UUID>]
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createHash } from 'node:crypto';
const name = process.argv[2];
if (!/^battery-[0-9TZ-]+$/.test(name ?? '')) throw new Error('invalid_battery_name');
const directory = join(tmpdir(), 'knot-acceptance-uf26aun6d49w1tsjsm2u9', name);
const load = (path: string): any => JSON.parse(readFileSync(join(directory, path), 'utf8'));
const hash = (value: Uint8Array) => createHash('sha256').update(value).digest('hex');
const extra = process.argv.slice(3);
if (extra.length && (extra.length !== 2 || extra[0] !== '--session' || !/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(extra[1] ?? ''))) throw new Error('explicit_owned_session_uuid_required');
const identity = { accountID: 'e00a9064-5f85-40bb-9f44-8bd60f90d24a', workspaceID: 'whisper-e00a9064-5f85-40bb-9f44-8bd60f90d24a', sessionID: extra[1] ?? 'b07b1d7d-a49a-4d3b-bd84-7bab81cca227' };
const results = load('results.json') as any[];
const facts = (detail: any) => Object.fromEntries(['reason', 'check', 'programID', 'programSHA256', 'sliceIndex', 'sliceCount', 'finishReason', 'contentBytes', 'attempt', 'attempts', 'tokenLimit', 'deadlineMs', 'elapsedMs', 'promptBytes', 'promptSections', 'transportAttempt', 'transportOutcome', 'transportCallCount', 'transportElapsedMs', 'transportFirstTokenMs', 'transportChunkCount', 'transportMaxIdleMs', 'transportTimeoutKind', 'transportStreaming', 'programBytes', 'authoringResponses', 'authoringElapsedMs', 'authoringBytesPerSecond', 'authoringBasePromptBytes', 'authoringPromptTargetExceeded', 'programByteCeiling', 'budgetBytesPerSecond', 'marginPermille', 'authoringBudgetMs', 'completionReserveMs', 'turnBudgetMs'].filter(key => detail?.[key] !== undefined).map(key => [key, detail[key]]));
const report = results.map(result => {
  if (result.accountID !== identity.accountID || result.workspaceID !== identity.workspaceID) throw new Error('battery_identity_mismatch');
  const events = load(result.key + '/events.json');
  const activities = [...(events.activities ?? [])].sort((a: any, b: any) => a.sequence - b.sequence);
  const records = events.records ?? [];
  // Conversation summaries deliberately omit executor Events. Read each exact
  // proposal's retained Event response; absence must not masquerade as no Event.
  const executorEvents = records.flatMap((record: any) => {
    const proposalID = record.spec?.id;
    if (!/^[a-f0-9-]{36}$/.test(proposalID ?? '') || record.taskID !== result.requestID || record.sourceMessageID !== result.sourceMessageID || record.spec.conversationID !== result.conversationID) throw new Error('event_record_identity_mismatch');
    const scoped = load(result.key + '/' + proposalID + '-events.json');
    if (!Array.isArray(scoped.events) || !scoped.records?.some((item: any) => item.spec?.id === proposalID && item.taskID === result.requestID && item.sourceMessageID === result.sourceMessageID && item.spec.conversationID === result.conversationID)) throw new Error('scoped_event_identity_mismatch');
    if (scoped.events.some((event: any) => event.proposalID !== proposalID)) throw new Error('executor_event_identity_mismatch');
    return scoped.events;
  }).sort((a: any, b: any) => a.sequence - b.sequence);
  const contentReviews = (events.documents ?? []).map((document: any) => {
    const captured = (result.documents ?? []).find((item: any) => item.id === document.id);
    if (!captured || captured.sha256 !== document.sha256 || captured.size !== document.size || captured.proposalID !== document.proposalID) throw new Error('content_review_capture_mismatch');
    const review = document.contentReview;
    return { deliveryID: document.id, finalSHA256: document.sha256, status: review?.status ?? 'absent', scope: review?.scope,
      finalHashMatches: review ? review.finalSHA256 === document.sha256 : false,
      byteFidelity: document.byteFidelity ?? null, contentQuality: document.contentQuality ?? null,
      attempts: (review?.contentCheckAttempts ?? []).map((attempt: any) => ({ attempt: attempt.attempt, model: attempt.model, durationMs: attempt.durationMs, outcome: attempt.outcome, finishReason: attempt.finishReason })),
      scopeLimit: 'Recorded request/source coverage verdict, not an independent factual, nutrition/safety or native-interaction acceptance.' };
  });
  let computation: unknown;
  const failures: unknown[] = [];
  const workLogReceipts: unknown[] = [];
  for (const execution of result.executions ?? []) {
    const stem = result.key + '/' + execution.proposalID;
    const receipt = load(stem + '-result.json');
    if (receipt.sessionID !== identity.sessionID || receipt.proposalID !== execution.proposalID || receipt.conversationID !== result.conversationID) throw new Error('receipt_identity_mismatch');
    if (receipt.status === 'failed') {
      // Inspect retained text only. Never execute or evaluate a proposed command.
      const proposal = load(stem + '-proposal.json');
      if (proposal.id !== execution.proposalID || proposal.taskID !== result.requestID || proposal.sourceMessageID !== result.sourceMessageID || proposal.conversationID !== result.conversationID) throw new Error('failed_proposal_identity_mismatch');
      const command: string = proposal.command;
      const lines = command.split('\n');
      const delimiter = /^command -p python3 -I - <<'([A-Z_]+)'$/.exec(lines[0])?.[1];
      const traceback = [...String(receipt.stderr).matchAll(/File "<stdin>", line ([0-9]+), in <module>/g)];
      const stdinLine = traceback.length ? Number(traceback[traceback.length - 1][1]) : undefined;
      let assertion: unknown;
      if (delimiter && lines[lines.length - 1] === delimiter && stdinLine && /^AssertionError(?:\n|$)/m.test(receipt.stderr)) {
        const python = lines.slice(1, -1);
        if (stdinLine > python.length || !python[stdinLine - 1].startsWith('assert ')) throw new Error('retained_assertion_mapping_mismatch');
        const log = load(stem + '-log.json'), boundary = receipt.commandReceipt;
        if (log.session_id !== identity.sessionID || log.truncated || log.stdout_from !== 0 || log.stderr_from !== 0 || boundary?.proposal_id !== execution.proposalID || boundary?.session_id !== identity.sessionID) throw new Error('failed_log_identity_or_coverage_mismatch');
        const outputs = [[boundary.stdout_start, boundary.stdout_end, log.stdout, receipt.stdout], [boundary.stderr_start, boundary.stderr_end, log.stderr, receipt.stderr]] as const;
        for (const [start, end, retained, expected] of outputs) {
          const bytes = Buffer.from(retained, 'utf8');
          if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start < 0 || end < start || end > bytes.length || !bytes.subarray(start, end).equals(Buffer.from(expected, 'utf8'))) throw new Error('failed_log_boundary_or_receipt_mismatch');
        }
        if (!receipt.terminationConfirmed || !receipt.outputComplete || receipt.truncated || boundary.exit_code !== receipt.exitCode) throw new Error('failed_receipt_incomplete');
        assertion = { stdinLine, predicate: python[stdinLine - 1], commandBytes: Buffer.byteLength(command), commandSHA256: hash(Buffer.from(command)), logReceiptMatch: true,
          nearbyLines: python.slice(Math.max(0, stdinLine - 3), stdinLine + 2).map((text: string, index: number) => ({ line: Math.max(0, stdinLine - 3) + index + 1, text })),
          diagnosisScope: 'Exact assertion located in retained command; no conjunct values inferred and no execution replayed.' };
      }
      failures.push({ proposalID: receipt.proposalID, exitCode: receipt.exitCode, stderr: receipt.stderr, ...(assertion ? { assertion } : {}) });
    }
    if (execution.operation !== 'work') continue;
    const proposal = load(stem + '-proposal.json'), log = load(stem + '-log.json');
    const boundary = receipt.commandReceipt;
    if (proposal.id !== execution.proposalID || proposal.conversationID !== result.conversationID || proposal.taskID !== result.requestID || proposal.sourceMessageID !== result.sourceMessageID || log.session_id !== identity.sessionID || log.truncated || log.stdout_from !== 0 || log.stderr_from !== 0 || boundary?.proposal_id !== execution.proposalID || boundary?.session_id !== identity.sessionID) throw new Error('log_identity_or_coverage_mismatch');
    const stdout = Buffer.from(log.stdout, 'utf8'), stderr = Buffer.from(log.stderr, 'utf8');
    for (const [start, end, bytes] of [[boundary.stdout_start, boundary.stdout_end, stdout], [boundary.stderr_start, boundary.stderr_end, stderr]] as const) {
      if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start < 0 || end < start || end > bytes.length) throw new Error('log_boundary_mismatch');
    }
    const observed = stdout.subarray(boundary.stdout_start, boundary.stdout_end);
    const observedError = stderr.subarray(boundary.stderr_start, boundary.stderr_end);
    if (!observed.equals(Buffer.from(receipt.stdout)) || !observedError.equals(Buffer.from(receipt.stderr)) || !receipt.terminationConfirmed || !receipt.outputComplete || receipt.truncated || boundary.exit_code !== receipt.exitCode) throw new Error('log_receipt_mismatch');
    workLogReceipts.push({ proposalID: proposal.id, status: receipt.status, exitCode: receipt.exitCode, stage: proposal.documentInvocation?.stage ?? null, logReceiptMatch: true, commandBytes: Buffer.byteLength(proposal.command), commandSHA256: hash(Buffer.from(proposal.command)), stdoutBytes: observed.length, stdoutSHA256: hash(observed), stderrBytes: observedError.length, startedAt: boundary.started_at, endedAt: boundary.observed_finished_at });
    if (result.key === 'prime-sum' && receipt.exitCode === 0) computation = { logReceiptMatch: true, stdoutBytes: observed.length, stdoutSHA256: hash(observed), stdout: receipt.stdout, startedAt: boundary.started_at, endedAt: boundary.observed_finished_at, elapsedMs: receipt.durationMs, nativeCardObserved: false };
  }
  return { key: result.key, taskID: result.taskID, conversationID: result.conversationID, sourceMessageID: result.sourceMessageID, startedAt: result.startedAt, endedAt: result.endedAt, elapsedMs: result.elapsedMs, completed: result.completed, workIncomplete: result.workIncomplete, issue: result.issue, documents: result.documents, stopConfirmed: result.stopConfirmed, recordCount: records.length, activityCount: activities.length,
    contentReviews, workLogReceipts,
    turnEconomics: activities.filter((row: any) => row.kind === 'turn_economics').map((row: any) => ({ sequence: row.sequence, ...facts(row.detail) })),
    fidelityObservations: executorEvents.filter((event: any) => ['document_fidelity_verified', 'document_content_quality'].includes(event.kind)),
    styleObservations: executorEvents.filter((event: any) => event.kind === 'document_style_evidence'),
    contentCheckAttempts: executorEvents.filter((event: any) => event.kind === 'document_content_check_attempt'),
    visualObservations: executorEvents.filter((event: any) => ['document_visual_blocked', 'document_visual_reviewed', 'document_visual_qualified'].includes(event.kind)),
    authoring: activities.filter((row: any) => ['document_program_sealed', 'document_program_retry', 'document_work_unavailable', 'tool_request_rejected'].includes(row.kind) || row.kind === 'model_transport_outcome' && row.detail?.stage === 'document_authoring').map((row: any) => ({ kind: row.kind, sequence: row.sequence, recordedAt: row.recordedAt, ...facts(row.detail) })), failures, ...(computation ? { computation } : {}) };
});
const output = { battery: name, reviewedAt: new Date().toISOString(), readOnly: true, ...identity, evidence: report, endToEndAcceptance: 'Not established by this local evidence review; content, visual/gameplay and signed-Release native acceptance must be assessed separately' };
writeFileSync(join(directory, 'streaming-review.json'), JSON.stringify(output, null, 2), { mode: 0o600 });
console.log(JSON.stringify(output, null, 2));
