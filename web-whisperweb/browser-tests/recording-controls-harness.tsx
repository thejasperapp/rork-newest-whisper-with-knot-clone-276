import { createRoot } from "react-dom/client";
import { useEffect, useState } from "react";
import { MeetingActivities } from "../src/components/MeetingActivities";
import { MeetingRecordingControls } from "../src/components/MeetingRecordingControls";
import { MeetingRecordingSession, type RecordingSessionState } from "../src/lib/meetingRecordingSession";
import type { LiveParticipantInfo, WhisperLiveRTC } from "../src/lib/whisperLiveRTC";
import { listRecordings } from "../src/lib/meetingRecordingStorage";
import "../src/index.css";

const owner = crypto.randomUUID();
const guest = crypto.randomUUID();
const sourceContext = new AudioContext();
const tones = [440, 880].map((frequency) => {
  const oscillator = sourceContext.createOscillator();
  const gain = sourceContext.createGain();
  const destination = sourceContext.createMediaStreamDestination();
  oscillator.frequency.value = frequency; gain.gain.value = 0.2;
  oscillator.connect(gain); gain.connect(destination); oscillator.start();
  return { oscillator, stream: destination.stream };
});
const canvas = document.createElement("canvas"); canvas.width = 640; canvas.height = 360;
const drawing = canvas.getContext("2d")!;
const frames = window.setInterval(() => { drawing.fillStyle = "#202124"; drawing.fillRect(0, 0, 640, 360); drawing.fillStyle = "white"; drawing.font = "24px sans-serif"; drawing.fillText(`Live meeting · ${Date.now()}`, 30, 180); }, 100);
const camera = canvas.captureStream(10);
const local = new MediaStream([...tones[0].stream.getTracks(), ...camera.getTracks()]);
const roster = [local, tones[1].stream].map((stream, index) => ({
  peerId: index ? "guest-peer" : "host-peer", userId: index ? guest : owner, name: index ? "Guest" : "Host",
  remoteStream: stream, hasAudio: true, hasVideo: !index, micOn: true, isSpeaker: true,
  isScreenSharing: false, isSpeaking: false,
})) as LiveParticipantInfo[];
const rtc = { localPeerId: "host-peer", sendAppEvent: () => {} } as unknown as WhisperLiveRTC;
let session: MeetingRecordingSession;

declare global {
  interface Window {
    recordingHarness: { approve: () => void; recordedCount: () => Promise<number>; trackStates: () => string[] };
  }
}
function Harness(): JSX.Element {
  const asPanel = new URLSearchParams(window.location.search).has("activities");
  const [activities, setActivities] = useState<boolean>(false);
  const [open, setOpen] = useState<boolean>(false);
  const [state, setState] = useState<RecordingSessionState>({ request: null, remote: null, approved: 0, required: 0, notice: null, update: null });
  const [active] = useState<MeetingRecordingSession>(() => new MeetingRecordingSession(owner, null, () => rtc, () => owner, () => "Browser UI regression", setState));
  session = active;
  useEffect(() => {
    active.activate(); active.reconcile(roster);
    const video = document.querySelector("video")!; video.muted = true; video.srcObject = local; void video.play();
    return () => { active.dispose(); video.srcObject = null; };
  }, [active]);
  return <main data-meeting-stage className="fixed inset-0 z-[60] bg-[#202124] text-white">
    <video aria-label="Live meeting camera" muted autoPlay playsInline controls={false} className="h-full w-full object-contain" />
    <div className="pointer-events-none absolute left-3 right-3 top-[max(4rem,calc(env(safe-area-inset-top)+3.5rem))] z-40 flex justify-center">
      <MeetingRecordingControls session={active} state={state} isHost open={open} onOpenChange={setOpen} asPanel={asPanel} onBack={() => { setOpen(false); setActivities(true); }} />
    </div>
    {asPanel && <button className="absolute bottom-4 right-4 rounded-full bg-white px-5 py-3 text-black" onClick={() => setActivities(true)}>Activities</button>}
    {activities && <MeetingActivities onClose={() => setActivities(false)} onRecording={() => { setActivities(false); setOpen(true); }} onLayout={() => setActivities(false)} />}
    <button className="absolute bottom-4 left-4 rounded-full bg-white px-5 py-3 text-black" onClick={() => void document.querySelector("main")!.requestFullscreen()}>Full screen</button>
  </main>;
}
window.recordingHarness = {
  approve: () => { if (session.state.request) session.receive("recording-reply-v2", { requestId: session.state.request.requestId, accepted: true }, "guest-peer"); },
  recordedCount: async () => (await listRecordings(owner)).length,
  trackStates: () => [...local.getTracks(), ...tones[1].stream.getTracks()].map((track) => track.readyState),
};
window.addEventListener("pagehide", () => { session.dispose(); clearInterval(frames); tones.forEach((tone) => tone.oscillator.stop()); [...local.getTracks(), ...tones[1].stream.getTracks()].forEach((track) => track.stop()); void sourceContext.close(); });
createRoot(document.getElementById("root")!).render(<Harness />);
