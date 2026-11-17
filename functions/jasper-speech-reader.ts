type SpeechCursor = { id: string; spoken_at: string };

/** Keyset traversal avoids offset shifts when live or recovered speech is inserted. */
export async function readJasperSpeech<T extends SpeechCursor>(read: (params: Record<string, string>) => Promise<T[]>, filters: Record<string, string>): Promise<T[]> {
  const rows = new Map<string, T>();
  let cursor: SpeechCursor | undefined;
  for (let pageIndex = 0; pageIndex <= 10; pageIndex++) {
    const page = await read({ ...filters, order: 'spoken_at.desc,id.desc', limit: '200', ...(cursor ? { and: `(or(spoken_at.lt.${cursor.spoken_at},and(spoken_at.eq.${cursor.spoken_at},id.lt.${cursor.id})))` } : {}) });
    for (const row of page) rows.set(row.id, row);
    if (rows.size > 2000) throw new Error('narrow_search');
    if (page.length < 200) return [...rows.values()];
    const next = page[page.length - 1];
    if (!/^[0-9a-f-]{36}$/i.test(next.id) || !/^\d{4}-\d{2}-\d{2}T[\d:.+Z-]+$/.test(next.spoken_at) || (cursor?.id === next.id && cursor.spoken_at === next.spoken_at)) throw new Error('meeting_read_failed');
    cursor = next;
  }
  throw new Error('narrow_search');
}
