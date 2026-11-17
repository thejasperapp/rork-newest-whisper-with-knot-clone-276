import { useEffect, useRef, useState, type HTMLAttributes, type ReactNode } from "react";
import { Anchor } from "@radix-ui/react-popover";
import { MoreHorizontal } from "lucide-react";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import type { MessageReaction } from "@/hooks/useMessageReactions";
import { cn } from "@/lib/utils";
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog";

export interface MessageAction { label: string; icon?: ReactNode; run: () => void | Promise<void>; destructive?: boolean; confirmation?: { title: string; detail: string } }

/** One accessible press/right-click menu shared by direct and group messages. */
export function MessageActions({ children, className, mine, reactions, onReaction, actions, disabled, insetControls, ...props }: HTMLAttributes<HTMLDivElement> & {
  mine: boolean; reactions: MessageReaction[]; onReaction: (emoji: string) => void; actions: MessageAction[]; disabled?: boolean; insetControls?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [confirm, setConfirm] = useState<MessageAction | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout>>();
  const origin = useRef({ x: 0, y: 0 });
  const held = useRef(false);
  const actionFocus = useRef(false);
  const cancel = () => { clearTimeout(timer.current); };
  useEffect(() => () => clearTimeout(timer.current), []);
  return <><Popover open={open} onOpenChange={setOpen}>
    <Anchor asChild><div {...props} className={cn("group/message relative", className)}
      onContextMenu={event => { if (!disabled) { event.preventDefault(); setOpen(true); } }}
      onPointerDown={event => {
        held.current = false;
        if (disabled || event.pointerType === "mouse" || (event.target as HTMLElement).closest("button,input,textarea")) return;
        origin.current = { x: event.clientX, y: event.clientY };
        timer.current = setTimeout(() => { held.current = true; setOpen(true); }, 450);
      }}
      onPointerMove={event => { if (Math.hypot(event.clientX - origin.current.x, event.clientY - origin.current.y) > 8) cancel(); }}
      onPointerUp={cancel} onPointerCancel={cancel}
      onClickCapture={event => { if (held.current) { event.preventDefault(); event.stopPropagation(); held.current = false; } }}>
      {children}
      {reactions.length > 0 && <div className="flex flex-wrap gap-1 pt-0.5" aria-label="Message reactions">{reactions.map(row => <button key={row.emoji} type="button" aria-pressed={row.mine} aria-label={`${row.emoji}, ${row.reaction_count} reactions${row.mine ? ", including yours" : ""}`} onClick={event => { event.stopPropagation(); onReaction(row.emoji); }} className={cn("min-h-8 rounded-full border bg-background px-2 text-sm shadow-sm", row.mine ? "border-blue-400/60 bg-blue-100/50 dark:bg-blue-950/50" : "border-border")}>
        {row.emoji} <span className="text-xs tabular-nums">{row.reaction_count}</span>
      </button>)}</div>}
      {!disabled && <PopoverTrigger asChild><button type="button" aria-label="Message actions" className={cn("absolute top-0 flex h-11 w-8 items-center justify-center rounded-full text-muted-foreground opacity-60 hover:bg-secondary focus-visible:opacity-100 sm:opacity-0 sm:group-hover/message:opacity-100", insetControls ? mine ? "left-0" : "right-0" : mine ? "-left-8" : "-right-8")}><MoreHorizontal className="h-4 w-4" /></button></PopoverTrigger>}
    </div></Anchor>
    <PopoverContent side="top" align={mine ? "end" : "start"} sideOffset={8} collisionPadding={12} className="max-h-[min(70dvh,var(--radix-popover-content-available-height))] w-[272px] overflow-y-auto rounded-[24px] border-border bg-background/95 p-2 shadow-xl backdrop-blur-xl" onCloseAutoFocus={event => { if (actionFocus.current) { event.preventDefault(); actionFocus.current = false; } }} onClick={event => event.stopPropagation()}>
      <div className="mb-1 flex justify-between border-b border-border pb-2" aria-label="Choose a reaction">{["❤️", "😂", "🔥", "👏", "😮", "😢"].map(emoji => <button key={emoji} type="button" aria-label={`React ${emoji}`} aria-pressed={reactions.some(row => row.emoji === emoji && row.mine)} className="flex h-11 w-10 items-center justify-center rounded-full text-[23px] hover:bg-secondary aria-pressed:bg-secondary" onClick={() => { setOpen(false); onReaction(emoji); }}>{emoji}</button>)}</div>
      {actions.map(action => <button key={action.label} type="button" className={cn("chat-attachment-action", action.destructive && "text-destructive")} onClick={() => { actionFocus.current = true; setOpen(false); if (action.confirmation) setConfirm(action); else void action.run(); }}>{action.icon}<span>{action.label}</span></button>)}
    </PopoverContent>
  </Popover>
  <AlertDialog open={!!confirm} onOpenChange={value => { if (!value) setConfirm(null); }}><AlertDialogContent><AlertDialogHeader><AlertDialogTitle>{confirm?.confirmation?.title}</AlertDialogTitle><AlertDialogDescription>{confirm?.confirmation?.detail}</AlertDialogDescription></AlertDialogHeader><AlertDialogFooter><AlertDialogCancel>Cancel</AlertDialogCancel><AlertDialogAction onClick={() => { if (confirm) void confirm.run(); setConfirm(null); }}>{confirm?.label}</AlertDialogAction></AlertDialogFooter></AlertDialogContent></AlertDialog>
  </>;
}
