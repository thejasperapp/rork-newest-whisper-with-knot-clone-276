import { BACKEND_URL } from "@/lib/billing";
import { knotVoiceAudioBusy } from "@/lib/knotAudioOwnership";
import { supabase } from "@/lib/supabase";
import { WHISPER_KNOWLEDGE } from "@/lib/ember";
import { parseEmberBlocks, type EmberBlock } from "@/lib/emberBrain";

/**
 * Ember's live voice — a true speech-to-speech OpenAI Realtime session over
 * WebRTC (model `gpt-realtime`, voice `echo`). No robotic browser TTS: the
 * model hears the mic directly and answers with natural human-sounding audio,
 * while transcripts and visual tool calls stream over the data channel.
 *
 * Credentials come from the project backend (`/ai/realtime-token`, signed-in
 * users only) — no OpenAI key ever ships in the browser bundle.
 */

const REALTIME_MODEL = "gpt-realtime";
const REALTIME_CALLS_URL = `https://api.openai.com/v1/realtime/calls?model=${REALTIME_MODEL}`;

/** The one Ember voice — warm, human, preset everywhere. */
export const EMBER_REALTIME_VOICE = "echo";

export type EmberRealtimeState =
  | "idle"
  | "connecting"
  | "live"
  | "closed"
  | "error";

/** OpenAI function-tool definition (flattened realtime shape). */
export interface EmberRealtimeTool {
  type: "function";
  name: string;
  description: string;
  parameters: Record<string, unknown>;
}

export interface EmberRealtimeCallbacks {
  onState?: (state: EmberRealtimeState) => void;
  /** Voice activity on the user's mic (from server VAD). */
  onUserSpeech?: (active: boolean) => void;
  /** Live transcription of what the user is saying. */
  onUserTranscript?: (text: string, final: boolean) => void;
  /** Accumulated text of the answer Ember is currently speaking. */
  onAssistantDelta?: (fullText: string) => void;
  /** The answer finished (full transcript of the spoken reply). */
  onAssistantDone?: (fullText: string) => void;
  /** Audio is actually playing out of the speaker. */
  onSpeaking?: (speaking: boolean) => void;
  /** A reply is being produced (between question and first audio/text). */
  onThinking?: (thinking: boolean) => void;
  /** A display tool was invoked; return a short result string for the model. */
  onToolCall?: (name: string, args: Record<string, unknown>) => string | void;
  onError?: (message: string) => void;
}

interface RealtimeServerEvent {
  type?: string;
  delta?: string;
  transcript?: string;
  text?: string;
  call_id?: string;
  name?: string;
  arguments?: string;
  item?: { type?: string; call_id?: string; name?: string };
  response?: { id?: string };
  error?: { message?: string; code?: string };
}

/**
 * Fetches a short-lived Realtime credential. Order: project backend (works on
 * production with zero client keys) → mint directly with the public key →
 * the raw public key itself (also accepted by the calls endpoint).
 */
