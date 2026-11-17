import { dispatchKnotActor, memoryReadCommand, proposeKnotShell, readKnotShellResult, type KnotShellEnv, type ShellEvidence, type ShellWorkflow } from './knot-shell';
import type { KnotBot } from './knot-agent';

/** The same owned executor, one fixed fresh read, no preloaded file snapshot.
 * Conversational turns on either client never receive an executable task card.
 * This route cannot run agent-authored code, skills, writes or old continuations.
 * Exact dispatch is attempted once; all following operations observe or cancel. */
export async function readConversationMemory(env: KnotShellEnv, owner: string, bot: KnotBot, conversationID: string,
  workflow: ShellWorkflow, signal: AbortSignal, budgetMs: number): Promise<ShellEvidence | null> {
  if (!workflow.conversationMemoryOnly || workflow.parentID || workflow.commands !== 0 || signal.aborted || budgetMs < 1000) return null;
  const bounded = AbortSignal.any([signal, AbortSignal.timeout(Math.min(20000, budgetMs))]);
  let proposalID: string | undefined, finished = false;
  let cancellation: Promise<void> | undefined;
  const cancel = (): Promise<void> => {
    if (!proposalID) return Promise.resolve();
    return cancellation ??= dispatchKnotActor(env, owner, 'cancel', { bot, conversationID, proposalID }, AbortSignal.timeout(5000))
      .then(async response => { await response.body?.cancel(); }).catch(() => {});
  };
  const aborted = () => { void cancel(); };
  bounded.addEventListener('abort', aborted, { once: true });
  try {
    if (bounded.aborted) return null;
    // Preparation itself dispatches nothing. Bound its read-only binding and
    // inert review creation too. If interrupted before its identity returns,
    // any saved review expires unexecuted; it is never recovered or dispatched.
    const proposal = await proposeKnotShell(env, owner, bot, conversationID,
      { tool: 'session_input', title: 'Read workspace memory for this conversation', command: memoryReadCommand, timeoutMs: 15000 }, workflow, bounded);
    proposalID = proposal.id;
    if (bounded.aborted || proposal.command !== memoryReadCommand) return null;
    const response = await dispatchKnotActor(env, owner, 'execute', { bot, conversationID, proposalID,
      executionVersion: 'knot_shell_automatic_v1', command: proposal.command, timeoutMs: proposal.timeoutMs }, bounded);
    await response.body?.cancel();
    if (!response.ok || bounded.aborted) return null;
    while (!bounded.aborted) {
      const receipt = await readKnotShellResult(env, owner, bot, conversationID, proposalID, bounded);
      if (receipt) {
        finished = true;
        return receipt.workflow?.conversationMemoryOnly && receipt.workflow.rootID === workflow.rootID && receipt.reviewedCommand === memoryReadCommand &&
          receipt.status === 'completed' && receipt.exitCode === 0 && receipt.outputComplete && !receipt.truncated && !receipt.contextTruncated &&
          receipt.workflow.memoryRead && receipt.sessionID ? receipt : null;
      }
      await new Promise<void>(resolve => {
        const done = () => { clearTimeout(timer); bounded.removeEventListener('abort', done); resolve(); };
        const timer = setTimeout(done, 350);
        bounded.addEventListener('abort', done, { once: true });
        if (bounded.aborted) done();
      });
    }
    return null;
  } catch { return null; }
  finally {
    bounded.removeEventListener('abort', aborted);
    if (!finished) await cancel();
  }
}
