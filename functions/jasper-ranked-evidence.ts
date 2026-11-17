import { jasperSearchTerms } from './jasper-meeting-rules';
type Passage = { id: string; meeting_id: string; text: string; username: string; spoken_at: string; offset?: number };
/** Bounded lexical ranking with correction and adjacent context; never claims an exhaustive answer. */
export function rankJasperPassages<T extends Passage>(input: T[], question: string, scanning: boolean, budget: { characters: number; passages: number } = { characters: 24000, passages: 160 }): { rows: (T & { offset: number })[]; excerpted: boolean } {
  const chronological = [...input].sort((a, b) => a.spoken_at.localeCompare(b.spoken_at) || a.id.localeCompare(b.id));
  const chunks = chronological.flatMap((row) => {
    const parts: (T & { offset: number })[] = [];
    for (let offset = 0; offset < row.text.length; offset += 1100) parts.push({ ...row, text: row.text.slice(offset, offset + 1100), offset });
    return parts;
  });
  const excerpted = chunks.length > budget.passages || chunks.reduce((sum, row) => sum + row.text.length, 0) > budget.characters;
  if (!excerpted || scanning) return { rows: chunks, excerpted };
  const terms = jasperSearchTerms(question);
  const corrections = /\b(actually|correction|corrected|instead|not anymore|revised|to clarify|i meant|no longer|rather than)\b/i;
  const counts = new Map<string, number>();
  const keys = chunks.map((r) => `${r.meeting_id}:${r.text.toLowerCase().replace(/\s+/g, ' ').trim()}`);
  keys.forEach((key) => counts.set(key, (counts.get(key) ?? 0) + 1));
  const scores = chunks.map((row, index) => {
    const text = `${row.username} ${row.text}`.toLowerCase();
    const matching = terms.reduce((sum, term) => sum + (text.includes(term) ? 4 : 0), 0);
    const correction = corrections.test(row.text) ? 8 : 0;
    const commitment = /\b(promise|will|agreed|follow up|next step|deadline|decision)\b/i.test(row.text) ? 2 : 0;
    return (matching + correction + commitment) / Math.sqrt(counts.get(keys[index]) ?? 1);
  });
  const ranked = chunks.map((row, i) => {
    const neighbors = [i - 1, i + 1].filter((n) => n >= 0 && n < chunks.length && chunks[n].meeting_id === row.meeting_id);
    return { row, score: Math.max(scores[i], ...neighbors.map((n) => scores[n] * 0.8)), i };
  }).sort((a, b) => b.score - a.score || b.row.spoken_at.localeCompare(a.row.spoken_at) || a.i - b.i);
  return { rows: ranked.map((r) => r.row), excerpted };
}
