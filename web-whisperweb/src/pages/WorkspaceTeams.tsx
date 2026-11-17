import { Link } from 'react-router-dom';
import { BusinessPlusPanel } from '@/components/BusinessPlusPanel';
import { useAuth } from '@/hooks/useAuth';

/** A discoverable door into the existing Business+ roster, not a second team system. */
export default function WorkspaceTeams(): JSX.Element {
  const { user } = useAuth();
  return <main className="mx-auto max-w-3xl space-y-6 px-4 py-7 sm:px-6">
    <header><p className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">Workspace</p><h1 className="mt-2 text-3xl font-semibold">Teams</h1><p className="mt-2 text-sm leading-6 text-muted-foreground">Set up your team through Business+. Owners can name their team, add people by exact Whisper username, and update roles here. Members can view their team without buying a separate plan.</p></header>
    <nav className="flex flex-wrap gap-4 text-sm"><Link className="inline-flex min-h-11 items-center underline" to="/work?portal=workspace">Back to Work desk</Link><Link className="inline-flex min-h-11 items-center underline" to="/meetings?portal=workspace">Meet with your team</Link></nav>
    <p className="rounded-2xl border p-4 text-sm leading-6 text-muted-foreground">Joining a team does not share your private meeting notes, recordings or Jasper conversations. Role titles describe people; only the owner manages membership.</p>
    <BusinessPlusPanel key={user?.id ?? 'signed-out'} />
  </main>;
}
