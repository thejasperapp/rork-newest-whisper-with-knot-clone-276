import { Avatar } from "@/components/Avatar";

/** Only render identities supplied by a real RSVP or per-recipient read receipt. */
export function ParticipantStack({ people, label }: { people: { id: string; username: string; avatar?: string | null }[]; label: string }) {
  const unique = people.filter((p, index) => people.findIndex(other => other.id.toLowerCase() === p.id.toLowerCase()) === index);
  if (!unique.length) return null;
  return <details className="max-w-full text-xs text-muted-foreground">
    <summary className="flex min-h-11 cursor-pointer list-none items-center gap-2 rounded-lg focus-visible:outline focus-visible:outline-2" aria-label={`${label}: ${unique.map(p => p.username).join(", ")}`}>
      <span className="flex -space-x-2" aria-hidden="true">{unique.slice(0, 5).map(p => <span key={p.id} className="rounded-full border-2 border-background bg-background"><Avatar url={p.avatar ?? undefined} name={p.username} size={24} /></span>)}</span>
      <span>{label} · {unique.length}</span>
    </summary>
    <ul className="space-y-2 py-2">{unique.map(p => <li key={p.id} className="flex items-center gap-2"><Avatar url={p.avatar ?? undefined} name={p.username} size={24} /><span className="break-words">{p.username}</span></li>)}</ul>
  </details>;
}
