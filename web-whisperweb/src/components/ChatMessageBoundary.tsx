import { Component, type ReactNode } from "react";

/** A malformed legacy attachment must not take the whole conversation down. */
export class ChatMessageBoundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  state = { failed: false };
  static getDerivedStateFromError(): { failed: boolean } { return { failed: true }; }
  render(): ReactNode {
    return this.state.failed ? <div role="status" className="rounded-2xl border border-border bg-secondary p-4 text-sm text-foreground">This attachment couldn't be displayed. The rest of your conversation is still available.</div> : this.props.children;
  }
}
