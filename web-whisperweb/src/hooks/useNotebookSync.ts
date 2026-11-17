import { useEffect, useRef } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useChatOperationGuard } from "./useChatOperationGuard";
import { protectNotebookEditor, syncNotebook } from "@/lib/notebookSync";

/** Foreground-only sync; durable local writes are the retry queue. */
export function useNotebookSync(owner: string, activeEditor: string | null) {
  const client = useQueryClient(); const guard = useChatOperationGuard(owner, "notebook-sync");
  const active = useRef<string | null>(activeEditor); active.current = activeEditor;
  const controller = useRef<AbortController | null>(null);
  const mutation = useMutation({
    mutationFn: async () => {
      const assertCurrent = guard();
      if (controller.current) return "Sync already in progress";
      const abort = new AbortController(); controller.current = abort;
      try {
        const result = await syncNotebook(owner, () => active.current, assertCurrent, abort.signal);
        assertCurrent();
        return result;
      } finally {
        if (controller.current === abort) controller.current = null;
        // Earlier notes may have been acknowledged even when a later upload fails.
        if (!abort.signal.aborted) {
          assertCurrent();
          await client.invalidateQueries({ queryKey: ["personal-notebook", owner] });
        }
      }
    },
  });
  const trigger = useRef<() => void>(() => undefined);
  trigger.current = () => { if (!controller.current && !document.hidden && navigator.onLine) mutation.mutate(); };
  useEffect(() => activeEditor ? protectNotebookEditor(owner, activeEditor) : undefined, [owner, activeEditor]);
  useEffect(() => {
    const run = (): void => trigger.current();
    run(); const timer = setInterval(run, 20000);
    window.addEventListener("online", run); window.addEventListener("focus", run);
    let queued: ReturnType<typeof setTimeout> | undefined;
    const changed = (): void => { clearTimeout(queued); queued = setTimeout(run, 1000); };
    window.addEventListener("notebook-saved", changed);
    return () => { clearTimeout(queued); window.removeEventListener("notebook-saved", changed); clearInterval(timer); controller.current?.abort(); controller.current = null; window.removeEventListener("online", run); window.removeEventListener("focus", run); };
  }, [owner]);
  useEffect(() => { if (!activeEditor) trigger.current(); }, [activeEditor]);
  return mutation;
}