async function mintRealtimeSecret(): Promise<string | null> {
  try {
    const { data } = await supabase.auth.getSession();
    const token = data.session?.access_token;
    if (token && BACKEND_URL) {
      const res = await fetch(`${BACKEND_URL}/ai/realtime-token`, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}` },
      });
      if (res.ok) {
        const json = (await res.json()) as { value?: string };
        if (json.value) return json.value;
      } else {
        console.warn("[ember-voice] backend token failed", res.status);
      }
    }
  } catch (err) {
    console.warn("[ember-voice] backend token error", err);
  }
  // No client-side key fallback — realtime voice is available to signed-in
  // users through the backend mint only.
  return null;
}

/**
 * One live speech-to-speech session. Create → `connect()` → talk (mic is
 * hot, semantic VAD turns) or `sendText()` — Ember replies out loud in the
 * echo voice either way. Always `close()` when done.
 */
export interface EmberRealtimeCredential { value: string; instructions?: string; firstMessage?: string }
export class EmberRealtimeSession {
  private static readonly sessions = new Set<EmberRealtimeSession>();
  static get isBusy(): boolean { return this.sessions.size > 0; }
  private readonly lifecycle = new AbortController();
  private readonly exclusive: boolean;
  private readonly credentialProvider?: (signal: AbortSignal) => Promise<EmberRealtimeCredential>;
  private pc: RTCPeerConnection | null = null;
  private dc: RTCDataChannel | null = null;
  private mic: MediaStream | null = null;
  private audioEl: HTMLAudioElement | null = null;
  private remoteStreamValue: MediaStream | null = null;
  private closedFlag = false;
  private stateValue: EmberRealtimeState = "idle";
  private assistantText = "";
  private userInterim = "";
  private activeResponse = false;
  private continueAfterTools = false;
  private readonly callNames = new Map<string, string>();
  private readonly pendingToolOutputs: { callId: string; output: string }[] = [];
  private readonly instructions: string;
  private readonly tools: EmberRealtimeTool[];
  private readonly cb: EmberRealtimeCallbacks;
  private readonly micRequested: boolean;

  constructor(options: {
    instructions: string;
    tools?: EmberRealtimeTool[];
    callbacks?: EmberRealtimeCallbacks;
    /** Set false for speak-only sessions (deck narration) — no mic is opened. */
    mic?: boolean;
    /** One-call welcome uses server-claimed credentials and no chat context. */
    credentialProvider?: (signal: AbortSignal) => Promise<EmberRealtimeCredential>;
    exclusive?: boolean;
  }) {
    this.instructions = options.instructions;
    this.tools = options.tools ?? [];
    this.cb = options.callbacks ?? {};
    this.micRequested = options.mic !== false;
    this.credentialProvider = options.credentialProvider;
    this.exclusive = options.exclusive === true;
  }

  get state(): EmberRealtimeState {
    return this.stateValue;
  }

  get isLive(): boolean {
    return this.stateValue === "live";
  }

  get micAvailable(): boolean {
    return this.mic != null;
  }

  /** Ember's live voice as a MediaStream — mixable into a call's outgoing
   *  audio so everyone in a meeting hears the same narration. */
  get remoteAudioStream(): MediaStream | null {
    return this.remoteStreamValue;
  }

  async connect(): Promise<void> {
    if (this.stateValue !== "idle") return;
    if (knotVoiceAudioBusy() || (this.exclusive && EmberRealtimeSession.isBusy) || [...EmberRealtimeSession.sessions].some(session => session.exclusive)) throw new Error("Another voice call is already open.");
    EmberRealtimeSession.sessions.add(this);
    this.setState("connecting");
    try {
      const credential: { value: string | null; instructions?: string; firstMessage?: string } = this.credentialProvider ? await this.credentialProvider(this.lifecycle.signal) : { value: await mintRealtimeSecret() };
      if (this.closedFlag) return;
      if (!credential.value) throw new Error("Knot's live voice isn't configured in this build.");
      const pc = new RTCPeerConnection();
      this.pc = pc;

      // Remote audio — Ember's actual voice.
      const audio = document.createElement("audio");
      audio.autoplay = true;
      audio.setAttribute("playsinline", "true");
      audio.style.display = "none";
      document.body.appendChild(audio);
      this.audioEl = audio;
      pc.ontrack = (event) => {
        const stream = event.streams[0] ?? new MediaStream([event.track]);
        this.remoteStreamValue = stream;
        audio.srcObject = stream;
        void audio.play().catch(() => undefined);
      };

      // Mic — optional; text questions still work without it. Speak-only
      // sessions (mic: false) never touch the microphone at all.
      if (this.micRequested) {
        try {
          const mic = await navigator.mediaDevices.getUserMedia({
            audio: { echoCancellation: true, noiseSuppression: true },
          });
          if (this.closedFlag) {
            for (const track of mic.getTracks()) track.stop();
            throw new Error("closed");
          }
          this.mic = mic;
          for (const track of mic.getTracks()) pc.addTrack(track, mic);
        } catch {
          if (this.credentialProvider && this.exclusive) throw new Error("Allow microphone access in your browser to answer Knot.");
          pc.addTransceiver("audio", { direction: "recvonly" });
        }
      } else {
        pc.addTransceiver("audio", { direction: "recvonly" });
      }

      const dc = pc.createDataChannel("oai-events");
      this.dc = dc;
      dc.onmessage = (event) => this.handleEvent(String(event.data));
      const channelOpen = new Promise<void>((resolve, reject) => {
        const timer = window.setTimeout(
          () => reject(new Error("Jasper's voice line timed out.")),
          15000,
        );
        dc.onopen = () => {
          window.clearTimeout(timer);
          resolve();
        };
        dc.onerror = () => {
          window.clearTimeout(timer);
          reject(new Error("Jasper's voice channel failed."));
        };
      });

      const offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      const res = await fetch(REALTIME_CALLS_URL, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${credential.value}`,
          "Content-Type": "application/sdp",
        },
        body: offer.sdp ?? "",
        signal: this.lifecycle.signal,
      });
      if (!res.ok) {
        throw new Error(`Ember's voice service refused (${res.status}).`);
      }
      const answer = await res.text();
      if (this.closedFlag) throw new Error("closed");
      await pc.setRemoteDescription({ type: "answer", sdp: answer });
      await channelOpen;

      // Session config: instructions, live input transcription, semantic
      // VAD turn-taking, the echo voice, and the visual display tools.
      this.send({
        type: "session.update",
        session: {
          type: "realtime",
          instructions: credential.instructions ?? this.instructions,
          audio: {
            input: {
              transcription: { model: "gpt-4o-mini-transcribe", language: "en" },
              turn_detection: { type: "semantic_vad" },
            },
            output: { voice: EMBER_REALTIME_VOICE },
          },
          ...(this.tools.length > 0
            ? { tools: this.tools, tool_choice: "auto" }
            : {}),
        },
      });
      this.setState("live");
      if ('firstMessage' in credential && typeof credential.firstMessage === 'string' && credential.firstMessage.trim()) {
        // Assistant-first audio, not a fabricated user utterance or transcript.
        this.send({ type: 'response.create', response: { instructions: `Begin this answered welcome call by saying this greeting naturally, then listen: ${JSON.stringify(credential.firstMessage)}` } });
      }
    } catch (err) {
      this.teardown();
      if (!this.closedFlag) this.setState("error");
      throw err instanceof Error ? err : new Error("Voice connection failed.");
    }
  }

  /** Ask by text — Ember still answers out loud (plus transcript). */
  sendText(text: string): void {
    const clean = text.trim();
    if (!clean || !this.dc || this.dc.readyState !== "open") return;
    if (this.activeResponse) this.send({ type: "response.cancel" });
    this.send({
      type: "conversation.item.create",
      item: {
        type: "message",
        role: "user",
        content: [{ type: "input_text", text: clean }],
      },
    });
    this.send({ type: "response.create" });
  }

  /** Mute/unmute Ember's ears without dropping the session. */
  setMicEnabled(enabled: boolean): void {
    for (const track of this.mic?.getTracks() ?? []) {
      track.enabled = enabled;
    }
  }

  /** Cancel whatever Ember is currently saying (used when skipping slides). */
  cancelSpeech(): void {
    if (this.activeResponse) this.send({ type: "response.cancel" });
  }

  close(): void {
    if (this.closedFlag) return;
    this.closedFlag = true;
    this.lifecycle.abort();
    this.teardown();
    this.setState("closed");
  }

  // ── internals ─────────────────────────────────────────────────────────────

  private setState(state: EmberRealtimeState): void {
    if (this.stateValue === state) return;
    this.stateValue = state;
    this.cb.onState?.(state);
  }

  private send(payload: Record<string, unknown>): void {
    if (!this.dc || this.dc.readyState !== "open") return;
    try {
      this.dc.send(JSON.stringify(payload));
    } catch (err) {
      console.warn("[ember-voice] send failed", err);
    }
  }

  private teardown(): void {
    EmberRealtimeSession.sessions.delete(this);
    for (const track of this.mic?.getTracks() ?? []) track.stop();
    this.mic = null;
    this.remoteStreamValue = null;
    try {
      this.dc?.close();
    } catch {
      /* already closed */
    }
    this.dc = null;
    try {
      this.pc?.close();
    } catch {
      /* already closed */
    }
    this.pc = null;
    if (this.audioEl) {
      this.audioEl.srcObject = null;
      this.audioEl.remove();
      this.audioEl = null;
    }
  }

  private handleEvent(raw: string): void {
    let event: RealtimeServerEvent;
    try {
      event = JSON.parse(raw) as RealtimeServerEvent;
    } catch {
      return;
    }
    switch (event.type) {
      case "input_audio_buffer.speech_started":
        this.cb.onUserSpeech?.(true);
        break;
      case "input_audio_buffer.speech_stopped":
        this.cb.onUserSpeech?.(false);
        break;
      case "conversation.item.input_audio_transcription.delta":
        this.userInterim += event.delta ?? "";
        if (this.userInterim.trim()) {
          this.cb.onUserTranscript?.(this.userInterim.trim(), false);
        }
        break;
      case "conversation.item.input_audio_transcription.completed": {
        const finalText = (event.transcript ?? this.userInterim).trim();
        this.userInterim = "";
        if (finalText) this.cb.onUserTranscript?.(finalText, true);
        break;
      }
      case "response.created":
        this.activeResponse = true;
        if (this.continueAfterTools) {
          // Tool continuation — keep the transcript flowing as one answer.
          this.continueAfterTools = false;
          if (this.assistantText) this.assistantText += " ";
        } else {
          this.assistantText = "";
        }
        this.cb.onThinking?.(true);
        break;
      case "response.output_audio_transcript.delta":
      case "response.audio_transcript.delta":
      case "response.output_text.delta":
      case "response.text.delta":
        this.assistantText += event.delta ?? "";
        this.cb.onThinking?.(false);
        this.cb.onAssistantDelta?.(this.assistantText);
        break;
      case "response.output_audio_transcript.done":
      case "response.audio_transcript.done":
        if (event.transcript && event.transcript.trim()) {
          // Trust the server's final transcript for this segment.
          this.assistantText = this.continuationBase() + event.transcript;
          this.cb.onAssistantDelta?.(this.assistantText);
        }
        break;
      case "output_audio_buffer.started":
        this.cb.onSpeaking?.(true);
        break;
      case "output_audio_buffer.stopped":
      case "output_audio_buffer.cleared":
        this.cb.onSpeaking?.(false);
        break;
      case "response.output_item.added":
        if (event.item?.type === "function_call" && event.item.call_id) {
          this.callNames.set(event.item.call_id, event.item.name ?? "");
        }
        break;
      case "response.function_call_arguments.done": {
        const callId = event.call_id ?? "";
        const name = event.name ?? this.callNames.get(callId) ?? "";
        if (!callId || !name) break;
        let args: Record<string, unknown> = {};
        try {
          args = JSON.parse(event.arguments ?? "{}") as Record<string, unknown>;
        } catch {
          args = {};
        }
        const output = this.cb.onToolCall?.(name, args) ?? "displayed";
        this.pendingToolOutputs.push({ callId, output: String(output) });
        break;
      }
      case "response.done": {
        this.activeResponse = false;
        this.cb.onThinking?.(false);
        if (this.pendingToolOutputs.length > 0) {
          // Feed tool results back and let Ember keep talking.
          for (const pending of this.pendingToolOutputs) {
            this.send({
              type: "conversation.item.create",
              item: {
                type: "function_call_output",
                call_id: pending.callId,
                output: pending.output,
              },
            });
          }
          this.pendingToolOutputs.length = 0;
          this.continueAfterTools = true;
          this.send({ type: "response.create" });
        } else if (this.assistantText.trim()) {
          this.cb.onAssistantDone?.(this.assistantText.trim());
        }
        break;
      }
      case "error": {
        const message = event.error?.message ?? "Jasper's voice hit an error.";
        // Benign turn-management noise (cancel with nothing active, etc.).
        if (!/no active response/i.test(message)) {
          console.warn("[ember-voice] server error", message);
          this.cb.onError?.(message);
        }
        break;
      }
      default:
        break;
    }
  }

  /** Text already spoken before a tool-continuation segment. */
  private continuationBase(): string {
    const idx = this.assistantText.lastIndexOf(" ");
    return this.continueAfterTools && idx > 0
      ? this.assistantText.slice(0, idx + 1)
      : "";
  }
}

