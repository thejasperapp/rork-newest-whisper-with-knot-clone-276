// Read-only recovery after temporary acceptance evidence was lost. Never submits,
// executes, continues, captures, reviews, or cancels a task. Credentials stay private.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
const base = join(tmpdir(), 'knot-acceptance-uf26aun6d49w1tsjsm2u9');
const root = join(base, 'recovered-visible-contract-02');
const origin = 'https://uf26aun6d49w1tsjsm2u9-backend.rork.app';
const owner = 'e00a9064-5f85-40bb-9f44-8bd60f90d24a';
const conversationID = '945599ab-4390-4ae9-b38c-f2fcd12a3efd';
const safeCode = (v: unknown) => typeof v === 'string' && /^[a-zA-Z0-9_:-]{1,100}$/.test(v) ? v : undefined;
const safeID = (v: unknown) => typeof v === 'string' && /^[a-f0-9-]{36}$/.test(v) ? v : undefined;
const safeNumber = (v: unknown) => typeof v === 'number' && Number.isFinite(v) ? v : undefined;
function fact(value: unknown, code: string): asserts value { if (!value) throw new Error(code); }
function eventSummary(row: any) {
  const detail = row.detail ?? row;
  return { kind: safeCode(row.kind), proposalID: safeID(row.proposalID), taskID: safeID(row.taskID), sourceMessageID: safeID(row.sourceMessageID), recordedAt: row.recordedAt,
    stage: safeCode(detail.stage), phase: safeCode(detail.selectionPhase), reason: safeCode(detail.reason), status: safeNumber(detail.status),
    turnElapsedMs: safeNumber(detail.turnElapsedMs), elapsedMs: safeNumber(detail.elapsedMs),
    check: detail.check ? { verdict: safeCode(detail.check.verdict), issue: safeCode(detail.check.issue), sourceProposalID: safeID(detail.check.sourceProposalID), observations: detail.check.observations?.length, attempts: detail.check.contentCheckAttempts?.map((attempt: any) => ({ outcome: safeCode(attempt.outcome), reason: safeCode(attempt.reason), failureStage: safeCode(attempt.failureStage), validationCode: safeCode(attempt.validationCode), itemIndex: safeNumber(attempt.itemIndex) })), requestedItems: detail.check.requestedItems?.length, findings: detail.check.findings?.map((finding: any) => ({ kind: safeCode(finding.kind), item: String(finding.item).slice(0, 100), detail: String(finding.detail).slice(0, 200), repair: String(finding.repair).slice(0, 180) })) } : undefined };
}
async function main() {
  const local = process.argv[2] === '--local-only';
  fact(local || process.argv[2] === '--read-only', 'read_only_flag_required');
  mkdirSync(root, { recursive: true, mode: 0o700 });
  let accessToken: string | undefined;
  if (!local) {
    const account = JSON.parse(readFileSync(join(base, 'account.json'), 'utf8'));
    fact(account.accountID === owner && account.projectRef === 'uryyyegnbtlmyhqlgndy', 'exact_account_required');
    accessToken = account.accessToken;
  }
  async function events(proposalID?: string): Promise<any> {
    const file = join(root, conversationID + (proposalID ? '-' + proposalID : '') + '-events.json');
    if (local) return JSON.parse(readFileSync(file, 'utf8'));
    const response = await fetch(origin + '/knot/shell/events', { method: 'POST', redirect: 'error', headers: { 'X-Whisper-Authorization': 'Bearer ' + accessToken, 'Content-Type': 'application/json' }, body: JSON.stringify({ bot: 'main', conversationID, ...(proposalID ? { proposalID } : {}) }), signal: AbortSignal.timeout(30000) });
    fact(response.ok, 'owned_read_http_' + response.status);
    const value = await response.json();
    writeFileSync(file, JSON.stringify(value), { mode: 0o600 });
    return value;
  }
  const all = await events();
  const records = [];
  for (const row of all.records ?? []) {
    const proposalID = safeID(row.id ?? row.spec?.id); fact(proposalID, 'owned_proposal_required');
    const perProposal = await events(proposalID);
    records.push({ proposalID, taskID: safeID(row.taskID), sourceMessageID: safeID(row.sourceMessageID), state: safeCode(row.state), operation: safeCode(row.operation), stage: safeCode(row.spec?.documentInvocation?.stage),
      result: row.result ? { status: safeCode(row.result.status), exitCode: safeNumber(row.result.exitCode), terminationConfirmed: row.result.terminationConfirmed === true, outputComplete: row.receiptOutputComplete === true, truncated: row.receiptTruncated === true } : undefined,
      events: (perProposal.events ?? []).map(eventSummary) });
  }
  const observation = { observedAt: new Date().toISOString(), conversationID, records, capturedDocuments: (all.documents ?? []).length, activities: (all.activities ?? []).map(eventSummary), originalOrderedStreamRecovered: false };
  writeFileSync(join(root, 'redacted-observation.json'), JSON.stringify(observation, null, 2), { mode: 0o600 });
  console.log(JSON.stringify({ readOnly: true, local, newTasks: 0, providerCalls: 0, observation }, null, 2));
}
main().catch(error => { console.error(JSON.stringify({ status: 'unconfirmed', reason: error instanceof Error && /^[a-z0-9_]+$/.test(error.message) ? error.message : 'recovery_unavailable', credentialsPrinted: false })); process.exitCode = 2; });
