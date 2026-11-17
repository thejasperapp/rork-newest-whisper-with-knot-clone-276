/** Runaway protection, not an ordinary task allowance. Keep every projection,
 * admission and Events clamp on this one ceiling. Infrastructure has receipts
 * but does not spend work commands. Unknown operations always meter. */
export const shellCommandLimit = 10000;
export function shellOperationPlumbing(operation: string | undefined): boolean {
  return ['memory_read', 'memory_write', 'skill_index', 'skill_read', 'communication_read', 'workspace_inventory', 'recovery_read'].includes(operation ?? '');
}
export function shellOperationCost(operation: string | undefined): 0 | 1 {
  return shellOperationPlumbing(operation) ? 0 : 1;
}
export function shellWorkAccounting(operation: string | undefined, commands: number | undefined, version?: 'work_v1') {
  return { accounting: version ?? 'legacy_includes_plumbing', plumbing: shellOperationPlumbing(operation), ...(version ? { workCost: shellOperationCost(operation) } : {}), workCommands: commands, commandLimit: shellCommandLimit };
}
export const remainingShellCommands = (commands: number): number => Math.max(0, shellCommandLimit - commands);