// ── Display tools ("the modals") ─────────────────────────────────────────────

/**
 * The visual cards Ember can throw on screen while talking. Every tool maps
 * to an existing Ember block renderer, so voice and typed answers share the
 * exact same card system.
 */
export function emberDisplayTools(options?: {
  /** Include the launcher for the full interactive Whisper pitch deck. */
  includePitchLauncher?: boolean;
  /** Include the in-meeting interactive tools — the real WPP slider
   *  calculator, the real brand-card modals, and the narrated deck
   *  walkthrough that reads slides aloud to the whole room. */
  includeMeetingTools?: boolean;
}): EmberRealtimeTool[] {
  const tools: EmberRealtimeTool[] = [
    {
      type: "function",
      name: "show_pitch_deck",
      description:
        "Display a swipeable slide-deck card. REQUIRED whenever you pitch Whisper, walk through the business model, monetization, WPP, sponsorships, or prep someone to present. 4-7 tight slides, real Whisper numbers only.",
      parameters: {
        type: "object",
        properties: {
          title: { type: "string" },
          slides: {
            type: "array",
            items: {
              type: "object",
              properties: {
                title: { type: "string" },
                body: { type: "string", description: "1-2 sentences" },
                bullets: { type: "array", items: { type: "string" } },
                stat: { type: "string", description: "hero stat, e.g. \"10%\"" },
                statLabel: { type: "string", description: "e.g. \"platform fee\"" },
              },
              required: ["title"],
            },
          },
        },
        required: ["title", "slides"],
      },
    },
    {
      type: "function",
      name: "show_chart",
      description:
        "Display a line chart card. REQUIRED whenever you cite a numeric series, earnings math, follower growth, RPM tiers, or any comparison of numbers.",
      parameters: {
        type: "object",
        properties: {
          title: { type: "string" },
          unit: { type: "string", description: "e.g. $, followers, %" },
          points: {
            type: "array",
            items: {
              type: "object",
              properties: {
                x: { type: "string" },
                y: { type: "number" },
              },
              required: ["x", "y"],
            },
          },
        },
        required: ["title", "points"],
      },
    },
    {
      type: "function",
      name: "show_tips_card",
      description:
        "Display a titled card with a short summary and bullet tips. Use for recruiting advice, coaching strategy, creator growth moves, closing techniques, or any list of recommendations.",
      parameters: {
        type: "object",
        properties: {
          title: { type: "string" },
          summary: { type: "string" },
          tips: { type: "array", items: { type: "string" } },
        },
        required: ["title", "tips"],
      },
    },
    {
      type: "function",
      name: "show_plan",
      description:
        "Display a structured plan card with weekly focus points and dated milestones. Use whenever someone asks how to get somewhere: onboarding a prospect, launching a coaching business, hitting a follower goal.",
      parameters: {
        type: "object",
        properties: {
          title: { type: "string" },
          summary: { type: "string" },
          targetDate: { type: "string" },
          weeklyFocus: { type: "array", items: { type: "string" } },
          milestones: {
            type: "array",
            items: {
              type: "object",
              properties: {
                label: { type: "string" },
                date: { type: "string" },
              },
              required: ["label"],
            },
          },
        },
        required: ["title"],
      },
    },
  ];
  if (options?.includePitchLauncher) {
    tools.push({
      type: "function",
      name: "open_full_pitch_deck",
      description:
        "Offer the full interactive Whisper pitch deck (real product components with sample data). Call IN ADDITION to show_pitch_deck when they want the complete investor/brand/creator walkthrough.",
      parameters: { type: "object", properties: {} },
    });
  }
  if (options?.includeMeetingTools) {
    tools.push(
      {
        type: "function",
        name: "open_wpp_calculator",
        description:
          "Open the REAL interactive WPP (Whisper Paid Partners) earnings calculator on screen — working sliders for followers and monthly views with live payout math. REQUIRED when someone asks to see, try, or play with WPP numbers, RPM tiers, or 'what would I earn'.",
        parameters: { type: "object", properties: {} },
      },
      {
        type: "function",
        name: "open_brand_cards",
        description:
          "Open the REAL brand marketplace cards on screen — the actual sponsor brand card modals from the pitch deck (Apex Nutrition, Stride Athletics, Forge Recovery Lab) with tap-through brand profiles, escrow terms, and the apply flow. REQUIRED when someone asks to see the brands, sponsorships, or the marketplace.",
        parameters: { type: "object", properties: {} },
      },
      {
        type: "function",
        name: "start_deck_walkthrough",
        description:
          "Start the narrated Whisper deck walkthrough: you read each slide out loud to the ENTIRE meeting (everyone hears you), the current line is highlighted on screen, and interactive WPP sliders + brand cards are embedded in the slides. REQUIRED when someone asks you to walk through the deck, present Whisper, pitch the room, or read the slides.",
        parameters: { type: "object", properties: {} },
      },
    );
  }
  return tools;
}

