import { useEffect, useState } from "react";
import { Circle, Library, Loader2, Monitor, ShieldCheck, Square } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { MeetingRecordingSession, type RecordingSessionState } from "@/lib/meetingRecordingSession";
import { recordingTime } from "@/lib/meetingRecordingModel";
import { MeetingActivityShell } from "./MeetingActivityShell";

/** Recording is a meeting action, never a playback overlay on the live video. */
export function MeetingRecordingControls({ session, state, isHost, open, onOpenChange, asPanel = false, onBack, meetingId }: {
  session: MeetingRecordingSession;
  state: RecordingSessionState;
  isHost: boolean;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  asPanel?: boolean;
  onBack?: () => void;
  meetingId?: string | null;
}): JSX.Element {
  const [video, setVideo] = useState<boolean>(true);
  const [transcribe, setTranscribe] = useState<boolean>(false);
  const [archive, setArchive] = useState<boolean>(false);
  const [confirmStop, setConfirmStop] = useState<boolean>(false);
  const remote = state.remote;
  const recording = state.update?.state === "recording";
  const starting = state.update?.state === "starting";
  const saving = state.update?.state === "saving";
  const waiting = !!state.request && !recording && !starting && !saving;
  const notice = state.update?.error ?? state.notice ?? (state.update?.state === "error" ? "Recording could not be finalized. Check this meeting’s recordings for retained parts." : null);
  const consentOpen = !!remote && remote.accepted === null;
  const unsupported = typeof MediaRecorder === "undefined" || typeof AudioWorkletNode === "undefined";
  const libraryURL = `/notebook?portal=workspace${meetingId ? `&meeting=${encodeURIComponent(meetingId)}` : ""}${state.update ? `&recording=${state.update.recordingId}` : ""}`;
  // Above MeetingHostSurface (z-60), and inside the browser's fullscreen root.
  const dialogProps = {
    portalContainer: document.fullscreenElement as HTMLElement | null,
    overlayClassName: "z-[100] bg-black/40 pointer-events-auto",
    className: "pointer-events-auto z-[101] max-h-[85dvh] w-[calc(100%-2rem)] overflow-y-auto rounded-2xl text-foreground sm:rounded-2xl",
  };
  useEffect(() => { if (!recording) setConfirmStop(false); }, [recording]);
  useEffect(() => { if (recording) onOpenChange(false); }, [recording, onOpenChange]);

  const status = <div className="pointer-events-auto flex max-w-full flex-wrap items-center justify-center gap-2">
      {((isHost && (!asPanel || recording || starting || saving || waiting)) || remote || notice) && <Button type="button" variant="ghost" className="min-h-11 gap-2 rounded-full border border-white/15 bg-[#303134] px-4 text-white shadow-sm hover:bg-[#3c4043] hover:text-white" onClick={() => onOpenChange(true)}>
        {starting || saving || waiting ? <Loader2 className="h-4 w-4 animate-spin" /> : <Circle className={`h-3.5 w-3.5 ${recording || remote?.active ? "fill-rose-500 text-rose-500" : "text-white/75"}`} />}
        {recording ? `REC · ${recordingTime(state.update?.seconds ?? 0)}` : remote?.active ? "Recording in progress" : starting ? "Starting recording…" : saving ? "Saving recording…" : waiting ? `Waiting for permission · ${state.approved}/${state.required}` : notice ? "Recording · attention needed" : remote ? "Recording permission" : "Record meeting"}
      </Button>}
      {recording && <Button type="button" variant="ghost" className="min-h-11 rounded-full bg-[#303134] text-white hover:bg-[#3c4043] hover:text-white" onClick={() => setConfirmStop(true)}><Square className="mr-2 h-3.5 w-3.5 fill-current" />Stop recording</Button>}
      {state.update?.state === "ready" && !state.request && <a className="inline-flex min-h-11 items-center gap-2 rounded-full bg-[#303134] px-4 text-xs text-white" href={libraryURL} target="_blank" rel="noopener noreferrer"><Library className="h-4 w-4" />Recording saved · Open</a>}
    </div>;

  const setup = <>
      <p className="text-sm leading-relaxed text-muted-foreground">Keep the conversation without changing the live meeting.</p>
      {notice && <p role="alert" className="rounded-xl border border-amber-500/25 bg-amber-500/10 p-3 text-sm">{notice}</p>}
      {state.update?.state === "ready" && !state.request && <p role="status" className="rounded-xl bg-muted p-3 text-sm font-medium">Recording saved to this meeting’s notes in this browser. The live meeting is still connected.</p>}
      {remote ? <div className="space-y-4">
        <p className="font-medium">{remote.active ? `${remote.name} is recording this meeting.` : remote.accepted ? "You allowed recording. Waiting for the host to start." : "You declined recording. The host has been asked to stop."}</p>
        {remote.accepted && <Button className="min-h-11 rounded-full" variant="outline" onClick={() => session.reply(false)}>Withdraw permission and stop recording</Button>}
      </div> : isHost ? <>
        {recording ? <div className="space-y-4"><p className="text-3xl font-semibold tabular-nums">{recordingTime(state.update?.seconds ?? 0)}</p><p className="text-sm text-muted-foreground">Recording is in progress. Your microphone and camera controls still work normally.</p><Button className="min-h-11 w-full rounded-full" variant="destructive" onClick={() => setConfirmStop(true)}>Stop recording</Button></div>
        : starting || saving ? <div className="space-y-3 py-4" role="status"><Loader2 className="h-6 w-6 animate-spin" /><p className="font-medium">{starting ? "Starting recording…" : "Saving your recording…"}</p><p className="text-sm text-muted-foreground">{starting ? "Preparing audio and video. The call stays connected." : "Capture has stopped. Keep this tab open while the final pieces are saved."}</p>{starting && <Button variant="outline" onClick={() => void session.stop(true)}>Cancel start</Button>}</div>
        : waiting ? <div className="space-y-4" role="status"><ShieldCheck className="h-8 w-8" /><p className="font-semibold">Waiting for everyone’s permission</p><p className="text-sm text-muted-foreground">{state.approved} of {state.required} participants approved. Recording starts automatically after everyone allows it. No audio or video is saved yet.</p><p className="text-xs text-muted-foreground">Participants need a current Whisper version. Unanswered requests expire after one minute.</p><Button variant="outline" className="min-h-11 w-full rounded-full" onClick={() => void session.stop()}>Cancel request</Button></div>
        : <div className="space-y-4">
          <div className="flex gap-3 rounded-xl bg-muted p-4"><Monitor className="mt-0.5 h-5 w-5 shrink-0" /><div><p className="text-sm font-medium">Saved to this meeting’s notes in this browser</p><p className="mt-1 text-xs leading-relaxed text-muted-foreground">This is not hosted recording. Keep this tab visible and your computer awake. Keep the meeting expanded. Leaving, hiding the tab, or a participant change stops capture.</p></div></div>
          <p className="text-xs leading-relaxed text-muted-foreground">Video follows your visible Whisper Meet tiles, focus, camera framing and self-view. Your own shared screen is recorded large instead of the “You’re presenting” placeholder. Whisper’s chat, private notes, Jasper panels and controls aren’t added to the video. Anything visible inside the screen you choose to share is included.</p>
          <label className="flex min-h-11 items-center gap-3 text-sm"><input type="checkbox" checked={video} onChange={(event) => setVideo(event.target.checked)} />Include video and shared screen</label>
          <label className="flex min-h-11 items-center gap-3 text-sm"><input type="checkbox" checked={transcribe} onChange={(event) => setTranscribe(event.target.checked)} />Also transcribe with Jasper</label>
          <label className="flex min-h-11 items-center gap-3 text-sm"><input type="checkbox" checked={archive} onChange={(event) => setArchive(event.target.checked)} />Request permission for private cloud backup</label>
          <p className="text-sm text-muted-foreground">Everyone will be asked for permission. Start confirms yours; recording begins only after all participants approve.</p>
          {transcribe && <p className="text-xs text-muted-foreground">Audio is sent to Whisper’s cloud transcription provider in roughly 30-second pieces. Jasper can analyze the transcript. Results can be inaccurate.</p>}
          {archive && <p className="text-xs text-muted-foreground">After saving, you can separately confirm an upload to your private Whisper cloud account. Nothing is automatically uploaded or shared with attendees.</p>}
          <details className="text-xs text-muted-foreground"><summary className="cursor-pointer py-2">Coverage and storage</summary><p className="leading-relaxed">Records received meeting voices and your outgoing audio, optionally with video from up to 25 people. No other-app audio, shared-screen sound, chat, or private Jasper panels. Limits: 2 hours or 450 MB including backup audio. Export before clearing browser data. Permission uses cooperative app signaling, not a server-enforced restriction.</p></details>
          {unsupported && <p role="alert" className="text-sm">Recording isn’t supported in this browser. Use a current desktop Chrome or Safari browser.</p>}
          <Button type="button" disabled={unsupported} className="min-h-11 w-full rounded-full" onClick={() => session.request(video, transcribe, archive, true)}><Circle className="mr-2 h-3.5 w-3.5 fill-current" />Start recording</Button>
        </div>}
      </> : <p className="text-sm text-muted-foreground">Only the signed-in meeting host can start recording. You’ll be asked for permission before your meeting is recorded.</p>}
      {!recording && !starting && !saving && !waiting && <a className="inline-flex min-h-11 items-center gap-2 text-sm font-medium" href={libraryURL} target="_blank" rel="noopener noreferrer"><Library className="h-4 w-4" />Open saved recordings</a>}
    </>;

  return <>
    {status}
    {asPanel ? open && !consentOpen && !confirmStop && <MeetingActivityShell title="Recording" onClose={() => onOpenChange(false)} onBack={onBack}>{setup}</MeetingActivityShell> : <Dialog open={open && !consentOpen && !confirmStop} onOpenChange={onOpenChange}><DialogContent {...dialogProps}><DialogHeader><DialogTitle>Recording</DialogTitle><DialogDescription className="sr-only">Recording settings and permission</DialogDescription></DialogHeader>{setup}</DialogContent></Dialog>}
    <Dialog open={consentOpen} onOpenChange={(visible) => { if (!visible) session.reply(false); }}><DialogContent {...dialogProps}>
      <DialogHeader><DialogTitle>{remote?.name} wants to record</DialogTitle><DialogDescription>{remote?.video ? "Meeting audio, video and shared screen" : "Meeting audio"} will be saved on the host’s browser and can be exported.</DialogDescription></DialogHeader>
      <p className="text-sm text-muted-foreground">{remote?.archive ? "The host also requests permission to back up the recording, transcript and markers privately in their Whisper cloud account until they delete it." : "Cloud recording backup is not allowed by this request."}</p>
      <p className="text-sm text-muted-foreground">{remote?.transcribe ? "Audio will also be sent to cloud AI for transcription and the transcript may be analyzed by Jasper." : "Cloud transcription and AI analysis are off."}</p>
      <p className="text-sm">Nothing starts until everyone allows it. You can withdraw while recording. This cannot prevent someone recording outside Whisper.</p>
      <div className="flex gap-3"><Button variant="outline" className="min-h-11 flex-1 rounded-full" onClick={() => session.reply(false)}>Decline</Button><Button className="min-h-11 flex-1 rounded-full" onClick={() => session.reply(true)}>Allow recording</Button></div>
    </DialogContent></Dialog>

    <Dialog open={confirmStop && recording} onOpenChange={setConfirmStop}><DialogContent {...dialogProps}>
      <DialogHeader><DialogTitle>Stop recording?</DialogTitle><DialogDescription>The meeting will continue. Your recording will finish saving to this meeting’s notes in this browser.</DialogDescription></DialogHeader>
      <div className="flex gap-3"><Button variant="outline" className="min-h-11 flex-1 rounded-full" onClick={() => setConfirmStop(false)}>Keep recording</Button><Button variant="destructive" className="min-h-11 flex-1 rounded-full" onClick={() => { setConfirmStop(false); onOpenChange(true); void session.stop(); }}>Stop and save</Button></div>
    </DialogContent></Dialog>
  </>;
}
