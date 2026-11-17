import { Search } from 'lucide-react';
import { Button } from './ui/button';

/** Opens the one account-bound palette mounted beside the router. */
export function WorkspaceSearchButton(): JSX.Element {
  return <Button variant="outline" className="min-h-11 gap-2 rounded-full" onClick={() => window.dispatchEvent(new Event('whisper-workspace-search'))}><Search className="h-4 w-4" />Search workspace<span className="ml-3 hidden text-xs text-muted-foreground sm:inline">⌘K / Ctrl K</span></Button>;
}
