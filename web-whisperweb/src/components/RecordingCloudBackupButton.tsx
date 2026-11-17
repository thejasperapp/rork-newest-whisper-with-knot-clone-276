import { useEffect, useRef, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { CloudUpload } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog";
import { useChatOperationGuard } from "@/hooks/useChatOperationGuard";
import { backupRecording } from "@/lib/recordingCloud";
import type { MeetingRecording } from "@/lib/meetingRecordingModel";

/** Upload is always a separate affirmative action; enabling transcription does not authorize storage. */
export function RecordingCloudBackupButton({ record, disabled = false, resume = false }: { record: MeetingRecording; disabled?: boolean; resume?: boolean }): JSX.Element {
  const begin = useChatOperationGuard(record.ownerId, record.id);
  const queryClient = useQueryClient(); const controller = useRef<AbortController | null>(null);
  const [confirm, setConfirm] = useState<boolean>(false), [progress, setProgress] = useState<number>(0);
  const upload = useMutation({ networkMode: "always", mutationFn: async ({ check, abort, snapshot }: { check: () => void; abort: AbortController; snapshot: MeetingRecording }) => {
    check(); abort.signal.throwIfAborted();
    await backupRecording(snapshot, abort.signal, check, setProgress); check();
    toast.success("Private cloud backup confirmed. Your local recording is unchanged.");
  }, onError: (error) => toast.error(error instanceof Error ? error.message : "Backup failed. Local media is retained."), onSettled: () => { controller.current = null; void queryClient.invalidateQueries({ queryKey: ["recording-cloud", record.ownerId] }); } });
  const startUpload = (): void => {
    if (controller.current) return;
    const check = begin(); const abort = new AbortController(); controller.current = abort; setProgress(0);
    upload.mutate({ check, abort, snapshot: record });
  };
  useEffect(() => () => controller.current?.abort(), []);
  useEffect(() => { if (!upload.isPending) return; const warn = (event: BeforeUnloadEvent): void => { event.preventDefault(); event.returnValue = ""; }; window.addEventListener("beforeunload", warn); return () => window.removeEventListener("beforeunload", warn); }, [upload.isPending]);
  return <div className="space-y-2">
    <div className="flex flex-wrap items-center gap-2"><Button variant="outline" disabled={disabled || upload.isPending || !record.storageConsent || record.status === "recording" || record.transcriptionState === 'pending'} onClick={() => setConfirm(true)}><CloudUpload className="mr-2 h-4 w-4" />{upload.isPending ? `Backing up · ${Math.round(progress * 100)}%` : resume ? "Resume / finish backup" : "Save private cloud snapshot"}</Button>{upload.isPending && <Button variant="ghost" onClick={() => controller.current?.abort()}>Stop upload</Button>}</div>
    {upload.isPending && <p role="status" className="text-xs text-muted-foreground">Keep this window open. {progress >= 1 ? "Verifying both saved files…" : "Sending resumable pieces; local recording stays safe."}</p>}
    {!record.storageConsent && <p className="text-xs text-muted-foreground">Cloud backup wasn’t included in this recording’s permission. It remains on this browser.</p>}
    <AlertDialog open={confirm} onOpenChange={setConfirm}><AlertDialogContent portalContainer={document.fullscreenElement as HTMLElement | null} overlayClassName="z-[100]" className="z-[110]"><AlertDialogHeader><AlertDialogTitle>{resume ? "Resume this private backup?" : "Save a private cloud snapshot?"}</AlertDialogTitle><AlertDialogDescription>The recording, continuous audio backup, transcript and reviewed markers will be stored in your Whisper account on the existing Supabase backend. Only your account can open it through the app; it is not added to shared recaps or sent to attendees. This is a snapshot, not automatic sync. Later edits need a new backup. Cloud copies stay until you delete them, independently of local files. Storage-provider administrators can access stored data; this is not end-to-end encryption.</AlertDialogDescription></AlertDialogHeader><AlertDialogFooter><AlertDialogCancel>Keep local only</AlertDialogCancel><AlertDialogAction onClick={startUpload}>Save private backup</AlertDialogAction></AlertDialogFooter></AlertDialogContent></AlertDialog>
  </div>;
}
