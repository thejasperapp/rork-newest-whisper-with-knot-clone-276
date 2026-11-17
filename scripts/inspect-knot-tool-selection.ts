// Operator-authenticated, fixed synthetic schema observation only.
// No member context, actor admission, browser run or remote mutation.
// Run: rork env run -- bun scripts/inspect-knot-tool-selection.ts
const operator = process.env.BROADCAST_SECRET;
if (!operator) throw new Error('Existing operator credential is unavailable.');
const forcedShell = process.argv.includes('--forced-shell');
// Both hosts are fixed aliases returned by this project's deployment tooling.
const deploymentAlias = process.argv.includes('--deployment-alias');
const origin = deploymentAlias ? 'https://newest-whisper-with-knot-clone-589qc2i-backend.rork.app' : 'https://uf26aun6d49w1tsjsm2u9-backend.rork.app';
const response = await fetch(origin + '/admin/knot-text-transport?check=' + (forcedShell ? 'forced-shell' : 'browser-tools'), {
  method: 'POST', headers: { 'X-Whisper-Operator': operator }, signal: AbortSignal.timeout(30000), redirect: 'error',
});
if (!response.ok) { await response.body?.cancel(); throw new Error('Synthetic observation failed with HTTP ' + response.status); }
const result = await response.json() as Record<string, unknown>;
console.log(JSON.stringify({ check: forcedShell ? 'deployed_forced_shell_selection' : 'deployed_synthetic_tool_selection', deploymentAlias, observedAt: new Date().toISOString(),
  provider: ['openai', 'rork', 'unavailable'].includes(String(result.provider)) ? result.provider : 'unknown',
  configured: result.configured === true, completed: result.completed === true,
  status: typeof result.status === 'number' ? result.status : null,
  toolCount: typeof result.toolCount === 'number' ? result.toolCount : null,
  finish: ['tool_calls', 'stop', 'length', 'content_filter'].includes(String(result.finish)) ? result.finish : 'other',
  ...(['tool_finish_reason_invalid', 'incomplete_tool_selection', 'tool_call_count_invalid', 'tool_envelope_invalid', 'tool_not_advertised', 'invalid_tool_arguments'].includes(String(result.validationReason)) ? { validationReason: result.validationReason } : {}),
  remoteMutationPerformed: false, authenticatedAppAcceptance: false,
}));
if (result.completed !== true) process.exitCode = 1;
export {};
