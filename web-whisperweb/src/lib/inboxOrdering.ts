/** Shared chronological ordering for direct, dating, and group inbox entries. */
export function orderInbox<T extends { id: string; date: string | null; unread: number }>(entries: readonly T[], sort: "recent" | "oldest" | "unread"): T[] {
  const stamp = (date: string | null): number => date ? Date.parse(date) || 0 : 0;
  return [...entries].sort((a, b) => {
    if (sort === "unread" && (a.unread > 0) !== (b.unread > 0)) return a.unread > 0 ? -1 : 1;
    const chronological = stamp(a.date) - stamp(b.date);
    return (sort === "oldest" ? chronological : -chronological) || a.id.localeCompare(b.id);
  });
}
