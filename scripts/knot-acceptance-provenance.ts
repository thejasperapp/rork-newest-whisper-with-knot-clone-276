// Read-only acceptance evidence validation. This never submits or recovers work.
import { createHash } from 'node:crypto';

type Data = Record<string, any>;
export type AcceptanceOwner = { accountID: string; workspaceID: string };
export type AcceptanceTurn = { conversationID: string; requestID: string; sourceMessageID: string };
const digest = (stdout: string, stderr: string) => createHash('sha256').update(JSON.stringify([stdout, stderr])).digest('hex');
const installed = (command: unknown): command is string => typeof command === 'string' && /^cat \/opt\/knot-skills\/(?:[a-zA-Z0-9_-]+\/)+SKILL\.md$/.exec(command)?.[0] === command;
const complete = (result: Data) => result.status === 'completed' && result.exitCode === 0 && result.terminationConfirmed === true && result.outputComplete === true && result.truncated === false && result.contextTruncated !== true && typeof result.stdout === 'string' && !!result.stdout.trim() && typeof result.stderr === 'string';
export function assertAcceptanceIdentity(proposal: Data, result: Data, turn: AcceptanceTurn): void {
  if (proposal.bot !== 'main' || proposal.conversationID !== turn.conversationID || proposal.taskID !== turn.requestID || proposal.sourceMessageID !== turn.sourceMessageID || !/^[a-f0-9-]{36}$/.test(proposal.id) || result.proposalID !== proposal.id || result.bot !== 'main' || result.conversationID !== turn.conversationID) throw new Error('execution_identity_mismatch');
}
type Original = { sessionID: string; command: string; stdout: string; stderr: string; sha256: string; observedAt: string };
/** Only validated original executions enter this map. Cached data cannot seed or
 * chain provenance. A known completed prior read may be explicitly imported from
 * this same dedicated account's retained evidence, never adopted as new work. */
export class AcceptanceSkillProvenance {
  private readonly originals = new Map<string, Original>();
  constructor(private readonly owner: AcceptanceOwner) {
    if (owner.workspaceID !== 'whisper-' + owner.accountID) throw new Error('acceptance_workspace_mismatch');
  }
  remember(proposal: Data, result: Data, turn: AcceptanceTurn): void {
    assertAcceptanceIdentity(proposal, result, turn);
    if (!installed(proposal.command) || result.cachedData) return;
    const receipt = result.commandReceipt, provider = result.providerReceipt;
    const validRange = (a: unknown, b: unknown) => Number.isSafeInteger(a) && Number.isSafeInteger(b) && Number(a) >= 0 && Number(b) >= Number(a);
    if (!complete(result) || typeof result.sessionID !== 'string' || !result.sessionID || !receipt || receipt.source !== 'harness_shell_boundaries_v1' || receipt.session_id !== result.sessionID || receipt.proposal_id !== proposal.id || receipt.exit_code !== 0 || receipt.background_jobs !== false || !validRange(receipt.stdout_start, receipt.stdout_end) || !validRange(receipt.stderr_start, receipt.stderr_end) || typeof receipt.started_at !== 'string' || typeof receipt.observed_finished_at !== 'string' || !Number.isFinite(Date.parse(receipt.started_at)) || !Number.isFinite(Date.parse(receipt.observed_finished_at)) || Date.parse(receipt.observed_finished_at) < Date.parse(receipt.started_at) || !provider || provider.session_id !== result.sessionID || provider.user_id !== this.owner.workspaceID || provider.output_complete !== true || provider.output_late_bytes !== 0) throw new Error('original_skill_provenance_unconfirmed');
    const original = { sessionID: result.sessionID, command: proposal.command, stdout: result.stdout, stderr: result.stderr, sha256: digest(result.stdout, result.stderr), observedAt: receipt.observed_finished_at };
    const prior = this.originals.get(proposal.id);
    if (prior && JSON.stringify(prior) !== JSON.stringify(original)) throw new Error('original_skill_provenance_changed');
    this.originals.set(proposal.id, original);
  }
  acceptCache(proposal: Data, result: Data, turn: AcceptanceTurn): boolean {
    assertAcceptanceIdentity(proposal, result, turn);
    if (!result.cachedData) return false;
    const cache = result.cachedData, original = this.originals.get(cache.sourceProposalID);
    if (!installed(proposal.command) || !complete(result) || !original || cache.source !== 'session_skill_cache_v1' || cache.newExecution !== false || result.commandReceipt !== undefined || result.providerReceipt !== undefined || result.sessionID !== original.sessionID || proposal.command !== original.command || cache.observedAt !== original.observedAt || cache.sha256 !== original.sha256 || digest(result.stdout, result.stderr) !== original.sha256 || result.stdout !== original.stdout || result.stderr !== original.stderr) throw new Error('cached_skill_provenance_unconfirmed');
    return true;
  }
}
