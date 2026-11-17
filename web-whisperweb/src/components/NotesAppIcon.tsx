import { cn } from "@/lib/utils";

/** Supplied Notes artwork follows the app's appearance; adjacent text names the action. */
export function NotesAppIcon({ className }: { className?: string }) {
  return (
    <span aria-hidden="true" className={cn("inline-block h-10 w-10 shrink-0 overflow-hidden rounded-[11px]", className)}>
      <img src="/notes-app-light-20260926-v1.png" alt="" width={1024} height={1024} draggable={false} className="block h-full w-full object-contain dark:hidden" />
      <img src="/notes-app-dark-20260926-v8.png" alt="" width={1024} height={1024} draggable={false} className="hidden h-full w-full object-contain dark:block" />
    </span>
  );
}
