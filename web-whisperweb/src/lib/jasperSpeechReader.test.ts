import { describe, expect, it, vi } from 'vitest';
import { readJasperSpeech } from '../../../functions/jasper-speech-reader';
import { jasperRetrievalTerms } from '../../../functions/jasper-meeting-rules';
const row = (number: number) => ({ id: `00000000-0000-4000-8000-${String(number).padStart(12, '0')}`, spoken_at: '2026-09-13T12:00:00+00:00', text: 'We will ship on Thursday.' });
describe('saved meeting evidence traversal', () => {
  it('passes a paraphrased question through without dropping the answer', async () => {
    const terms = jasperRetrievalTerms('What is the deadline?', true, false);
    const filters: Record<string, string> = { meeting_id: 'eq.selected-meeting' };
    if (terms.length) filters.or = `(${terms.map((term) => `text.ilike.*${term}*`).join(',')})`;
    const read = vi.fn().mockResolvedValue([row(1)]);
    expect((await readJasperSpeech<ReturnType<typeof row>>(read, filters))[0].text).toBe('We will ship on Thursday.');
    expect(read.mock.calls[0][0]).not.toHaveProperty('or');
    expect(read.mock.calls[0][0].meeting_id).toBe('eq.selected-meeting');
  });
  it('uses the timestamp and ID cursor, deduplicating backfilled speech', async () => {
    const first = Array.from({ length: 200 }, (_, index) => row(400 - index));
    const read = vi.fn().mockResolvedValueOnce(first).mockResolvedValueOnce([row(201), row(200)]);
    const result = await readJasperSpeech(read, { meeting_id: 'eq.selected-meeting' });
    expect(result).toHaveLength(201);
    expect(read.mock.calls[1][0].and).toContain(`id.lt.${row(201).id}`);
    expect(read.mock.calls[1][0]).not.toHaveProperty('offset');
  });
  it('fails boundedly if the database does not advance its cursor', async () => {
    const first = Array.from({ length: 200 }, (_, index) => row(400 - index));
    await expect(readJasperSpeech(vi.fn().mockResolvedValue(first), {})).rejects.toThrow('meeting_read_failed');
  });
});
