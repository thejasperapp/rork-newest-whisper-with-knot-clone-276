import { ChevronRight, NotebookPen, Video, LayoutGrid, type LucideIcon } from "lucide-react";
import { MeetingActivityShell } from "./MeetingActivityShell";

/** Only real, available meeting tools are listed; no placeholder Google features. */
export function MeetingActivities({ onClose, onRecording, onNotes, onLayout, tools = [] }: { onClose: () => void; onRecording?: () => void; onNotes?: () => void; onLayout: () => void; tools?: { title: string; hint: string; icon: LucideIcon; action: () => void }[] }): JSX.Element {
  const rows = [
    ...(onRecording ? [{ title: "Recording", hint: "Record meetings for on-demand viewing", icon: Video, action: onRecording }] : []),
    ...(onNotes ? [{ title: "Jasper sidekick", hint: "Ask about this meeting and read its transcript", icon: NotebookPen, action: onNotes }] : []),
    { title: "Meeting layout", hint: "Choose how people appear on your stage", icon: LayoutGrid, action: onLayout },
    ...tools,
  ];
  return <MeetingActivityShell title="Tools" onClose={onClose}>
    <div className="space-y-2">{rows.map(({ title, hint, icon: Icon, action }) => <button key={title} type="button" onClick={action} className="group flex min-h-20 w-full items-center gap-3 rounded-[22px] bg-muted/60 px-3 py-3 text-left transition-colors hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
      <span className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-muted"><Icon className={title === "Recording" ? "h-5 w-5 text-[#F22659]" : "h-5 w-5"} /></span>
      <span className="min-w-0 flex-1"><span className="block text-sm font-semibold">{title}</span><span className="mt-1 block text-xs leading-relaxed text-muted-foreground">{hint}</span></span><ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
    </button>)}</div>
    <p className="pt-3 text-xs leading-relaxed text-muted-foreground">Tools stay beside the conversation. Starting a recording always asks everyone for permission.</p>
  </MeetingActivityShell>;
}
