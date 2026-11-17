import { useEffect, useRef, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { backupRecording } from "@/lib/recordingCloud";
import { listRecordings } from "@/lib/meetingRecordingStorage";
import { useChatOperationGuard } from "@/hooks/useChatOperationGuard";
import { Button } from "./ui/button";

/** A user-requested batch never grants recording permission or deletes original media. */
export function NotebookRecordingBackup({ owner }: { owner: string }): JSX.Element {
  const begin = useChatOperationGuard(owner, "recording-backup-batch");
  const client = useQueryClient();
  const controller = useRef<AbortController | null>(null);
  const [progress, setProgress] = useState<string>("");
  const [issues, setIssues] = useState<string[]>([]);
  useEffect(() => () => controller.current?.abort(), []);
  const backup = useMutation({ networkMode: "always", mutationFn: async () => {
    const check = begin(), abort = new AbortController(); controller.current = abort;
    setIssues([]); let done = 0;
    try {
      const records = await listRecordings(owner); check();
      const eligible = records.filter((record) => record.storageConsent && record.status !== "recording");
      const skipped = records.length - eligible.length;
      for (const record of eligible) {
        check(); abort.signal.throwIfAborted();
        try {
          await backupRecording(record, abort.signal, check, (fraction) => setProgress(`${done + 1} of ${eligible.length} · ${Math.round(fraction * 100)}%`));
          check(); ++done;
        } catch (error) {
          check(); if (abort.signal.aborted) throw error;
          setIssues((prior) => [...prior, `${record.title || "Recording"}: ${error instanceof Error ? error.message : "Backup needs attention."}`]);
        }
      }
      setProgress(`${done} backups confirmed${skipped ? ` · ${skipped} local recordings are still capturing or lack backup permission` : ""}. Local originals kept.`);
    } finally { if (controller.current === abort) controller.current = null; void client.invalidateQueries({ queryKey: ["recording-cloud", owner] }); }
  } });
  return <details className="mb-4 border-b border-border text-xs"><summary className="min-h-11 cursor-pointer py-3">Private recording backups</summary><p className="mb-3 text-muted-foreground">Back up existing recordings from this browser whose original permissions allow account storage. Keep this window open; no transcript is sent to Jasper.</p><Button variant="outline" className="mb-2 h-11 rounded-full text-xs" disabled={backup.isPending} onClick={() => backup.mutate()}>Back up permitted recordings / retry</Button>{backup.isPending && <Button variant="ghost" className="h-11" onClick={() => controller.current?.abort()}>Pause</Button>}<p role="status">{progress}</p>{backup.isError && <p role="alert" className="py-2">Backup paused. Local files are retained; reconnect and retry.</p>}{issues.map((issue, index) => <p key={index} className="py-2 text-muted-foreground">{issue}</p>)}</details>;
}
