import { z } from "zod";
import type { MeetingStageSnapshot } from "./meetingStageCapture";
import { MeetingRecorder, type RecorderUpdate } from "./meetingRecorder";
import type { LiveParticipantInfo, WhisperLiveRTC } from "./whisperLiveRTC";

const requestSchema = z.object({ requestId: z.string().uuid(), video: z.boolean(), transcribe: z.boolean(), archive: z.boolean() });
export type RecordingRequest = z.infer<typeof requestSchema>;
export type RemoteRecording = RecordingRequest & { peerId: string; name: string; accepted: boolean | null; active: boolean; heardAt: number };
export type RecordingSessionState = { request: RecordingRequest | null; remote: RemoteRecording | null; approved: number; required: number; update: RecorderUpdate | null; notice: string | null };
const initialState = (): RecordingSessionState => ({ request: null, remote: null, approved: 0, required: 0, update: null, notice: null });

/** Cooperative, fail-closed consent. A missing reply, new peer or expired consent lease stops capture. */
export class MeetingRecordingSession {
  state: RecordingSessionState = initialState();
  stageSnapshot: (() => MeetingStageSnapshot | null) | undefined;
  private recorder: MeetingRecorder | null = null;
  private roster: LiveParticipantInfo[] = [];
  private expected = new Set<string>();
  private approvals = new Map<string, number>();
  private requestedAt = 0;
  private startWhenApproved = false;
  private preparedAudio: AudioContext | null = null;
  private releasePreparedAudio(): void {
    const audio = this.preparedAudio; this.preparedAudio = null;
    if (audio) void audio.close().catch(() => undefined);
  }
  private timer: ReturnType<typeof setInterval> | null = null;
  private disposed = true;
  private enabled = true;
  private readonly jobs = new Set<MeetingRecorder>();
  constructor(private readonly ownerId: string, private readonly meetingId: string | null, private readonly rtc: () => WhisperLiveRTC | null, private readonly hostId: () => string | null, private readonly title: () => string, private readonly changed: (state: RecordingSessionState) => void, private readonly lifecycleChanged: (state: RecordingSessionState) => void = () => undefined) {}
  private publish(patch: Partial<RecordingSessionState>): void { this.state = { ...this.state, ...patch }; this.lifecycleChanged(this.state); if (!this.disposed) this.changed(this.state); }
  private send(event: string, data: unknown): void { this.rtc()?.sendAppEvent(event, data); }
  async whenSettled(): Promise<void> { await Promise.all([...this.jobs].map(async (job) => { await job.stop(); await job.cloudCompletion; })); }
  activate(): void { this.disposed = false; this.publish({}); if (!this.timer) this.timer = setInterval(() => this.tick(), 4000); }
  setEnabled(enabled: boolean): void { this.enabled = enabled; if (!enabled) { this.reply(false); void this.stop(false); this.publish({ remote: null }); } }
  private isHost(): boolean { return !!this.ownerId && this.ownerId.toLowerCase() === this.hostId()?.toLowerCase(); }
  private peers(): Set<string> { const self = this.rtc()?.localPeerId; return new Set(this.roster.filter((p) => p.peerId !== self).map((p) => p.peerId)); }
  private sources(): Parameters<MeetingRecorder["start"]>[0] { return this.roster.map((p) => ({ id: p.peerId, name: p.name, stream: p.remoteStream, transcriptionStream: p.peerId === this.rtc()?.localPeerId ? this.rtc()?.localAudioStream : undefined, hasVideo: p.hasVideo, isSelf: p.peerId === this.rtc()?.localPeerId, isScreenShare: p.isScreenSharing, isSpeaking: p.isSpeaking, micOn: p.micOn })); }
  reconcile(roster: LiveParticipantInfo[]): void {
    this.roster = roster;
    const peers = this.peers();
    if (this.state.request && (!this.isHost() || peers.size !== this.expected.size || [...peers].some((id) => !this.expected.has(id)))) {
      // Stop BEFORE connecting the new roster's tracks to the recording graph.
      void this.stop(false, "The room changed. Saved audio is kept; ask everyone again to continue.");
    } else this.recorder?.update(this.sources());
    const remote = this.state.remote;
    if (remote && !roster.some((p) => p.peerId === remote.peerId && p.userId.toLowerCase() === this.hostId()?.toLowerCase())) this.publish({ remote: null });
  }
  request(video: boolean, transcribe: boolean, archive = false, startWhenApproved = false): void {
    if (this.disposed || !this.enabled || !this.rtc()) { this.publish({ notice: "Reconnect to this meeting before starting a recording." }); return; }
    if (!this.isHost()) { this.publish({ notice: "Only the signed-in meeting host can start a recording." }); return; }
    if (this.state.request || this.recorder) { this.publish({ notice: "A recording is already starting or saving. Please wait." }); return; }
    if (video && this.roster.length > 25) { this.publish({ notice: "Video recording supports up to 25 people. Choose audio instead." }); return; }
    this.startWhenApproved = startWhenApproved;
    // Unlock an empty recording-only context inside the host's Start gesture.
    // No call sources are attached and no media is saved before consent.
    if (startWhenApproved) {
      try {
        this.preparedAudio = new AudioContext({ sampleRate: 24000 });
        void this.preparedAudio.resume().catch(() => undefined);
      } catch {
        this.startWhenApproved = false;
        this.releasePreparedAudio();
        this.publish({ notice: "This browser cannot start audio recording. Use a current desktop Chrome or Safari browser." });
        return;
      }
    }
    this.expected = this.peers(); this.approvals.clear(); this.requestedAt = Date.now();
    const request: RecordingRequest = { requestId: crypto.randomUUID(), video, transcribe, archive };
    this.publish({ request, approved: 0, required: this.expected.size, update: null, notice: null });
    this.send("recording-request-v2", request);
    if (this.startWhenApproved && this.expected.size === 0) void this.start();
  }
  async start(): Promise<void> {
    const request = this.state.request;
    if (this.disposed || !this.enabled || !request || this.recorder || !this.isHost()) return;
    if ([...this.expected].some((id) => Date.now() - (this.approvals.get(id) ?? 0) > 15000)) {
      this.publish({ notice: "Waiting for everyone’s current permission. Recording has not started." }); return;
    }
    this.startWhenApproved = false;
    if (document.hidden) { await this.stop(false, "Keep this meeting tab visible, then start recording again."); return; }
    const preparedAudio = this.preparedAudio; this.preparedAudio = null;
    const recorder = new MeetingRecorder(this.ownerId, this.meetingId, this.title(), (update) => {
      if (update.state === "ready" || update.state === "error") void recorder.cloudCompletion.finally(() => this.jobs.delete(recorder));
      if (this.state.update?.recordingId !== recorder.id) return;
      this.publish({ update });
      if (this.recorder === recorder && (update.state === "ready" || update.state === "error")) {
        this.send("recording-state-v2", { requestId: request.requestId, active: false });
        this.recorder = null; this.publish({ request: null });
      }
    }, preparedAudio);
    recorder.stageSnapshot = this.stageSnapshot;
    this.recorder = recorder; this.jobs.add(recorder);
    this.publish({ update: { state: "starting", seconds: 0, error: null, recordingId: recorder.id, audioInputs: 0 } });
    try { await recorder.start(this.sources(), request.video, request.transcribe, request.archive); if (this.recorder === recorder && this.state.request === request) this.send("recording-state-v2", { ...request, active: true }); }
    catch (error) {
      if (!this.disposed && this.state.update?.recordingId === recorder.id) this.publish({ notice: error instanceof Error ? error.message : "Recording could not start." });
    }
  }
  receive(event: string, data: unknown, from: string): boolean {
    if (!event.startsWith("recording-")) return false;
    if (this.disposed || !this.enabled) return true;
    if (event.endsWith("-v1")) {
      const old = z.object({ requestId: z.string().uuid() }).safeParse(data);
      if (old.success && this.roster.some((peer) => peer.peerId === from) && (event === "recording-request-v1" || event === "recording-state-v1")) this.send("recording-reply-v1", { requestId: old.data.requestId, accepted: false });
      return true;
    }
    const sender = this.roster.find((p) => p.peerId === from);
    if (!sender || from === this.rtc()?.localPeerId) return true;
    if (event === "recording-reply-v2") {
      const reply = z.object({ requestId: z.string().uuid(), accepted: z.boolean() }).safeParse(data);
      if (!reply.success || reply.data.requestId !== this.state.request?.requestId || !this.expected.has(from)) return true;
      if (!reply.data.accepted) { void this.stop(false, `${sender.name} declined or withdrew permission. Recording stopped.`); return true; }
      this.approvals.set(from, Date.now()); this.publish({ approved: this.approvals.size });
      if (this.startWhenApproved && [...this.expected].every((id) => Date.now() - (this.approvals.get(id) ?? 0) <= 15000)) void this.start();
      return true;
    }
    if (sender.userId.toLowerCase() !== this.hostId()?.toLowerCase()) return true;
    if (event === "recording-request-v2") {
      const parsed = requestSchema.safeParse(data); if (!parsed.success) return true;
      const current = this.state.remote;
      if (current?.requestId === parsed.data.requestId && current.peerId === from) { if (current.video !== parsed.data.video || current.transcribe !== parsed.data.transcribe || current.archive !== parsed.data.archive) { this.reply(false); return true; } this.publish({ remote: { ...current, heardAt: Date.now() } }); if (current.accepted !== null) this.send("recording-reply-v2", { requestId: current.requestId, accepted: current.accepted }); }
      else this.publish({ remote: { ...parsed.data, peerId: from, name: sender.name, accepted: null, active: false, heardAt: Date.now() } });
    }
    if (event === "recording-state-v2") {
      const parsed = z.object({ requestId: z.string().uuid(), active: z.boolean() }).safeParse(data); if (!parsed.success) return true;
      const remote = this.state.remote;
      if (!remote || remote.peerId !== from || remote.requestId !== parsed.data.requestId) {
        if (parsed.data.active) { this.send("recording-reply-v2", { requestId: parsed.data.requestId, accepted: false }); this.publish({ notice: "The host announced recording without your consent. A stop request was sent; leave if it continues." }); }
        return true;
      }
      if (!parsed.data.active) this.publish({ remote: null });
      else {
        const scope = requestSchema.safeParse(data);
        if (!scope.success || scope.data.video !== remote.video || scope.data.transcribe !== remote.transcribe || scope.data.archive !== remote.archive) { this.reply(false); this.publish({ notice: "Recording scope changed. Permission withdrawn; ask the host for a new request." }); return true; }
        this.publish({ remote: { ...remote, active: true, heardAt: Date.now() } }); this.send("recording-reply-v2", { requestId: remote.requestId, accepted: remote.accepted === true });
      }
    }
    return true;
  }
  reply(accepted: boolean): void { const remote = this.state.remote; if (!remote) return; accepted = accepted && !this.disposed && this.enabled && Date.now() - remote.heardAt <= 15000; this.publish({ remote: { ...remote, accepted } }); this.send("recording-reply-v2", { requestId: remote.requestId, accepted }); }
  private tick(): void {
    this.reconcile(this.roster);
    const request = this.state.request;
    if (request) {
      if (!this.recorder && Date.now() - this.requestedAt > 60000) { void this.stop(false, "Consent request expired. Everyone needs a current Whisper version and must allow recording."); return; }
      if (this.recorder && [...this.expected].some((id) => Date.now() - (this.approvals.get(id) ?? 0) > 15000)) { void this.stop(false, "Consent connection was lost. Recording stopped; request permission again."); return; }
      if (this.state.update?.state === "recording") this.send("recording-state-v2", { ...request, active: true });
      else this.send("recording-request-v2", request);
      const approved = [...this.expected].filter((id) => Date.now() - (this.approvals.get(id) ?? 0) <= 15000).length;
      if (approved !== this.state.approved) this.publish({ approved });
    }
    const remote = this.state.remote;
    if (remote && Date.now() - remote.heardAt > 15000) { this.reply(false); this.publish({ notice: "Recording status connection lost. Permission withdrawn; check with the host before continuing.", remote: null }); }
  }
  async stop(cancelCloud = false, notice: string | null = null): Promise<void> {
    const request = this.state.request; const recorder = this.recorder;
    this.startWhenApproved = false; this.releasePreparedAudio();
    if (cancelCloud) for (const job of this.jobs) void job.stop(true);
    // stop() disconnects sources synchronously, before the first await.
    const drain = recorder?.stop(cancelCloud);
    if (request) this.send("recording-state-v2", { requestId: request.requestId, active: false });
    this.publish({ request: null, notice: notice ?? this.state.notice }); this.approvals.clear();
    await drain;
    if (this.recorder === recorder) this.recorder = null;
  }
  dispose(cancelCloud = true): void { this.reply(false); this.disposed = true; if (this.timer) clearInterval(this.timer); this.timer = null; void this.stop(cancelCloud); this.publish({ remote: null, request: null }); }
}
