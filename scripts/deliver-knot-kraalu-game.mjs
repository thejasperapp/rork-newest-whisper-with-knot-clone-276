// Prepare a chat download of the exact captured artifact; no remote work or replay.
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createHash } from 'node:crypto';
const root = join(tmpdir(), 'knot-acceptance-uf26aun6d49w1tsjsm2u9', 'battery-2026-11-14T00-59-25-344Z');
const directory = join(root, 'battle-game');
const load = file => JSON.parse(readFileSync(join(directory, file), 'utf8'));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const sessionID = 'bc3a2c8d-5511-4a19-b974-e78cabaef213';
const sha256 = 'c1d9486a616c8476c7376fa9d6fadaa5cbdab1a4c367d72b02d703dd0b73113b';
const deliveryID = '0e213a02d8694fa2cb8736cc3c62a985d09498ce381d52a1d25aab83c085d6de';
const result = load('result.json');
if (result.requestID !== '11ad2f4c-5144-484c-9c7e-55e9ff20f2fd' || result.accountID !== 'e00a9064-5f85-40bb-9f44-8bd60f90d24a' || result.workspaceID !== 'whisper-e00a9064-5f85-40bb-9f44-8bd60f90d24a' || !result.completed || result.workIncomplete || result.executions.length !== 5) throw new Error('fresh_request_identity');
const receipts = result.executions.map(execution => {
  const id = execution.proposalID, proposal = load(id + '-proposal.json'), receipt = load(id + '-result.json'), log = load(id + '-log.json'), boundary = receipt.commandReceipt;
  if (proposal.id !== id || proposal.taskID !== result.requestID || proposal.sourceMessageID !== result.sourceMessageID || proposal.conversationID !== result.conversationID || receipt.proposalID !== id || receipt.conversationID !== result.conversationID || receipt.sessionID !== sessionID || log.session_id !== sessionID || log.stdout_from !== 0 || log.stderr_from !== 0 || log.truncated || boundary?.proposal_id !== id || boundary?.session_id !== sessionID) throw new Error('execution_identity');
  for (const stream of ['stdout', 'stderr']) {
    const bytes = Buffer.from(log[stream], 'utf8'), start = boundary[stream + '_start'], end = boundary[stream + '_end'];
    if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start < 0 || end < start || end > bytes.length || !bytes.subarray(start, end).equals(Buffer.from(receipt[stream], 'utf8'))) throw new Error('execution_log_boundaries');
  }
  if (receipt.status !== 'completed' || receipt.exitCode !== 0 || !receipt.terminationConfirmed || !receipt.outputComplete || receipt.truncated || receipt.contextTruncated || boundary.exit_code !== 0 || boundary.background_jobs !== false) throw new Error('execution_not_complete');
  return { proposalID: id, operation: execution.operation, logReceiptMatch: true, stdoutSHA256: hash(Buffer.from(receipt.stdout)), commandSHA256: hash(Buffer.from(proposal.command)), startedAt: boundary.started_at, endedAt: boundary.observed_finished_at };
});
const document = result.documents.find(item => item.id === deliveryID && item.proposalID === '10baf573-1128-4451-8550-8efc1960cdb6');
if (!document || document.sha256 !== sha256 || document.size !== 25837 || document.deliveredSHA256 !== sha256 || document.boxSHA256 !== sha256 || !document.deliveredMatches || !document.boxMatches) throw new Error('capture_download_identity');
const events = load('10baf573-1128-4451-8550-8efc1960cdb6-events.json').events;
if (!events.some(event => event.kind === 'document_captured' && event.documentID === deliveryID && event.sha256 === sha256 && event.bytes === 25837)) throw new Error('capture_event_required');
const observation = load('browser-observation/observations.json');
if (observation.artifactSHA256 !== sha256 || observation.unchangedArtifact !== true || observation.observations.length !== 2 || observation.observations.some(item => item.observationIssue || item.elapsedPlayMs < 65000 || item.errors.length || item.blockedRequests.length || !item.outcomes.some(outcome => outcome.outcome === 'VICTORY!') || !item.outcomes.some(outcome => outcome.outcome === 'DEFEATED...'))) throw new Error('browser_evidence_required');
const bytes = readFileSync(join(directory, deliveryID + '.html'));
if (bytes.length !== 25837 || hash(bytes) !== sha256) throw new Error('actual_file_identity');
mkdirSync('deliveries', { recursive: true });
const output = 'deliveries/wilds-of-kraalu-creature-battle-c1d9486a616c.html';
const preview = 'deliveries/wilds-of-kraalu-preview-c1d9486a616c.png';
function immutableCopy(path, contents) {
  if (existsSync(path)) { if (!readFileSync(path).equals(contents)) throw new Error('delivery_collision'); }
  else writeFileSync(path, contents, { flag: 'wx' });
}
immutableCopy(output, bytes);
immutableCopy(preview, readFileSync(join(directory, 'browser-observation/390-battle-start.png')));
const report = { observedAt: new Date().toISOString(), title: 'Wilds of Kraalu: Creature Battle', deliveryID, sessionID, sha256, size: bytes.length, output, preview, exactCaptureCopy: true, receipts, scope: 'Local immutable download plus real headless-browser gameplay; not signed-Release native testing.' };
writeFileSync(join(directory, 'chat-delivery-verification.json'), JSON.stringify(report, null, 2), { flag: 'wx', mode: 0o600 });
console.log(JSON.stringify(report, null, 2));
