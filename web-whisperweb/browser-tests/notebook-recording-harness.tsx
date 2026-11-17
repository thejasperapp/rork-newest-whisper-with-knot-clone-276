import { createRoot } from "react-dom/client";
import { lazy, Suspense, useState } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { MemoryRouter } from "react-router-dom";
import { Toaster } from "sonner";
import { PrivateNotebookWorkspace } from "../src/components/PrivateNotebookWorkspace";
import { PrivateNotebookEditor } from "../src/components/PrivateNotebookEditor";
import { NotebookRecordingSources } from "../src/components/NotebookRecordingSources";
import { MeetingRecorder } from "../src/lib/meetingRecorder";
import { editRecording } from "../src/lib/meetingRecordingStorage";
import { newNotebookDocument } from "../src/lib/notebookDocument";
import { listNotebookDocuments, saveNotebookDocument } from "../src/lib/notebookStorage";
import type { NotebookDocument } from "../src/lib/notebookDocument";
import type { PipMosaicSource } from "../src/lib/meetPipMosaic";
import "../src/index.css";

declare global {
  interface Window {
    notebookHarness: {
      workspace: (owner: string) => Promise<void>;
      recap: (owner: string, id: string, meetingId: string) => Promise<void>;
      create: (video: boolean) => Promise<{ owner: string; id: string }>;
      linkMeeting: (owner: string, recordingId: string, meetingId: string) => Promise<void>;
      reopen: (owner: string, id: string) => Promise<void>;
      stored: (owner: string, id: string) => Promise<NotebookDocument | undefined>;
    };
  }
}
const MeetingNotesScreen = lazy(async () => ({ default: (await import("../src/components/MeetingNotesScreen")).MeetingNotesScreen }));
const client = new QueryClient({ defaultOptions: { queries: { retry: false, refetchOnWindowFocus: false }, mutations: { retry: false } } });
function Harness(): JSX.Element {
  const [recap, setRecap] = useState<{ owner: string; id: string; meetingId: string } | null>(null);
  const [workspaceOwner, setWorkspaceOwner] = useState<string | null>(null);
  const [note, setNote] = useState<NotebookDocument | null>(null);
  async function reopen(owner: string, id: string): Promise<void> {
    const saved = (await listNotebookDocuments(owner)).find((item) => item.id === id);
    if (!saved) throw new Error("Finalized recording note missing");
    setNote(saved);
  }
  window.notebookHarness = {
    reopen,
    recap: async (owner, id, meetingId) => {
      await editRecording(owner, id, (record) => ({ ...record, meetingId, storageConsent: true }));
      localStorage.setItem("recap-test-owner", owner);
      setRecap({ owner, id, meetingId });
    },
    linkMeeting: async (owner, recordingId, meetingId) => { await editRecording(owner, recordingId, (record) => ({ ...record, meetingId })); },
    workspace: async (owner) => {
      await saveNotebookDocument({ ...newNotebookDocument(owner, null, "Second selected note"), notes: "Review the launch checklist on Friday." }, () => {});
      await saveNotebookDocument({ ...newNotebookDocument(owner, null, "Unselected sibling"), notes: "This should never become selected context." }, () => {});
      setWorkspaceOwner(owner);
    },
    stored: async (owner, id) => (await listNotebookDocuments(owner)).find((item) => item.id === id),
    create: async (includeVideo) => {
      const owner = crypto.randomUUID(), context = new AudioContext();
      await context.resume();
      const oscillator = context.createOscillator(), gain = context.createGain(), destination = context.createMediaStreamDestination();
      oscillator.frequency.value = 440; gain.gain.value = 0.2;
      oscillator.connect(gain); gain.connect(destination); oscillator.start();
      const canvas = document.createElement("canvas"); canvas.width = 640; canvas.height = 360;
      const drawing = canvas.getContext("2d")!;
      const paint = (): void => { drawing.fillStyle = "#202124"; drawing.fillRect(0, 0, 640, 360); drawing.fillStyle = "#FF7340"; drawing.fillRect(32, 32, 40, 40); drawing.fillStyle = "white"; drawing.font = "26px sans-serif"; drawing.fillText("Planning session · synthetic test", 32, 160); drawing.font = "16px sans-serif"; drawing.fillText(String(Date.now()), 32, 196); };
      paint(); const frames = window.setInterval(paint, 100), camera = canvas.captureStream(10);
      const stream = new MediaStream([...destination.stream.getTracks(), ...camera.getTracks()]);
      const sources: PipMosaicSource[] = [{ id: "self", name: "Test host", stream, isSelf: true, hasVideo: true, isScreenShare: false, isSpeaking: true, micOn: true }];
      const engine = new MeetingRecorder(owner, null, "Notebook recording regression", () => {});
      try {
        await engine.start(sources, includeVideo, false, false);
        await new Promise((resolve) => setTimeout(resolve, 3700)); await engine.stop();
        await editRecording(owner, engine.id, (record) => ({ ...record, transcript: [{ id: "fixture-1", start: 1, end: 2, text: "Synthetic source text", timing: "chunk" }] }));
        await reopen(owner, engine.id);
        return { owner, id: engine.id };
      } finally {
        await engine.stop(); clearInterval(frames); oscillator.stop(); stream.getTracks().forEach((track) => track.stop()); await context.close();
      }
    },
  };
  return <QueryClientProvider client={client}><MemoryRouter><main className="mx-auto max-w-6xl px-4 py-6">{recap ? <Suspense fallback={<p>Opening recap…</p>}><MeetingNotesScreen title="Launch meeting" notes="The team agreed to launch Thursday." transcript="Alex: Launch is Thursday." meetingId={recap.meetingId} recordingId={recap.id} onClose={() => setRecap(null)} /></Suspense> : workspaceOwner ? <PrivateNotebookWorkspace key={workspaceOwner} userId={workspaceOwner} /> : note ? <PrivateNotebookEditor key={`${note.ownerId}:${note.id}`} initial={note} onClose={() => setNote(null)} onSaved={() => {}} recordingContent={(onImportTranscript) => <NotebookRecordingSources note={note} onImportTranscript={onImportTranscript} />} /> : <p>Notebook regression ready</p>}</main><Toaster /></MemoryRouter></QueryClientProvider>;
}
createRoot(document.getElementById("root")!).render(<Harness />);