/**
 * Converts a display tool call into a renderable Ember block by round-tripping
 * through the existing fenced-block decoder — voice cards and typed cards stay
 * pixel-identical.
 */
export function emberBlockFromTool(
  name: string,
  args: Record<string, unknown>,
): EmberBlock | null {
  let fence: string | null = null;
  if (name === "show_pitch_deck") {
    fence = `\`\`\`deck ${JSON.stringify({
      title: args.title ?? null,
      slides: args.slides ?? [],
    })}\`\`\``;
  } else if (name === "show_chart") {
    fence = `\`\`\`chart ${JSON.stringify({
      type: "line",
      title: args.title ?? null,
      unit: args.unit ?? null,
      data: args.points ?? [],
    })}\`\`\``;
  } else if (name === "show_tips_card") {
    fence = `\`\`\`profilecard ${JSON.stringify({
      title: args.title ?? null,
      bio: args.summary ?? null,
      tips: args.tips ?? [],
    })}\`\`\``;
  } else if (name === "show_plan") {
    fence = `\`\`\`goalplan ${JSON.stringify({
      title: args.title ?? null,
      summary: args.summary ?? null,
      targetDate: args.targetDate ?? null,
      weeklyFocus: args.weeklyFocus ?? [],
      milestones: args.milestones ?? [],
    })}\`\`\``;
  }
  if (!fence) return null;
  return parseEmberBlocks(fence).block;
}

