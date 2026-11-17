import { Sparkles } from 'lucide-react';
import { Button } from './ui/button';
import type { WorkspaceObjectTarget } from './WorkspaceObjectView';

/** Identity-only handoff; the destination rechecks access and asks for cloud consent. */
export function WorkspaceAskButton({ target }: { target: WorkspaceObjectTarget }): JSX.Element {
  return <Button type="button" variant="ghost" className="min-h-11 gap-2 text-xs" onClick={() => window.dispatchEvent(new CustomEvent('whisper-workspace-ask', { detail: { ...target, ask: true } }))}><Sparkles className="h-4 w-4" />Ask Jasper about this</Button>;
}
