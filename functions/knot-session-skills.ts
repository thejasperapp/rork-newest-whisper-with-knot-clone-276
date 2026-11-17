import type { ShellResult } from './knot-shell';

export type SessionSkillCache = { sourceProposalID: string; sessionID: string; command: string; stdout: string; stderr: string; sha256: string; observedAt: string; commandReceipt?: Record<string, unknown> };
/** Only read-only installed guides, never mutable workspace drafts or task files. */
export const installedSkillRead = (command: string): boolean => /^cat \/opt\/knot-skills\/(?:[a-zA-Z0-9_-]+\/)+SKILL\.md$/.test(command);
export function completeSessionSkill(result: ShellResult, sessionID: string): boolean {
  return result.sessionID === sessionID && result.status === 'completed' && result.terminationConfirmed && result.exitCode === 0 && result.outputComplete && !result.truncated && !result.contextTruncated && !!result.stdout.trim() && new TextEncoder().encode(result.stdout).length <= 500000;
}
export async function skillDataSHA256(stdout: string, stderr: string): Promise<string> {
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify([stdout, stderr])))), byte => byte.toString(16).padStart(2, '0')).join('');
}
export async function verifiedSessionSkill(value: SessionSkillCache, sessionID: string, command: string): Promise<boolean> {
  return value.sessionID === sessionID && value.command === command && installedSkillRead(command) && /^[a-f0-9]{64}$/.test(value.sha256) && value.sha256 === await skillDataSHA256(value.stdout, value.stderr);
}