// ── Instructions ─────────────────────────────────────────────────────────────

const VOICE_STYLE = `VOICE STYLE — you are speaking out loud in a natural human voice:
- Sound like a sharp, warm friend: contractions, rhythm, small reactions. Never robotic, never a lecture.
- Keep spoken answers to 1-3 short sentences unless they ask for depth. Numbers said simply ("about ninety cents per thousand views").
- Never read JSON, tool syntax, or URLs out loud. Never mention tools — the cards just appear.
- ALWAYS speak English. Even when a transcript line looks like another language (mis-heard audio), reply in English — only switch languages if the person explicitly asks you to.`;

const TOOL_RULES = `VISUAL CARDS — you have display tools that put rich cards on the user's screen while you talk. RULES:
- ANY time the conversation touches recruiting, prospects, pipelines, coaching, creators, athletes, monetization, WPP, pricing, sponsorships, audience growth, or pitching Whisper — you MUST call a display tool. Not optional; every single time one of those topics comes up.
- Pitching or explaining the business → show_pitch_deck (4-7 slides, real numbers). Numeric series or money math → show_chart. Advice or strategy lists → show_tips_card. Roadmaps → show_plan.
- Use them liberally — several per conversation is great. Keep talking naturally while cards appear.`;

/** Instructions for Ember's live voice inside a meeting. */
export function emberMeetingVoiceInstructions(context: {
  meetingTitle: string;
  participants: string[];
}): string {
  const roster = context.participants
    .map((name) => name.trim())
    .filter((name) => name.length > 0 && name.toLowerCase() !== "you")
    .slice(0, 12);
  return `You are Knot, the built-in AI companion inside Whisper — a social platform with a full creator economy. You are live INSIDE a Whisper video meeting titled "${context.meetingTitle.slice(0, 120)}"${
    roster.length > 0 ? ` with ${roster.join(", ")} on the call` : ""
  }. Only the person talking to you can hear or see you — you are their private whisper during the call.

${VOICE_STYLE}

${TOOL_RULES}

${WHISPER_KNOWLEDGE}`;
}

/** Instructions for Jasper's live voice in the assistant chat. */
export function emberAssistantVoiceInstructions(): string {
  return `You are Knot, the built-in AI companion inside Whisper. Jasper is the separate connected fitness app, not your name. Whisper is a social platform for thoughts, stories, and conversations, with a full creator economy. You are having a live voice conversation with a Whisper member.

${VOICE_STYLE}

${TOOL_RULES}

${WHISPER_KNOWLEDGE}`;
}
