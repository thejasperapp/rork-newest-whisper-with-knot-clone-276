export type CommandLedgerInput = { id: string; taskID: string; preparedAt: number; submitted: boolean; cached: boolean };
export type CommandLedgerEntry = { commandOrder?: number; commandSequence?: number; orderSource: 'persisted_input_intent' | 'persisted_cache_reuse' | 'historical_inferred' | 'not_dispatched'; newExecution: boolean; recordedAt?: string };
/** Per-task ordinal comes only from durable input/cache sequence. Preparation
 * time never moves a later-dispatched command ahead of session startup. Old
 * missing sequences are explicitly inferred, not presented as exact order. */
export function commandLedger(records: CommandLedgerInput[], events: { proposal_id: string; seq: number; recordedAt?: string }[]): Map<string, CommandLedgerEntry> {
  const sequences = new Map(events.map(event => [event.proposal_id, event.seq]));
  const dates = new Map(events.map(event => [event.proposal_id, event.recordedAt]));
  const counts = new Map<string, number>();
  const result = new Map<string, CommandLedgerEntry>();
  for (const record of [...records].sort((a,b) => (sequences.get(a.id) ?? Infinity) - (sequences.get(b.id) ?? Infinity) || a.preparedAt - b.preparedAt || a.id.localeCompare(b.id))) {
    const seq = sequences.get(record.id);
    const source = seq !== undefined ? record.cached ? 'persisted_cache_reuse' : 'persisted_input_intent' : record.submitted ? 'historical_inferred' : 'not_dispatched';
    const order = seq !== undefined ? (counts.get(record.taskID) ?? 0) + 1 : undefined;
    if (order !== undefined) counts.set(record.taskID, order);
    result.set(record.id, { ...(order !== undefined ? { commandOrder: order, commandSequence: seq } : {}), orderSource: source, newExecution: record.submitted && !record.cached, ...(dates.get(record.id) ? { recordedAt: dates.get(record.id) } : {}) });
  }
  return result;
}
