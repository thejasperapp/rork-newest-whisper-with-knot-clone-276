import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useMeetingPanels } from '@/hooks/useMeetingPanels';
import { MeetingJasperButton } from '@/components/MeetingJasperButton';
import { MeetingTitleButton } from '@/components/MeetingTitleButton';
import { useNavigate } from "react-router-dom";
import { MeetingCaptureDrain } from '@/lib/meetingCaptureDrain';
import { retainTranscript, flushTranscriptOutbox } from '@/lib/transcriptOutbox';
import { useQuery } from "@tanstack/react-query";
import {
  AlertTriangle,
  AudioLines,
  BadgeCheck,
  BookOpen,
  Briefcase,
  Calculator,
  CalendarClock,
  CalendarPlus,
  Captions,
  Check,
  ChevronDown,
  ClipboardCheck,
  ClipboardList,
  Copy,
  Droplets,
  Dumbbell,
  ExternalLink,
  Flame,
  Footprints,
  Headphones,
  HeartPulse,
  History,
  Images,
  Instagram,
  BarChart3,
  Loader2,
  Volume2,
  Mail,
  Maximize2,
  MessageCircle,
  Mic,
  MicOff,
  Monitor,
  MonitorOff,
  Moon,
  Music2,
  NotebookPen,
  PhoneCall,
  PhoneOff,
  PictureInPicture2,
  Pin,
  Presentation,
  QrCode,
  RefreshCw,
  Search,
  Send,
  Share2,
  Shield,
  Sparkles,
  Star,
  TrendingUp,
  User,
  UserPlus,
  Users,
  Video,
  RotateCw,
  VideoOff,
  Wand2,
  X,
  Hand,
  Smile,
  MoreVertical,
  Info,
  LayoutGrid,
  Minimize2,
  Settings,
  MessageSquare,
} from "lucide-react";
import { UserX } from "lucide-react";
import { ArrowUp, ChevronUp, Lock } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Avatar } from "@/components/Avatar";
import { EmberMascot } from "@/components/EmberMascot";
import {
  CreatorAnalyticsMiniCard,
  CreatorAnalyticsModal,
} from "@/components/MeetingCreatorAnalytics";
import {
  buildCreatorAnalyticsCard,
  creatorJasperContext,
  type CreatorAnalyticsCardPayload,
} from "@/lib/creatorMeetingCard";
import {
  businessApplyUrl,
  fetchMyBusinessPlus,
  fetchPositions,
  fetchTeam,
  recordMeetingInterest,
  type MyBusinessPlus,
} from "@/lib/businessPlus";
import { BusinessPlusMark } from "@/components/BusinessPlusMark";
import { fetchBrand } from "@/lib/brands";
import { useMyBadge } from "@/hooks/useMyBadge";
import { JasperKitKeyframes, JasperReplyCard, JasperThinkingRail } from "@/components/JasperIntelKit";
import { MeetingSidekick } from "@/components/MeetingSidekick";
import { MeetingWorkspace } from '@/components/MeetingWorkspace';
import { MeetingNotesScreen, transcriptPlainText, withTranscriptBlock } from "@/components/MeetingNotesScreen";
import {
  jasperGlassShellStyle,
  jasperMintShellStyle,
  jasperPillPalette,
} from "@/lib/jasperIntel";
import { useAuth } from "@/hooks/useAuth";
import { useMeetingHost } from "@/hooks/useMeetingHost";
import {
  deleteCloudBackdrop,
  fetchCloudBackdrops,
  saveCloudBackdrop,
  type CloudBackdrop,
} from "@/lib/backdrops";
import { MEET_PORTAL } from "@/lib/portal";
import { parseMeetingInvitation } from "@/lib/meetingInvitation";
import {
  AdjustViewDialog,
  FloatingReactionsLayer,
  MeetMoreMenu,
  MeetReactionsStrip,
  MeetSidePanel,
  MeetSideDrawer,
  MeetKnockPrompt,
  MeetAskingToJoin,
  MeetingReadyCard,
  useFloatingReactions,
  type MeetChatMessage,
  type MeetKnock,
  type MeetKnockState,
  type MeetMenuItem,
  type MeetPanelParticipant,
  type MeetPanelTab,
} from "@/components/MeetRoomKit";
import { meetKnockId, openMeetDoorbell, type MeetDoorbell } from "@/lib/meetDoorbell";
import { MeetPipMosaic, type PipMosaicSource } from "@/lib/meetPipMosaic";
import { useMeetingRecording } from "@/hooks/useMeetingRecording";
import { MeetingRecordingControls } from "@/components/MeetingRecordingControls";
import { MeetingActivities } from "@/components/MeetingActivities";
import { readMeetingStage } from "@/lib/meetingStageCapture";
import { isLikelyEmail, sendMeetingInviteEmails } from "@/lib/meetInvites";
import { MeetSettingsDialog } from "@/components/MeetSettingsDialog";
import { ReportBugDialog } from "@/components/ReportBugDialog";
import {
  MeetPostCallScreen,
  MeetStillThereDialog,
  type PostCallReason,
} from "@/components/MeetRoomKit";
import {
  playMeetEndDing,
  playMeetJoinChime,
  playMeetLeaveChime,
  playMeetTick,
  primeMeetSounds,
} from "@/lib/meetSounds";
import { readMeetPrefs, useMeetPrefs } from "@/lib/meetPrefs";
import {
  WhisperLiveRTC,
  describeMediaBlock,
  isMobileWebKit,
  type LiveParticipantInfo,
  type LocalMediaState,
} from "@/lib/whisperLiveRTC";
import {
  addTranscriptSegment,
  createMeeting,
  endMeeting,
  ensureMeetingRoom,
  fetchHeartRates,
  fetchMeeting,
  fetchTranscript,
  generateMeetingNotes,
  isMeetingUuid,
  joinMeeting,
  reopenMeeting,
  meetingLink,
  resolveMeetingRoomId,
  startMeeting,
} from "@/lib/meetings";
import { createCalendarEvent, type CalendarEventType } from "@/lib/calendar";
import {
  attachesMeetingByDefault,
  detectSpokenSchedule,
  formatSpokenDate,
  SCHEDULE_TYPE_COLORS,
  SCHEDULE_TYPE_LABELS,
  suggestedScheduleTitle,
  toLocalInputValue,
} from "@/lib/scheduleDetect";
import { fetchFollowing, fetchProfilesByIds, sendMessage } from "@/lib/api";
import { fetchVerificationBadges, type VerificationBadge } from "@/lib/verification";
import { EmberBlockCard } from "@/components/EmberBlocks";
import {
  coachModeInfo,
  loadCoachMode,
  type EmberBlock,
  type EmberCoachMode,
} from "@/lib/emberBrain";
import { PITCH_AUDIENCES } from "@/lib/pitch";
import {
  fetchActiveQuestions,
  fetchRecruiterResponses,
  submitApplicantResponse,
  type ApplicantQuestion,
  type ApplicantResponse,
} from "@/lib/applicantQuestionnaire";
import {
  fetchInstagramGallery,
  fetchOrCreateReferralCode,
  fetchProspects,
  instagramAvatarUrl,
  PROSPECT_STATUS_COLORS,
  PROSPECT_STATUS_LABELS,
  type Prospect,
  type ProspectStatus,
} from "@/lib/recruiter";
import { PitchDeckInline } from "@/components/PitchDeckInline";
import {
  SAMPLE_PITCH_DECK,
  fetchPitchDeck,
  generatePitchDeck,
  loadCachedDeck,
  savePitchDeck,
  type JasperPitchDeck,
} from "@/lib/pitchDeck";
import { BACKEND_URL } from "@/lib/billing";
import {
  fetchClientSnapshot,
  fetchCoachRequests,
  type ClientSnapshot,
  type CoachRequest,
} from "@/lib/coach";
import { supabase } from "@/lib/supabase";
import {
  emberExtractApplicationAnswers,
  emberImagine,
  emberMeetingAnswer,
  emberProspectEvaluation,
  type ProspectEvaluation,
} from "@/lib/ember";
import {
  datingCardWirePayload,
  decodeDatingCardWire,
  hasDatingCard,
  isSpeedDateRoom,
  loadDatingCardLocal,
  markSpeedDateRoom,
  type DatingCardWire,
} from "@/lib/datingCards";
import { DatingCardEditor } from "@/components/DatingCardEditor";
import { BlindDateStage } from "@/components/BlindDateStage";
import { BlindDateWrap } from "@/components/BlindDateWrap";
import {
  BLIND_FALLBACK_DECK,
  BLIND_WIRE,
  BlindDateSession,
  blindPairedPartner,
  blindRecordKey,
  encodeBlindDeck,
  generateBlindDeck,
  isBlindReady,
  markBlindReady,
  openBlindRecord,
} from "@/lib/blindDate";
import {
  EmberRealtimeSession,
  emberBlockFromTool,
  emberDisplayTools,
  emberMeetingVoiceInstructions,
} from "@/lib/emberRealtime";
import {
  EMBER_TOUR_SLIDES,
  clampTourPosition,
  emberTourPresenterInstructions,
  emberTourReadPrompt,
  nextTourPosition,
  type DeckTourEventPayload,
} from "@/lib/emberDeckTour";
import {
  BrandCardsDialog,
  EmberDeckTourOverlay,
  WppCalculatorDialog,
} from "@/components/EmberDeckTour";
import {
  startMeetingRecorderTranscription,
  type MeetingRecorderTranscriber,
} from "@/lib/meetingTranscription";
import { cn } from "@/lib/utils";
import { WHISPER_BRAND_GRADIENT_DIAGONAL } from "@/lib/brand";
import {
  BACKDROP_PRESETS,
  deleteBackdrop,
  presetDataUrl,
  saveBackdrop,
  savedBackdrops,
  videoFx,
  type VideoFxMode,
} from "@/lib/videoEffects";

/** Minimal typing for the vendor-prefixed Web Speech API. */
interface SpeechRecognitionLike {
  continuous: boolean;
  interimResults: boolean;
  lang: string;
  onresult: ((event: SpeechRecognitionEventLike) => void) | null;
  onerror: ((event: SpeechRecognitionErrorLike) => void) | null;
  onend: (() => void) | null;
  start: () => void;
  stop: () => void;
}

interface SpeechRecognitionErrorLike {
  error?: string;
}
interface SpeechRecognitionEventLike {
  resultIndex: number;
  results: ArrayLike<{ isFinal: boolean; 0: { transcript: string } }>;
}

function createRecognizer(): SpeechRecognitionLike | null {
  const w = window as unknown as {
    SpeechRecognition?: new () => SpeechRecognitionLike;
    webkitSpeechRecognition?: new () => SpeechRecognitionLike;
  };
  const Ctor = w.SpeechRecognition ?? w.webkitSpeechRecognition;
  if (!Ctor) return null;
  const rec = new Ctor();
  rec.continuous = true;
  rec.interimResults = true;
  rec.lang = "en-US";
  return rec;
}

/** Verification badge icon to show beside a participant's name. */
function BadgeChip({ badge }: { badge: VerificationBadge }) {
  if (badge === "none") return null;
  const config: Record<VerificationBadge, { color: string; icon: React.ReactNode }> = {
    none: { color: "", icon: null },
    verified: {
      color: "text-blue-400",
      icon: <BadgeCheck className="h-3 w-3" />,
    },
    moderator: {
      color: "text-emerald-400",
      icon: <Shield className="h-3 w-3" />,
    },
    admin: {
      color: "text-amber-400",
      icon: <Shield className="h-3 w-3" />,
    },
    owner: {
      color: "text-purple-400",
      icon: <Shield className="h-3 w-3" />,
    },
  };
  const c = config[badge];
  return <span className={c.color}>{c.icon}</span>;
}

/** Role badge — shows coach/recruiter/athlete icon next to name. */
function RoleChip({ username, profileMap }: { username: string; profileMap: Record<string, { is_coach?: boolean; is_recruiter?: boolean; is_athlete?: boolean; is_verified?: boolean }> }) {
  const p = profileMap[username.toLowerCase()];
  if (!p) return null;
  if (p.is_coach) return <Dumbbell className="h-3 w-3 text-orange-400" />;
  if (p.is_recruiter) return <TrendingUp className="h-3 w-3 text-cyan-400" />;
  return null;
}

/**
 * Broadcast payload for "present this client to the whole meeting". The
 * presenter sends the full snapshot so viewers never need database access
 * to the recruiter's private pipeline.
 */
/** The prospect's QR-application state, snapshotted into the broadcast. */
interface PresentedApplication {
  taken: boolean;
  potentialScore: number | null;
  confidenceScore: number | null;
  bestPosition: string | null;
  status: string | null;
  submittedAt: string | null;
}

/** Compact fitness snapshot broadcast with coach-client presentations —
 *  macros, activity, and recent workouts so the whole room sees the
 *  client's real progress without any database access. */
interface PresentedSnapshot {
  caloriesToday: number;
  caloriesGoal: number;
  proteinToday: number;
  proteinGoal: number;
  carbsToday: number;
  carbsGoal: number;
  fatToday: number;
  fatGoal: number;
  waterCups: number;
  streak: number;
  sleepHours: number;
  steps: number;
  activeMinutes: number;
  restingHeartRate: number;
  weightLbs: number;
  bodyFatPct: number;
  workouts: { type: string; durationMinutes: number; calories: number; date: string }[];
}

/** Shrinks the full client snapshot to the broadcast-safe essentials. */
function compactSnapshot(s: ClientSnapshot): PresentedSnapshot {
  return {
    caloriesToday: s.caloriesToday,
    caloriesGoal: s.caloriesGoal,
    proteinToday: s.proteinToday,
    proteinGoal: s.proteinGoal,
    carbsToday: s.carbsToday,
    carbsGoal: s.carbsGoal,
    fatToday: s.fatToday,
    fatGoal: s.fatGoal,
    waterCups: s.waterCount,
    streak: s.loggingStreak,
    sleepHours: s.sleepHours,
    steps: s.steps,
    activeMinutes: s.activeMinutes,
    restingHeartRate: s.restingHeartRate,
    weightLbs: s.bodyMassLbs,
    bodyFatPct: s.bodyFatPct,
    workouts: (s.recentWorkouts ?? []).slice(0, 4),
  };
}

interface PresentedClientPayload {
  kind: "prospect" | "coach-client";
  id: string;
  username: string | null;
  displayName: string | null;
  imageUrl: string | null;
  /** The presented person's Whisper user id (for DM/profile actions). */
  userId: string | null;
  status: string;
  rating: number | null;
  niche: string | null;
  location: string | null;
  source: string | null;
  instagram: string | null;
  tiktok: string | null;
  suggestedRole: string | null;
  notes: string | null;
  contactLog: { date: string; method: string; note: string }[];
  addedAt: string | null;
  application: PresentedApplication | null;
  /** The application Q&A itself — lets recruiters present the application. */
  applicationAnswers: { q: string; a: string }[];
  /** Public photos — prospect Instagram grid or client progress shots. */
  photos: string[];
  /** Coach-client live fitness snapshot (macros, activity, workouts). */
  snapshot: PresentedSnapshot | null;
  /** Bumped on every re-broadcast that carries richer data, so viewers
   *  accept the enriched payload instead of ignoring it as a heartbeat. */
  rev?: number;
  presenterUserId: string;
  presenterName: string;
}

function payloadFromProspect(
  p: Prospect,
  presenterUserId: string,
  presenterName: string,
  application: PresentedApplication | null = null,
  photos: string[] = [],
  applicationAnswers: { q: string; a: string }[] = [],
): PresentedClientPayload {
  return {
    kind: "prospect",
    id: p.id,
    username: p.prospect_username,
    displayName: p.prospect_display_name,
    // Fall back to their Instagram profile photo when none is stored.
    imageUrl: p.prospect_image_url ?? instagramAvatarUrl(p.instagram),
    userId: p.prospect_user_id,
    status: p.status,
    rating: p.rating,
    niche: p.niche,
    location: p.location,
    source: p.source,
    instagram: p.instagram,
    tiktok: p.tiktok,
    suggestedRole: p.suggested_role,
    notes: p.notes ? p.notes.slice(0, 800) : null,
    contactLog: (p.contact_log ?? []).slice(-4),
    addedAt: p.created_at,
    application,
    applicationAnswers,
    photos,
    snapshot: null,
    presenterUserId,
    presenterName,
  };
}

/** A coach's active client, snapshotted for present-to-everyone. */
function payloadFromCoachClient(
  c: CoachRequest,
  presenterUserId: string,
  presenterName: string,
  extras?: {
    displayName?: string | null;
    imageUrl?: string | null;
    snapshot?: PresentedSnapshot | null;
    photos?: string[];
  },
): PresentedClientPayload {
  return {
    kind: "coach-client",
    id: c.id,
    username: c.client_username,
    displayName: extras?.displayName ?? null,
    imageUrl: extras?.imageUrl ?? null,
    userId: c.client_user_id,
    status: "active",
    rating: null,
    niche: null,
    location: null,
    source: null,
    instagram: null,
    tiktok: null,
    suggestedRole: null,
    notes: c.message ? c.message.slice(0, 800) : null,
    contactLog: [],
    addedAt: c.created_at,
    application: null,
    applicationAnswers: [],
    photos: extras?.photos ?? [],
    snapshot: extras?.snapshot ?? null,
    presenterUserId,
    presenterName,
  };
}

/**
 * Pair a pipeline prospect with their QR applicant-questionnaire response.
 * Matches by linked user id first, then by name/handle so responses filed
 * before the prospect signed up still connect.
 */
function matchApplicationResponse(
  p: Prospect,
  responses: ApplicantResponse[],
): ApplicantResponse | null {
  const norm = (s: string | null | undefined): string =>
    (s ?? "").trim().toLowerCase().replace(/^@/, "");
  const username = norm(p.prospect_username);
  const displayName = norm(p.prospect_display_name);
  return (
    responses.find((r) => {
      if (
        p.prospect_user_id &&
        r.applicant_user_id &&
        r.applicant_user_id === p.prospect_user_id
      ) {
        return true;
      }
      const name = norm(r.applicant_name);
      const emailUser = norm(r.applicant_email).split("@")[0] ?? "";
      return (
        (name.length > 1 && (name === username || name === displayName)) ||
        (emailUser.length > 1 && emailUser === username)
      );
    }) ?? null
  );
}

function applicationFromResponse(match: ApplicantResponse): PresentedApplication {
  return {
    taken: true,
    potentialScore: match.potential_score,
    confidenceScore: match.confidence_score,
    bestPosition: match.best_position,
    status: match.status,
    submittedAt: match.created_at,
  };
}

/** The Q&A pairs from a matched application — broadcast so recruiters can
 *  present the actual application to the room. */
function answersFromResponse(
  match: ApplicantResponse | null,
): { q: string; a: string }[] {
  if (!match) return [];
  return Object.values(match.answers ?? {})
    .filter(
      (entry): entry is { question: string; answer: string } =>
        !!entry &&
        typeof entry.question === "string" &&
        typeof entry.answer === "string" &&
        entry.answer.trim().length > 0,
    )
    .slice(0, 8)
    .map((entry) => ({
      q: entry.question.slice(0, 140),
      a: entry.answer.slice(0, 220),
    }));
}

function matchApplication(
  p: Prospect,
  responses: ApplicantResponse[],
): PresentedApplication | null {
  const match = matchApplicationResponse(p, responses);
  return match ? applicationFromResponse(match) : null;
}

/** Compact date for profile facts and contact history rows. */
function shortDate(iso: string | null): string | null {
  if (!iso) return null;
  const parsed = new Date(iso);
  if (Number.isNaN(parsed.getTime())) return null;
  return parsed.toLocaleDateString([], { month: "short", day: "numeric", year: "numeric" });
}

/** A live client stats card a coach broadcast to the whole meeting. */
interface SharedClientCard {
  name: string;
  client: string;
  bpm: number | null;
  sleep: number;
  steps: number;
  calories: number;
  caloriesGoal: number;
  protein: number;
  proteinGoal: number;
  training: string | null;
  at: number;
}

/** Compact live-snapshot block for in-meeting coach questions — the same
 *  one-call source Coach Studio reads, so Jasper coaches from REAL numbers. */
function buildClientVitalsContext(name: string, s: ClientSnapshot): string {
  const lines = [
    `=== CLIENT ON THIS CALL (@${name}) — LIVE SNAPSHOT ===`,
    "You are their accepted coach. Coach from these real numbers when relevant:",
    `Calories today: ${Math.round(s.caloriesToday)}${s.caloriesGoal > 0 ? ` / ${Math.round(s.caloriesGoal)}` : ""}`,
    `Protein today: ${Math.round(s.proteinToday)}g${s.proteinGoal > 0 ? ` / ${Math.round(s.proteinGoal)}g` : ""}`,
    `Sleep last night: ${s.sleepHours > 0 ? `${s.sleepHours.toFixed(1)}h` : "not logged"}`,
    `Steps today: ${s.steps > 0 ? s.steps.toLocaleString() : "not logged"}`,
    s.restingHeartRate > 0 ? `Resting HR: ${Math.round(s.restingHeartRate)} bpm` : null,
    s.bodyMassLbs > 0 ? `Weight: ${Math.round(s.bodyMassLbs)} lb` : null,
    s.loggingStreak > 0 ? `Logging streak: ${s.loggingStreak} days` : null,
    s.recentWorkouts.length > 0
      ? `Recent training: ${s.recentWorkouts
          .slice(0, 3)
          .map((w) => `${w.type} ${Math.round(w.durationMinutes)}m`)
          .join(", ")}`
      : "No recent workouts logged",
  ].filter((l): l is string => typeof l === "string");
  return lines.join("\n");
}

/** An Ember answer someone chose to share with the whole meeting. */
interface SharedEmberAnswer {
  name: string;
  text: string;
  block: EmberBlock | null;
  at: number;
}

/** Live walkthrough state shared across the room via `deck-tour` events. */
interface DeckTourView {
  slide: number;
  segment: number;
  playing: boolean;
  driverPeerId: string;
  driverName: string;
  /** "driver" — narration rides the driver's call audio (web drivers);
   *  "device" — each device plays the fixed line locally (iOS drivers). */
  voice: "driver" | "device";
}

/** Minimal typing for Chrome's Document Picture-in-Picture API. */
interface DocumentPipWindowHost {
  documentPictureInPicture?: {
    requestWindow: (options?: { width?: number; height?: number }) => Promise<Window>;
  };
}

/** Styles injected into the Document PiP mini-window. */
const PIP_WINDOW_CSS = `
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body { width: 100%; height: 100%; background: #070707; overflow: hidden;
    font-family: ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
  #pip-root { display: grid; gap: 6px; padding: 6px; width: 100%; height: 100%; grid-auto-rows: 1fr; }
  .tile { position: relative; overflow: hidden; border-radius: 12px; background: #141416;
    border: 1px solid rgba(255,255,255,0.08); }
  .tile.speaking { border-color: #22d3ee; box-shadow: 0 0 0 1px #22d3ee; }
  .tile video { width: 100%; height: 100%; object-fit: cover; display: block; }
  .tile .fallback { position: absolute; inset: 0; display: flex; align-items: center;
    justify-content: center; color: rgba(255,255,255,0.85); font-size: 22px; font-weight: 800;
    background: #1d1d21; }
  .tile .label { position: absolute; left: 6px; bottom: 6px; max-width: calc(100% - 12px);
    overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: #fff;
    font-size: 10.5px; font-weight: 700; background: rgba(0,0,0,0.55); border-radius: 999px;
    padding: 2px 8px; }
`;

/** Traffic-light color for a 0-100 score. */
function scoreColor(score: number): string {
  return score >= 70 ? "#34d399" : score >= 45 ? "#fbbf24" : "#f87171";
}

/** iPhone/iPad browser — where the native Whisper app may be installed. */
function isIOSBrowser(): boolean {
  if (typeof navigator === "undefined") return false;
  const ua = navigator.userAgent;
  const touchMac = navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1;
  return /iPhone|iPad|iPod/i.test(ua) || touchMac;
}

/** Explicit OS handoff: ordinary rooms use Meet; dating/calls stay social.
 * The current browser lobby remains available when the target app is absent. */
function openMeetingInApp(idOrCode: string, speedDate: boolean, invitationLink?: string): void {
  const target = invitationLink ? parseMeetingInvitation(invitationLink) : null;
  const social = speedDate || target?.social === true;
  const query = speedDate ? "?sd=1" : target?.social ? new URL(target.href).search : "";
  window.location.href = `${social ? "whisper" : "whisperworkspace"}://meet/${encodeURIComponent(idOrCode)}${query}`;
}

/** "Open in the Whisper app" — iOS browsers only; app-first, web as backup. */
function OpenInAppButton({
  idOrCode,
  speedDate,
  invitationLink,
  tone = "light",
}: {
  idOrCode: string;
  speedDate: boolean;
  invitationLink?: string;
  tone?: "light" | "rose";
}) {
  if (!isIOSBrowser()) return null;
  return (
    <button
      type="button"
      onClick={() => openMeetingInApp(idOrCode, speedDate, invitationLink)}
      className={cn(
        "mt-3 flex h-11 w-full items-center justify-center gap-2 rounded-full text-[13.5px] font-bold transition-transform active:scale-[0.98]",
        tone === "rose"
          ? "border border-white/25 bg-white/10 text-white"
          : "border border-border bg-card text-foreground hover:bg-accent",
      )}
    >
      <ExternalLink className="h-4 w-4" />
      {speedDate || (invitationLink && parseMeetingInvitation(invitationLink)?.social) ? "Open in the Whisper app" : "Open in Whisper Meet"}
    </button>
  );
}

/** The white check that marks the applied backdrop tile. */
function SelectedMark({ className }: { className?: string }): JSX.Element {
  return (
    <span
      className={cn(
        "pointer-events-none absolute grid h-5 w-5 place-items-center rounded-full bg-white text-black shadow-[0_1px_4px_rgba(0,0,0,0.4)]",
        className ?? "right-1.5 top-1.5",
      )}
    >
      <Check className="h-3 w-3" strokeWidth={3} />
    </span>
  );
}

/**
 * Backgrounds & effects — Meet's side-panel grammar on desktop (a card
 * docked to the right edge like People / Chat, the stage stays visible), a
 * bottom sheet on phones. A live, mirrored self-preview sits on top so the
 * effect is judged on your own face before anyone else sees it.
 */
function BackgroundsPanel({
  open,
  mode,
  imageUrl,
  onClose,
  onSelect,
  previewTrack,
}: {
  open: boolean;
  mode: VideoFxMode;
  imageUrl: string | null;
  onClose: () => void;
  onSelect: (mode: VideoFxMode, imageUrl?: string | null) => void;
  /** The outgoing camera track (processed when an effect is on). */
  previewTrack?: () => MediaStreamTrack | null;
}) {
  const { user } = useAuth();
  const previewRef = useRef<HTMLVideoElement | null>(null);
  const [previewLive, setPreviewLive] = useState<boolean>(false);
  const previewGetter = useRef<(() => MediaStreamTrack | null) | undefined>(previewTrack);
  previewGetter.current = previewTrack;

  // Follow the outgoing track: effects swap the published track in place, so
  // poll cheaply instead of threading every swap through props.
  useEffect(() => {
    if (!open) return;
    const el = previewRef.current;
    let last: MediaStreamTrack | null | undefined;
    const sync = (): void => {
      const track = previewGetter.current?.() ?? null;
      const live = !!track && track.readyState === "live";
      if (track === last) return;
      last = track;
      if (el) {
        el.srcObject = live ? new MediaStream([track]) : null;
        if (live) void el.play().catch(() => undefined);
      }
      setPreviewLive(live);
    };
    sync();
    const timer = window.setInterval(sync, 700);
    return () => {
      window.clearInterval(timer);
      if (el) el.srcObject = null;
    };
  }, [open]);
  const [prompt, setPrompt] = useState<string>("");
  const [generating, setGenerating] = useState<boolean>(false);
  const [genError, setGenError] = useState<string | null>(null);
  const [saved, setSaved] = useState<string[]>([]);
  const [cloud, setCloud] = useState<CloudBackdrop[]>([]);

  useEffect(() => {
    if (!open) return;
    setSaved(savedBackdrops());
    // The synced library — the exact list the iOS effects sheet shows.
    void fetchCloudBackdrops().then((result) => setCloud(result.items));
  }, [open]);

  if (!open) return null;

  const generate = async (): Promise<void> => {
    const trimmed = prompt.trim();
    if (!trimmed || generating) return;
    setGenerating(true);
    setGenError(null);
    const url = await emberImagine(
      `Video call virtual background, no people, wide 16:9 framing, photographic, softly lit: ${trimmed}`,
    );
    if (url) {
      setSaved(saveBackdrop(url));
      onSelect("backdrop", url);
      setPrompt("");
      if (user) {
        // Sync to the shared library so every device gets it.
        const row = await saveCloudBackdrop(user.id, url, trimmed);
        if (row) {
          setCloud((prev) =>
            [row, ...prev.filter((c) => c.id !== row.id)].slice(0, 12),
          );
        }
      }
    } else {
      setGenError("Couldn't generate that backdrop. Try a different prompt.");
    }
    setGenerating(false);
  };

  const tileClass =
    "relative aspect-video overflow-hidden rounded-[14px] border transition-transform active:scale-95";

  return (
    <div className="fixed inset-0 z-[70]">
      {/* Click-away: dims on phones (a sheet); clear on desktop (a side
          panel — the stage stays visible, Meet grammar). */}
      <button
        type="button"
        className="absolute inset-0 bg-black/55 sm:bg-transparent"
        onClick={onClose}
        aria-label="Close backgrounds"
      />
      <div className="absolute inset-x-0 bottom-0 flex max-h-[86vh] flex-col overflow-hidden rounded-t-[26px] bg-[#1f2023] text-white shadow-2xl ring-1 ring-white/10 sm:inset-y-4 sm:bottom-4 sm:left-auto sm:right-4 sm:max-h-none sm:w-[380px] sm:rounded-[16px]">
        <div className="mx-auto mt-3 h-1 w-9 shrink-0 rounded-full bg-white/20 sm:hidden" />
        <div className="flex shrink-0 items-center justify-between pb-2 pl-5 pr-3 pt-4">
          <h2 className="text-[17px] font-semibold">Backgrounds & effects</h2>
          <button
            type="button"
            onClick={onClose}
            className="grid h-10 w-10 place-items-center rounded-full text-white/80 transition-colors hover:bg-white/10 hover:text-white"
            aria-label="Close"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto px-5 pb-[max(1.5rem,env(safe-area-inset-bottom))] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
        {/* Live self-preview — what everyone else sees, effect applied. */}
        <div className="relative aspect-video w-full overflow-hidden rounded-[14px] bg-black ring-1 ring-white/10">
          <video
            ref={previewRef}
            autoPlay
            playsInline
            muted
            className={cn(
              "absolute inset-0 h-full w-full -scale-x-100 object-cover transition-opacity duration-300",
              previewLive ? "opacity-100" : "opacity-0",
            )}
          />
          {!previewLive && (
            <div className="absolute inset-0 flex flex-col items-center justify-center gap-1.5 text-white/55">
              <VideoOff className="h-5 w-5" />
              <span className="text-[12px] font-semibold">Camera is off</span>
            </div>
          )}
          <span className="absolute bottom-2 left-2 rounded-full bg-black/55 px-2 py-0.5 text-[10.5px] font-bold text-white backdrop-blur-md">
            {mode === "none" ? "No effect" : mode === "blur" ? "Blur" : "Backdrop"}
          </span>
        </div>

        <p className="mb-2 mt-5 text-[10.5px] font-black uppercase tracking-[0.14em] text-white/45">
          Effect
        </p>
        <div className="grid grid-cols-2 gap-2.5">
          <button
            type="button"
            onClick={() => onSelect("none")}
            className={cn(
              "flex h-[74px] flex-col items-center justify-center gap-1.5 rounded-[14px] border text-[12px] font-bold transition-colors",
              mode === "none"
                ? "border-transparent bg-white text-black"
                : "border-white/12 bg-white/8 text-white hover:bg-white/12",
            )}
          >
            <User className="h-5 w-5" />
            None
          </button>
          <button
            type="button"
            onClick={() => onSelect("blur")}
            className={cn(
              "flex h-[74px] flex-col items-center justify-center gap-1.5 rounded-[14px] border text-[12px] font-bold transition-colors",
              mode === "blur"
                ? "border-transparent bg-white text-black"
                : "border-white/12 bg-white/8 text-white hover:bg-white/12",
            )}
          >
            <Droplets className="h-5 w-5" />
            Blur
          </button>
        </div>

        <p className="mb-2 mt-5 text-[10.5px] font-black uppercase tracking-[0.14em] text-white/45">
          Backdrops
        </p>
        <div className="grid grid-cols-3 gap-2.5">
          {BACKDROP_PRESETS.map((preset) => {
            const url = presetDataUrl(preset);
            const selected = mode === "backdrop" && imageUrl === url;
            return (
              <button
                key={preset.id}
                type="button"
                onClick={() => onSelect("backdrop", url)}
                className={cn(tileClass, selected ? "border-transparent ring-2 ring-white" : "border-white/10")}
              >
                <img src={url} alt={preset.name} className="absolute inset-0 h-full w-full object-cover" />
                <span className="absolute bottom-1.5 left-1.5 rounded-full bg-black/55 px-2 py-0.5 text-[10px] font-bold">
                  {preset.name}
                </span>
                {selected && <SelectedMark />}
              </button>
            );
          })}
        </div>

        <p className="mb-2 mt-5 text-[10.5px] font-black uppercase tracking-[0.14em] text-white/45">
          Generate with Jasper
        </p>
        <div className="flex items-center gap-2">
          <input
            value={prompt}
            onChange={(e) => setPrompt(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") void generate();
            }}
            placeholder="A cozy cabin office, warm light…"
            className="h-11 min-w-0 flex-1 rounded-2xl border border-white/12 bg-white/8 px-4 text-[14px] text-white placeholder:text-white/35 focus:outline-none focus:ring-1 focus:ring-white/30"
          />
          <button
            type="button"
            onClick={() => void generate()}
            disabled={generating || !prompt.trim()}
            className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-white text-black transition-opacity disabled:opacity-50"
            aria-label="Generate backdrop"
          >
            {generating ? (
              <Loader2 className="h-4.5 w-4.5 animate-spin" />
            ) : (
              <Sparkles className="h-4.5 w-4.5" />
            )}
          </button>
        </div>
        {generating && (
          <p className="mt-2 text-[12px] font-semibold text-white/55">
            Jasper is painting your backdrop…
          </p>
        )}
        {genError && (
          <p className="mt-2 text-[12px] font-semibold text-red-400">{genError}</p>
        )}

        {(cloud.length > 0 || saved.length > 0) && (
          <>
            <p className="mb-2 mt-5 text-[10.5px] font-black uppercase tracking-[0.14em] text-white/45">
              Your backdrops · synced to your account
            </p>
            <div className="grid grid-cols-3 gap-2.5">
              {cloud.map((item) => {
                const selected = mode === "backdrop" && imageUrl === item.url;
                return (
                  <div
                    key={item.id}
                    className={cn(tileClass, selected ? "border-transparent ring-2 ring-white" : "border-white/10")}
                  >
                    <button
                      type="button"
                      onClick={() => onSelect("backdrop", item.url)}
                      className="absolute inset-0"
                      aria-label="Use this backdrop"
                    >
                      <img
                        src={item.url}
                        alt={item.prompt ?? "Saved backdrop"}
                        className="absolute inset-0 h-full w-full object-cover"
                        loading="lazy"
                      />
                    </button>
                    <button
                      type="button"
                      onClick={() => {
                        setCloud((prev) => prev.filter((c) => c.id !== item.id));
                        void deleteCloudBackdrop(item);
                        if (imageUrl === item.url) onSelect("none");
                      }}
                      className="absolute right-1 top-1 flex h-6 w-6 items-center justify-center rounded-full bg-black/65 text-white"
                      aria-label="Delete backdrop"
                    >
                      <X className="h-3 w-3" />
                    </button>
                    {selected && <SelectedMark className="left-1.5 top-1.5" />}
                  </div>
                );
              })}
              {saved
                .filter((url) => !cloud.some((c) => c.url === url))
                .map((url, index) => {
                  const selected = mode === "backdrop" && imageUrl === url;
                  return (
                    <div
                      key={`${index}-${url.slice(-16)}`}
                      className={cn(tileClass, selected ? "border-transparent ring-2 ring-white" : "border-white/10")}
                    >
                      <button
                        type="button"
                        onClick={() => onSelect("backdrop", url)}
                        className="absolute inset-0"
                        aria-label="Use this backdrop"
                      >
                        <img src={url} alt="Saved backdrop" className="absolute inset-0 h-full w-full object-cover" />
                      </button>
                      <button
                        type="button"
                        onClick={() => {
                          setSaved(deleteBackdrop(url));
                          if (imageUrl === url) onSelect("none");
                        }}
                        className="absolute right-1 top-1 flex h-6 w-6 items-center justify-center rounded-full bg-black/65 text-white"
                        aria-label="Delete backdrop"
                      >
                        <X className="h-3 w-3" />
                      </button>
                      {selected && <SelectedMark className="left-1.5 top-1.5" />}
                    </div>
                  );
                })}
            </div>
          </>
        )}

        <p className="mt-5 text-[11px] leading-relaxed text-white/40">
          Applies to your camera in meetings and calls. Only you need to change it — everyone sees your new background. Generated backdrops sync to your account, so the same library appears in the iOS app.
        </p>
        </div>
      </div>
    </div>
  );
}

/** Coach / creator / athlete chips with the recommended one lit. Dark-context only. */
function PlacementChips({
  placement,
  compact = false,
}: {
  placement: string;
  compact?: boolean;
}): React.ReactElement {
  return (
    <div className="flex flex-wrap gap-1.5">
      {(["coach", "creator", "athlete"] as const).map((role) => (
        <span
          key={role}
          className={cn(
            "rounded-full font-black uppercase tracking-wide transition-colors",
            compact ? "px-2 py-0.5 text-[8.5px]" : "px-2.5 py-1 text-[10px]",
            role === placement
              ? "bg-cyan-400 text-slate-950"
              : "bg-white/8 text-white/40",
          )}
        >
          {role}
        </span>
      ))}
    </div>
  );
}

/** The DM notes card body — the "📋 Meeting notes —" prefix is the wire every
 *  client detects, so it stays first; then the notes, the link to the room,
 *  and the FULL transcript under its marker line (every client — web + iOS —
 *  splits it off and renders the collapsible transcript card). */
function notesDmText(title: string, notes: string, link?: string, transcript?: string | null): string {
  const header = `\u{1F4CB} Meeting notes — ${title}`;
  const tail = link ? `\n\n\u{1F517} Full notes & transcript: ${link}` : "";
  return withTranscriptBlock(`${header}\n\n${notes.trim().slice(0, 6000)}${tail}`, transcript);
}

/** Kind-specific accent theming for presented cards. */
const PRESENT_THEMES = {
  prospect: { accent: "#22d3ee", chip: "Prospect", ring: "rgba(34,211,238," },
  "coach-client": { accent: "#fb923c", chip: "Client", ring: "rgba(251,146,60," },
} as const;

function presentTheme(kind: PresentedClientPayload["kind"]) {
  return PRESENT_THEMES[kind] ?? PRESENT_THEMES.prospect;
}

/** Animates a number from 0 to `target` with an ease-out — the score count-up. */
function useCountUp(target: number | null): number | null {
  const [value, setValue] = useState<number | null>(null);
  useEffect(() => {
    if (target == null) {
      setValue(null);
      return;
    }
    let raf = 0;
    const start = performance.now();
    const duration = 950;
    const tick = (now: number): void => {
      const t = Math.min(1, (now - start) / duration);
      const eased = 1 - Math.pow(1 - t, 3);
      setValue(Math.round(target * eased));
      if (t < 1) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [target]);
  return value;
}

/**
 * Wraps a floating overlay so anyone can grab it and park it anywhere on
 * screen — presented cards and shared answers must never block the call.
 * The position persists per surface, stays clamped to the viewport, and a
 * real drag suppresses the click so buttons inside keep working normally.
 */
function DraggableFloat({
  storageKey,
  className,
  children,
}: {
  storageKey: string;
  className?: string;
  children: React.ReactNode;
}): React.ReactElement {
  const [pos, setPos] = useState<{ x: number; y: number } | null>(() => {
    try {
      const raw = localStorage.getItem(storageKey);
      if (!raw) return null;
      const parsed = JSON.parse(raw) as { x?: number; y?: number };
      return typeof parsed.x === "number" && typeof parsed.y === "number"
        ? { x: parsed.x, y: parsed.y }
        : null;
    } catch {
      return null;
    }
  });
  const ref = useRef<HTMLDivElement | null>(null);
  const dragRef = useRef<{
    startX: number;
    startY: number;
    offsetX: number;
    offsetY: number;
    moved: boolean;
  } | null>(null);
  const suppressClickRef = useRef<boolean>(false);

  const clamp = useCallback((x: number, y: number): { x: number; y: number } => {
    const el = ref.current;
    const w = el?.offsetWidth ?? 140;
    const h = el?.offsetHeight ?? 160;
    return {
      x: Math.min(Math.max(6, x), Math.max(6, window.innerWidth - w - 6)),
      y: Math.min(Math.max(6, y), Math.max(6, window.innerHeight - h - 6)),
    };
  }, []);

  // Keep the card on-screen when the window resizes.
  useEffect(() => {
    if (!pos) return;
    const onResize = (): void => setPos((p) => (p ? clamp(p.x, p.y) : p));
    window.addEventListener("resize", onResize);
    return () => window.removeEventListener("resize", onResize);
  }, [pos, clamp]);

  return (
    <div
      ref={ref}
      className={cn("float-grab", className)}
      style={
        pos
          ? {
              position: "fixed",
              left: pos.x,
              top: pos.y,
              right: "auto",
              bottom: "auto",
              transform: "none",
              margin: 0,
            }
          : undefined
      }
      onPointerDown={(event) => {
        if (event.pointerType === "mouse" && event.button !== 0) return;
        const el = ref.current;
        if (!el) return;
        const rect = el.getBoundingClientRect();
        // NO pointer capture here — capturing on pointerdown retargets the
        // eventual click to this wrapper, which silently swallowed every
        // button inside (expand/stop/dismiss). Capture starts only after
        // the movement crosses the drag threshold below.
        dragRef.current = {
          startX: event.clientX,
          startY: event.clientY,
          offsetX: event.clientX - rect.left,
          offsetY: event.clientY - rect.top,
          moved: false,
        };
      }}
      onPointerMove={(event) => {
        const drag = dragRef.current;
        const el = ref.current;
        if (!drag || !el) return;
        if (!drag.moved) {
          const travelled = Math.hypot(
            event.clientX - drag.startX,
            event.clientY - drag.startY,
          );
          if (travelled < 7) return;
          drag.moved = true;
          try {
            el.setPointerCapture(event.pointerId);
          } catch {
            /* capture unsupported */
          }
        }
        setPos(clamp(event.clientX - drag.offsetX, event.clientY - drag.offsetY));
      }}
      onPointerUp={(event) => {
        const drag = dragRef.current;
        dragRef.current = null;
        try {
          ref.current?.releasePointerCapture(event.pointerId);
        } catch {
          /* already released */
        }
        if (drag?.moved) {
          suppressClickRef.current = true;
          setPos((p) => {
            if (p) {
              try {
                localStorage.setItem(storageKey, JSON.stringify(p));
              } catch {
                /* storage unavailable */
              }
            }
            return p;
          });
        }
      }}
      onClickCapture={(event) => {
        if (suppressClickRef.current) {
          suppressClickRef.current = false;
          event.preventDefault();
          event.stopPropagation();
        }
      }}
    >
      {children}
    </div>
  );
}

/**
 * The phone-shaped presenting card — docked above the controls for everyone
 * in the call (and mirrored inside the presenter's video frame). Springs in
 * with a blur-pop, slips out on stop, spins a soft accent ring around the
 * avatar, and counts the potential score up from zero.
 */
function MiniClientPhoneCard({
  client,
  onExpand,
  onStop,
  leaving = false,
  size = "md",
}: {
  client: PresentedClientPayload;
  onExpand: () => void;
  onStop?: (() => void) | null;
  /** Plays the exit animation while the card unmounts. */
  leaving?: boolean;
  size?: "sm" | "md";
}): React.ReactElement {
  const theme = presentTheme(client.kind);
  const score = client.application?.taken
    ? client.application.potentialScore
    : null;
  const animatedScore = useCountUp(
    typeof score === "number" ? Math.round(score) : null,
  );
  const sm = size === "sm";
  return (
    <div className={cn("relative", leaving ? "present-card-out" : "present-card-in")}>
      <button
        type="button"
        onClick={(event) => {
          event.stopPropagation();
          onExpand();
        }}
        aria-label={`Expand ${client.displayName ?? client.username ?? "client"}'s profile`}
        className={cn(
          "block overflow-hidden rounded-[20px] border text-left shadow-[0_16px_44px_rgba(0,0,0,0.6)] backdrop-blur-xl transition-transform duration-200 hover:scale-[1.045] active:scale-95",
          sm ? "w-[92px]" : "w-[122px]",
        )}
        style={{
          borderColor: `${theme.ring}0.45)`,
          background: `linear-gradient(168deg, ${theme.ring}0.2) 0%, ${theme.ring}0.05) 34%, rgba(9,10,13,0.94) 62%)`,
        }}
      >
        {/* Phone notch */}
        <div className="flex justify-center pt-1.5">
          <span className="h-1 w-7 rounded-full bg-white/18" />
        </div>
        <div className={cn("flex flex-col items-center pb-2 pt-1.5", sm ? "px-1.5" : "px-2")}>
          <span className="relative">
            <span
              className="present-ring"
              style={{
                background: `conic-gradient(from 0deg, transparent 8%, ${theme.accent} 30%, transparent 52%, ${theme.ring}0.55) 76%, transparent 94%)`,
              }}
              aria-hidden
            />
            <Avatar
              url={client.imageUrl}
              name={client.displayName ?? client.username ?? "?"}
              size={sm ? 34 : 42}
              className="relative ring-2 ring-zinc-950"
            />
          </span>
          <p
            className={cn(
              "mt-1.5 w-full truncate text-center font-bold leading-tight text-white",
              sm ? "text-[8.5px]" : "text-[10px]",
            )}
          >
            {client.displayName ?? client.username ?? "Client"}
          </p>
          <span
            className="mt-1 flex items-center gap-1 rounded-full px-1.5 py-0.5"
            style={{ background: `${theme.ring}0.14)` }}
          >
            <span
              className="h-1 w-1 animate-pulse rounded-full"
              style={{ background: theme.accent }}
            />
            <span
              className={cn(
                "font-black uppercase tracking-[0.1em]",
                sm ? "text-[6.5px]" : "text-[7px]",
              )}
              style={{ color: theme.accent }}
            >
              Live · {theme.chip}
            </span>
          </span>
          {typeof score === "number" && (
            <div className="mt-1.5 w-full px-0.5">
              <div className="flex items-baseline justify-between">
                <span className={cn("font-black text-white", sm ? "text-[9px]" : "text-[12px]")}>
                  {animatedScore ?? 0}
                </span>
                <span className="text-[6px] font-bold uppercase text-white/40">/100</span>
              </div>
              <div className="mt-0.5 h-[3px] overflow-hidden rounded-full bg-white/10">
                <div
                  className="h-full rounded-full transition-[width] duration-200"
                  style={{
                    width: `${Math.min(100, Math.max(4, animatedScore ?? 0))}%`,
                    background: scoreColor(score),
                  }}
                />
              </div>
            </div>
          )}
          {client.kind === "coach-client" && client.snapshot && (
            <div className="mt-1.5 w-full px-0.5">
              <div className="flex items-baseline justify-between">
                <span className={cn("font-black text-white", sm ? "text-[9px]" : "text-[11px]")}>
                  {client.snapshot.caloriesToday}
                </span>
                <span className="text-[6px] font-bold uppercase text-white/40">
                  /{client.snapshot.caloriesGoal > 0 ? client.snapshot.caloriesGoal : "—"} kcal
                </span>
              </div>
              <div className="mt-0.5 h-[3px] overflow-hidden rounded-full bg-white/10">
                <div
                  className="h-full rounded-full transition-[width] duration-200"
                  style={{
                    width: `${Math.min(100, Math.max(4, client.snapshot.caloriesGoal > 0 ? (client.snapshot.caloriesToday / client.snapshot.caloriesGoal) * 100 : 4))}%`,
                    background: "#fb923c",
                  }}
                />
              </div>
            </div>
          )}
          {!sm && (
            <span className="mt-1.5 w-full truncate text-center text-[6.5px] font-bold uppercase tracking-wide text-white/40">
              by @{client.presenterName}
            </span>
          )}
          <span className={cn("flex items-center gap-0.5 font-bold uppercase tracking-wide text-white/45", sm ? "mt-1 text-[6.5px]" : "mt-1 text-[7px]")}>
            <Maximize2 className="h-2 w-2" />
            Tap to expand
          </span>
        </div>
      </button>
      {onStop && (
        <button
          type="button"
          onClick={(event) => {
            event.stopPropagation();
            onStop();
          }}
          aria-label="Stop presenting"
          className="absolute -right-1.5 -top-1.5 flex h-5 w-5 items-center justify-center rounded-full bg-red-500 text-white shadow-md transition-colors hover:bg-red-400"
        >
          <X className="h-2.5 w-2.5" />
        </button>
      )}
    </div>
  );
}

/**
 * The client profile card — shown to the presenter as a preview and to the
 * whole meeting as the presented overlay. Pure display; actions come via
 * `footer` so both uses stay in sync.
 */
function ClientProfileCard({
  client,
  live = false,
  footer,
}: {
  client: PresentedClientPayload;
  live?: boolean;
  footer?: React.ReactNode;
}): React.ReactElement {
  const isClient = client.kind === "coach-client";
  const accent = isClient ? "#fb923c" : "#22d3ee";
  const statusColor = isClient
    ? "#34d399"
    : PROSPECT_STATUS_COLORS[client.status as ProspectStatus] ?? "#6b7280";
  const statusLabel = isClient
    ? "Active client"
    : PROSPECT_STATUS_LABELS[client.status as ProspectStatus] ?? client.status;
  const added = shortDate(client.addedAt);
  const facts: { label: string; value: string }[] = [];
  if (client.niche) facts.push({ label: "Niche", value: client.niche });
  if (client.location) facts.push({ label: "Location", value: client.location });
  if (client.source) facts.push({ label: "Source", value: client.source });
  if (added) facts.push({ label: isClient ? "Client since" : "In pipeline since", value: added });

  // Coach-client live snapshot — macros, activity, and recent workouts.
  const snap = client.snapshot;
  const macroRows = snap
    ? [
        { label: "Calories", today: snap.caloriesToday, goal: snap.caloriesGoal, unit: "kcal", color: "#fb923c" },
        { label: "Protein", today: snap.proteinToday, goal: snap.proteinGoal, unit: "g", color: "#34d399" },
        { label: "Carbs", today: snap.carbsToday, goal: snap.carbsGoal, unit: "g", color: "#60a5fa" },
        { label: "Fat", today: snap.fatToday, goal: snap.fatGoal, unit: "g", color: "#fbbf24" },
      ].filter((m) => m.today > 0 || m.goal > 0)
    : [];
  const activityTiles = snap
    ? [
        { label: "Steps", value: snap.steps > 0 ? snap.steps.toLocaleString() : null },
        { label: "Sleep", value: snap.sleepHours > 0 ? `${snap.sleepHours.toFixed(1)}h` : null },
        { label: "Water", value: snap.waterCups > 0 ? `${snap.waterCups} cups` : null },
        { label: "Weight", value: snap.weightLbs > 0 ? `${Math.round(snap.weightLbs)} lb` : null },
        { label: "Body fat", value: snap.bodyFatPct > 0 ? `${snap.bodyFatPct.toFixed(1)}%` : null },
        { label: "Resting HR", value: snap.restingHeartRate > 0 ? `${Math.round(snap.restingHeartRate)} bpm` : null },
      ].filter((t): t is { label: string; value: string } => t.value !== null)
    : [];

  return (
    <div
      className="overflow-hidden rounded-[28px] border bg-zinc-950 shadow-[0_30px_90px_rgba(0,0,0,0.6)]"
      style={{ borderColor: `${accent}33` }}
    >
      <div
        className="relative h-20"
        style={{
          background: `radial-gradient(circle at 20% 0%, ${accent}52, transparent 60%), linear-gradient(135deg, ${accent}42, rgba(9,9,11,0.2))`,
        }}
      >
        {live && (
          <span className="absolute right-3 top-3 flex items-center gap-1.5 rounded-full bg-black/55 px-2.5 py-1 backdrop-blur">
            <span className="h-1.5 w-1.5 animate-pulse rounded-full" style={{ background: accent }} />
            <span className="text-[9px] font-black uppercase tracking-[0.14em]" style={{ color: accent }}>
              Presenting live
            </span>
          </span>
        )}
      </div>
      <div className="px-5 pb-5">
        <div className="-mt-10 flex items-end justify-between gap-3">
          <Avatar
            url={client.imageUrl}
            name={client.displayName ?? client.username ?? "?"}
            size={84}
            className="shadow-2xl ring-4 ring-zinc-950"
          />
          {typeof client.rating === "number" && client.rating > 0 && (
            <div className="mb-1 flex items-center gap-0.5">
              {[1, 2, 3, 4, 5].map((i) => (
                <Star
                  key={i}
                  className={cn(
                    "h-4 w-4",
                    i <= (client.rating ?? 0)
                      ? "fill-amber-400 text-amber-400"
                      : "text-white/15",
                  )}
                />
              ))}
            </div>
          )}
        </div>
        <div className="mt-2.5">
          <p className="text-[20px] font-extrabold leading-tight text-white">
            {client.displayName ?? client.username ?? "Unknown client"}
          </p>
          {client.username && (
            <p className="text-[13px] font-medium text-white/45">@{client.username}</p>
          )}
        </div>
        <div className="mt-3 flex flex-wrap items-center gap-1.5">
          <span
            className="rounded-full px-2.5 py-1 text-[10px] font-black uppercase tracking-wide"
            style={{ backgroundColor: `${statusColor}26`, color: statusColor }}
          >
            {statusLabel}
          </span>
          {client.suggestedRole && (
            <span className="rounded-full bg-white/8 px-2.5 py-1 text-[10px] font-bold uppercase tracking-wide text-white/70">
              Future {client.suggestedRole}
            </span>
          )}
        </div>
        {/* Prospect application (the QR questionnaire) + potential score —
            recruiter cards only; coach clients show their own footer facts. */}
        {!isClient && (client.application?.taken ? (
          <div className="mt-4 rounded-2xl border border-emerald-400/20 bg-emerald-400/[0.06] p-3.5">
            <div className="flex items-center justify-between gap-2">
              <span className="flex items-center gap-1.5">
                <ClipboardCheck className="h-3.5 w-3.5 text-emerald-300" />
                <span className="text-[9px] font-black uppercase tracking-[0.12em] text-emerald-200">
                  Prospect application
                </span>
              </span>
              {shortDate(client.application.submittedAt) && (
                <span className="text-[9.5px] font-semibold text-white/40">
                  {shortDate(client.application.submittedAt)}
                </span>
              )}
            </div>
            {typeof client.application.potentialScore === "number" && (
              <div className="mt-2.5 flex items-center gap-3">
                <p className="text-[27px] font-black leading-none text-white">
                  {Math.round(client.application.potentialScore)}
                  <span className="ml-0.5 text-[11px] font-bold text-white/40">/100</span>
                </p>
                <div className="h-1.5 min-w-0 flex-1 overflow-hidden rounded-full bg-white/10">
                  <div
                    className="h-full rounded-full transition-[width] duration-700"
                    style={{
                      width: `${Math.min(100, Math.max(3, client.application.potentialScore))}%`,
                      background:
                        client.application.potentialScore >= 70
                          ? "#34d399"
                          : client.application.potentialScore >= 45
                            ? "#fbbf24"
                            : "#f87171",
                    }}
                  />
                </div>
              </div>
            )}
            <p className="mt-1 text-[9px] font-bold uppercase tracking-[0.12em] text-white/35">
              Potential score
            </p>
            <div className="mt-2 flex flex-wrap gap-1.5">
              {client.application.bestPosition && (
                <span className="rounded-full bg-emerald-400/12 px-2.5 py-1 text-[10px] font-bold uppercase tracking-wide text-emerald-200">
                  Best fit · {client.application.bestPosition}
                </span>
              )}
              {typeof client.application.confidenceScore === "number" && (
                <span className="rounded-full bg-white/8 px-2.5 py-1 text-[10px] font-bold uppercase tracking-wide text-white/60">
                  {Math.round(client.application.confidenceScore)}% confidence
                </span>
              )}
              {client.application.status && client.application.status !== "submitted" && (
                <span className="rounded-full bg-white/8 px-2.5 py-1 text-[10px] font-bold uppercase tracking-wide text-white/60">
                  {client.application.status}
                </span>
              )}
            </div>
          </div>
        ) : (
          <div className="mt-4 flex items-center gap-2.5 rounded-2xl border border-dashed border-white/12 bg-white/[0.03] px-3.5 py-3">
            <QrCode className="h-4 w-4 shrink-0 text-white/35" />
            <p className="text-[11.5px] leading-snug text-white/50">
              Hasn't taken the prospect application yet — share your QR code to
              get their potential score.
            </p>
          </div>
        ))}
        {/* The application Q&A — the recruiter presenting the actual
            application the prospect filed (or Ember captured live). */}
        {!isClient && client.applicationAnswers.length > 0 && (
          <div className="mt-3 rounded-2xl border border-white/8 bg-white/[0.04] p-3.5">
            <div className="flex items-center gap-1.5 text-white/40">
              <ClipboardList className="h-3.5 w-3.5" />
              <p className="text-[9px] font-black uppercase tracking-[0.12em]">
                Application answers
              </p>
            </div>
            <div className="mt-2 space-y-2.5">
              {client.applicationAnswers.map((qa, index) => (
                <div key={index}>
                  <p className="text-[10.5px] font-bold leading-snug text-white/45">{qa.q}</p>
                  <p className="mt-0.5 text-[12.5px] leading-snug text-white/90">{qa.a}</p>
                </div>
              ))}
            </div>
          </div>
        )}
        {/* Coach-client: today's real nutrition + activity + workouts. */}
        {isClient && snap && macroRows.length > 0 && (
          <div className="mt-4 rounded-2xl border border-orange-400/20 bg-orange-400/[0.06] p-3.5">
            <div className="flex items-center justify-between gap-2">
              <span className="flex items-center gap-1.5">
                <Flame className="h-3.5 w-3.5 text-orange-300" />
                <span className="text-[9px] font-black uppercase tracking-[0.12em] text-orange-200">
                  Today's nutrition
                </span>
              </span>
              {snap.streak > 0 && (
                <span className="rounded-full bg-orange-400/15 px-2 py-0.5 text-[9px] font-black uppercase tracking-wide text-orange-200">
                  {snap.streak}-day streak
                </span>
              )}
            </div>
            <div className="mt-3 space-y-2.5">
              {macroRows.map((m) => (
                <div key={m.label}>
                  <div className="flex items-baseline justify-between">
                    <span className="text-[10.5px] font-bold text-white/70">{m.label}</span>
                    <span className="text-[11px] font-black text-white">
                      {Math.round(m.today)}
                      <span className="font-semibold text-white/40">
                        {m.goal > 0 ? ` / ${Math.round(m.goal)}` : ""} {m.unit}
                      </span>
                    </span>
                  </div>
                  <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-white/10">
                    <div
                      className="h-full rounded-full transition-[width] duration-700"
                      style={{
                        width: `${Math.min(100, Math.max(3, m.goal > 0 ? (m.today / m.goal) * 100 : 3))}%`,
                        background: m.color,
                      }}
                    />
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}
        {isClient && activityTiles.length > 0 && (
          <div className="mt-2.5 grid grid-cols-3 gap-2">
            {activityTiles.map((tile) => (
              <div key={tile.label} className="rounded-2xl bg-white/[0.05] px-3 py-2.5">
                <p className="flex items-center gap-1 text-[9px] font-black uppercase tracking-[0.12em] text-white/40">
                  {tile.label === "Steps" ? (
                    <Footprints className="h-3 w-3" />
                  ) : tile.label === "Sleep" ? (
                    <Moon className="h-3 w-3" />
                  ) : tile.label === "Water" ? (
                    <Droplets className="h-3 w-3" />
                  ) : (
                    <HeartPulse className="h-3 w-3" />
                  )}
                  {tile.label}
                </p>
                <p className="mt-0.5 truncate text-[13px] font-semibold text-white">{tile.value}</p>
              </div>
            ))}
          </div>
        )}
        {isClient && snap && snap.workouts.length > 0 && (
          <div className="mt-3">
            <div className="mb-1.5 flex items-center gap-1.5 text-white/40">
              <Dumbbell className="h-3.5 w-3.5" />
              <p className="text-[9px] font-black uppercase tracking-[0.12em]">Recent workouts</p>
            </div>
            <div className="space-y-1.5">
              {snap.workouts.map((workout, index) => (
                <div
                  key={`${workout.type}-${index}`}
                  className="flex items-center gap-2.5 rounded-xl bg-white/[0.04] px-3 py-2"
                >
                  <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-orange-400/12 text-orange-300">
                    <Dumbbell className="h-3.5 w-3.5" />
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-[12px] font-bold text-white">{workout.type}</p>
                    <p className="text-[10.5px] text-white/50">
                      {workout.durationMinutes} min · {workout.calories} kcal
                      {shortDate(workout.date) ? ` · ${shortDate(workout.date)}` : ""}
                    </p>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}
        {/* Photos — prospect Instagram grid or client progress shots. */}
        {client.photos.length > 0 && (
          <div className="mt-4">
            <div className="mb-1.5 flex items-center gap-1.5 text-white/40">
              <Images className="h-3.5 w-3.5" />
              <p className="text-[9px] font-black uppercase tracking-[0.12em]">
                {isClient
                  ? "Progress photos"
                  : client.instagram
                    ? `Instagram · @${client.instagram.replace(/^@/, "")}`
                    : "Photos"}
              </p>
            </div>
            <div className="-mx-1 flex gap-1.5 overflow-x-auto px-1 pb-1">
              {client.photos.slice(0, 12).map((src, index) => (
                <img
                  key={index}
                  src={src}
                  alt=""
                  loading="lazy"
                  referrerPolicy="no-referrer"
                  className="h-24 w-[4.75rem] shrink-0 rounded-xl border border-white/10 object-cover"
                />
              ))}
            </div>
          </div>
        )}
        {facts.length > 0 && (
          <div className="mt-4 grid grid-cols-2 gap-2">
            {facts.map((fact) => (
              <div key={fact.label} className="rounded-2xl bg-white/[0.05] px-3 py-2.5">
                <p className="text-[9px] font-black uppercase tracking-[0.12em] text-white/40">
                  {fact.label}
                </p>
                <p className="mt-0.5 truncate text-[13px] font-semibold text-white">{fact.value}</p>
              </div>
            ))}
          </div>
        )}
        {(client.instagram || client.tiktok) && (
          <div className="mt-2.5 flex flex-wrap gap-1.5">
            {client.instagram && (
              <span className="flex items-center gap-1.5 rounded-full bg-white/[0.06] px-3 py-1.5 text-[11.5px] font-semibold text-white/80">
                <Instagram className="h-3.5 w-3.5 text-pink-400" />
                {client.instagram.replace(/^@/, "")}
              </span>
            )}
            {client.tiktok && (
              <span className="flex items-center gap-1.5 rounded-full bg-white/[0.06] px-3 py-1.5 text-[11.5px] font-semibold text-white/80">
                <Music2 className="h-3.5 w-3.5 text-cyan-300" />
                {client.tiktok.replace(/^@/, "")}
              </span>
            )}
          </div>
        )}
        {client.notes && (
          <div className="mt-3 rounded-2xl border border-white/8 bg-white/[0.04] p-3.5">
            <p className="text-[9px] font-black uppercase tracking-[0.12em] text-white/40">
              {isClient ? "Coach note" : "Recruiter notes"}
            </p>
            <p className="mt-1 whitespace-pre-wrap text-[12.5px] leading-relaxed text-white/85">
              {client.notes}
            </p>
          </div>
        )}
        {client.contactLog.length > 0 && (
          <div className="mt-3">
            <div className="mb-1.5 flex items-center gap-1.5 text-white/40">
              <History className="h-3.5 w-3.5" />
              <p className="text-[9px] font-black uppercase tracking-[0.12em]">Contact history</p>
            </div>
            <div className="space-y-1.5">
              {client.contactLog
                .slice(-4)
                .reverse()
                .map((entry, index) => (
                  <div
                    key={`${entry.date}-${index}`}
                    className="flex items-start gap-2 rounded-xl bg-white/[0.04] px-3 py-2"
                  >
                    <span className="mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full bg-cyan-300/70" />
                    <div className="min-w-0 flex-1">
                      <p className="text-[12px] font-bold text-white">
                        {entry.method}
                        {shortDate(entry.date) && (
                          <span className="ml-1.5 font-medium text-white/40">
                            {shortDate(entry.date)}
                          </span>
                        )}
                      </p>
                      {entry.note && (
                        <p className="truncate text-[11.5px] text-white/60">{entry.note}</p>
                      )}
                    </div>
                  </div>
                ))}
            </div>
          </div>
        )}
        {live && (
          <p className="mt-4 text-center text-[10px] font-semibold uppercase tracking-[0.14em] text-white/35">
            Presented by @{client.presenterName}
          </p>
        )}
        {footer && <div className="mt-3">{footer}</div>}
      </div>
    </div>
  );
}

/**
 * Play a tile's media; when the browser blocks unmuted autoplay (Safari,
 * Firefox strict mode), fall back to muted playback so video keeps flowing
 * and raise the room-wide "tap to enable audio" prompt — the truthful fix
 * for "I can see them but can't hear them" on stricter browsers.
 */
function playWithAutoplayRescue(el: HTMLMediaElement, isSelf: boolean): void {
  const videoOnly = el instanceof HTMLVideoElement;
  if (videoOnly) { el.muted = true; el.defaultMuted = true; el.controls = false; }
  const source = el.srcObject;
  void el.play().catch((err: unknown) => {
    if (!el.isConnected || el.srcObject !== source) return;
    const name = err instanceof DOMException ? err.name : "";
    if (name !== "NotAllowedError" || isSelf || videoOnly) {
      // Transient failure (element re-attach mid-play) — retry shortly.
      window.setTimeout(() => {
        if (el.isConnected && el.srcObject === source) void el.play().catch(() => undefined);
      }, 400);
      return;
    }
    el.muted = true;
    el.dataset.autoplayMuted = "1";
    void el.play().catch(() => undefined);
    window.dispatchEvent(new CustomEvent("whisper-audio-blocked"));
  });
}

/**
 * The ALWAYS-ON audio path for one remote participant. Tiles unmount their
 * <video> the moment a camera goes off (the avatar takes its place), and for
 * a long time that <video> was the only thing playing the person's AUDIO —
 * so turning a camera off silenced the mic for everyone else, and members
 * beyond the visible grid were never audible at all. Audio rides these
 * hidden elements now: one per peer, alive for the whole call, independent
 * of layout, overflow, pins, or camera state.
 */
/** One shared graph for every remote voice's leveler. */
let levelerCtx: AudioContext | null = null;
function getLevelerContext(): AudioContext | null {
  if (levelerCtx) return levelerCtx;
  try {
    levelerCtx = new AudioContext();
  } catch {
    levelerCtx = null;
  }
  return levelerCtx;
}

/**
 * The VOICE LEVELER — why desktop meetings sounded quiet: a phone mic two
 * feet from someone's face lands at a fraction of a headset's level, and a
 * bare <audio> element plays exactly what arrives. The same thing every
 * meeting product does under the hood: a gentle compressor that catches
 * the loud peaks plus make-up gain so quiet voices come up to a normal
 * speaking level — never clipping, never touching the echo path (the
 * browser's echo canceller runs on capture, not on playback).
 */
function buildLeveledStream(stream: MediaStream): { out: MediaStream; dispose: () => void } | null {
  const ctx = getLevelerContext();
  if (!ctx || ctx.state !== "running" || stream.getAudioTracks().length === 0) return null;
  try {
    const source = ctx.createMediaStreamSource(stream);
    const compressor = ctx.createDynamicsCompressor();
    compressor.threshold.value = -28;
    compressor.knee.value = 24;
    compressor.ratio.value = 6;
    compressor.attack.value = 0.004;
    compressor.release.value = 0.22;
    const makeup = ctx.createGain();
    makeup.gain.value = 2.4;
    const dest = ctx.createMediaStreamDestination();
    source.connect(compressor);
    compressor.connect(makeup);
    makeup.connect(dest);
    return {
      out: dest.stream,
      dispose: () => {
        try {
          source.disconnect();
          compressor.disconnect();
          makeup.disconnect();
          dest.stream.getTracks().forEach((track) => track.stop());
        } catch {
          /* already gone */
        }
      },
    };
  } catch {
    return null;
  }
}

function RemoteAudioSink({
  stream,
  sinkId,
}: {
  stream: MediaStream;
  sinkId: string | null;
}): React.ReactElement {
  const ref = useRef<HTMLAudioElement | null>(null);
  // Chromium quirk: a remote WebRTC track only flows into WebAudio while
  // SOME media element also holds the stream — this muted one keeps it
  // flowing; the audible element plays the leveled copy.
  const rawRef = useRef<HTMLAudioElement | null>(null);
  const [leveled, setLeveled] = useState<MediaStream | null>(null);

  useEffect(() => {
    let current = buildLeveledStream(stream);
    setLeveled(current?.out ?? null);
    const raw = rawRef.current;
    if (raw && raw.srcObject !== stream) {
      raw.srcObject = stream;
      raw.muted = true;
      void raw.play().catch(() => undefined);
    }
    // A track that lands later (a mic re-acquired mid-call, a joiner who
    // came in muted) rebuilds the graph so the new track is leveled too.
    const onAddTrack = (): void => {
      current?.dispose();
      current = buildLeveledStream(stream);
      setLeveled(current?.out ?? null);
      if (raw) void raw.play().catch(() => undefined);
    };
    stream.addEventListener("addtrack", onAddTrack);
    stream.addEventListener("removetrack", onAddTrack);
    const context = getLevelerContext();
    context?.addEventListener("statechange", onAddTrack);
    const resume = (): void => {
      const ctx = getLevelerContext();
      if (ctx && ctx.state === "suspended") void ctx.resume().catch(() => undefined);
    };
    window.addEventListener("pointerdown", resume, { passive: true });
    window.addEventListener("keydown", resume);
    return () => {
      stream.removeEventListener("addtrack", onAddTrack);
      stream.removeEventListener("removetrack", onAddTrack);
      context?.removeEventListener("statechange", onAddTrack);
      window.removeEventListener("pointerdown", resume);
      window.removeEventListener("keydown", resume);
      if (raw) { raw.pause(); raw.srcObject = null; }
      current?.dispose();
    };
  }, [stream]);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const play = leveled ?? stream;
    if (el.srcObject !== play) el.srcObject = play;
    el.volume = 1;
    el.muted = false;
    playWithAutoplayRescue(el, false);
    const onAddTrack = (): void => playWithAutoplayRescue(el, false);
    play.addEventListener("addtrack", onAddTrack);
    const restore = (): void => { if (!document.hidden && el.paused) onAddTrack(); };
    document.addEventListener("visibilitychange", restore);
    return () => {
      play.removeEventListener("addtrack", onAddTrack);
      document.removeEventListener("visibilitychange", restore);
      el.pause(); el.srcObject = null; delete el.dataset.autoplayMuted;
    };
  }, [stream, leveled]);

  useEffect(() => {
    const el = ref.current;
    if (!el || sinkId === null) return;
    const sinkable = el as HTMLAudioElement & { setSinkId?: (deviceId: string) => Promise<void> };
    void sinkable.setSinkId?.(sinkId).catch(() => undefined);
  }, [sinkId]);

  return (
    <>
      <audio ref={rawRef} muted autoPlay />
      <audio ref={ref} autoPlay />
    </>
  );
}

/**
 * The JOIN SETUP SCREEN — shown from the Join click until the room is up.
 * The old lobby just spun its button while the camera, microphone, and
 * connection came up one after another, which read as lag. Now the page
 * says what it's doing, step by step, until you're let in.
 */
function JoinSetupScreen({
  title,
  audioOnly,
}: {
  title: string;
  audioOnly: boolean;
}): React.ReactElement {
  const steps = useMemo(
    () =>
      audioOnly
        ? ["Warming up your microphone", "Connecting you to the room", "Almost there"]
        : ["Checking your camera", "Warming up your microphone", "Connecting you to the room", "Almost there"],
    [audioOnly],
  );
  const [step, setStep] = useState<number>(0);
  const [slow, setSlow] = useState<boolean>(false);
  useEffect(() => {
    const t = window.setInterval(() => {
      setStep((s) => Math.min(steps.length - 1, s + 1));
    }, 1400);
    const slowTimer = window.setTimeout(() => setSlow(true), 18000);
    return () => {
      window.clearInterval(t);
      window.clearTimeout(slowTimer);
    };
  }, [steps.length]);
  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-background px-6 text-center text-foreground">
      <div className="relative mb-7 flex h-24 w-24 items-center justify-center">
        <span
          className="absolute inset-0 animate-ping rounded-full opacity-25"
          style={{ background: WHISPER_BRAND_GRADIENT_DIAGONAL, animationDuration: "1.8s" }}
          aria-hidden
        />
        <span
          className="relative flex h-16 w-16 items-center justify-center rounded-[22px] text-white shadow-lg"
          style={{ background: WHISPER_BRAND_GRADIENT_DIAGONAL }}
        >
          {audioOnly ? <PhoneCall className="h-7 w-7" /> : <Video className="h-7 w-7" />}
        </span>
      </div>
      <p className="text-[11px] font-bold uppercase tracking-[0.18em] text-muted-foreground">Getting everything set up</p>
      <h1 className="mt-2 max-w-md text-[22px] font-extrabold leading-tight">{title}</h1>
      <ul className="mt-7 w-full max-w-xs space-y-2.5 text-left">
        {steps.map((label, i) => {
          const done = i < step;
          const active = i === step;
          return (
            <li
              key={label}
              className={cn(
                "flex items-center gap-3 text-[14px] transition-colors",
                done ? "text-muted-foreground" : active ? "font-semibold text-foreground" : "text-muted-foreground/60",
              )}
            >
              <span
                className={cn(
                  "flex h-5 w-5 shrink-0 items-center justify-center rounded-full border",
                  done ? "border-transparent bg-foreground text-background" : active ? "border-foreground" : "border-border",
                )}
              >
                {done ? (
                  <Check className="h-3 w-3" strokeWidth={3} />
                ) : active ? (
                  <Loader2 className="h-3 w-3 animate-spin" />
                ) : null}
              </span>
              {label}
            </li>
          );
        })}
      </ul>
      <p className="mt-8 max-w-sm text-[12.5px] leading-relaxed text-muted-foreground">
        {slow
          ? "This is taking longer than usual — check that no other app is holding your camera or microphone."
          : "Your browser may ask for camera and microphone access — choose Allow and we'll bring you in."}
      </p>
    </div>
  );
}

/** One video tile.  `contain` mode is used for screen shares so the full
 *  desktop is visible without cropping; `cover` for camera tiles. */
function Tile({
  participant,
  stream,
  bpm,
  badge,
  profileMap,
  avatarUrl,
  isSelf = false,
  isSpotlight = false,
  isFocused = false,
  compact = false,
  aspect = "video",
  onPin,
  onKick,
  presentedClient = null,
  onExpandPresentation,
}: {
  participant: LiveParticipantInfo;
  stream: MediaStream | null;
  /** Live heart rate (coach view) — shown as a pulsing chip when known. */
  bpm?: number | null;
  /** Verification badge for this participant's username. */
  badge?: VerificationBadge;
  /** Profile data map for role badges. */
  profileMap?: Record<string, { is_coach?: boolean; is_recruiter?: boolean; is_athlete?: boolean; is_verified?: boolean }>;
  avatarUrl?: string | null;
  isSelf?: boolean;
  isSpotlight?: boolean;
  isFocused?: boolean;
  compact?: boolean;
  /** `fit` sizes the card to the video's REAL aspect inside the available
   *  box (Meet's spotlight) — nothing is cropped or letterboxed inside a
   *  mismatched frame; `fill` stretches to the box. */
  aspect?: "video" | "square" | "portrait" | "fill" | "fit";
  onPin?: () => void;
  /** Host-only: remove this participant from the meeting. */
  onKick?: () => void;
  /** When this participant is presenting a client, the phone-shaped mini
   *  profile docks inside their frame — tap it to expand. */
  presentedClient?: PresentedClientPayload | null;
  onExpandPresentation?: () => void;
}): React.ReactElement {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const boxRef = useRef<HTMLDivElement | null>(null);
  const fitRef = useRef<HTMLDivElement | null>(null);
  // Real camera orientation (portrait phone vs landscape webcam) + the
  // tile's own box orientation — mismatches letterbox instead of cropping.
  const [videoAspect, setVideoAspect] = useState<number | null>(null);
  const [boxAspect, setBoxAspect] = useState<number | null>(null);
  const [fitBox, setFitBox] = useState<{ w: number; h: number }>({ w: 0, h: 0 });
  const isScreenShare = participant.isScreenSharing;
  const fitMode = aspect === "fit";
  const aspectClass =
    aspect === "fill" || fitMode
      ? "h-full w-full"
      : aspect === "portrait"
        ? "aspect-[3/4]"
        : aspect === "square" || compact
          ? "aspect-square"
          : "aspect-video";

  // Fit mode measures the box it's GIVEN and sizes the card to the stream's
  // own aspect (16:9 until the metadata says otherwise), centered — exactly
  // how Meet frames a spotlight or a shared screen.
  useEffect(() => {
    if (!fitMode) return;
    const el = fitRef.current;
    if (!el || typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver((entries) => {
      const rect = entries[0]?.contentRect;
      if (rect) setFitBox({ w: rect.width, h: rect.height });
    });
    observer.observe(el);
    return () => observer.disconnect();
  }, [fitMode]);
  const fitStyle = useMemo((): React.CSSProperties | undefined => {
    if (!fitMode || fitBox.w <= 8 || fitBox.h <= 8) return undefined;
    const ratio =
      participant.hasVideo && stream && videoAspect && videoAspect > 0.2 && videoAspect < 6
        ? videoAspect
        : 16 / 9;
    const w = Math.min(fitBox.w, fitBox.h * ratio);
    const h = w / ratio;
    return { width: Math.floor(w), height: Math.floor(h) };
  }, [fitMode, fitBox.w, fitBox.h, participant.hasVideo, stream, videoAspect]);

  // The <video> is unmounted while the camera is off and a NEW element is
  // mounted when it comes back — with the SAME stream object. Keying this on
  // hasVideo too is what re-attaches the source to that fresh element;
  // without it a camera turned off and on again stayed black for everyone.
  useEffect(() => {
    const el = videoRef.current;
    if (!el) return;
    if (!stream || !participant.hasVideo) return;
    el.muted = true; el.defaultMuted = true; el.controls = false;
    if (el.srcObject !== stream) el.srcObject = stream;
    const play = (): void => { if (!document.hidden && el.paused) playWithAutoplayRescue(el, true); };
    play();
    el.addEventListener("loadedmetadata", play);
    el.addEventListener("canplay", play);
    stream.addEventListener("addtrack", play);
    document.addEventListener("visibilitychange", play);
    window.addEventListener("pointerdown", play, { passive: true });
    window.addEventListener("keydown", play);
    return () => {
      el.removeEventListener("loadedmetadata", play);
      el.removeEventListener("canplay", play);
      stream.removeEventListener("addtrack", play);
      document.removeEventListener("visibilitychange", play);
      window.removeEventListener("pointerdown", play);
      window.removeEventListener("keydown", play);
      el.pause(); el.srcObject = null;
    };
  }, [stream, participant.hasVideo, participant.isScreenSharing]);

  // Watch the incoming track's real dimensions — phones rotate mid-call, so
  // the `resize` event matters as much as `loadedmetadata`.
  useEffect(() => {
    const el = videoRef.current;
    if (!el) return;
    const update = (): void => {
      if (el.videoWidth > 0 && el.videoHeight > 0) {
        setVideoAspect(el.videoWidth / el.videoHeight);
      }
    };
    update();
    el.addEventListener("loadedmetadata", update);
    el.addEventListener("resize", update);
    return () => {
      el.removeEventListener("loadedmetadata", update);
      el.removeEventListener("resize", update);
    };
  }, [stream, participant.hasVideo]);

  useEffect(() => {
    const el = boxRef.current;
    if (!el || typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver((entries) => {
      const rect = entries[0]?.contentRect;
      if (rect && rect.height > 4) setBoxAspect(rect.width / rect.height);
    });
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  // A portrait phone camera in a landscape tile (or the reverse) letterboxes
  // on the dark backdrop instead of cropping half the person away. Compact
  // thumbs and the PiP keep the cover crop — they're too small to letterbox.
  const orientationMismatch =
    !compact &&
    !isScreenShare &&
    !fitMode &&
    videoAspect !== null &&
    boxAspect !== null &&
    ((videoAspect < 0.95 && boxAspect > 1.05) ||
      (videoAspect > 1.05 && boxAspect < 0.95));

  const card = (
    <div
      ref={boxRef}
      data-recording-peer={participant.peerId}
      data-recording-fit={isScreenShare || orientationMismatch ? "contain" : "cover"}
      data-recording-avatar={avatarUrl ?? ""}
      data-recording-avatar-size={compact ? 40 : isSpotlight ? 96 : 68}
      data-recording-focused={isFocused}
      style={fitStyle}
      className={cn(
        "group relative overflow-hidden rounded-[18px] border border-white/[0.06] bg-[color:var(--meet-tile)] shadow-[0_12px_42px_rgba(0,0,0,0.22)] transition-[box-shadow,transform] duration-300",
        fitMode && !fitStyle ? "h-full w-full" : aspectClass,
        fitMode && fitStyle && "h-auto w-auto max-h-full max-w-full shrink-0",
        isFocused && "z-10 ring-[2.5px] ring-white/85 shadow-[0_0_0_1px_rgba(255,255,255,0.35),0_16px_46px_rgba(0,0,0,0.38)]",
        onPin && "cursor-pointer focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-white/70",
      )}
      onClick={onPin}
      onKeyDown={(event) => {
        if (onPin && (event.key === "Enter" || event.key === " ")) {
          event.preventDefault();
          onPin();
        }
      }}
      role={onPin ? "button" : undefined}
      tabIndex={onPin ? 0 : undefined}
      aria-label={onPin ? `Focus ${participant.name}` : undefined}
    >
      {participant.hasVideo && stream ? (
        <video
          ref={videoRef}
          controls={false}
          disablePictureInPicture
          tabIndex={-1}
          disableRemotePlayback
          autoPlay
          playsInline
          // Audio never rides the tile — RemoteAudioSink owns it, so a tile
          // that unmounts (camera off) can't take the person's voice with it.
          muted
          className={cn(
            "pointer-events-none h-full w-full bg-black [&::-webkit-media-controls]:hidden [&::-webkit-media-controls-start-playback-button]:hidden",
            isScreenShare || orientationMismatch
              ? "object-contain"
              : "object-cover",
          )}
          style={isSelf && !isScreenShare ? { transform: "scaleX(-1)" } : undefined}
        />
      ) : (
        // Camera off — the iOS grammar (WhisperVideoAvatarBackdrop): the
        // person's own profile photo blurred into the backdrop, darkened,
        // with the sharp avatar disc on top. Never a flat gray plate.
        <div className="relative flex h-full w-full items-center justify-center overflow-hidden bg-[#141414]">
          {avatarUrl ? (
            <img
              src={avatarUrl}
              alt=""
              aria-hidden
              draggable={false}
              className="pointer-events-none absolute inset-[-12%] h-[124%] w-[124%] select-none object-cover opacity-90 blur-[36px] saturate-[0.9]"
            />
          ) : (
            <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_30%_20%,#3f3f46,transparent_44%),linear-gradient(135deg,#18181b,#09090b)]" />
          )}
          <div className="pointer-events-none absolute inset-0 bg-black/[0.42]" />
          <Avatar
            url={avatarUrl}
            name={participant.name}
            size={compact ? 40 : isSpotlight ? 96 : 68}
            className="relative ring-1 ring-white/25 shadow-[0_5px_14px_rgba(0,0,0,0.45)]"
          />
        </div>
      )}
      <div className="absolute bottom-2 left-2 flex max-w-[calc(100%-1rem)] items-center gap-1.5 rounded-full bg-black/65 px-2.5 py-1 backdrop-blur-md">
        {isScreenShare && <Monitor className="h-3 w-3 shrink-0 text-emerald-300" />}
        {!participant.micOn && <MicOff className="h-3 w-3 shrink-0 text-red-300" />}
        <span className="truncate text-[11px] font-semibold text-white">
          {participant.name}
          {isSelf && " (You)"}
        </span>
        {badge && badge !== "none" && <BadgeChip badge={badge} />}
        {profileMap && <RoleChip username={participant.name} profileMap={profileMap} />}
      </div>
      {!isSelf && participant.connectionState !== "connected" && (
        <div className="absolute inset-0 z-[5] flex items-center justify-center bg-black/45 backdrop-blur-[2px]">
          <div className="flex items-center gap-1.5 rounded-full bg-black/70 px-3 py-1.5">
            <Loader2 className="h-3.5 w-3.5 animate-spin text-white/80" />
            <span className="text-[11px] font-semibold text-white/90">
              {participant.connectionState === "reconnecting" ? "Reconnecting…" : "Connecting…"}
            </span>
          </div>
        </div>
      )}
      {participant.isSpeaking && (
        <div className="absolute left-2 top-2 flex h-6 w-6 items-center justify-center rounded-full bg-cyan-400/90 shadow-sm">
          <AudioLines className="h-3.5 w-3.5 text-black" />
        </div>
      )}
      {bpm != null && (
        <div className="absolute right-2 top-2 flex items-center gap-1 rounded-full bg-black/60 px-2.5 py-1 backdrop-blur">
          <HeartPulse className="h-3.5 w-3.5 animate-pulse text-red-400" />
          <span className="text-[11px] font-bold text-white">{bpm}</span>
          <span className="text-[9px] font-semibold text-white/60">bpm</span>
        </div>
      )}
      {onPin && !isSpotlight && (
        <div className="absolute right-2 top-2 flex h-7 w-7 items-center justify-center rounded-full bg-black/55 text-white opacity-0 transition-opacity group-hover:opacity-100 group-focus-within:opacity-100">
          <Pin className="h-3.5 w-3.5" />
        </div>
      )}
      {onKick && (
        <button
          onClick={(e) => {
            e.stopPropagation();
            onKick();
          }}
          aria-label={`Remove ${participant.name} from the meeting`}
          className="absolute left-2 top-2 z-10 flex h-7 w-7 items-center justify-center rounded-full bg-red-600/85 text-white opacity-0 transition-opacity hover:bg-red-600 group-hover:opacity-100 group-focus-within:opacity-100"
        >
          <UserX className="h-3.5 w-3.5" />
        </button>
      )}
      {presentedClient && onExpandPresentation && (
        <div className="absolute bottom-2 right-2 z-10">
          <MiniClientPhoneCard
            client={presentedClient}
            onExpand={onExpandPresentation}
            size="sm"
          />
        </div>
      )}
    </div>
  );

  if (!fitMode) return card;
  return (
    <div ref={fitRef} className="flex h-full min-h-0 w-full items-center justify-center">
      {card}
    </div>
  );
}

/** Meet's "You're presenting to everyone" card — shown in place of your own
 *  shared screen (never the infinite-mirror crop). */
function SelfPresentingCard({
  compact = false,
  onStop,
}: {
  compact?: boolean;
  onStop: () => void;
}): React.ReactElement {
  return (
    <div
      className={cn(
        "flex flex-col items-center justify-center gap-2 rounded-[18px] border border-white/[0.08] bg-[color:var(--meet-tile)] text-center text-white shadow-[0_12px_42px_rgba(0,0,0,0.22)]",
        compact ? "aspect-[3/4] p-3" : "h-full w-full p-6",
      )}
    >
      <span className={cn("grid place-items-center rounded-full bg-emerald-400/15 text-emerald-300", compact ? "h-9 w-9" : "h-14 w-14")}>
        <Monitor className={compact ? "h-4 w-4" : "h-6 w-6"} />
      </span>
      <p className={cn("font-semibold", compact ? "text-[12px] leading-tight" : "text-[17px]")}>
        {compact ? "You're presenting" : "You're presenting to everyone"}
      </p>
      {!compact && (
        <p className="max-w-xs text-[13px] text-white/60">
          Everyone in the call sees your screen. Your camera stays off the stage while you present.
        </p>
      )}
      <button
        type="button"
        onClick={onStop}
        className={cn(
          "rounded-full bg-[#ea4335] font-bold text-white transition-colors hover:bg-[#f04a3c]",
          compact ? "mt-0.5 px-3 py-1.5 text-[11.5px]" : "mt-1 h-11 px-6 text-[14px]",
        )}
      >
        Stop presenting
      </button>
    </div>
  );
}

/**
 * Meet-style stage math — pick the column count that maximizes the 16:9
 * video area each cell can show, then let tiles FILL their cells. Wide
 * containers prefer wider layouts (2 side-by-side, 3×2 for 6, 4×3 for 12);
 * tall phone containers naturally collapse to stacked / 2-column grids.
 */
function computeStageGrid(
  count: number,
  width: number,
  height: number,
  gap: number
): { cols: number; rows: number; tileW: number; tileH: number } | null {
  if (count <= 0 || width <= 20 || height <= 20) return null;
  const TARGET = 16 / 9;
  const candidates: {
    cols: number;
    rows: number;
    tileW: number;
    tileH: number;
    score: number;
  }[] = [];
  for (let cols = 1; cols <= count; cols += 1) {
    const rows = Math.ceil(count / cols);
    const cellW = (width - gap * (cols - 1)) / cols;
    const cellH = (height - gap * (rows - 1)) / rows;
    if (cellW <= 0 || cellH <= 0) continue;
    const fitW = Math.min(cellW, cellH * TARGET);
    candidates.push({
      cols,
      rows,
      tileW: Math.floor(cellW),
      tileH: Math.floor(cellH),
      score: fitW * (fitW / TARGET),
    });
  }
  if (candidates.length === 0) return null;
  const best = Math.max(...candidates.map((c) => c.score));
  // Among near-best layouts (within 10%), prefer MORE columns — faces read
  // better side-by-side than stretched across ultra-wide strips.
  const near = candidates.filter((c) => c.score >= best * 0.9);
  near.sort((a, b) => b.cols - a.cols);
  const pick = near[0];
  return { cols: pick.cols, rows: pick.rows, tileW: pick.tileW, tileH: pick.tileH };
}

const STAGE_MAX_TILES = 12;

/**
 * The gallery stage — measures its REAL box (ResizeObserver) and sizes
 * every tile from it: 1 person fills the stage, 2 sit side-by-side on
 * desktop / stacked on phones, 4 make a 2×2, 6 a 3×2, 12 a 4×3 — and
 * beyond 12 an overflow tile counts the rest instead of shrinking
 * everyone into postage stamps. The last row self-centers.
 */
function StageGrid({
  participants,
  renderTile,
  maxTiles,
}: {
  participants: LiveParticipantInfo[];
  renderTile: (participant: LiveParticipantInfo) => React.ReactNode;
  /** Adjust-view tiles cap (falls back to the stage default). */
  maxTiles?: number;
}) {
  const tileCap = Math.max(2, maxTiles ?? STAGE_MAX_TILES);
  const stageRef = useRef<HTMLDivElement | null>(null);
  const [size, setSize] = useState<{ w: number; h: number }>({ w: 0, h: 0 });

  useEffect(() => {
    const el = stageRef.current;
    if (!el || typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver((entries) => {
      const rect = entries[0]?.contentRect;
      if (rect) setSize({ w: rect.width, h: rect.height });
    });
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  const overflow = Math.max(0, participants.length - tileCap);
  const visible =
    overflow > 0 ? participants.slice(0, tileCap - 1) : participants;
  const cellCount = visible.length + (overflow > 0 ? 1 : 0);
  const GAP = 12;

  const layout = useMemo(
    () => computeStageGrid(cellCount, size.w, size.h, GAP),
    [cellCount, size.w, size.h]
  );

  const extras = overflow > 0 ? participants.slice(tileCap - 1) : [];

  return (
    <div ref={stageRef} className="h-full min-h-0 w-full">
      {layout && (
        <div
          className="flex h-full w-full flex-wrap content-center items-center justify-center"
          style={{ gap: GAP }}
        >
          {visible.map((participant) => (
            <div
              key={participant.peerId}
              className="min-h-0"
              style={{ width: layout.tileW, height: layout.tileH }}
            >
              {renderTile(participant)}
            </div>
          ))}
          {overflow > 0 && (
            <div
              className="flex items-center justify-center rounded-[18px] border border-white/[0.06] bg-[#171717]"
              style={{ width: layout.tileW, height: layout.tileH }}
            >
              <div className="flex flex-col items-center gap-2.5 px-4 text-center">
                <div className="flex -space-x-3">
                  {extras.slice(0, 3).map((p) => (
                    <Avatar
                      key={p.peerId}
                      name={p.name}
                      size={40}
                      className="ring-2 ring-[#171717]"
                    />
                  ))}
                </div>
                <p className="text-[13px] font-bold text-white">
                  +{overflow} other{overflow === 1 ? "" : "s"}
                </p>
                <p className="text-[11px] font-medium text-white/50">
                  in the meeting
                </p>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

/**
 * Private meeting room — reuses the live-room mesh WebRTC engine on the
 * `meeting:{id}` signaling channel (shared with iOS). Everyone joins as a
 * speaker. Local speech is transcribed with the Web Speech API and, when the
 * host ends the call, an AI summary (key points / decisions / action items)
 * is generated for all participants.
 */
export default function MeetingRoom({
  meetingId,
  callWith,
  callMode = null,
}: {
  meetingId: string;
  /** 1:1 DM calls arrive as /meet/{id}?call={otherUsername} — no lobby, the
   *  room connects immediately and shows a ringing state until they answer. */
  callWith: string | null;
  /** Voice-only calls skip camera acquisition entirely (iOS parity). */
  callMode?: "audio" | "video" | null;
}) {
  // Route ids come in two shapes: real database uuids (Meetings lists,
  // calendar links, 1:1 calls) and human codes (wsp-xxxx-xxxx from Meet and
  // recruiter links). Codes map DETERMINISTICALLY to a uuid — the id column
  // IS a uuid, so the raw code must never reach a database query — and the
  // first signed-in arriver creates the row under that derived id.
  const isCodeRoom = !isMeetingUuid(meetingId);
  const id = useMemo(() => resolveMeetingRoomId(meetingId), [meetingId]);
  /** Blind/speed-date rooms are known BEFORE joining: the starter's lobby
   *  primed the code, or the invite link carries ?sd=1 (marked here so a
   *  refresh keeps the rose screens). Drives the custom pre-join screen and
   *  where "leave" lands — never the generic meeting lobby. */
  const speedDateRoom = useMemo<boolean>(() => {
    if (!meetingId) return false;
    try {
      if (new URLSearchParams(window.location.search).get("sd") === "1") {
        markSpeedDateRoom(meetingId);
        return true;
      }
    } catch {
      // URL parsing blocked — fall through to the stored flag.
    }
    return isSpeedDateRoom(meetingId);
  }, [meetingId]);
  /** Where leaving this room lands signed-in members. */
  const homePath = speedDateRoom ? "/c/dating" : "/meetings";
  const isAudioCall = !!callWith && callMode === "audio";
  const { user, profile, loading: authLoading } = useAuth();
  const navigate = useNavigate();
  // Floating-window host: the room is mounted OUTSIDE the router, so
  // navigation never unmounts a live call — minimize shrinks it to a tile.
  const meetingHost = useMeetingHost();
  const minimized = meetingHost.minimized;

  /** Close the floating room and land on `path`. On meet.mydailywhisper.com
   *  the app routes don't exist — every exit lands on the Meet landing. */
  const exitTo = useCallback(
    (path: string): void => {
      // Guests have no app routes on the main domain — /meetings is
      // auth-walled and would bounce them to the marketing page with the
      // call still docked in the corner. Guests exit to the front door.
      const capture = recordingSessionRef.current;
      if (capture.state.request || capture.state.update?.state === "saving" || capture.state.update?.state === "starting") {
        void capture.stop(true);
        toast("Finishing your recording. Keep this tab open; the save status will stay visible.");
        return;
      }
      if (meetingHost.close()) navigate(!user ? "/" : MEET_PORTAL && path.split("?")[0] !== "/notebook" ? "/" : path);
    },
    [navigate, meetingHost, user],
  );

  // ─── Guest access ─── Anyone with the link can join without an account:
  // they pick a display name and get full video/audio. Captions, transcripts,
  // Ember voice, and calendar actions stay account-only (they need database
  // writes a guest can't make).
  const [guestName, setGuestName] = useState<string>(() => {
    try {
      return localStorage.getItem("whisper_guest_name") ?? "";
    } catch {
      return "";
    }
  });
  const [guestDraft, setGuestDraft] = useState<string>(() => {
    try {
      return localStorage.getItem("whisper_guest_name") ?? "";
    } catch {
      return "";
    }
  });
  const [guestReady, setGuestReady] = useState<boolean>(false);
  const guestIdRef = useRef<string>("");
  if (!guestIdRef.current) {
    try {
      const existing = sessionStorage.getItem("whisper_guest_id");
      guestIdRef.current =
        existing ?? `guest_${Math.random().toString(36).slice(2, 10)}`;
      sessionStorage.setItem("whisper_guest_id", guestIdRef.current);
    } catch {
      guestIdRef.current = `guest_${Math.random().toString(36).slice(2, 10)}`;
    }
  }
  /** My identity on the signaling channel — account id or stable guest id. */
  const selfId = user?.id ?? guestIdRef.current;
  const selfName =
    profile?.username ?? (user ? "member" : guestName || "guest");
  /** Latest display name for the (stable) signaling handler. */
  const selfNameRef = useRef<string>("");
  selfNameRef.current = selfName;

  const [participants, setParticipants] = useState<LiveParticipantInfo[]>([]);
  const [meetingAccessReady, setMeetingAccessReady] = useState<boolean>(false);
  /** The join RPC refused because the meeting ENDED (older databases keep
   *  ended rows unreadable for non-members) — the link is still real. */
  const [joinRefusal, setJoinRefusal] = useState<"unavailable" | null>(null);
  /** Signed-in members on a uuid link get a short grace window (the host's
   *  row insert or our own membership may still be landing) before a dead
   *  "not found" is ever shown. */
  const [graceOver, setGraceOver] = useState<boolean>(false);
  const [reopening, setReopening] = useState<boolean>(false);
  /** True once anyone else has ever been in the room with us this session. */
  const everHadCompanyRef = useRef<boolean>(false);
  /** We ended the meeting ourselves just now — the recap must not offer "Start again". */
  const endedByMeRef = useRef<boolean>(false);
  const [joined, setJoined] = useState<boolean>(false);
  // Mic/cam mirror the REAL device state (set after acquisition succeeds).
  const [micOn, setMicOn] = useState<boolean>(false);
  const [camOn, setCamOn] = useState<boolean>(false);
  const [ending, setEnding] = useState<boolean>(false);
  const [notes, setNotes] = useState<string | null>(null);
  const [generating, setGenerating] = useState<boolean>(false);
  const [sharing, setSharing] = useState<boolean>(false);
  const [heartRates, setHeartRates] = useState<Record<string, number>>({});
  const [spotlightId, setSpotlightId] = useState<string | null>(null);
  /** Set when the host kicks ME — an effect below leaves + exits. */
  const [kickedOut, setKickedOut] = useState<boolean>(false);
  /** Meet's leave menu — a host with people still in the room chooses. */
  const [leaveMenuOpen, setLeaveMenuOpen] = useState<boolean>(false);
  /** The post-call screen's reason (null while in the meeting / lobby). */
  const [postCall, setPostCall] = useState<PostCallReason | null>(null);
  /** Who ended the call for everyone — named on the post-call screen. */
  const endedByRef = useRef<string>("");
  /** The room's acting host once the owner left (handoff wire or election). */
  const [actingHostId, setActingHostId] = useState<string | null>(null);
  /** The owner was seen in the room — elections only REPLACE a host who left. */
  const hostSeenRef = useRef<boolean>(false);
  /** "Are you still there?" after a long stretch alone in the room. */
  const [alonePrompt, setAlonePrompt] = useState<boolean>(false);
  const [aloneEpoch, setAloneEpoch] = useState<number>(0);
  const [aloneSecondsLeft, setAloneSecondsLeft] = useState<number>(120);
  /** The bottom-left "Ask Jasper" box. */
  const [jasperAsk, setJasperAsk] = useState<string>("");
  /** Remote peerIds seen so far — drives the join / leave chimes. */
  const seenPeerIdsRef = useRef<Set<string> | null>(null);
  /** Which Settings tab the mic / camera carets open. */
  const [meetSettingsTab, setMeetSettingsTab] = useState<"audio" | "video" | "general">("audio");
  /** True while the tab-switch auto-dock is the one that opened PiP. */
  const autoPipRef = useRef<boolean>(false);
  const [showInvite, setShowInvite] = useState<boolean>(false);
  const [inviteQuery, setInviteQuery] = useState<string>("");
  const [inviting, setInviting] = useState<boolean>(false);
  const [badgeMap, setBadgeMap] = useState<Record<string, VerificationBadge>>({});
  const [profileMap, setProfileMap] = useState<Record<string, { is_coach?: boolean; is_recruiter?: boolean; is_athlete?: boolean; is_verified?: boolean; profile_image_url?: string | null }>>({});
  const { showRecruiterTools, setShowRecruiterTools, showCoachTools, setShowCoachTools, showCreatorTools, setShowCreatorTools, panelTab, setPanelTab, emberPanelOpen, setEmberPanelOpen, recordingOpen, setRecordingOpen, activitiesOpen, setActivitiesOpen, notebookOpen, setNotebookOpen } = useMeetingPanels<MeetPanelTab>();
  const myBadge = useMyBadge();
  // Verified creators, moderators, admins, and the owner get creator tools —
  // the same gate iOS uses for its in-meeting creator features.
  const isCreatorRole = myBadge !== "none";
  // The live creator analytics card shared into the call (mine or theirs).
  const [creatorCard, setCreatorCard] = useState<CreatorAnalyticsCardPayload | null>(null);
  /** Business+ "present company" card — same broadcast discipline as the
   *  creator card (rev stamp, sync re-broadcast, presenter-leave hygiene). */
  interface BusinessCardWire {
    presenterUserId: string;
    presenterName: string;
    businessId: string;
    mode: "company" | "roles" | "team";
    company: string;
    about: string | null;
    industry: string | null;
    logoUrl: string | null;
    positions: string[];
    roles: { title: string; blurb: string }[];
    team: { username: string; roleTitle: string; accent: string }[];
    applyUrl: string;
    rev: number;
  }
  const [bizCard, setBizCard] = useState<BusinessCardWire | null>(null);
  // ── Blind dating — the date mode of a room (cards on the wire, the
  // curtain + reveal stage, and the wrap when it ends) ─────────────────
  const [speedDate, setSpeedDate] = useState<boolean>(false);
  /** The invited side's custom JOIN takeover — the starter marked themselves
   *  ready in the Dating-hub lobby, so they skip it; queue-paired dates show
   *  it to both people. */
  const [speedDateWelcome, setSpeedDateWelcome] = useState<boolean>(false);
  const [roomCardEditor, setRoomCardEditor] = useState<boolean>(false);
  const [datingCards, setDatingCards] = useState<Record<string, DatingCardWire>>({});
  type BlindWrapContext = {
    partnerUserId: string;
    partnerName: string;
    partnerAvatarUrl: string | null;
    transcript: string;
    theirCard: DatingCardWire | null;
    revealed: boolean;
    partnerLeft: boolean;
    elapsedSec: number;
  };
  /** The session — shared clock, curtain/reveal, extensions, deck — a
   *  mutable object the stage re-renders on a half-second tick. */
  const blindRef = useRef<BlindDateSession>(new BlindDateSession());
  const [blindTick, setBlindTick] = useState<number>(0);
  const bumpBlind = useCallback((): void => setBlindTick((t) => t + 1), []);
  /** Set when the date ends (time's up, END, or they left) — shows the wrap. */
  const [blindWrap, setBlindWrap] = useState<BlindWrapContext | null>(null);
  const blindWrapRef = useRef<BlindWrapContext | null>(null);
  const blindLeavingRef = useRef<boolean>(false);
  const blindDeckRequestedRef = useRef<boolean>(false);
  const blindCardsRef = useRef<Record<string, DatingCardWire>>({});
  const blindParticipantsRef = useRef<LiveParticipantInfo[]>([]);
  /** The clock/wire actions, reachable from the wire handler defined earlier. */
  const blindActionsRef = useRef<{
    start: () => void;
    reveal: (broadcast: boolean) => void;
    extend: () => void;
    finish: (partnerLeft: boolean) => Promise<void>;
  }>({ start: () => undefined, reveal: () => undefined, extend: () => undefined, finish: async () => undefined });
  useEffect(() => {
    blindWrapRef.current = blindWrap;
  }, [blindWrap]);
  useEffect(() => {
    blindCardsRef.current = datingCards;
  }, [datingCards]);
  useEffect(() => {
    blindParticipantsRef.current = participants;
  }, [participants]);
  const [myBizPlus, setMyBizPlus] = useState<MyBusinessPlus | null>(null);
  const [bizMenuOpen, setBizMenuOpen] = useState<boolean>(false);
  /** Presenter side — who raised a hand on the live company card. */
  const [bizInterested, setBizInterested] = useState<string[]>([]);
  /** Viewer side — hand already raised on the current card. */
  const [bizHandRaised, setBizHandRaised] = useState<boolean>(false);
  const [creatorExpanded, setCreatorExpanded] = useState<boolean>(false);
  const [creatorBuilding, setCreatorBuilding] = useState<boolean>(false);
  const [emberTranscribing, setEmberTranscribing] = useState<boolean>(false);
  const [showCaptions, setShowCaptions] = useState<boolean>(() => readMeetPrefs().captions);
  // ── Google-Meet-grammar room state (reactions · hands · panels · layout) ──
  const [meetPrefs] = useMeetPrefs();
  const [reactionsOpen, setReactionsOpen] = useState<boolean>(false);
  const [floatingReactions, pushFloatingReaction] = useFloatingReactions();
  /** Raised hands keyed by lowercased userId → display name (iOS `call-hand` wire). */
  const [raisedHands, setRaisedHands] = useState<Record<string, string>>({});
  const [roomChat, setRoomChat] = useState<MeetChatMessage[]>([]);
  const [chatUnread, setChatUnread] = useState<number>(0);
  const [adjustOpen, setAdjustOpen] = useState<boolean>(false);
  const [moreOpen, setMoreOpen] = useState<boolean>(false);
  const [meetSettingsOpen, setMeetSettingsOpen] = useState<boolean>(false);
  const [bugReportOpen, setBugReportOpen] = useState<boolean>(false);
  const [isFullscreen, setIsFullscreen] = useState<boolean>(false);
  const [roomPolicy, setRoomPolicy] = useState<{ chat: boolean; reactions: boolean; present: boolean; quickAccess: boolean }>({
    chat: true,
    reactions: true,
    present: true,
    quickAccess: true,
  });
  /** Latest policy for the (stable) signaling handler. */
  const roomPolicyRef = useRef(roomPolicy);
  roomPolicyRef.current = roomPolicy;
  // ─── Knocking (Meet's "Ask to join") ───
  /** People waiting at the door — only the doorkeeper acts on them. */
  const [pendingKnocks, setPendingKnocks] = useState<MeetKnock[]>([]);
  /** MY knock, while I'm the one waiting outside. */
  const [knockState, setKnockState] = useState<MeetKnockState | null>(null);
  const knockHostNameRef = useRef<string | null>(null);
  const [knockHostName, setKnockHostName] = useState<string | null>(null);
  const doorbellRef = useRef<MeetDoorbell | null>(null);
  const knockTimersRef = useRef<number[]>([]);
  /** Whether THIS client answers knocks (acting host, or the doorkeeper when no host is in). */
  const isDoorkeeperRef = useRef<boolean>(false);
  /** Invite-by-email from the room's Add-people drawer. */
  const [inviteEmail, setInviteEmail] = useState<string>("");
  const [inviteEmailBusy, setInviteEmailBusy] = useState<boolean>(false);
  const [readyCardDismissed, setReadyCardDismissed] = useState<boolean>(false);
  /** Bumped by `call-mute-all` / a targeted `call-mute` — the mic effect below acts on it. */
  const [muteRequest, setMuteRequest] = useState<number>(0);
  const [captionText, setCaptionText] = useState<string>("");
  // Ember's live voice — a true OpenAI Realtime session (echo voice), no TTS.
  const [emberVoice, setEmberVoice] = useState<"off" | "connecting" | "live">("off");
  const [emberSpeaking, setEmberSpeaking] = useState<boolean>(false);
  const [emberHearing, setEmberHearing] = useState<boolean>(false);
  const [emberMicMuted, setEmberMicMuted] = useState<boolean>(false);
  const [emberReply, setEmberReply] = useState<string | null>(null);
  const [emberBusy, setEmberBusy] = useState<boolean>(false);
  const [emberError, setEmberError] = useState<boolean>(false);
  const [mediaState, setMediaState] = useState<LocalMediaState | null>(null);
  const [mediaBusy, setMediaBusy] = useState<boolean>(false);
  const [deviceBannerDismissed, setDeviceBannerDismissed] = useState<boolean>(false);
  const [joinBusy, setJoinBusy] = useState<boolean>(false);
  const [lobbyBlocked, setLobbyBlocked] = useState<boolean>(false);
  // Pre-join device choices — applied the moment the call connects (iOS parity).
  const [joinPrefMic, setJoinPrefMic] = useState<boolean>(true);
  const [joinPrefCam, setJoinPrefCam] = useState<boolean>(true);
  const joinPrefMicRef = useRef<boolean>(true);
  const joinPrefCamRef = useRef<boolean>(true);
  // Backgrounds & effects — shared engine across the lobby preview and the call.
  const [effectsOpen, setEffectsOpen] = useState<boolean>(false);
  const [fxMode, setFxMode] = useState<VideoFxMode>(videoFx.mode);
  const [fxImage, setFxImage] = useState<string | null>(videoFx.imageUrl);
  const [lobbyCamState, setLobbyCamState] = useState<"loading" | "ready" | "blocked" | "off">("loading");
  /** Bumps re-run the lobby camera acquisition from a real user gesture —
   *  Safari auto-denies getUserMedia calls that don't ride a click, so the
   *  blocked state needs a tap-powered second chance. */
  const [lobbyCamRetry, setLobbyCamRetry] = useState<number>(0);
  const lobbyStreamRef = useRef<MediaStream | null>(null);
  const lobbyVideoRef = useRef<HTMLVideoElement | null>(null);
  // Present-to-everyone — the client profile pinned to the presenter's frame.
  const [presentation, setPresentation] = useState<PresentedClientPayload | null>(null);
  const [presentationExpanded, setPresentationExpanded] = useState<boolean>(false);
  // Lagging copy of the presentation so the dock can play its exit animation.
  const [dockPayload, setDockPayload] = useState<PresentedClientPayload | null>(null);
  const [dockLeaving, setDockLeaving] = useState<boolean>(false);
  const [selectedProspect, setSelectedProspect] = useState<Prospect | null>(null);
  // Ember's in-meeting persona + rich reply payload.
  // Start from the user's saved personality (Auto resolves live) — the
  // in-meeting Jasper wears the same ghost as the main chat.
  const [emberMode, setEmberMode] = useState<EmberCoachMode>(() => loadCoachMode());
  const [emberBlocks, setEmberBlocks] = useState<EmberBlock[]>([]);
  const [emberPitchOffer, setEmberPitchOffer] = useState<boolean>(false);
  const [showPitchDeck, setShowPitchDeck] = useState<boolean>(false);
  // Ember's interactive pitch tools — the REAL components, in-meeting.
  const [wppOpen, setWppOpen] = useState<boolean>(false);
  const [brandCardsOpen, setBrandCardsOpen] = useState<boolean>(false);
  // Ember deck walkthrough — synced room-wide; the driver runs Ember's voice.
  const [deckTour, setDeckTour] = useState<DeckTourView | null>(null);
  const [tourVoice, setTourVoice] = useState<"off" | "connecting" | "live">("off");
  const [tourHidden, setTourHidden] = useState<boolean>(false);
  // Pop-out meeting view (Document PiP / video PiP fallback).
  const [docPipOpen, setDocPipOpen] = useState<boolean>(false);
  // Ember ask panel — typed input + live voice interim so a tap ALWAYS works.
  const [emberDraft, setEmberDraft] = useState<string>("");
  const [emberUserInterim, setEmberUserInterim] = useState<string>("");
  const [emberVoiceHint, setEmberVoiceHint] = useState<string | null>(null);
  // An Ember answer somebody shared with the whole meeting.
  const [sharedEmber, setSharedEmber] = useState<SharedEmberAnswer | null>(null);
  const [sharedClientCard, setSharedClientCard] = useState<SharedClientCard | null>(null);
  // Recruiter-only: Ember's live prospect read + the post-meeting evaluation.
  const [liveEval, setLiveEval] = useState<ProspectEvaluation | null>(null);
  const [liveEvalCollapsed, setLiveEvalCollapsed] = useState<boolean>(false);
  /** Dismissed for THIS meeting — the float disappears entirely and comes
   *  back only from Recruiter tools. */
  const [liveEvalDismissed, setLiveEvalDismissed] = useState<boolean>(false);
  const [evalPhase, setEvalPhase] = useState<"listening" | "evaluating" | "ready">("listening");
  const [evalNow, setEvalNow] = useState<number>(Date.now());
  const [finalEval, setFinalEval] = useState<ProspectEvaluation | null>(null);
  const [finalEvalBusy, setFinalEvalBusy] = useState<boolean>(false);
  // Jasper's pitch deck — drafted mid-meeting from the live transcript,
  // finalized from the full transcript when the meeting ends.
  const [pitchDeck, setPitchDeck] = useState<JasperPitchDeck | null>(null);
  const [deckSampleOpen, setDeckSampleOpen] = useState<boolean>(false);
  const [deckBusy, setDeckBusy] = useState<boolean>(false);
  const [deckToast, setDeckToast] = useState<boolean>(false);
  const deckDraftRef = useRef<boolean>(false);
  const meetingTitleRef = useRef<string>("Meeting");
  // Notes sharing (ended screen).
  const [showNotesShare, setShowNotesShare] = useState<boolean>(false);
  const [notesSending, setNotesSending] = useState<boolean>(false);
  const [notesEmailOpen, setNotesEmailOpen] = useState<boolean>(false);
  const [notesEmails, setNotesEmails] = useState<string>("");
  const [notesEmailSending, setNotesEmailSending] = useState<boolean>(false);
  // Application capture — Ember fills the recruiter's standard application
  // questions from the live conversation and files them to their applicants.
  const [appCapOn, setAppCapOn] = useState<boolean>(false);
  const [appCapAnswers, setAppCapAnswers] = useState<
    Record<string, { question: string; answer: string }>
  >({});
  const [appCapBusy, setAppCapBusy] = useState<boolean>(false);
  const [appCapName, setAppCapName] = useState<string>("");
  const [appCapSaving, setAppCapSaving] = useState<boolean>(false);
  const [appCapSavedAt, setAppCapSavedAt] = useState<number | null>(null);
  // Voice auto-schedule — a date spoken by anyone in the call becomes a
  // one-tap shared-calendar event with every participant tagged. Detection
  // runs on each client's own captions and is broadcast so the whole room
  // sees (and can agree to) the same prompt.
  const [scheduleSuggest, setScheduleSuggest] = useState<{
    dateMs: number;
    snippet: string;
    eventType: CalendarEventType;
    byName: string;
  } | null>(null);
  const [scheduleOpen, setScheduleOpen] = useState<boolean>(false);
  const [scheduleTitle, setScheduleTitle] = useState<string>("");
  const [scheduleWhen, setScheduleWhen] = useState<string>("");
  const [scheduleType, setScheduleType] = useState<CalendarEventType>("meet");
  const [scheduleAttach, setScheduleAttach] = useState<boolean>(true);
  const [scheduleBusy, setScheduleBusy] = useState<boolean>(false);
  const scheduleBucketsRef = useRef<Set<number>>(new Set());
  const pipVideoRef = useRef<HTMLVideoElement | null>(null);
  const lobbyCleanupRef = useRef<(() => void) | null>(null);
  const openRecording = useCallback((open: boolean): void => { setRecordingOpen(open); if (open) { setActivitiesOpen(false); setPanelTab(null); } }, []);
  /** True while the user explicitly popped out the fallback video PiP. */
  const manualPipRef = useRef<boolean>(false);
  const docPipWindowRef = useRef<Window | null>(null);
  const pipTilesRef = useRef<
    Map<string, { wrap: HTMLDivElement; video: HTMLVideoElement; fallback: HTMLDivElement; label: HTMLDivElement }>
  >(new Map());
  const renderDocPipRef = useRef<(() => void) | null>(null);
  const participantsRef = useRef<LiveParticipantInfo[]>([]);
  /** The canvas mosaic behind classic (single-video) PiP — every participant
   *  painted into one stream, since that PiP can only carry ONE element. */
  const pipMosaicRef = useRef<MeetPipMosaic | null>(null);
  /** Ember walkthrough driver internals — voice session, position, timers. */
  const tourSessionRef = useRef<EmberRealtimeSession | null>(null);
  const tourEpochRef = useRef<number>(0);
  const tourPosRef = useRef<{ slide: number; segment: number; playing: boolean } | null>(null);
  const tourHeartbeatRef = useRef<number | null>(null);
  const tourBeatRef = useRef<number>(0);
  const tourFlagsRef = useRef<{ done: boolean; quiet: boolean }>({ done: false, quiet: true });
  const tourAdvanceTimerRef = useRef<number | null>(null);
  const tourWatchdogRef = useRef<number | null>(null);
  const speakTourSegmentRef = useRef<((slide: number, segment: number) => void) | null>(null);
  const tourMaybeAdvanceRef = useRef<(() => void) | null>(null);
  const startDeckTourRef = useRef<(() => void) | null>(null);
  const stopDeckTourRef = useRef<((options?: { silent?: boolean }) => void) | null>(null);
  /** Local playback for device-voiced walkthroughs (iOS drivers) — every
   *  participant's machine speaks the same fixed script line. */
  const tourAudioRef = useRef<HTMLAudioElement | null>(null);
  const tourAudioKeyRef = useRef<string>("");

  const rtcRef = useRef<WhisperLiveRTC | null>(null);
  const recognizerRef = useRef<SpeechRecognitionLike | null>(null);
  const recorderTranscriberRef = useRef<MeetingRecorderTranscriber | null>(null);
  const captureDrainRef = useRef<MeetingCaptureDrain>(new MeetingCaptureDrain());
  const transcriptFinalizationRef = useRef<Promise<void>>(Promise.resolve());
  const [transcriptFinishing, setTranscriptFinishing] = useState<boolean>(false);
  /** Mic stream the captions fallback owns when RTC hasn't produced one. */
  const ownedMicStreamRef = useRef<MediaStream | null>(null);
  /** Last time each participant's Jasper app streamed live vitals. */
  const liveVitalsAtRef = useRef<Record<string, number>>({});
  const appCapCharsRef = useRef<number>(0);
  const appCapBusyRef = useRef<boolean>(false);
  const appCapNameRef = useRef<string>("");
  const autoJoinedRef = useRef<boolean>(false);
  const transcriptionPausedRef = useRef<boolean>(false);
  const nativeTranscriptionActiveRef = useRef<boolean>(false);
  const transcriptWriteQueueRef = useRef<Promise<void>>(Promise.resolve());
  /** The live speech-to-speech session + an epoch guard for stale callbacks. */
  const emberSessionRef = useRef<EmberRealtimeSession | null>(null);
  const emberVoiceEpochRef = useRef<number>(0);
  const stoppingRef = useRef<boolean>(false);
  const lastEmberQuestionRef = useRef<string>("");
  /** Live prospect scoring — dedupe + growth tracking between evaluations. */
  const evalBusyRef = useRef<boolean>(false);
  const lastEvalCharsRef = useRef<number>(0);
  const evalHintRef = useRef<string | null>(null);
  // The eval interval reads these through refs so hydrating profile/meeting
  // data never restarts the loop's cadence. (Synced below, after the
  // meeting query is declared.)
  const profileRef = useRef<{ username?: string | null } | null>(null);
  const meetingHostRef = useRef<string | null>(null);
  /** Presenter-side heartbeat so late joiners receive the presentation. */
  const presentHeartbeatRef = useRef<number | null>(null);
  const presentationPayloadRef = useRef<PresentedClientPayload | null>(null);
  /** Viewer-side freshness stamp — clears the overlay if the presenter vanishes. */
  const presentBeatRef = useRef<number>(0);
  const creatorCardRef = useRef<CreatorAnalyticsCardPayload | null>(null);
  const bizCardRef = useRef<BusinessCardWire | null>(null);
  const speedDateRef = useRef<boolean>(false);
  const myDatingWireRef = useRef<Record<string, unknown> | null>(null);
  const datingHeartbeatRef = useRef<number | null>(null);
  const activateSpeedDateRef = useRef<() => void>(() => {});
  const bizBuildingRef = useRef<boolean>(false);
  /** Viewer-side rev key — a fresh card resets the hand-raise button. */
  const bizSeenRevRef = useRef<string>("");
  /** Businesses this viewer already got filed as a lead for (this session). */
  const bizLeadSentRef = useRef<Set<string>>(new Set());
  const creatorKeyRef = useRef<string>("");
  const creatorBeatRef = useRef<number>(0);
  const creatorHeartbeatRef = useRef<number | null>(null);
  const presentationKeyRef = useRef<string>("");

  /** True inside the embedded preview iframe, where hardware permissions are
   *  often withheld — we offer "open in a browser tab" instead of failing. */
  const isEmbedded = useMemo<boolean>(() => {
    try {
      return window.self !== window.top;
    } catch {
      return true;
    }
  }, []);

  // The link grant is recorded before reads so strict RLS can keep meeting
  // metadata and transcripts private to the host and link participants.
  useEffect(() => {
    if (!id) {
      setMeetingAccessReady(false);
      return;
    }
    if (!user) {
      // Guests hold no account — the unguessable link itself is their grant.
      setMeetingAccessReady(true);
      return;
    }
    // Signed-in but the profile row hasn't landed yet (auth bootstrap):
    // wait — stamping the room/participant with the "member" placeholder
    // here is exactly how hosts ended up named @member. The effect re-runs
    // the moment the profile loads (or bootstrap settles without one).
    if (!profile && authLoading) return;
    let cancelled = false;
    setMeetingAccessReady(false);
    void (async () => {
      if (isCodeRoom) {
        // Code rooms have no creator flow — whoever arrives signed-in first
        // opens the room (idempotent; concurrent arrivals can't error).
        await ensureMeetingRoom({
          id,
          hostId: user.id,
          hostUsername: profile?.username ?? "member",
        }).catch(() => undefined);
      }
      // The link IS the invitation: joining records membership, which is
      // also what unlocks the row read. A transient failure gets one quiet
      // retry; a refusal because the meeting ENDED is remembered so the
      // room can say "ended" instead of a false "not found".
      const join = (): Promise<void> =>
        joinMeeting({ meetingId: id, userId: user.id, username: profile?.username ?? "member" });
      try {
        await join();
        if (!cancelled) setJoinRefusal(null);
      } catch (err) {
        const message =
          err instanceof Error ? err.message : String((err as { message?: string } | null)?.message ?? err);
        if (/meeting_unavailable/i.test(message)) {
          if (!cancelled) setJoinRefusal("unavailable");
        } else {
          await new Promise((resolve) => setTimeout(resolve, 900));
          await join().catch(() => undefined);
        }
      }
    })().finally(() => {
      if (!cancelled) setMeetingAccessReady(true);
    });
    return () => {
      cancelled = true;
    };
  }, [id, isCodeRoom, profile, authLoading, user?.id]);

  const meetingQuery = useQuery({
    queryKey: ["meeting", id ?? ""],
    queryFn: () => fetchMeeting(id!),
    enabled: !!id && meetingAccessReady,
    // Guests can open a code link before any signed-in member has created
    // the row — keep checking quietly so the room opens by itself.
    // Guests on a uuid link poll too: their row read depends on the anon
    // policy landing, and the host may still be on their way in.
    refetchInterval: (query) =>
      (isCodeRoom || !user || !graceOver) && !query.state.data ? 3500 : joined ? 6000 : false,
  });
  const meeting = meetingQuery.data ?? null;
  // Keep the route's public code, not its derived database UUID, when sharing.
  const invitationLink = speedDateRoom
    ? `https://www.mydailywhisper.com/meet/${meetingId}?sd=1`
    : callWith
      ? `https://www.mydailywhisper.com/meet/${meetingId}?call=${encodeURIComponent(callWith)}${callMode === "audio" ? "&mode=audio" : ""}`
      : meeting?.summary?.startsWith("::whisper-group-call-v1::") || meeting?.title?.startsWith("Group call · ")
        ? `https://www.mydailywhisper.com/meet/${meetingId}?groupCall=1`
        : meetingLink(meetingId ?? "");
  useEffect(() => {
    if (!meetingAccessReady) {
      setGraceOver(false);
      return;
    }
    const timer = window.setTimeout(() => setGraceOver(true), 15_000);
    return () => window.clearTimeout(timer);
  }, [meetingAccessReady, id]);
  /** The room's current host — the owner, or whoever holds the room after
   *  the owner left without ending the call (Meet's handoff rule). */
  const hostUserId: string | null = actingHostId ?? meeting?.host_id ?? null;
  const isHost = !!user && !!meeting && hostUserId === user.id;
  const currentHostIdRef = useRef<string | null>(hostUserId);
  currentHostIdRef.current = hostUserId;
  const recordingCapture = useMeetingRecording(user?.id ?? "", id ?? null, meeting?.title ?? "Meeting", hostUserId, rtcRef, joined && !postCall && !kickedOut && !speedDateRoom, (state) => {
    const update = state.update ?? (state.request ? { state: "starting" as const, seconds: 0, error: null, recordingId: state.request.requestId, audioInputs: 0 } : null);
    if (update && user && id && meetingId) meetingHost.setRecordingStatus({ ownerId: user.id, meetingId: id, routeId: meetingId, update, inCall: joined });
    else if (!state.request) meetingHost.setRecordingStatus(null, meetingId);
  });
  recordingCapture.session.stageSnapshot = () => readMeetingStage(document.querySelector<HTMLElement>("[data-meeting-stage]"));
  useEffect(() => { if (panelTab || minimized) { setActivitiesOpen(false); setRecordingOpen(false); } }, [panelTab, minimized]);
  useEffect(() => {
    if (minimized && recordingCapture.session.state.request) void recordingCapture.session.stop(false, "Recording stopped because the meeting was minimized. Keep the meeting visible when recording.");
  }, [minimized, recordingCapture.session]);
  const minimizeToTile = useCallback((): void => {
    if (recordingCapture.session.state.request || recordingCapture.session.state.update?.state === "saving") {
      toast("Stop and save the recording before minimizing; video follows the visible meeting.");
      return;
    }
    setActivitiesOpen(false); setRecordingOpen(false);
    meetingHost.minimize();
    navigate(MEET_PORTAL ? "/" : !user ? "/" : callWith ? "/messages" : "/meetings");
  }, [recordingCapture.session, meetingHost, navigate, callWith, user]);
  const recordingSessionRef = useRef(recordingCapture.session);
  recordingSessionRef.current = recordingCapture.session;
  const publishRecordingStatus = meetingHost.setRecordingStatus;
  useEffect(() => {
    const update = recordingCapture.session.state.update;
    if (update && user && id && meetingId) publishRecordingStatus({ ownerId: user.id, meetingId: id, routeId: meetingId, update, inCall: joined });
  }, [recordingCapture.session, user, id, meetingId, joined, publishRecordingStatus]);
  // The DOORKEEPER answers knocks: the acting host while they're in the room;
  // when no host is present, the lowest signed-in userId (deterministic on
  // every client, like the host election) so a guest is never left waiting
  // at a door nobody can open.
  const hostPresent = !!hostUserId && participants.some((p) => p.userId === hostUserId);
  const lowestMemberId =
    participants
      .map((p) => p.userId)
      .filter((uid) => !!uid && !uid.startsWith("guest_") && !uid.startsWith("local_"))
      .sort()[0] ?? null;
  const isDoorkeeper = isHost || (!!user && !hostPresent && lowestMemberId === user.id);
  isDoorkeeperRef.current = isDoorkeeper;
  const hasEnded = meeting?.status === "ended";

  /** Meet's rule that a link is never dead: reopen an ended meeting so
   *  everyone holding the link can come back in. */
  const startAgain = async (): Promise<void> => {
    if (!user || !id || reopening) return;
    setReopening(true);
    try {
      await reopenMeeting({ meetingId: id, userId: user.id, username: profile?.username ?? "member" });
      setJoinRefusal(null);
      setNotes(null);
      setPostCall(null);
      endedByMeRef.current = false;
      await meetingQuery.refetch();
      toast.success("The meeting is open again — everyone with the link can join.");
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Couldn't start the meeting again.");
    } finally {
      setReopening(false);
    }
  };

  // Following list for the invite picker.
  const followingQuery = useQuery({
    queryKey: ["meeting-following", user?.id ?? ""],
    queryFn: () => fetchFollowing(user!.id),
    enabled: !!user && (showInvite || showNotesShare),
  });
  const following = followingQuery.data ?? [];
  const inviteNeedle = inviteQuery.trim().toLowerCase();
  const filteredFollowing = inviteNeedle
    ? following.filter(
        (f) =>
          f.username.toLowerCase().includes(inviteNeedle) ||
          (f.profile?.display_name ?? "").toLowerCase().includes(inviteNeedle),
      )
    : following;

  // Load persisted notes for ended meetings.
  useEffect(() => {
    if (meeting?.summary && !meeting.summary.startsWith("::whisper-group-call-v1::")) setNotes(meeting.summary);
  }, [meeting?.summary]);

  const [sidekickCaptureStatus, setSidekickCaptureStatus] = useState<string>("Transcription hasn't started");
  const [sidekickInterim, setSidekickInterim] = useState<string>("");
  // The raw transcript for the post-meeting screen — shown even when the AI
  // notes step fails so captured speech is never invisible.
  const transcriptQuery = useQuery({
    queryKey: ["meeting-transcript", id ?? ""],
    queryFn: () => fetchTranscript(id!),
    enabled: !!id && !!user && meetingAccessReady && (hasEnded || notes != null),
    refetchInterval: hasEnded ? 5000 : false,
  });

  // Applicant questionnaire responses (the QR application) so presented
  // client profiles carry real potential scores into the broadcast.
  const applicantResponsesQuery = useQuery({
    queryKey: ["meeting-applicant-responses", user?.id ?? ""],
    queryFn: () => fetchRecruiterResponses(user!.id),
    enabled: !!user && !!profile?.is_recruiter && joined,
  });

  /** Re-run the full prospect evaluation from the final transcript. */
  const runFinalEval = useCallback(async (): Promise<void> => {
    if (!id || finalEvalBusy) return;
    const segments = transcriptQuery.data ?? [];
    // Score ONLY the prospect's own answers — the host/recruiter's pitch
    // lines must never move the read.
    const excludedSpeakers = new Set(
      [profile?.username, meeting?.host_username]
        .filter(Boolean)
        .map((u) => (u as string).toLowerCase()),
    );
    const text = segments
      .filter((s) => !excludedSpeakers.has((s.username || "").toLowerCase()))
      .map((s) => `${s.username || "speaker"}: ${s.text}`)
      .join("\n");
    if (text.length < 80) {
      toast("Not enough of the prospect's own words to evaluate yet.");
      return;
    }
    setFinalEvalBusy(true);
    const result = await emberProspectEvaluation(text, null).catch(() => null);
    setFinalEvalBusy(false);
    if (result) {
      setFinalEval(result);
      try {
        localStorage.setItem(`whisper_meeting_eval:${id}`, JSON.stringify(result));
      } catch {
        /* storage unavailable */
      }
    } else {
      toast("Jasper couldn't evaluate right now — try again in a moment.");
    }
  }, [finalEvalBusy, id, transcriptQuery.data, profile?.username, meeting?.host_username]);

  /** DM the notes to one person from the share picker — the FULL transcript
   *  rides along (the loaded one, or a fresh read when it isn't in hand). */
  const sendNotesDm = useCallback(
    async (toUserId: string, toUsername: string): Promise<void> => {
      if (!user || !notes) return;
      setNotesSending(true);
      try {
        const segments =
          transcriptQuery.data && transcriptQuery.data.length > 0
            ? transcriptQuery.data
            : id
              ? await fetchTranscript(id).catch(() => [])
              : [];
        await sendMessage(
          user.id,
          profile?.username ?? "me",
          toUserId,
          toUsername,
          notesDmText(meeting?.title ?? "Meeting", notes, invitationLink, transcriptPlainText(segments)),
        );
        toast.success(`Notes sent to @${toUsername}`);
      } catch {
        toast.error(`Couldn't send to @${toUsername} — try again`);
      } finally {
        setNotesSending(false);
      }
    },
    [meeting?.title, notes, profile?.username, user, id, transcriptQuery.data, invitationLink],
  );

  /** Voice auto-schedule — scan my finalized caption for a spoken future
   *  date ("let's film Friday at 3"). On a hit the prompt shows locally AND
   *  broadcasts so every participant can agree to the same event. */
  const maybeDetectSchedule = useCallback((text: string): void => {
    if (!user) return;
    const hit = detectSpokenSchedule(text);
    if (!hit) return;
    const bucket = Math.floor(hit.date.getTime() / 600_000);
    if (scheduleBucketsRef.current.has(bucket)) return;
    scheduleBucketsRef.current.add(bucket);
    const byName = profile?.username ?? "someone";
    setScheduleSuggest({
      dateMs: hit.date.getTime(),
      snippet: hit.snippet,
      eventType: hit.eventType,
      byName,
    });
    rtcRef.current?.sendAppEvent("schedule-suggest", {
      byUserId: user.id,
      byName,
      dateMs: hit.date.getTime(),
      snippet: hit.snippet,
      eventType: hit.eventType,
    });
  }, [profile?.username, user]);

  /** Queue writes so the final caption reaches Supabase before host notes run. */
  const enqueueTranscript = useCallback((rawText: string, capture?: { spokenAt: string }): void => {
    if (!id || !user) return;
    const text = rawText.trim();
    if (!text) return;

    setCaptionText(text);
    setEmberTranscribing(true);
    window.setTimeout(() => setEmberTranscribing(false), 1600);
    maybeDetectSchedule(text);
    const retention = retainTranscript({ meetingId: id, userId: user.id, username: profile?.username ?? 'speaker', text, spokenAt: capture?.spokenAt })
      .catch(() => { setSidekickCaptureStatus('Speech recovery needs attention; keep this meeting open'); });
    transcriptWriteQueueRef.current = transcriptWriteQueueRef.current.catch(() => undefined)
      .then(async () => { await retention; await flushTranscriptOutbox(user.id); })
      .catch(() => { setSidekickCaptureStatus('Captured speech is waiting to save · retry transcript'); });
  }, [id, user, profile?.username, maybeDetectSchedule]);

  /** Everyone on the call except me — tagged on the calendar event so each
   *  person gets the invite card in DMs (group meetings included). */
  const taggableParticipants = useCallback((): { ids: string[]; names: string[] } => {
    const map = new Map<string, string>();
    const meId = user?.id.toLowerCase() ?? "";
    for (const p of participants) {
      const uid = (p.userId || "").trim().toLowerCase();
      if (!uid || uid === meId || uid === "guest" || uid.startsWith("local_")) continue;
      if (!map.has(uid)) map.set(uid, p.name);
    }
    return { ids: Array.from(map.keys()), names: Array.from(map.values()) };
  }, [participants, user?.id]);

  /** Prefill the schedule modal from the voice suggestion + who's here. */
  const openScheduleModal = useCallback((): void => {
    if (!scheduleSuggest) return;
    const { names } = taggableParticipants();
    setScheduleTitle(suggestedScheduleTitle(scheduleSuggest.eventType, names));
    setScheduleWhen(toLocalInputValue(scheduleSuggest.dateMs));
    setScheduleType(scheduleSuggest.eventType);
    setScheduleAttach(attachesMeetingByDefault(scheduleSuggest.eventType));
    setScheduleOpen(true);
  }, [scheduleSuggest, taggableParticipants]);

  /** Create the scheduled meeting (optional) + the tagged calendar event. */
  const submitSchedule = useCallback(async (): Promise<void> => {
    if (!user || scheduleBusy) return;
    const title = scheduleTitle.trim() || "Follow-up";
    const when = new Date(scheduleWhen);
    if (Number.isNaN(when.getTime()) || when.getTime() < Date.now()) {
      toast.error("Pick a future time");
      return;
    }
    setScheduleBusy(true);
    try {
      const username = profile?.username ?? "member";
      const iso = when.toISOString();
      let link: string | undefined;
      if (scheduleAttach) {
        try {
          const scheduled = await createMeeting({
            hostId: user.id,
            hostUsername: username,
            title,
            scheduledAt: iso,
          });
          link = meetingLink(scheduled.id);
        } catch {
          /* The calendar event still gets created without the room link. */
        }
      }
      const { ids, names } = taggableParticipants();
      const created = await createCalendarEvent({
        createdBy: user.id,
        createdByUsername: username,
        title,
        description: `Planned live in \u201C${meeting?.title ?? "a Whisper meeting"}\u201D`,
        eventType: scheduleType,
        startTime: iso,
        meetingLink: link,
        taggedUserIds: ids,
        taggedUsernames: names,
      });
      if (!created) throw new Error("event failed");
      toast.success(
        link
          ? "Added to the shared calendar — meeting attached"
          : "Added to the shared calendar",
      );
      setScheduleOpen(false);
      setScheduleSuggest(null);
    } catch {
      toast.error("Couldn't create the event. Try again.");
    } finally {
      setScheduleBusy(false);
    }
  }, [meeting?.title, profile?.username, scheduleAttach, scheduleBusy, scheduleTitle, scheduleType, scheduleWhen, taggableParticipants, user]);

  /** Caption fallback borrows the RTC microphone; it never acquires capture. */
  const startRecorderFallback = useCallback((stream: MediaStream | null): void => {
    if (!user || !id || (recorderTranscriberRef.current?.isActive || recorderTranscriberRef.current?.isStarting) || stoppingRef.current || transcriptionPausedRef.current || !stream?.getAudioTracks().some((track) => track.enabled && track.readyState === 'live')) return;
    const previous = recorderTranscriberRef.current;
    if (previous) { recorderTranscriberRef.current = null; captureDrainRef.current.retire(previous); }
    const tryStart = (s: MediaStream): boolean => {
      const recorder = startMeetingRecorderTranscription({
        stream: s, ownerId: user.id,
        onTranscript: enqueueTranscript,
        onReady: () => setSidekickCaptureStatus('Transcribing your microphone'),
        onError: (message: string) => { setSidekickCaptureStatus(message); },
      });
      if (recorder) { recorderTranscriberRef.current = recorder; setSidekickCaptureStatus("Preparing microphone transcription…"); }
      if (!recorder) setSidekickCaptureStatus('Transcription cannot access call audio · retry capture');
      return recorder != null;
    };
    if (stream && stream.getAudioTracks().length > 0) {
      tryStart(stream);
      return;
    }
    // RTC alone owns capture. Never open a competing microphone for captions.
  }, [enqueueTranscript, user, id]);

  /** Start continuous local speech capture → transcript rows and live captions. */
  const startTranscription = useCallback((): void => {
    if (!id || !user || recognizerRef.current || (recorderTranscriberRef.current?.isActive || recorderTranscriberRef.current?.isStarting) || !rtcRef.current?.localAudioStream?.getAudioTracks().some((track) => track.enabled && track.readyState === "live")) return;
    stoppingRef.current = false;
    transcriptionPausedRef.current = false;
    nativeTranscriptionActiveRef.current = false;
    const rec = isMobileWebKit() ? null : createRecognizer();
    if (!rec) {
      // No Web Speech in this browser (Firefox, some embedded views) — go
      // straight to the recorder → server transcription fallback so the host
      // still gets captions, a transcript, and AI notes.
      startRecorderFallback(rtcRef.current?.localAudioStream ?? null);
      return;
    }

    recognizerRef.current = rec;
    rec.onresult = (event) => {
      let interimText = "";
      for (let index = event.resultIndex; index < event.results.length; index++) {
        const result = event.results[index];
        const text = result[0].transcript.trim();
        if (result.isFinal) {
          enqueueTranscript(text);
        } else {
          interimText += `${interimText ? " " : ""}${text}`;
        }
      }
      setSidekickInterim(interimText);
      if (interimText) setCaptionText(interimText);
    };
    rec.onerror = (event) => {
      if (stoppingRef.current || transcriptionPausedRef.current) return;
      nativeTranscriptionActiveRef.current = false;
      setSidekickCaptureStatus("Recognition interrupted · checking fallback");
      setSidekickInterim("");
      if (recognizerRef.current === rec) recognizerRef.current = null;
      rec.onresult = null; rec.onend = null; rec.onerror = null;
      try { rec.stop(); } catch { /* Already stopped. */ }
      startRecorderFallback(rtcRef.current?.localAudioStream ?? null);
    };
    // Chrome stops recognition periodically. Restart while the meeting owns it,
    // but never race Ember's private question listener.
    rec.onend = () => {
      if (stoppingRef.current || transcriptionPausedRef.current || recognizerRef.current !== rec) return;
      try {
        rec.start();
      } catch {
        nativeTranscriptionActiveRef.current = false;
        recognizerRef.current = null;
        startRecorderFallback(rtcRef.current?.localAudioStream ?? null);
      }
    };
    try {
      rec.start();
      nativeTranscriptionActiveRef.current = true;
      setSidekickCaptureStatus("Transcribing your microphone");
    } catch {
      recognizerRef.current = null;
      startRecorderFallback(rtcRef.current?.localAudioStream ?? null);
    }
  }, [enqueueTranscript, id, startRecorderFallback, user]);

  useEffect(() => {
    if (!joined) return;
    const timer = setInterval(() => {
      const rtc = rtcRef.current;
      if (!rtc || stoppingRef.current || transcriptionPausedRef.current || recognizerRef.current) return;
      const track = rtc.localAudioStream?.getAudioTracks().find((item) => item.enabled && item.readyState === 'live');
      if (!track) return;
      const fallback = recorderTranscriberRef.current;
      if ((!fallback?.isActive && !fallback?.isStarting) || fallback?.trackId !== track.id) {
        if (fallback) { recorderTranscriberRef.current = null; captureDrainRef.current.retire(fallback); }
        startTranscription();
      }
    }, 8000);
    return () => clearInterval(timer);
  }, [joined, startTranscription]);

  /** Finalizes every capture path and flushes persisted local captions. */
  const stopTranscription = useCallback(async (): Promise<void> => {
    stoppingRef.current = true;
    setSidekickCaptureStatus("Transcription stopped");
    setSidekickInterim("");
    transcriptionPausedRef.current = false;
    nativeTranscriptionActiveRef.current = false;
    const rec = recognizerRef.current;
    recognizerRef.current = null;
    if (rec) {
      await new Promise<void>((resolve) => {
        const timer = window.setTimeout(() => { toast("The final caption could not be confirmed. Review the saved transcript for omissions."); finish(); }, 4000);
        const finish = (): void => { window.clearTimeout(timer); rec.onend = null; rec.onerror = null; rec.onresult = null; resolve(); };
        rec.onend = finish; rec.onerror = finish;
        try { rec.stop(); } catch { finish(); }
      });
    }
    const recorder = recorderTranscriberRef.current;
    recorderTranscriberRef.current = null;
    if (recorder) captureDrainRef.current.retire(recorder);
    ownedMicStreamRef.current?.getTracks().forEach((t) => t.stop());
    ownedMicStreamRef.current = null;
    const completion = captureDrainRef.current.finish().then(async () => { await transcriptWriteQueueRef.current; });
    transcriptFinalizationRef.current = completion;
    setTranscriptFinishing(true);
    void completion.finally(() => { if (transcriptFinalizationRef.current === completion) setTranscriptFinishing(false); });
    // Room closure must not wait on minutes of queued cloud work. Recap generation waits separately.
    await captureDrainRef.current.finishWithin(2500);
    setCaptionText("");
  }, []);

  /** Pause live browser recognition while Ember owns the speech session. */
  const pauseTranscriptionForEmber = useCallback((): void => {
    transcriptionPausedRef.current = true;
    setSidekickCaptureStatus("Transcription paused for private Jasper voice");
    const fallback = recorderTranscriberRef.current; recorderTranscriberRef.current = null;
    if (fallback) captureDrainRef.current.retire(fallback);
    try {
      recognizerRef.current?.stop();
    } catch {
      /* Already stopped. */
    }
  }, []);

  const resumeTranscriptionAfterEmber = useCallback((): void => {
    if (stoppingRef.current) return;
    transcriptionPausedRef.current = false;
    setSidekickCaptureStatus("Resuming transcription");
    const rec = recognizerRef.current;
    if (!rec) return;
    try {
      rec.start();
    } catch {
      /* The recognition session may already be running. */
    }
  }, []);

  /** Tears down Ember's live voice line and gives the mic back to captions. */
  const stopEmberVoice = useCallback((): void => {
    emberVoiceEpochRef.current += 1;
    const session = emberSessionRef.current;
    emberSessionRef.current = null;
    session?.close();
    setEmberVoice("off");
    setEmberSpeaking(false);
    setEmberHearing(false);
    setEmberMicMuted(false);
    setEmberUserInterim("");
    resumeTranscriptionAfterEmber();
  }, [resumeTranscriptionAfterEmber]);

  useEffect(() => { if (!emberPanelOpen && emberSessionRef.current) stopEmberVoice(); }, [emberPanelOpen, stopEmberVoice]);

  /** Ask Ember a private, meeting-aware question. With the live voice line
   *  up, the question rides the Realtime data channel and Ember answers OUT
   *  LOUD in the echo voice (transcript + cards stream in via callbacks).
   *  Otherwise it falls back to the text path — same brain, same cards, no
   *  robotic browser TTS ever. */
  // Live client snapshot context for coach 1:1 calls — synced via ref (the
  // vitals query is declared later in the component) so Jasper's meeting
  // brain can coach from the client's REAL numbers.
  const callVitalsCtxRef = useRef<string | null>(null);

  const askEmber = useCallback(async (question: string) => {
    lastEmberQuestionRef.current = question;
    setEmberPanelOpen(true);
    setEmberError(false);
    setEmberVoiceHint(null);
    const session = emberSessionRef.current;
    if (session?.isLive) {
      setEmberBusy(true);
      setEmberReply(null);
      session.sendText(question);
      return;
    }
    setEmberBusy(true);
    setEmberReply(null);
    setEmberBlocks([]);
    setEmberPitchOffer(false);
    setEmberUserInterim("");
    try {
      // Creators get grounded answers: their live Creator Studio numbers ride
      // along with the ask (cached DB read — no AI spend until this tap).
      let creatorCtx: string | null = null;
      if (isCreatorRole && user && profile?.username) {
        creatorCtx = await creatorJasperContext(user.id, profile.username, myBadge);
      }
      const extras = [callVitalsCtxRef.current, creatorCtx]
        .filter((s): s is string => typeof s === "string" && s.length > 0)
        .join("\n\n");
      const reply = await emberMeetingAnswer(question, {
        meetingTitle: meeting?.title ?? "Meeting",
        participants: participants.map((p) => p.name),
        extraContext: extras || null,
      });
      setEmberMode(reply.mode);
      setEmberBlocks(reply.block ? [reply.block] : []);
      setEmberPitchOffer(reply.showPitch);
      setEmberReply(
        reply.text ||
          (reply.block
            ? "Here's what I put together:"
            : reply.showPitch
              ? "Want the full story? Open the pitch deck below."
              : "Done."),
      );
    } catch (err) {
      setEmberError(true);
      setEmberReply(
        err instanceof Error && err.message
          ? err.message
          : "Jasper couldn't answer that right now."
      );
    } finally {
      setEmberBusy(false);
    }
  }, [meeting?.title, participants, isCreatorRole, user, profile?.username, myBadge]);

  // Successful Ember replies fade away on their own; errors stay for retry,
  // and interactive replies (cards, decks, pitch offers) linger much longer.
  // A draft in the input — or a LIVE voice session — keeps the panel open.
  useEffect(() => {
    if (!emberReply || emberBusy || emberError) return;
    if (emberDraft.trim()) return;
    if (emberVoice !== "off") return;
    const interactive = emberBlocks.length > 0 || emberPitchOffer;
    const timer = window.setTimeout(() => {
      setEmberReply(null);
      setEmberBlocks([]);
      setEmberPitchOffer(false);
      setEmberPanelOpen(false);
    }, interactive ? 60000 : 18000);
    return () => window.clearTimeout(timer);
  }, [emberReply, emberBusy, emberError, emberBlocks, emberPitchOffer, emberDraft, emberVoice]);

  // A shared Ember answer lingers on everyone's stage, then fades on its own.
  useEffect(() => {
    if (!sharedEmber) return;
    const timer = window.setTimeout(() => setSharedEmber(null), 26000);
    return () => window.clearTimeout(timer);
  }, [sharedEmber]);

  // A shared client card lingers the same way, then fades on its own.
  useEffect(() => {
    if (!sharedClientCard) return;
    const timer = window.setTimeout(() => setSharedClientCard(null), 26000);
    return () => window.clearTimeout(timer);
  }, [sharedClientCard]);

  // The live prospect read is hinted with whoever is being presented.
  useEffect(() => {
    evalHintRef.current =
      presentation?.displayName ?? presentation?.username ?? null;
  }, [presentation]);

  // The recruiter's standard application questions — powers live capture.
  const applicantQuestionsQuery = useQuery({
    queryKey: ["applicant-questions"],
    queryFn: fetchActiveQuestions,
    enabled: !!profile?.is_recruiter && (showRecruiterTools || appCapOn),
    staleTime: 5 * 60 * 1000,
  });

  // Restore a previously captured application draft for this meeting.
  useEffect(() => {
    if (!id) return;
    try {
      const raw = localStorage.getItem(`whisper_meeting_appcap:${id}`);
      if (raw) {
        const parsed = JSON.parse(raw) as {
          answers?: Record<string, { question: string; answer: string }>;
          name?: string;
        };
        setAppCapAnswers(parsed.answers ?? {});
        setAppCapName(parsed.name ?? "");
        appCapNameRef.current = parsed.name ?? "";
      }
    } catch {
      /* storage unavailable */
    }
  }, [id]);

  // Application capture loop — while ON, Ember re-reads the transcript every
  // ~25s and fills in any application questions the prospect answered aloud.
  useEffect(() => {
    if (!appCapOn || !joined || !id || !profile?.is_recruiter) return;
    const questions = applicantQuestionsQuery.data ?? [];
    if (questions.length === 0) return;
    let cancelled = false;
    const tick = async (): Promise<void> => {
      if (appCapBusyRef.current) return;
      const segments = await fetchTranscript(id).catch(() => []);
      if (cancelled) return;
      const text = segments
        .map((s) => `${s.username || "speaker"}: ${s.text}`)
        .join("\n");
      if (text.length < 80 || text.length - appCapCharsRef.current < 60) return;
      appCapBusyRef.current = true;
      setAppCapBusy(true);
      const found = await emberExtractApplicationAnswers(
        questions.map((q) => ({ id: q.id, question: q.question })),
        text,
      ).catch(() => ({} as Record<string, string>));
      appCapBusyRef.current = false;
      setAppCapBusy(false);
      if (cancelled) return;
      appCapCharsRef.current = text.length;
      if (Object.keys(found).length === 0) return;
      setAppCapAnswers((prev) => {
        const next = { ...prev };
        for (const [qid, answer] of Object.entries(found)) {
          const q = questions.find((x) => x.id === qid);
          if (q) next[qid] = { question: q.question, answer };
        }
        try {
          localStorage.setItem(
            `whisper_meeting_appcap:${id}`,
            JSON.stringify({ answers: next, name: appCapNameRef.current }),
          );
        } catch {
          /* storage unavailable */
        }
        return next;
      });
    };
    void tick();
    // 45s cadence (was 25s) — application capture still fills during the
    // call while spending roughly half the credits.
    const timer = window.setInterval(() => void tick(), 45000);
    return () => {
      cancelled = true;
      window.clearInterval(timer);
    };
  }, [appCapOn, joined, id, profile?.is_recruiter, applicantQuestionsQuery.data]);

  /** Files the captured answers as a real applicant response (scored with
   *  the same position-match engine as the QR questionnaire). */
  const saveApplicationCapture = useCallback(async (): Promise<void> => {
    if (!user || Object.keys(appCapAnswers).length === 0 || appCapSaving) return;
    setAppCapSaving(true);
    try {
      const code = await fetchOrCreateReferralCode(
        user.id,
        profile?.username ?? "recruiter",
      );
      if (!code) throw new Error("no_code");
      await submitApplicantResponse({
        recruiterCode: code.code,
        applicantName:
          appCapName.trim() || (meeting?.title ?? "Meeting prospect"),
        answers: appCapAnswers,
      });
      setAppCapSavedAt(Date.now());
      toast.success("Application saved to your applicants");
    } catch {
      toast.error("Couldn't save the application — try again.");
    } finally {
      setAppCapSaving(false);
    }
  }, [user, profile?.username, appCapAnswers, appCapName, appCapSaving, meeting?.title]);

  // Keep the eval loop's speaker-exclusion refs fresh without restarting
  // its interval — confidence scoring must skip the host's and this
  // recruiter's own lines.
  useEffect(() => {
    profileRef.current = profile ?? null;
  }, [profile]);
  useEffect(() => {
    meetingHostRef.current = meeting?.host_username ?? null;
  }, [meeting?.host_username]);
  useEffect(() => {
    meetingTitleRef.current = meeting?.title ?? "Meeting";
  }, [meeting?.title]);
  // A different meeting id means a different deck — never leak one across.
  useEffect(() => {
    deckDraftRef.current = false;
    setPitchDeck(null);
    setDeckSampleOpen(false);
    setDeckToast(false);
    setDeckBusy(false);
  }, [id]);

  // ── Speed dating activation — the starter primes the room from the
  // Dating hub (sessionStorage flag); guests light up when the first
  // dating card arrives on the wire. My card broadcasts once + heartbeats
  // every 12s so late joiners always catch it.
  const activateSpeedDate = useCallback((): void => {
    if (!speedDateRef.current) {
      speedDateRef.current = true;
      setSpeedDate(true);
      const blind = blindRef.current;
      // The lobby's "Enter the date" already marked me ready; the invited
      // side (and both people of a queue pairing) get the welcome takeover.
      const ready = id ? isBlindReady(id) : false;
      if (ready) blind.myReady = true;
      const paired = id ? blindPairedPartner(id) : null;
      if (paired) blind.partnerName = paired;
      if (!ready) setSpeedDateWelcome(true);
      if (id) void openBlindRecord(blindRecordKey(id), paired ? "queue" : "invite");
      bumpBlind();
    }
    if (!user) return;
    if (!myDatingWireRef.current) {
      // An EMPTY card still announces me so the other side lights up.
      myDatingWireRef.current = datingCardWirePayload(
        user.id,
        profile?.username ?? "me",
        loadDatingCardLocal(user.id),
      );
    }
    rtcRef.current?.sendAppEvent("dating-card", myDatingWireRef.current);
    if (datingHeartbeatRef.current == null) {
      datingHeartbeatRef.current = window.setInterval(() => {
        const current = myDatingWireRef.current;
        if (speedDateRef.current && current) {
          rtcRef.current?.sendAppEvent("dating-card", current);
        }
      }, 12_000);
    }
  }, [user, profile?.username, id, bumpBlind]);
  useEffect(() => {
    activateSpeedDateRef.current = activateSpeedDate;
  }, [activateSpeedDate]);
  useEffect(() => {
    if (!joined || !id) return;
    // ?sd=1 on the invite link primes speed-date mode for guests instantly.
    try {
      if (new URLSearchParams(window.location.search).get("sd") === "1") {
        markSpeedDateRoom(id);
      }
    } catch {
      // URL parsing blocked — the wire activation still covers it.
    }
    if (isSpeedDateRoom(id)) activateSpeedDateRef.current();
  }, [joined, id]);
  useEffect(() => {
    return () => {
      if (datingHeartbeatRef.current != null) {
        window.clearInterval(datingHeartbeatRef.current);
      }
    };
  }, []);

  // Recruiter-only: Ember quietly listens to the meeting transcript and
  // re-scores the prospect as the conversation grows — automatically, on a
  // tight cadence, with a visible "listening" state before the first read.
  // Nothing is shown to anyone else.
  useEffect(() => {
    const recruiterEnabled = !!profile?.is_recruiter;
    if (!joined || !recruiterEnabled || !id) return;
    let cancelled = false;
    const tick = async (): Promise<void> => {
      setEvalNow(Date.now());
      if (evalBusyRef.current) return;
      // Speed dates replace the recruiter auto-analysis with the
      // compatibility judge — never both in one room.
      if (speedDateRef.current) return;
      const segments = await fetchTranscript(id).catch(() => []);
      if (cancelled) return;
      // Confidence scoring reads ONLY the prospect's answers — drop this
      // recruiter's own lines. (The host is NOT excluded: in a 1:1 call the
      // recruiter is usually the host, and when they aren't, the host is
      // often the very prospect being scored.)
      const me = (profileRef.current?.username ?? "").toLowerCase();
      const text = segments
        .filter((s) => (s.username || "").toLowerCase() !== me)
        .map((s) => `${s.username || "speaker"}: ${s.text}`)
        .join("\n");
      // Jasper drafts the pitch deck ONCE the prospect side has said enough
      // (~700 chars) — one quiet AI call; the popup invites the recruiter to
      // flip through it. The final deck regenerates from the full
      // transcript when the meeting ends.
      if (!deckDraftRef.current && text.length >= 700) {
        deckDraftRef.current = true;
        const fullText = segments
          .map((s) => `${s.username || "speaker"}: ${s.text}`)
          .join("\n");
        void generatePitchDeck({
          meetingId: id,
          meetingTitle: meetingTitleRef.current,
          transcript: fullText,
          recruiterUsername: profileRef.current?.username ?? "",
          prospectHint: evalHintRef.current,
          draft: true,
        }).then((draftDeck) => {
          if (cancelled) return;
          if (!draftDeck) {
            deckDraftRef.current = false;
            return;
          }
          setPitchDeck(draftDeck);
          void savePitchDeck(draftDeck);
          setDeckToast(true);
        });
      }
      // Credit guard: the FIRST read lands early (60 new chars) so the
      // pill isn't blank, then re-scores only after a real chunk of new
      // prospect speech (300+ chars) instead of every few words.
      const newChars = text.length - lastEvalCharsRef.current;
      if (text.length < 40 || newChars < (lastEvalCharsRef.current === 0 ? 60 : 300)) return;
      evalBusyRef.current = true;
      setEvalPhase("evaluating");
      const result = await emberProspectEvaluation(text, evalHintRef.current).catch(
        () => null,
      );
      evalBusyRef.current = false;
      if (cancelled) return;
      if (!result) {
        setEvalPhase(lastEvalCharsRef.current > 0 ? "ready" : "listening");
        return;
      }
      lastEvalCharsRef.current = text.length;
      setLiveEval(result);
      setEvalPhase("ready");
      try {
        localStorage.setItem(`whisper_meeting_eval:${id}`, JSON.stringify(result));
      } catch {
        /* storage unavailable */
      }
    };
    void tick();
    // 30s cadence (was 10s) — same live feel, a third of the AI spend.
    const timer = window.setInterval(() => void tick(), 30000);
    return () => {
      cancelled = true;
      window.clearInterval(timer);
    };
  }, [joined, profile?.is_recruiter, id]);

  // The presented-card dock lags the live payload so its exit animation can
  // play before unmount (presenting → stop → slide out).
  useEffect(() => {
    if (presentation) {
      setDockPayload(presentation);
      setDockLeaving(false);
      return;
    }
    setDockLeaving(true);
    const timer = window.setTimeout(() => {
      setDockPayload(null);
      setDockLeaving(false);
    }, 320);
    return () => window.clearTimeout(timer);
  }, [presentation]);

  // Load the stored live evaluation for the ended screen (recruiter only).
  useEffect(() => {
    if (!id || !profile?.is_recruiter || !(hasEnded || notes != null)) return;
    try {
      const raw = localStorage.getItem(`whisper_meeting_eval:${id}`);
      if (raw) setFinalEval(JSON.parse(raw) as ProspectEvaluation);
    } catch {
      /* storage unavailable */
    }
  }, [id, profile?.is_recruiter, hasEnded, notes]);

  // Load the stored pitch deck for the ended screen (recruiter only) —
  // local cache first, then the database copy.
  useEffect(() => {
    if (!id || !user || !profile?.is_recruiter || !(hasEnded || notes != null)) return;
    if (pitchDeck) return;
    const cached = loadCachedDeck(id);
    if (cached) {
      setPitchDeck(cached);
      return;
    }
    void fetchPitchDeck(id, user.id).then((stored) => {
      if (stored) setPitchDeck(stored);
    });
  }, [id, user, profile?.is_recruiter, hasEnded, notes, pitchDeck]);

  // The deck-ready popup dismisses itself.
  useEffect(() => {
    if (!deckToast) return;
    const timer = window.setTimeout(() => setDeckToast(false), 18000);
    return () => window.clearTimeout(timer);
  }, [deckToast]);

  // Viewer-side presentation hygiene: clear the overlay when the presenter's
  // heartbeat stops (crash, refresh) or they leave the call entirely.
  useEffect(() => {
    if (!presentation || presentation.presenterUserId === user?.id) return;
    const timer = window.setInterval(() => {
      if (Date.now() - presentBeatRef.current > 13000) {
        setPresentation(null);
      }
    }, 3000);
    return () => window.clearInterval(timer);
  }, [presentation, user?.id]);

  useEffect(() => {
    if (!presentation || presentation.presenterUserId === user?.id) return;
    if (participants.length === 0) return;
    const presenterHere = participants.some(
      (p) => p.userId === presentation.presenterUserId,
    );
    if (!presenterHere) setPresentation(null);
  }, [participants, presentation, user?.id]);

  // Creator-card hygiene (viewer side): drop the live analytics card when the
  // presenter's heartbeat stops (crash, refresh) or they leave the call.
  useEffect(() => {
    if (!creatorCard || creatorCard.presenterUserId === user?.id) return;
    const timer = window.setInterval(() => {
      if (Date.now() - creatorBeatRef.current > 13000) setCreatorCard(null);
    }, 3000);
    return () => window.clearInterval(timer);
  }, [creatorCard, user?.id]);

  useEffect(() => {
    if (!creatorCard || creatorCard.presenterUserId === user?.id) return;
    if (participants.length === 0) return;
    const presenterHere = participants.some(
      (p) => p.userId === creatorCard.presenterUserId,
    );
    if (!presenterHere) setCreatorCard(null);
  }, [participants, creatorCard, user?.id]);

  // Business-card hygiene (viewer side): the company card drops when its
  // presenter leaves the call.
  useEffect(() => {
    if (!bizCard || bizCard.presenterUserId === user?.id) return;
    if (participants.length === 0) return;
    const presenterHere = participants.some(
      (p) => p.userId === bizCard.presenterUserId,
    );
    if (!presenterHere) setBizCard(null);
  }, [participants, bizCard, user?.id]);

  // Business+ — load my plan once so the Present-company chip can appear.
  useEffect(() => {
    if (!user?.id) {
      setMyBizPlus(null);
      return;
    }
    let cancelled = false;
    fetchMyBusinessPlus(user.id)
      .then((res) => {
        if (!cancelled) setMyBizPlus(res);
      })
      .catch(() => undefined);
    return () => {
      cancelled = true;
    };
  }, [user?.id]);

  // Walkthrough hygiene (viewer side): drop the overlay when the driver's
  // heartbeat stops (crash, refresh) or they leave the call entirely.
  useEffect(() => {
    if (!deckTour || tourPosRef.current) return;
    const timer = window.setInterval(() => {
      if (Date.now() - tourBeatRef.current > 15000) setDeckTour(null);
    }, 4000);
    return () => window.clearInterval(timer);
  }, [deckTour]);

  useEffect(() => {
    if (!deckTour || tourPosRef.current) return;
    if (participants.length === 0) return;
    const driverHere = participants.some((p) => p.peerId === deckTour.driverPeerId);
    if (!driverHere) setDeckTour(null);
  }, [participants, deckTour]);

  // Device-voiced walkthroughs (iOS drivers can't mix Ember into their call
  // audio) — this machine plays the same fixed narration line locally, in
  // sync with the broadcast position. Web-driven tours never enter here.
  useEffect(() => {
    const audioEl = ((): HTMLAudioElement => {
      if (!tourAudioRef.current) {
        const el = new Audio();
        el.preload = "auto";
        tourAudioRef.current = el;
      }
      return tourAudioRef.current;
    })();
    const isDeviceTour =
      deckTour != null && !tourPosRef.current && deckTour.voice === "device";
    if (!isDeviceTour || !deckTour.playing) {
      if (tourAudioKeyRef.current) {
        tourAudioKeyRef.current = "";
        audioEl.pause();
      }
      return;
    }
    const key = `${deckTour.slide}:${deckTour.segment}`;
    if (tourAudioKeyRef.current === key) return;
    tourAudioKeyRef.current = key;
    audioEl.src = `${BACKEND_URL}/meetings/tour-audio?slide=${deckTour.slide}&segment=${deckTour.segment}`;
    void audioEl.play().catch((err: unknown) => {
      const name = err instanceof DOMException ? err.name : "";
      if (name !== "NotAllowedError") return;
      // Autoplay blocked — raise the room-wide unlock pill and retry on the
      // next tap, matching the call-audio rescue behavior.
      window.dispatchEvent(new CustomEvent("whisper-audio-blocked"));
      const retry = (): void => {
        void audioEl.play().catch(() => undefined);
      };
      window.addEventListener("pointerdown", retry, { once: true, capture: true });
    });
  }, [deckTour]);

  // Silence the local narration line the moment the room unmounts.
  useEffect(
    () => () => {
      tourAudioRef.current?.pause();
      tourAudioRef.current = null;
    },
    [],
  );

  /** Opens Ember's live voice — a real speech-to-speech OpenAI Realtime
   *  session in the `echo` voice. The meeting caption recognizer pauses so
   *  the two never fight over the mic, semantic VAD handles turn-taking and
   *  barge-in, and display tool calls stream visual cards into the panel
   *  while Ember talks. Typed questions keep working even if voice fails. */
  const startEmberVoice = useCallback((): void => {
    if (emberSessionRef.current) return;
    const epoch = ++emberVoiceEpochRef.current;
    const isStale = (): boolean => emberVoiceEpochRef.current !== epoch;
    setEmberVoice("connecting");
    setEmberVoiceHint(null);
    setEmberMicMuted(false);
    pauseTranscriptionForEmber();
    void rtcRef.current?.setMicEnabled(false);
    setMicOn(false);
    setEmberVoiceHint('Your meeting mic is muted for this private conversation. Unmute when you return to the call.');
    const session = new EmberRealtimeSession({
      instructions: emberMeetingVoiceInstructions({
        meetingTitle: meeting?.title ?? "Meeting",
        participants: participants.map((p) => p.name),
      }),
      tools: emberDisplayTools({ includePitchLauncher: true, includeMeetingTools: true }),
      callbacks: {
        onState: (state) => {
          if (isStale()) return;
          if (state === "closed" || state === "error") {
            emberSessionRef.current = null;
            setEmberVoice("off");
            setEmberSpeaking(false);
            setEmberHearing(false);
            resumeTranscriptionAfterEmber();
          }
        },
        onUserSpeech: (active) => {
          if (!isStale()) setEmberHearing(active);
        },
        onUserTranscript: (text, final) => {
          if (isStale()) return;
          setEmberUserInterim(text);
          if (final) {
            lastEmberQuestionRef.current = text;
            // Private voice questions stay in Jasper's conversation, never shared speech.
          }
        },
        onThinking: (thinking) => {
          if (isStale() || !thinking) return;
          setEmberBusy(true);
          setEmberError(false);
        },
        onAssistantDelta: (full) => {
          if (isStale()) return;
          setEmberBusy(false);
          setEmberUserInterim("");
          setEmberReply(full);
        },
        onAssistantDone: (full) => {
          if (isStale()) return;
          setEmberBusy(false);
          setEmberReply(full);
        },
        onSpeaking: (speaking) => {
          if (!isStale()) setEmberSpeaking(speaking);
        },
        onToolCall: (name, args) => {
          if (isStale()) return "stale";
          if (name === "open_full_pitch_deck") {
            setEmberPitchOffer(true);
            return "pitch deck launcher offered";
          }
          if (name === "open_wpp_calculator") {
            setWppOpen(true);
            return "the real WPP slider calculator is now open on screen";
          }
          if (name === "open_brand_cards") {
            setBrandCardsOpen(true);
            return "the real brand marketplace cards are now open on screen";
          }
          if (name === "start_deck_walkthrough") {
            window.setTimeout(() => startDeckTourRef.current?.(), 600);
            return "walkthrough starting — the presenter voice takes over from here";
          }
          const block = emberBlockFromTool(name, args);
          if (!block) return "unknown tool";
          setEmberBlocks((prev) => [block, ...prev].slice(0, 3));
          return "card displayed";
        },
        onError: () => undefined,
      },
    });
    emberSessionRef.current = session;
    void session
      .connect()
      .then(() => {
        if (isStale()) return;
        setEmberVoice("live");
        if (!session.micAvailable) {
          setEmberVoiceHint(
            "Mic is busy — type below and Jasper still answers out loud.",
          );
        }
      })
      .catch(() => {
        if (isStale()) return;
        emberSessionRef.current = null;
        setEmberVoice("off");
        resumeTranscriptionAfterEmber();
        setEmberVoiceHint("Live voice couldn't start — type your question below.");
      });
  }, [enqueueTranscript, meeting?.title, participants, pauseTranscriptionForEmber, resumeTranscriptionAfterEmber]);

  /** Send whatever's typed in the Ember panel input — rides the live voice
   *  session when it's up (spoken answer), otherwise the text path. */
  const submitEmberDraft = useCallback((): void => {
    const question = emberDraft.trim();
    if (!question || emberBusy) return;
    setEmberDraft("");
    void askEmber(question);
  }, [askEmber, emberBusy, emberDraft]);

  /** Broadcast the current Ember answer to everyone in the call. */
  const shareEmberAnswer = useCallback((): void => {
    if (!emberReply && emberBlocks.length === 0) return;
    rtcRef.current?.sendAppEvent("ember-share", {
      name: profile?.username ?? "someone",
      text: emberReply ?? "",
      block: emberBlocks[0] ?? null,
    });
    toast.success("Shared with everyone in the meeting");
  }, [emberBlocks, emberReply, profile?.username]);

  // ─── Ember deck walkthrough (driver engine) ────────────────────────────
  // The driver runs a speak-only Ember voice session, mixes its audio into
  // their outgoing call track (everyone hears it), and broadcasts the exact
  // slide + line being read so every screen highlights in sync.

  /** Broadcast the walkthrough state (or its end) to the whole room. */
  const broadcastTourState = useCallback(
    (open: boolean): void => {
      const rtc = rtcRef.current;
      if (!rtc) return;
      const pos = tourPosRef.current;
      const payload: DeckTourEventPayload = {
        open: open && pos != null,
        slide: pos?.slide ?? 0,
        segment: pos?.segment ?? 0,
        playing: pos?.playing ?? false,
        driverName: selfName,
        rev: Date.now(),
        voice: "driver",
      };
      rtc.sendAppEvent("deck-tour", payload);
    },
    [selfName],
  );

  const clearTourTimers = useCallback((): void => {
    if (tourAdvanceTimerRef.current != null) {
      window.clearTimeout(tourAdvanceTimerRef.current);
      tourAdvanceTimerRef.current = null;
    }
    if (tourWatchdogRef.current != null) {
      window.clearTimeout(tourWatchdogRef.current);
      tourWatchdogRef.current = null;
    }
  }, []);

  /** Push the driver's position into local state + broadcast it. */
  const syncTourView = useCallback((): void => {
    const pos = tourPosRef.current;
    if (!pos) return;
    setDeckTour({
      slide: pos.slide,
      segment: pos.segment,
      playing: pos.playing,
      driverPeerId: rtcRef.current?.localPeerId ?? "self",
      driverName: selfName,
      voice: "driver",
    });
    broadcastTourState(true);
  }, [broadcastTourState, selfName]);

  /** Tear down the walkthrough (driver side). Safe to call repeatedly. */
  const stopDeckTour = useCallback(
    (options?: { silent?: boolean }): void => {
      tourEpochRef.current += 1;
      clearTourTimers();
      if (tourHeartbeatRef.current != null) {
        window.clearInterval(tourHeartbeatRef.current);
        tourHeartbeatRef.current = null;
      }
      const wasDriving = tourPosRef.current != null;
      if (wasDriving) {
        tourPosRef.current = null;
        broadcastTourState(false);
      }
      const session = tourSessionRef.current;
      tourSessionRef.current = null;
      session?.close();
      void rtcRef.current?.stopAuxAudioMix();
      setTourVoice("off");
      setDeckTour(null);
      if (wasDriving && !options?.silent) toast("Walkthrough ended");
    },
    [broadcastTourState, clearTourTimers],
  );

  /** Advance to the next line once the current one is fully spoken. */
  const tourMaybeAdvance = useCallback((): void => {
    const pos = tourPosRef.current;
    const flags = tourFlagsRef.current;
    if (!pos || !pos.playing || !flags.done || !flags.quiet) return;
    if (tourAdvanceTimerRef.current != null) return;
    tourAdvanceTimerRef.current = window.setTimeout(() => {
      tourAdvanceTimerRef.current = null;
      const current = tourPosRef.current;
      if (!current || !current.playing) return;
      const next = nextTourPosition(current.slide, current.segment);
      if (next) {
        speakTourSegmentRef.current?.(next.slide, next.segment);
      } else {
        tourPosRef.current = { ...current, playing: false };
        syncTourView();
      }
    }, 850);
  }, [syncTourView]);

  /** Point Ember's voice at one deck line and highlight it everywhere. */
  const speakTourSegment = useCallback(
    (slide: number, segment: number): void => {
      const pos = clampTourPosition(slide, segment);
      clearTourTimers();
      tourFlagsRef.current = { done: false, quiet: false };
      const current = tourPosRef.current;
      tourPosRef.current = {
        slide: pos.slide,
        segment: pos.segment,
        playing: current?.playing ?? true,
      };
      syncTourView();
      const session = tourSessionRef.current;
      if (!session || !session.isLive) return;
      session.sendText(emberTourReadPrompt(pos.slide, pos.segment));
      // Watchdog — one stuck line must never stall the whole walkthrough.
      tourWatchdogRef.current = window.setTimeout(() => {
        tourFlagsRef.current = { done: true, quiet: true };
        tourMaybeAdvanceRef.current?.();
      }, 45000);
    },
    [clearTourTimers, syncTourView],
  );

  /** Start the narrated walkthrough — Ember reads the deck to the room. */
  const startDeckTour = useCallback((): void => {
    if (!user) {
      toast("Sign in to run Jasper's walkthrough");
      return;
    }
    const rtc = rtcRef.current;
    if (!rtc || !joined) {
      toast("Join the meeting first");
      return;
    }
    if (tourSessionRef.current) return;
    if (deckTour && deckTour.driverPeerId !== rtc.localPeerId) {
      toast(`@${deckTour.driverName} is already presenting`);
      return;
    }
    // One Ember voice at a time — the private Q&A line yields to the deck.
    stopEmberVoice();
    setEmberPanelOpen(false);
    setTourHidden(false);
    setTourVoice("connecting");
    const epoch = ++tourEpochRef.current;
    const isStale = (): boolean => tourEpochRef.current !== epoch;
    tourPosRef.current = { slide: 0, segment: 0, playing: true };
    syncTourView(); // deck appears room-wide while the voice warms up
    const session = new EmberRealtimeSession({
      instructions: emberTourPresenterInstructions(meeting?.title ?? "Meeting"),
      mic: false,
      callbacks: {
        onState: (state) => {
          if (isStale()) return;
          if (state === "closed" || state === "error") {
            if (tourSessionRef.current) {
              tourSessionRef.current = null;
              stopDeckTourRef.current?.({ silent: true });
              if (state === "error") toast.error("Jasper's walkthrough voice dropped");
            }
          }
        },
        onAssistantDone: () => {
          if (isStale()) return;
          tourFlagsRef.current.done = true;
          tourMaybeAdvanceRef.current?.();
        },
        onSpeaking: (speaking) => {
          if (isStale()) return;
          tourFlagsRef.current.quiet = !speaking;
          if (!speaking) tourMaybeAdvanceRef.current?.();
        },
        onError: () => undefined,
      },
    });
    tourSessionRef.current = session;
    void session
      .connect()
      .then(async () => {
        if (isStale()) {
          session.close();
          return;
        }
        setTourVoice("live");
        const voice = session.remoteAudioStream;
        const shared = voice ? await rtc.startAuxAudioMix(voice) : false;
        if (!shared) {
          toast("Couldn't share Jasper's audio — others may not hear the narration");
        }
        if (tourHeartbeatRef.current == null) {
          tourHeartbeatRef.current = window.setInterval(() => {
            if (tourPosRef.current) broadcastTourState(true);
          }, 4000);
        }
        speakTourSegmentRef.current?.(0, 0);
      })
      .catch(() => {
        if (isStale()) return;
        tourSessionRef.current = null;
        stopDeckTourRef.current?.({ silent: true });
        toast.error("Jasper's walkthrough couldn't start — try again in a moment.");
      });
  }, [broadcastTourState, deckTour, joined, meeting?.title, stopEmberVoice, syncTourView, user]);

  /** Driver: jump slides (cancels the current line, reads the new slide). */
  const tourGoToSlide = useCallback((slideIndex: number): void => {
    if (!tourSessionRef.current || !tourPosRef.current) return;
    if (slideIndex < 0 || slideIndex >= EMBER_TOUR_SLIDES.length) return;
    tourSessionRef.current.cancelSpeech();
    speakTourSegmentRef.current?.(slideIndex, 0);
  }, []);

  /** Driver: pause/resume — resume re-reads the current line for context. */
  const tourTogglePlay = useCallback((): void => {
    const pos = tourPosRef.current;
    if (!pos) return;
    if (pos.playing) {
      tourPosRef.current = { ...pos, playing: false };
      tourSessionRef.current?.cancelSpeech();
      tourFlagsRef.current = { done: true, quiet: true };
      clearTourTimers();
      syncTourView();
    } else {
      tourPosRef.current = { ...pos, playing: true };
      syncTourView();
      speakTourSegmentRef.current?.(pos.slide, pos.segment);
    }
  }, [clearTourTimers, syncTourView]);

  useEffect(() => {
    speakTourSegmentRef.current = speakTourSegment;
  }, [speakTourSegment]);
  useEffect(() => {
    tourMaybeAdvanceRef.current = tourMaybeAdvance;
  }, [tourMaybeAdvance]);
  useEffect(() => {
    startDeckTourRef.current = startDeckTour;
  }, [startDeckTour]);
  useEffect(() => {
    stopDeckTourRef.current = stopDeckTour;
  }, [stopDeckTour]);

  /** Share a prospect's info into the meeting chat via the WebRTC signaling channel. */
  const shareProspect = useCallback((p: Prospect) => {
    const summary = `Prospect: ${p.prospect_display_name ?? p.prospect_username ?? "Unknown"} @${p.prospect_username ?? "unknown"} — Status: ${p.status}, Niche: ${p.niche ?? "N/A"}${p.location ? ", Location: " + p.location : ""}`;
    rtcRef.current?.sendReaction("\u{1F4CA}");
    toast.success(`Shared prospect: ${p.prospect_display_name ?? p.prospect_username ?? "Unknown"}`);
    // Also copy to clipboard for easy pasting.
    void navigator.clipboard.writeText(summary);
  }, []);

  /** Share a client's info into the meeting chat. */
  const shareClient = useCallback((c: CoachRequest) => {
    const summary = `Client: @${c.client_username} — Active coaching relationship.${c.message ? " Note: " + c.message : ""}`;
    rtcRef.current?.sendReaction("\u{1F4AA}");
    toast.success(`Shared client: @${c.client_username}`);
    void navigator.clipboard.writeText(summary);
  }, []);

  const stopPresentHeartbeat = useCallback((): void => {
    if (presentHeartbeatRef.current != null) {
      window.clearInterval(presentHeartbeatRef.current);
    }
    presentHeartbeatRef.current = null;
    presentationPayloadRef.current = null;
  }, []);

  /**
   * Put a profile card on everyone's screen. The payload is broadcast
   * immediately, re-broadcast every few seconds for late joiners, and
   * answered on demand via `present-sync-request` — three delivery paths so
   * the card reliably appears for the whole room. Switching people simply
   * replaces the payload.
   */
  const broadcastPresentation = useCallback(
    (payload: PresentedClientPayload, options?: { silent?: boolean }): void => {
      const stamped: PresentedClientPayload = { ...payload, rev: Date.now() };
      presentationPayloadRef.current = stamped;
      presentationKeyRef.current = `${stamped.presenterUserId}:${stamped.id}`;
      setPresentation(stamped);
      if (!options?.silent) setPresentationExpanded(false);
      rtcRef.current?.sendAppEvent("present-client", stamped);
      if (presentHeartbeatRef.current == null) {
        presentHeartbeatRef.current = window.setInterval(() => {
          const current = presentationPayloadRef.current;
          if (current) rtcRef.current?.sendAppEvent("present-client", current);
        }, 4000);
      }
      if (!options?.silent) {
        toast.success(
          `Presenting ${payload.displayName ?? payload.username ?? "client"} to everyone`,
        );
      }
    },
    [],
  );

  const presentProspect = useCallback(
    (p: Prospect): void => {
      if (!user || !rtcRef.current) return;
      const match = matchApplicationResponse(p, applicantResponsesQuery.data ?? []);
      const base = payloadFromProspect(
        p,
        user.id,
        profile?.username ?? "presenter",
        match ? applicationFromResponse(match) : null,
        [],
        answersFromResponse(match),
      );
      // The card appears instantly; the Instagram gallery hot-swaps in as a
      // silent re-broadcast the moment it resolves.
      broadcastPresentation(base);
      void fetchInstagramGallery(p.instagram).then((gallery) => {
        if (!gallery || (gallery.photos.length === 0 && !gallery.profilePic)) return;
        const current = presentationPayloadRef.current;
        if (!current || current.id !== base.id || current.presenterUserId !== user.id) return;
        broadcastPresentation(
          {
            ...current,
            photos: gallery.photos,
            imageUrl: current.imageUrl ?? gallery.profilePic,
          },
          { silent: true },
        );
      });
      setSelectedProspect(null);
      setShowRecruiterTools(false);
    },
    [applicantResponsesQuery.data, broadcastPresentation, profile?.username, user],
  );

  /** Coaches spotlight one of their active clients the same way — the card
   *  shows instantly, then silently enriches with the client's live fitness
   *  snapshot (macros, activity, workouts) and progress photos. */
  const presentCoachClient = useCallback(
    (c: CoachRequest): void => {
      if (!user || !rtcRef.current) return;
      const base = payloadFromCoachClient(c, user.id, profile?.username ?? "presenter");
      broadcastPresentation(base);
      setShowCoachTools(false);
      void (async () => {
        const [snapRow, profRow] = await Promise.all([
          fetchClientSnapshot(c.client_user_id).catch(() => null),
          supabase
            .from("whisper_profiles")
            .select("display_name, profile_image_url")
            .eq("user_id", c.client_user_id)
            .maybeSingle()
            .then(
              (r) =>
                r.data as {
                  display_name?: string | null;
                  profile_image_url?: string | null;
                } | null,
              () => null,
            ),
        ]);
        const current = presentationPayloadRef.current;
        if (!current || current.id !== base.id || current.presenterUserId !== user.id) return;
        const photos = [
          snapRow?.photoFrontUrl,
          snapRow?.photoSideUrl,
          snapRow?.photoBackUrl,
        ].filter((u): u is string => !!u);
        broadcastPresentation(
          {
            ...current,
            displayName: profRow?.display_name ?? current.displayName,
            imageUrl: profRow?.profile_image_url ?? current.imageUrl,
            snapshot: snapRow?.snapshot ? compactSnapshot(snapRow.snapshot) : null,
            photos,
          },
          { silent: true },
        );
      })();
    },
    [broadcastPresentation, profile?.username, user],
  );

  /** Presenter takes the profile off everyone's screen. */
  const stopPresenting = useCallback((): void => {
    stopPresentHeartbeat();
    rtcRef.current?.sendAppEvent("present-client-end", {
      presenterUserId: user?.id ?? "",
    });
    setPresentation(null);
    setPresentationExpanded(false);
  }, [stopPresentHeartbeat, user?.id]);

  /** Stop the creator-card heartbeat rebroadcast loop. */
  const stopCreatorHeartbeat = useCallback((): void => {
    if (creatorHeartbeatRef.current != null) {
      window.clearInterval(creatorHeartbeatRef.current);
      creatorHeartbeatRef.current = null;
    }
  }, []);

  /** Broadcast my live analytics card — instant send + 4s heartbeat so late
   *  joiners always catch it (same discipline as present-client, and the
   *  same wire format iOS speaks). */
  const broadcastCreatorCard = useCallback(
    (payload: CreatorAnalyticsCardPayload): void => {
      const stamped: CreatorAnalyticsCardPayload = { ...payload, rev: Date.now() };
      creatorCardRef.current = stamped;
      creatorKeyRef.current = `${stamped.presenterUserId}:${stamped.id}`;
      setCreatorCard(stamped);
      rtcRef.current?.sendAppEvent("creator-analytics", stamped);
      if (creatorHeartbeatRef.current == null) {
        creatorHeartbeatRef.current = window.setInterval(() => {
          const current = creatorCardRef.current;
          if (current) rtcRef.current?.sendAppEvent("creator-analytics", current);
        }, 4000);
      }
    },
    [],
  );

  /** Build my live Creator Studio card and put it on everyone's screen. */
  const shareMyAnalytics = useCallback(async (): Promise<void> => {
    const uname = profile?.username;
    if (!user || !uname || !rtcRef.current || creatorBuilding) return;
    setCreatorBuilding(true);
    try {
      const prof = await supabase
        .from("whisper_profiles")
        .select("profile_image_url")
        .eq("user_id", user.id)
        .maybeSingle()
        .then(
          (r) => r.data as { profile_image_url?: string | null } | null,
          () => null,
        );
      const card = await buildCreatorAnalyticsCard({
        userId: user.id,
        username: uname,
        imageUrl: prof?.profile_image_url ?? null,
        badge: myBadge,
        presenterName: uname,
      });
      if (!card) {
        toast.info("Post something first — your analytics card needs at least one post.");
        return;
      }
      broadcastCreatorCard(card);
      setShowCreatorTools(false);
      toast.success("Sharing your live analytics with everyone");
    } catch {
      toast.error("Couldn't load your analytics right now.");
    } finally {
      setCreatorBuilding(false);
    }
  }, [user, profile?.username, creatorBuilding, myBadge, broadcastCreatorCard]);

  /** Presenter takes their analytics card off everyone's screen. */
  const stopCreatorCard = useCallback((): void => {
    stopCreatorHeartbeat();
    creatorCardRef.current = null;
    rtcRef.current?.sendAppEvent("creator-analytics-end", {
      presenterUserId: user?.id ?? "",
    });
    setCreatorCard(null);
    setCreatorExpanded(false);
  }, [stopCreatorHeartbeat, user?.id]);

  /** Business+ — put a live company card on everyone's screen. Three modes:
   *  the company card, the open roles (with apply link), or the team intro. */
  const presentBusinessCard = useCallback(
    async (mode: "company" | "roles" | "team"): Promise<void> => {
      const biz = myBizPlus?.business;
      if (!biz || !user || !rtcRef.current || bizBuildingRef.current) return;
      bizBuildingRef.current = true;
      setBizMenuOpen(false);
      try {
        const [positions, brand, team] = await Promise.all([
          fetchPositions(biz.user_id).catch(() => []),
          fetchBrand(biz.user_id).catch(() => null),
          fetchTeam(biz.user_id).catch(() => []),
        ]);
        const open = positions.filter((p) => p.is_open);
        const payload: BusinessCardWire = {
          presenterUserId: user.id,
          presenterName: profile?.username ?? "presenter",
          businessId: biz.user_id,
          mode,
          company:
            biz.company_name?.trim() || `@${profile?.username ?? "our"}'s company`,
          about: brand?.about ?? null,
          industry: brand?.industry ?? null,
          logoUrl: brand?.logo_url ?? null,
          positions: open.slice(0, 3).map((p) => p.title),
          roles: open.slice(0, 4).map((p) => ({
            title: p.title,
            blurb: (p.blurb ?? "").slice(0, 90),
          })),
          team: team.slice(0, 6).map((m) => ({
            username: m.username,
            roleTitle: m.role_title,
            accent: m.accent,
          })),
          applyUrl: businessApplyUrl(biz.user_id, biz.company_name),
          rev: Date.now(),
        };
        bizCardRef.current = payload;
        setBizCard(payload);
        setBizInterested([]);
        rtcRef.current?.sendAppEvent("business-card", payload);
        toast.success(
          mode === "roles"
            ? "Presenting your open roles"
            : mode === "team"
              ? "Introducing the team"
              : "Presenting your company to everyone",
        );
      } catch {
        toast.error("Couldn't build the company card right now.");
      } finally {
        bizBuildingRef.current = false;
      }
    },
    [myBizPlus, user, profile?.username],
  );

  /** Presenter takes the company card down. */
  const stopBusinessCard = useCallback((): void => {
    bizCardRef.current = null;
    rtcRef.current?.sendAppEvent("business-card-end", {
      presenterUserId: user?.id ?? "",
    });
    setBizCard(null);
    setBizInterested([]);
  }, [user?.id]);

  /** Viewer — raise a hand on the presented card: pings the presenter live
   *  and files me as a lead in their Business+ applicant pipeline. */
  const raiseBusinessHand = useCallback((): void => {
    const card = bizCard;
    if (!card || !user || bizHandRaised) return;
    const username = profile?.username ?? "someone";
    rtcRef.current?.sendAppEvent("business-interest", {
      presenterUserId: card.presenterUserId,
      username,
    });
    setBizHandRaised(true);
    if (card.businessId && !bizLeadSentRef.current.has(card.businessId)) {
      bizLeadSentRef.current.add(card.businessId);
      void recordMeetingInterest({
        businessId: card.businessId,
        person: { id: user.id, username },
        company: card.company,
      }).catch(() => undefined);
    }
    toast.success(`👋 Sent — @${card.presenterName} sees your hand`);
  }, [bizCard, user, profile?.username, bizHandRaised]);

  /**
   * Join the call. Devices are requested and verified FIRST, inside the Join
   * click gesture, so the browser prompt isn't racing signaling setup. A
   * partial grant (mic-only / camera-only) still joins; a total block keeps
   * you in the lobby with truthful options instead of dead controls.
   */
  const join = useCallback(async (mode: "full" | "listen" = "full"): Promise<void> => {
    // The Join click is the user gesture that unlocks audio — warm the sound
    // kit here so the landing chime is never swallowed by autoplay policy.
    primeMeetSounds();
    const audioContext = getLevelerContext();
    if (audioContext?.state === "suspended") void audioContext.resume().catch(() => undefined);
    if (!id || rtcRef.current || joinBusy) return;
    setJoinBusy(true);
    const peerId = crypto.randomUUID();
    const name = selfName;
    const rtc = new WhisperLiveRTC(peerId, selfId, name);
    rtcRef.current = rtc;
    rtc.onParticipantUpdate = (list) => {
      if (rtcRef.current !== rtc) return;
      participantsRef.current = list;
      recordingSessionRef.current.reconcile(list);
      setParticipants(list);
    };
    // The browser's own "Stop sharing" bar ends a share without touching our
    // button — keep the bar + presenting card honest.
    rtc.onScreenShareChange = (isSharing) => {
      if (rtcRef.current !== rtc) return;
      setSharing(isSharing);
      setCamOn(rtc.localVideoTrack?.enabled ?? false);
    };
    rtc.onError = (error) => {
      if (rtcRef.current !== rtc) return;
      console.warn("[Meeting] RTC error:", error);
      toast.error(error);
    };
    // Present-to-everyone events ride the shared signaling channel.
    rtc.onAppEvent = (event, data, fromPeerId) => {
      if (rtcRef.current !== rtc) return;
      if (recordingSessionRef.current.receive(event, data, fromPeerId)) return;
      // Cooperative signaling: a roster check is not server-authenticated moderation.
      if (["meeting-kick", "call-end", "call-host", "call-policy", "call-mute", "call-mute-all"].includes(event)) {
        const sender = participantsRef.current.find((p) => p.peerId === fromPeerId);
        if (!sender?.userId || sender.userId.toLowerCase() !== currentHostIdRef.current?.toLowerCase()) return;
      }
      // ── Meeting lifecycle (Meet's rules, shared wire) ──
      if (event === "call-end") {
        void recordingSessionRef.current.stop(true);
        // The host ended the call for everyone — the ding, the teardown, and
        // the post-call screen all hang off this one state change.
        const info = data as { byName?: string } | null;
        endedByRef.current =
          typeof info?.byName === "string" && info.byName ? info.byName : "The host";
        setPostCall("host-ended");
        return;
      }
      if (event === "call-host") {
        // The host left without ending — the room was handed to someone.
        const info = data as { userId?: string; name?: string; byName?: string } | null;
        const uid = typeof info?.userId === "string" ? info.userId : "";
        if (!uid) return;
        setActingHostId(uid);
        if (uid === selfId) {
          toast("You're the host now — the previous host left the call");
        } else if (typeof info?.name === "string" && info.name) {
          toast(`${info.name} is the host now`);
        }
        return;
      }
      // ── iOS group-call wire (WhisperCallService): reactions · hands · mute ──
      if (event === "call-react") {
        const info = data as { emoji?: string; byName?: string } | null;
        pushFloatingReaction(
          typeof info?.emoji === "string" && info.emoji ? info.emoji : "💖",
          typeof info?.byName === "string" && info.byName ? info.byName : "someone",
        );
        return;
      }
      if (event === "call-hand") {
        const info = data as { up?: boolean; userId?: string; byName?: string } | null;
        const uid = typeof info?.userId === "string" ? info.userId.toLowerCase() : "";
        if (!uid) return;
        const name = typeof info?.byName === "string" && info.byName ? info.byName : "Someone";
        setRaisedHands((current) => {
          const next = { ...current };
          if (info?.up) next[uid] = name;
          else delete next[uid];
          return next;
        });
        if (info?.up) toast(`✋ ${name} raised a hand`);
        return;
      }
      if (event === "call-mute-all") {
        const info = data as { byName?: string } | null;
        toast(`${typeof info?.byName === "string" && info.byName ? info.byName : "The host"} muted everyone`);
        setMuteRequest((n) => n + 1);
        return;
      }
      if (event === "call-mute") {
        const info = data as { targetUserId?: string } | null;
        const target = typeof info?.targetUserId === "string" ? info.targetUserId.toLowerCase() : "";
        if (target && user && target === user.id.toLowerCase()) {
          toast("The host muted your microphone");
          setMuteRequest((n) => n + 1);
        }
        return;
      }
      if (event === "call-chat") {
        const info = data as { id?: string; text?: string; byName?: string; at?: number } | null;
        const text = typeof info?.text === "string" ? info.text.trim() : "";
        if (!text) return;
        const msgId = typeof info?.id === "string" && info.id ? info.id : `${Date.now()}-${fromPeerId}`;
        const name = typeof info?.byName === "string" && info.byName ? info.byName : "someone";
        const at = typeof info?.at === "number" ? info.at : Date.now();
        setRoomChat((current) =>
          current.some((m) => m.id === msgId)
            ? current
            : [...current.slice(-199), { id: msgId, name, text, at, self: false }],
        );
        setChatUnread((n) => n + 1);
        return;
      }
      if (event === "call-policy") {
        const info = data as { chat?: boolean; reactions?: boolean; present?: boolean; quickAccess?: boolean } | null;
        if (info && typeof info === "object") {
          const current = roomPolicyRef.current;
          const next = {
            chat: typeof info.chat === "boolean" ? info.chat : current.chat,
            reactions: typeof info.reactions === "boolean" ? info.reactions : current.reactions,
            present: typeof info.present === "boolean" ? info.present : current.present,
            quickAccess: typeof info.quickAccess === "boolean" ? info.quickAccess : current.quickAccess,
          };
          roomPolicyRef.current = next;
          setRoomPolicy(next);
          if (!next.present && currentHostIdRef.current?.toLowerCase() !== selfId.toLowerCase()) void rtc.stopScreenShare();
        }
        return;
      }
      // ── Knocking (Meet's "wants to join this call") — the doorkeeper answers ──
      if (event === "meeting-knock") {
        if (!isDoorkeeperRef.current) return;
        const info = data as {
          knockId?: string;
          name?: string;
          userId?: string | null;
          avatarUrl?: string | null;
          isGuest?: boolean;
          at?: number;
        } | null;
        const knockId = typeof info?.knockId === "string" ? info.knockId : "";
        if (!knockId) return;
        const knock: MeetKnock = {
          knockId,
          name: (typeof info?.name === "string" && info.name.trim()) || "Someone",
          avatarUrl: typeof info?.avatarUrl === "string" ? info.avatarUrl : null,
          isGuest: info?.isGuest !== false,
          at: typeof info?.at === "number" ? info.at : Date.now(),
        };
        // "Asking to join…" on their side the moment a host is reached.
        rtcRef.current?.sendAppEvent("meeting-knock-ack", { knockId, byName: selfNameRef.current });
        // Quick access: signed-in members walk straight in. Guests always wait.
        if (roomPolicyRef.current.quickAccess && !knock.isGuest) {
          rtcRef.current?.sendAppEvent("meeting-admit", { knockId, byName: selfNameRef.current });
          return;
        }
        setPendingKnocks((current) => {
          const fresh = current.filter((k) => k.knockId !== knockId && Date.now() - k.at < 200_000);
          if (fresh.length === current.length && current.some((k) => k.knockId === knockId)) return current;
          return [...fresh, knock];
        });
        playMeetTick();
        return;
      }
      if (event === "meeting-knock-cancel" || event === "meeting-admit" || event === "meeting-deny") {
        // The knocker left, or another host already answered — drop the row.
        const info = data as { knockId?: string } | null;
        const knockId = typeof info?.knockId === "string" ? info.knockId : "";
        if (knockId) setPendingKnocks((current) => current.filter((k) => k.knockId !== knockId));
        return;
      }
      if (event === "present-client") {
        const payload = data as PresentedClientPayload | null;
        if (!payload || typeof payload !== "object" || !payload.presenterUserId || !payload.id) {
          return;
        }
        presentBeatRef.current = Date.now();
        const key = `${payload.presenterUserId}:${payload.id}`;
        if (presentationKeyRef.current !== key) {
          presentationKeyRef.current = key;
          setPresentationExpanded(false);
        }
        setPresentation((current) =>
          current &&
          current.id === payload.id &&
          current.presenterUserId === payload.presenterUserId &&
          current.rev === payload.rev
            ? current
            : payload,
        );
      } else if (event === "present-client-end") {
        const info = data as { presenterUserId?: string } | null;
        setPresentation((current) =>
          current && (!info?.presenterUserId || current.presenterUserId === info.presenterUserId)
            ? null
            : current,
        );
      } else if (event === "creator-analytics") {
        // A creator (web or iOS — same camelCase wire) is sharing their live
        // analytics card with the room.
        const payload = data as CreatorAnalyticsCardPayload | null;
        if (!payload || typeof payload !== "object" || !payload.presenterUserId || !payload.id) {
          return;
        }
        creatorBeatRef.current = Date.now();
        const key = `${payload.presenterUserId}:${payload.id}`;
        if (creatorKeyRef.current !== key) {
          creatorKeyRef.current = key;
          setCreatorExpanded(false);
        }
        setCreatorCard((current) =>
          current &&
          current.id === payload.id &&
          current.presenterUserId === payload.presenterUserId &&
          current.rev === payload.rev
            ? current
            : payload,
        );
      } else if (event === "creator-analytics-end") {
        const info = data as { presenterUserId?: string } | null;
        setCreatorCard((current) =>
          current && (!info?.presenterUserId || current.presenterUserId === info.presenterUserId)
            ? null
            : current,
        );
      } else if (event === "business-card") {
        // A Business+ member is presenting their company card.
        const payload = data as BusinessCardWire | null;
        if (
          !payload ||
          typeof payload !== "object" ||
          !payload.presenterUserId ||
          !payload.company
        ) {
          return;
        }
        const revKey = `${payload.presenterUserId}:${payload.rev}`;
        if (bizSeenRevRef.current !== revKey) {
          bizSeenRevRef.current = revKey;
          setBizHandRaised(false);
        }
        setBizCard((current) =>
          current &&
          current.presenterUserId === payload.presenterUserId &&
          current.rev === payload.rev
            ? current
            : {
                ...payload,
                mode:
                  payload.mode === "roles" || payload.mode === "team"
                    ? payload.mode
                    : "company",
                positions: Array.isArray(payload.positions) ? payload.positions : [],
                roles: Array.isArray(payload.roles) ? payload.roles : [],
                team: Array.isArray(payload.team) ? payload.team : [],
                applyUrl: typeof payload.applyUrl === "string" ? payload.applyUrl : "",
                businessId:
                  typeof payload.businessId === "string" ? payload.businessId : "",
              },
        );
      } else if (event === "business-card-end") {
        const info = data as { presenterUserId?: string } | null;
        setBizCard((current) =>
          current && (!info?.presenterUserId || current.presenterUserId === info.presenterUserId)
            ? null
            : current,
        );
      } else if (event === "business-interest") {
        // A viewer raised a hand on MY card — the ref is only ever set on
        // the presenter's device, so its presence means I'm presenting.
        const info = data as { username?: string } | null;
        const mine = bizCardRef.current;
        if (!info?.username || !mine) return;
        const raiser = info.username;
        setBizInterested((prev) =>
          prev.includes(raiser) ? prev : [...prev, raiser],
        );
        toast(`👋 @${raiser} is interested in ${mine.company}`);
      } else if (event === "ember-share") {
        const info = data as { name?: string; text?: string; block?: unknown } | null;
        if (!info) return;
        const text = typeof info.text === "string" ? info.text : "";
        const block = (info.block as EmberBlock | null) ?? null;
        if (!text.trim() && !block) return;
        setSharedEmber({
          name: typeof info.name === "string" && info.name ? info.name : "someone",
          text,
          block,
          at: Date.now(),
        });
      } else if (event === "client-card") {
        const info = data as Partial<SharedClientCard> | null;
        if (!info || typeof info.client !== "string" || !info.client) return;
        setSharedClientCard({
          name: typeof info.name === "string" && info.name ? info.name : "coach",
          client: info.client,
          bpm: typeof info.bpm === "number" ? info.bpm : null,
          sleep: typeof info.sleep === "number" ? info.sleep : 0,
          steps: typeof info.steps === "number" ? info.steps : 0,
          calories: typeof info.calories === "number" ? info.calories : 0,
          caloriesGoal: typeof info.caloriesGoal === "number" ? info.caloriesGoal : 0,
          protein: typeof info.protein === "number" ? info.protein : 0,
          proteinGoal: typeof info.proteinGoal === "number" ? info.proteinGoal : 0,
          training: typeof info.training === "string" ? info.training : null,
          at: Date.now(),
        });
      } else if (event === "present-sync-request") {
        if (currentHostIdRef.current?.toLowerCase() === selfId.toLowerCase()) rtc.sendAppEvent("call-policy", roomPolicyRef.current);
        // A joiner asked "is anyone presenting?" — answer instantly instead
        // of making them wait for the next heartbeat.
        const current = presentationPayloadRef.current;
        if (current) rtc.sendAppEvent("present-client", current);
        const creatorCurrent = creatorCardRef.current;
        if (creatorCurrent) rtc.sendAppEvent("creator-analytics", creatorCurrent);
        const bizCurrent = bizCardRef.current;
        if (bizCurrent) rtc.sendAppEvent("business-card", bizCurrent);
        const datingCurrent = myDatingWireRef.current;
        if (speedDateRef.current && datingCurrent) {
          rtc.sendAppEvent("dating-card", datingCurrent);
        }
        const tourPos = tourPosRef.current;
        if (tourPos) {
          const tourPayload: DeckTourEventPayload = {
            open: true,
            slide: tourPos.slide,
            segment: tourPos.segment,
            playing: tourPos.playing,
            driverName: selfName,
            rev: Date.now(),
            voice: "driver",
          };
          rtc.sendAppEvent("deck-tour", tourPayload);
        }
      } else if (event === "client-vitals") {
        // A participant's Jasper app is streaming live vitals into the call
        // — fresher than the 15s snapshot poll, powers the coach overlays.
        const info = data as { userId?: string; bpm?: number } | null;
        const bpm = typeof info?.bpm === "number" ? Math.round(info.bpm) : 0;
        const uid = typeof info?.userId === "string" ? info.userId : "";
        if (!uid || bpm <= 0 || bpm > 250 || uid === selfId) return;
        liveVitalsAtRef.current[uid] = Date.now();
        setHeartRates((current) => ({ ...current, [uid]: bpm }));
      } else if (event === "schedule-suggest") {
        // Someone else's voice mentioned a concrete date — mirror the same
        // "add to shared calendar?" prompt so the whole room stays in sync.
        const info = data as {
          byUserId?: string;
          byName?: string;
          dateMs?: number;
          snippet?: string;
          eventType?: string;
        } | null;
        const dateMs = typeof info?.dateMs === "number" ? info.dateMs : 0;
        const byUserId = typeof info?.byUserId === "string" ? info.byUserId : "";
        if (!user || !dateMs || !byUserId || byUserId === selfId) return;
        if (dateMs < Date.now() + 5 * 60 * 1000) return;
        const bucket = Math.floor(dateMs / 600_000);
        if (scheduleBucketsRef.current.has(bucket)) return;
        scheduleBucketsRef.current.add(bucket);
        const rawType = (info?.eventType ?? "meet") as CalendarEventType;
        setScheduleSuggest({
          dateMs,
          snippet: typeof info?.snippet === "string" ? info.snippet : "",
          eventType: SCHEDULE_TYPE_LABELS[rawType] ? rawType : "meet",
          byName:
            typeof info?.byName === "string" && info.byName ? info.byName : "someone",
        });
      } else if (event === "dating-card") {
        // Blind dating — someone announced their dating card; the first card
        // in the room lights date mode for everyone, and everyone answers
        // with their own (an empty card still announces you).
        const wire = decodeDatingCardWire(data);
        if (!wire || wire.userId === selfId) return;
        setDatingCards((current) => ({ ...current, [wire.userId]: wire }));
        const blind = blindRef.current;
        if (!blind.partnerUserId) {
          blind.partnerUserId = wire.userId.toLowerCase();
          blind.partnerName = wire.username;
        }
        activateSpeedDateRef.current();
      } else if (event === "dating-verdict") {
        // Legacy in-room verdict — Jasper's read lives on the wrap now.
      } else if (event === BLIND_WIRE.ready) {
        const d = (data ?? {}) as { userId?: string };
        if ((d.userId ?? "") === selfId) return;
        blindRef.current.theirReady = true;
        blindActionsRef.current.start();
        setBlindTick((t) => t + 1);
      } else if (event === BLIND_WIRE.state) {
        // Their clock is running → they're ready by definition; converge on
        // the earliest start / longest duration / any reveal.
        const blind = blindRef.current;
        blind.theirReady = true;
        blind.adoptState(data);
        setBlindTick((t) => t + 1);
      } else if (event === BLIND_WIRE.reveal) {
        const d = (data ?? {}) as { userId?: string };
        if ((d.userId ?? "") === selfId) return;
        const blind = blindRef.current;
        blind.theirRevealTapped = true;
        if (blind.myRevealTapped) blindActionsRef.current.reveal(true);
        setBlindTick((t) => t + 1);
      } else if (event === BLIND_WIRE.extend) {
        const d = (data ?? {}) as { userId?: string; round?: number };
        if ((d.userId ?? "") === selfId) return;
        const blind = blindRef.current;
        blind.theirExtendRound = Math.max(blind.theirExtendRound, typeof d.round === "number" ? Math.round(d.round) : 0);
        blindActionsRef.current.extend();
        setBlindTick((t) => t + 1);
      } else if (event === BLIND_WIRE.prompts) {
        const d = (data ?? {}) as { prompts?: unknown; at?: number };
        blindRef.current.adoptDeck(d.prompts, typeof d.at === "number" ? d.at : 0);
        setBlindTick((t) => t + 1);
      } else if (event === BLIND_WIRE.promptIndex) {
        const d = (data ?? {}) as { index?: number; byUserId?: string };
        if ((d.byUserId ?? "") === selfId) return;
        const blind = blindRef.current;
        const idx = typeof d.index === "number" ? Math.round(d.index) : 0;
        blind.promptIndex = Math.max(0, Math.min(idx, Math.max(0, blind.deck.length - 1)));
        setBlindTick((t) => t + 1);
      } else if (event === BLIND_WIRE.left) {
        const d = (data ?? {}) as { userId?: string };
        if ((d.userId ?? "") === selfId) return;
        blindRef.current.partnerLeft = true;
        void blindActionsRef.current.finish(true);
      } else if (event === "meeting-kick") {
        // The host removed someone — if it's ME, leave gracefully (same
        // wire + payload shape as iOS).
        const d = (data ?? {}) as { targetUserId?: string; targetPeerId?: string };
        const meByUser =
          typeof d.targetUserId === "string" && !!d.targetUserId && d.targetUserId === selfId;
        const meByPeer =
          typeof d.targetPeerId === "string" && !!d.targetPeerId && d.targetPeerId === rtc.localPeerId;
        if (meByUser || meByPeer) {
          void recordingSessionRef.current.stop(true);
          void rtc.setMicEnabled(false);
          setKickedOut(true);
          void rtc.leave();
        } else {
          const targets = participantsRef.current.filter((p) => d.targetPeerId
            ? p.peerId === d.targetPeerId
            : !!d.targetUserId && p.userId.toLowerCase() === d.targetUserId.toLowerCase());
          for (const target of targets) rtc.forgetParticipant(target.peerId);
        }
      } else if (event === "deck-tour") {
        // Someone is running (or ending) the Ember deck walkthrough.
        const info = data as Partial<DeckTourEventPayload> | null;
        if (!info || typeof info !== "object") return;
        tourBeatRef.current = Date.now();
        if (tourPosRef.current) return; // I'm the driver — ignore echoes.
        if (info.open !== true) {
          setDeckTour((current) =>
            current && current.driverPeerId === fromPeerId ? null : current,
          );
          return;
        }
        const pos = clampTourPosition(
          typeof info.slide === "number" ? info.slide : 0,
          typeof info.segment === "number" ? info.segment : 0,
        );
        setDeckTour({
          slide: pos.slide,
          segment: pos.segment,
          playing: info.playing === true,
          driverPeerId: fromPeerId,
          driverName:
            typeof info.driverName === "string" && info.driverName
              ? info.driverName
              : "someone",
          voice: info.voice === "device" ? "device" : "driver",
        });
      }
    };
    try {
      let media: LocalMediaState | null = null;
      if (mode === "full") {
        // Synchronously invalidate pending lobby permission and release only its resources.
        const hadLobbyCamera = !!lobbyStreamRef.current;
        lobbyCleanupRef.current?.();
        if (hadLobbyCamera && isMobileWebKit()) {
          // iPhone/iPad browsers run ONE capture session: re-grabbing the
          // camera the instant the lobby preview stops races the hardware
          // teardown and fails with "in use" — give it a breath.
          await new Promise((resolve) => setTimeout(resolve, 320));
        }
        // Voice calls never touch the camera — mic-only acquisition. A
        // camera-off lobby choice skips video acquisition entirely.
        if (rtcRef.current !== rtc) return;
        media = await rtc.prepareLocalMedia({ video: !isAudioCall && joinPrefCamRef.current });
        if (rtcRef.current !== rtc) { rtc.leave(); return; }
        if (media.hasAudio && !joinPrefMicRef.current) await rtc.setMicEnabled(false);
        if (rtcRef.current !== rtc) return;
        setMediaState(media);
        setMicOn(media.hasAudio && joinPrefMicRef.current);
        setCamOn(media.hasVideo);
        setDeviceBannerDismissed(false);
        if (!media.hasAudio && !media.hasVideo) {
          setLobbyBlocked(true);
          rtc.leave();
          rtcRef.current = null;
          return;
        }
        // Captions/notes only start once the mic genuinely works — and never
        // on mobile WebKit: its speech recognizer takes over the SAME audio
        // session the call is sending, muting the WebRTC mic (the other side
        // hears nothing, the watchdog re-grabs the mic, the camera dies).
        if (media.hasAudio && joinPrefMicRef.current) startTranscription();
      } else {
        setMicOn(false);
        setCamOn(false);
      }
      await rtc.join(`meeting:${id}`, mode === "listen");
      if (rtcRef.current !== rtc) { rtc.leave(); return; }
      setJoined(true);
      setLobbyBlocked(false);
      setPostCall(null);
      playMeetJoinChime();
      // Apply the lobby mic choice (walk in muted) — mirrors iOS.
      if (media?.hasAudio && !joinPrefMicRef.current) {
        await rtc.setMicEnabled(false);
        setMicOn(false);
      }
      // Pull any in-flight presentation right away (heartbeat is the backup).
      rtc.sendAppEvent("present-sync-request", {});
      if (isHost && meeting?.status === "scheduled") {
        // The host going live is what starts a scheduled meeting.
        try {
          await startMeeting(id);
          void meetingQuery.refetch();
        } catch {
          /* The room still works; the row simply stays scheduled. */
        }
      }
      if (user) {
        await joinMeeting({ meetingId: id, userId: user.id, username: name }).catch(() => undefined);
      }
      if (rtcRef.current !== rtc) return;
      if (user && media?.hasAudio && joinPrefMicRef.current && !nativeTranscriptionActiveRef.current && !isMobileWebKit()) {
        startRecorderFallback(rtc.localAudioStream);
      }
      if (media && !media.hasVideo && media.videoError) {
        toast(describeMediaBlock(media.videoError, "camera"));
      }
      if (media && !media.hasAudio && media.audioError) {
        toast(describeMediaBlock(media.audioError, "microphone"));
      }
    } catch {
      if (rtcRef.current !== rtc) { rtc.leave(); return; }
      toast.error("Couldn't connect to the meeting — check your internet connection and try again.");
      rtc.leave();
      rtcRef.current = null;
      await stopTranscription();
    } finally {
      if (!rtcRef.current || rtcRef.current === rtc) setJoinBusy(false);
    }
  }, [id, isAudioCall, isHost, joinBusy, meeting?.status, meetingQuery, selfId, selfName, startRecorderFallback, startTranscription, stopTranscription, user]);

  // ─── Knocking (Meet's "Ask to join") — the knocker's side ───
  const clearKnockTimers = useCallback((): void => {
    for (const t of knockTimersRef.current) window.clearTimeout(t);
    knockTimersRef.current = [];
  }, []);

  /** Give up on my knock — tells the room so the host's prompt disappears. */
  const cancelKnock = useCallback((): void => {
    clearKnockTimers();
    const bell = doorbellRef.current;
    doorbellRef.current = null;
    if (bell) {
      void bell.cancel().finally(() => void bell.close());
    }
    setKnockState(null);
    setKnockHostName(null);
    knockHostNameRef.current = null;
  }, [clearKnockTimers]);

  /**
   * Join through the door. Hosts, 1:1 calls, and blind dates walk straight
   * in. Everyone else knocks first: signed-in members are auto-admitted by
   * the doorkeeper while Quick access is on (a ~300 ms detour) and join
   * directly when nobody in the room can answer; guests always wait for a
   * real Admit — "Asking to join…" — and keep knocking until a host arrives.
   */
  const requestToJoin = useCallback(async (mode: "full" | "listen" = "full"): Promise<void> => {
    if (knockState || joinBusy || rtcRef.current) return;
    const guest = !user;
    const needsDoor = !isHost && !speedDateRoom && !callWith && !!id;
    if (!needsDoor) {
      void join(mode);
      return;
    }
    primeMeetSounds();
    setKnockState("asking");
    setKnockHostName(null);
    knockHostNameRef.current = null;
    const knockId = meetKnockId();
    let settled = false;
    const finish = (next: () => void): void => {
      if (settled) return;
      settled = true;
      clearKnockTimers();
      const bell = doorbellRef.current;
      doorbellRef.current = null;
      const closing = bell ? bell.close() : Promise.resolve();
      void closing.finally(next);
    };
    try {
      const bell = await openMeetDoorbell(
        `meeting:${id}`,
        {
          knockId,
          name: selfName,
          userId: user?.id ?? null,
          avatarUrl: profile?.profile_image_url ?? null,
          isGuest: guest,
        },
        {
          onAck: (byName) => {
            knockHostNameRef.current = byName;
            setKnockHostName(byName);
            setKnockState("asking");
            // A host is on the door — stop the "nobody home" fallbacks and
            // give them three minutes to decide.
            clearKnockTimers();
            knockTimersRef.current.push(
              window.setTimeout(() => finish(() => setKnockState("timeout")), 180_000),
            );
          },
          onAdmit: () =>
            finish(() => {
              setKnockState(null);
              void join(mode);
            }),
          onDeny: () => finish(() => setKnockState("denied")),
        },
      );
      if (settled) {
        void bell.close();
        return;
      }
      doorbellRef.current = bell;
      await bell.knock();
      // Nobody answered: members walk into an open room; guests wait for
      // the host and re-ring every few seconds so the request lands the
      // moment someone who can answer arrives.
      knockTimersRef.current.push(
        window.setTimeout(() => {
          if (settled) return;
          if (!guest) {
            finish(() => {
              setKnockState(null);
              void join(mode);
            });
            return;
          }
          setKnockState("waiting-host");
          const ring = window.setInterval(() => {
            if (settled) {
              window.clearInterval(ring);
              return;
            }
            void doorbellRef.current?.knock();
          }, 6_000);
          knockTimersRef.current.push(ring);
        }, guest ? 3_000 : 2_500),
      );
    } catch {
      // Signaling unreachable from the lobby — the normal join surfaces its
      // own honest error.
      finish(() => {
        setKnockState(null);
        void join(mode);
      });
    }
  }, [callWith, clearKnockTimers, id, isHost, join, joinBusy, knockState, profile?.profile_image_url, selfName, speedDateRoom, user]);

  // Leaving the page mid-knock takes the knock with it.
  useEffect(
    () => () => {
      for (const t of knockTimersRef.current) window.clearTimeout(t);
      const bell = doorbellRef.current;
      doorbellRef.current = null;
      if (bell) void bell.cancel().finally(() => void bell.close());
    },
    [],
  );

  /** Select a background effect — persists, updates the lobby preview live,
   *  and swaps the outgoing camera feed mid-call without renegotiation. */
  const effectOperationRef = useRef<number>(0);
  const applyVideoEffect = useCallback(async (mode: VideoFxMode, imageUrl?: string | null) => {
    const operation = ++effectOperationRef.current;
    videoFx.setMode(mode, imageUrl ?? undefined);
    setFxMode(videoFx.mode);
    setFxImage(videoFx.imageUrl);
    const rtc = rtcRef.current;
    if (!rtc || rtc.isScreenSharing || rtc.isChangingScreenShare) return;
    const current = rtc.localVideoTrack;
    if (!current) return;
    if (videoFx.mode === "none") {
      const raw = videoFx.sourceTrack;
      if (raw && raw.readyState === "live" && current !== raw) {
        await rtc.swapOutgoingVideoTrack(raw, false);
      }
      if (rtcRef.current !== rtc || effectOperationRef.current !== operation || rtc.isScreenSharing || rtc.isChangingScreenShare || videoFx.sourceTrack !== raw || videoFx.mode !== "none") return;
      videoFx.release({ stopSource: false });
    } else if (videoFx.outputTrack !== current) {
      const processed = videoFx.wrap(current);
      if (processed !== current) {
        await rtc.swapOutgoingVideoTrack(processed, false);
      }
    }
  }, []);

  // Lobby camera preview — the welcoming-room self-view with live effects.
  const lobbyVisible = !!meeting && !joined && !joinBusy && !hasEnded && notes === null && !(callWith && !lobbyBlocked);
  useEffect(() => {
    // Retry nonce — a fresh user-gesture attempt re-runs the acquisition
    // (Safari only re-prompts when the request rides a real tap).
    void lobbyCamRetry;
    if (!lobbyVisible || isAudioCall) return;
    if (!joinPrefCam) {
      setLobbyCamState("off");
      return;
    }
    let cancelled = false;
    let ownedStream: MediaStream | null = null;
    const cleanup = (): void => {
      cancelled = true;
      const source = ownedStream?.getVideoTracks()[0];
      if (source && videoFx.sourceTrack === source) videoFx.release({ stopSource: false });
      ownedStream?.getTracks().forEach((track) => track.stop());
      if (lobbyStreamRef.current === ownedStream) lobbyStreamRef.current = null;
      if (lobbyCleanupRef.current === cleanup) lobbyCleanupRef.current = null;
    };
    lobbyCleanupRef.current = cleanup;
    setLobbyCamState("loading");
    void (async () => {
      try {
        const raw = await navigator.mediaDevices.getUserMedia({
          video: { width: { ideal: 1280 }, height: { ideal: 720 } },
        });
        if (cancelled) {
          raw.getTracks().forEach((t) => t.stop());
          return;
        }
        ownedStream = raw;
        lobbyStreamRef.current = raw;
        const rawTrack = raw.getVideoTracks()[0] ?? null;
        // Always pipe the lobby preview through the engine so switching
        // effects in the sheet previews instantly (passthrough when none).
        const outTrack = rawTrack ? videoFx.wrap(rawTrack) : null;
        if (lobbyVideoRef.current) {
          lobbyVideoRef.current.srcObject = new MediaStream(outTrack ? [outTrack] : []);
          void lobbyVideoRef.current.play().catch(() => undefined);
        }
        setLobbyCamState("ready");
      } catch {
        if (!cancelled) setLobbyCamState("blocked");
      }
    })();
    return cleanup;
  }, [lobbyVisible, isAudioCall, joinPrefCam, lobbyCamRetry]);

  // 1:1 calls skip the lobby entirely — connect the moment the room loads.
  useEffect(() => {
    if (!callWith || autoJoinedRef.current) return;
    if (!meeting || !user || !meetingAccessReady || joined || hasEnded) return;
    autoJoinedRef.current = true;
    void join("full");
  }, [callWith, meeting, user, meetingAccessReady, joined, hasEnded, join]);

  /** Re-attempt blocked devices in-call and publish whatever comes back.
   *  Listen-only viewers are promoted to full participants on success. */
  const retryDevices = useCallback(async (): Promise<void> => {
    const rtc = rtcRef.current;
    if (!rtc || mediaBusy) return;
    setMediaBusy(true);
    const prev = mediaState;
    try {
      let state: LocalMediaState;
      if (!rtc.isSpeakerRole) {
        const promoted = await rtc.becomeSpeaker();
        if (rtcRef.current !== rtc) return;
        state = rtc.localMediaState;
        if (promoted) toast.success("You're on stage — mic and camera are live");
      } else {
        state = await rtc.retryLocalMedia();
      }
      if (rtcRef.current !== rtc) return;
      setMediaState(state);
      if (state.hasAudio && !(prev?.hasAudio ?? false)) setMicOn(true);
      if (state.hasVideo && !(prev?.hasVideo ?? false)) setCamOn(true);
      if (state.hasAudio) {
        if (!nativeTranscriptionActiveRef.current && !recorderTranscriberRef.current) {
          startTranscription();
          if (!nativeTranscriptionActiveRef.current) {
            startRecorderFallback(rtc.localAudioStream);
          }
        }
        if (!(prev?.hasAudio ?? false)) toast.success("Microphone connected");
      }
      if (state.hasVideo && !(prev?.hasVideo ?? false)) toast.success("Camera connected");
      if (!state.hasAudio && !state.hasVideo) {
        toast.error("Still blocked — check your browser's site permissions.");
      }
    } finally {
      setMediaBusy(false);
    }
  }, [mediaBusy, mediaState, startRecorderFallback, startTranscription]);

  /** Mic toggle that reflects what the hardware ACTUALLY did. */
  const toggleMic = useCallback(async (): Promise<void> => {
    const rtc = rtcRef.current;
    if (!rtc || mediaBusy) return;
    if (emberSessionRef.current) stopEmberVoice();
    const target = !micOn;
    setMediaBusy(true);
    try {
      const applied = await rtc.setMicEnabled(target);
      if (rtcRef.current !== rtc) return;
      setMicOn(applied);
      setMediaState(rtc.localMediaState);
      if (target && !applied) {
        toast.error(describeMediaBlock(rtc.localMediaState.audioError ?? "unknown", "microphone"));
        return;
      }
      if (applied) {
        // Captions resume with the mic.
        if (!nativeTranscriptionActiveRef.current && !recorderTranscriberRef.current) {
          startTranscription();
          if (!nativeTranscriptionActiveRef.current) {
            startRecorderFallback(rtc.localAudioStream);
          }
        } else {
          resumeTranscriptionAfterEmber();
        }
      } else {
        // Muted — never keep transcribing a mic the user turned off.
        pauseTranscriptionForEmber();
        setCaptionText("");
      }
    } finally {
      setMediaBusy(false);
    }
  }, [mediaBusy, micOn, pauseTranscriptionForEmber, resumeTranscriptionAfterEmber, startRecorderFallback, startTranscription, stopEmberVoice]);

  // A host's "mute everyone" / targeted mute (iOS wire) — mute our own mic
  // once per request; hosts are exempt exactly like the iOS call service.
  const muteHandledRef = useRef<number>(0);
  useEffect(() => {
    if (muteRequest === 0 || muteHandledRef.current === muteRequest) return;
    muteHandledRef.current = muteRequest;
    if (micOn && !isHost) void toggleMic();
  }, [muteRequest, micOn, isHost, toggleMic]);

  /** Camera toggle that re-acquires the device when needed. */
  const toggleCam = useCallback(async (): Promise<void> => {
    const rtc = rtcRef.current;
    if (!rtc || mediaBusy) return;
    const target = !camOn;
    setMediaBusy(true);
    try {
      const applied = await rtc.setCameraEnabled(target);
      if (rtcRef.current !== rtc) return;
      setCamOn(applied);
      setMediaState(rtc.localMediaState);
      if (target && !applied) {
        toast.error(describeMediaBlock(rtc.localMediaState.videoError ?? "unknown", "camera"));
      }
    } finally {
      setMediaBusy(false);
    }
  }, [camOn, mediaBusy]);

  const [leaving, setLeaving] = useState<boolean>(false);
  const leaveTask = useRef<Promise<void> | null>(null);
  const leave = useCallback((): Promise<void> => {
    if (leaveTask.current) return leaveTask.current;
    setLeaving(true);
    const task = (async (): Promise<void> => {
    recordingSessionRef.current.reply(false);
    const recordingDrain = recordingSessionRef.current.stop();
    const departingRTC = rtcRef.current;
    rtcRef.current = null;
    departingRTC?.leave();
    setJoined(false);
    const transcriptionDrain = stopTranscription();
    stopEmberVoice();
    // Walkthrough + pop-out teardown BEFORE the channel drops so the
    // "walkthrough ended" broadcast still reaches the room.
    stopDeckTourRef.current?.({ silent: true });
    const docPipWindow = docPipWindowRef.current;
    docPipWindowRef.current = null;
    pipTilesRef.current.clear();
    if (docPipWindow && !docPipWindow.closed) docPipWindow.close();
    pipMosaicRef.current?.dispose();
    pipMosaicRef.current = null;
    setDocPipOpen(false);
    stopPresentHeartbeat();
    setPresentation(null);
    setPresentationExpanded(false);
    stopCreatorHeartbeat();
    creatorCardRef.current = null;
    creatorKeyRef.current = "";
    setCreatorCard(null);
    setCreatorExpanded(false);
    bizCardRef.current = null;
    bizSeenRevRef.current = "";
    setBizCard(null);
    setBizInterested([]);
    setBizHandRaised(false);
    setEmberPanelOpen(false);
    setSharedEmber(null);
    presentationKeyRef.current = "";
    await Promise.all([recordingDrain, transcriptionDrain]);
    })();
    leaveTask.current = task;
    void task.finally(() => { if (leaveTask.current === task) { leaveTask.current = null; setLeaving(false); } }).catch(() => undefined);
    return task;
  }, [stopEmberVoice, stopPresentHeartbeat, stopCreatorHeartbeat, stopTranscription]);

  // Cleanup on unmount.
  useEffect(() => () => { void leave(); }, [leave]);

  // ── Blind date — the clock, the wire, and the wrap (mirrors iOS exactly) ──
  const blindSend = useCallback((event: string, data: Record<string, unknown>): void => {
    rtcRef.current?.sendAppEvent(event, data);
  }, []);

  /** Both ready + no clock yet → start it and publish (the other side adopts
   *  the earliest start, so two starts converge). */
  const maybeStartBlindClock = useCallback((): void => {
    const b = blindRef.current;
    if (!speedDateRef.current || b.startedAt != null || !b.myReady || !b.theirReady) return;
    b.start();
    blindSend(BLIND_WIRE.state, b.statePayload());
    bumpBlind();
  }, [blindSend, bumpBlind]);

  const revealNow = useCallback(
    (broadcast: boolean): void => {
      const b = blindRef.current;
      if (b.revealed) return;
      b.revealed = true;
      if (broadcast) blindSend(BLIND_WIRE.state, b.statePayload());
      bumpBlind();
    },
    [blindSend, bumpBlind],
  );

  const blindTapReveal = useCallback((): void => {
    const b = blindRef.current;
    if (b.myRevealTapped || b.startedAt == null) return;
    b.myRevealTapped = true;
    blindSend(BLIND_WIRE.reveal, { userId: user?.id ?? "" });
    if (b.theirRevealTapped) revealNow(true);
    bumpBlind();
  }, [blindSend, bumpBlind, revealNow, user?.id]);

  /** An extension lands only when BOTH asked for the same round. */
  const resolveExtension = useCallback((): void => {
    const b = blindRef.current;
    const round = b.extensions + 1;
    if (b.myExtendRound < round || b.theirExtendRound < round) return;
    b.applyExtension();
    blindSend(BLIND_WIRE.state, b.statePayload());
    bumpBlind();
  }, [blindSend, bumpBlind]);

  const blindTapExtend = useCallback((): void => {
    const b = blindRef.current;
    if (!b.canExtend) return;
    const round = b.extensions + 1;
    if (b.myExtendRound >= round) return;
    b.myExtendRound = round;
    blindSend(BLIND_WIRE.extend, { userId: user?.id ?? "", round });
    resolveExtension();
    bumpBlind();
  }, [blindSend, bumpBlind, resolveExtension, user?.id]);

  const blindStepPrompt = useCallback(
    (delta: number): void => {
      const b = blindRef.current;
      if (b.deck.length === 0) return;
      const next = Math.max(0, Math.min(b.promptIndex + delta, b.deck.length - 1));
      if (next === b.promptIndex) return;
      b.promptIndex = next;
      blindSend(BLIND_WIRE.promptIndex, { index: next, byUserId: user?.id ?? "" });
      bumpBlind();
    },
    [blindSend, bumpBlind, user?.id],
  );

  /** ONE AI call for the deck — the lexicographically smaller user id
   *  generates and broadcasts; the other side waits, then falls back to the
   *  static deck so nobody stares at an empty card. */
  const buildBlindDeck = useCallback(async (): Promise<void> => {
    const b = blindRef.current;
    const me = user?.id ?? "";
    const iGenerate = !b.partnerUserId || me < b.partnerUserId;
    if (iGenerate && user) {
      const deck = await generateBlindDeck({
        userId: user.id,
        myName: profile?.username ?? "me",
        myCard: loadDatingCardLocal(user.id),
        theirCard: Object.values(blindCardsRef.current)[0] ?? null,
      });
      if (b.deck.length > 0) return;
      const stamp = Date.now();
      const lines = encodeBlindDeck(deck);
      b.adoptDeck(lines, stamp);
      blindSend(BLIND_WIRE.prompts, { prompts: lines, byUserId: me, at: stamp });
    } else {
      await new Promise((r) => setTimeout(r, 12_000));
      if (b.deck.length > 0) return;
      b.adoptDeck(encodeBlindDeck(BLIND_FALLBACK_DECK), Date.now());
    }
    bumpBlind();
  }, [blindSend, bumpBlind, profile?.username, user]);

  /** Ends the date on this side — announces it, leaves the call, pulls the
   *  transcript, and lands on the WRAP (decision + Jasper's recap). */
  const finishBlindDate = useCallback(
    async (partnerLeft: boolean): Promise<void> => {
      if (blindLeavingRef.current || blindWrapRef.current) return;
      blindLeavingRef.current = true;
      const b = blindRef.current;
      const me = user?.id ?? "";
      const partner = blindParticipantsRef.current.find((p) => p.userId && p.userId !== me);
      let partnerUserId = (partner?.userId ?? "").toLowerCase();
      if (!partnerUserId) partnerUserId = b.partnerUserId;
      if (!partnerUserId) partnerUserId = Object.keys(blindCardsRef.current)[0]?.toLowerCase() ?? "";
      const partnerName =
        partner?.name ?? (b.partnerName || Object.values(blindCardsRef.current)[0]?.username || "your date");
      const theirCard =
        blindCardsRef.current[partnerUserId] ?? Object.values(blindCardsRef.current)[0] ?? null;
      const revealed = b.revealed;
      const elapsedSec = Math.round(b.elapsed);
      if (!partnerLeft) {
        blindSend(BLIND_WIRE.left, { userId: me });
        await new Promise((r) => setTimeout(r, 250));
      }
      await leave();
      let transcript = "";
      try {
        const segments = id ? await fetchTranscript(id) : [];
        transcript = segments.map((s) => `${s.username || "speaker"}: ${s.text}`).join("\n");
      } catch {
        transcript = "";
      }
      let partnerAvatarUrl: string | null = null;
      if (partnerUserId) {
        try {
          const profiles = await fetchProfilesByIds([partnerUserId]);
          partnerAvatarUrl = profiles[partnerUserId]?.profile_image_url ?? null;
        } catch {
          partnerAvatarUrl = null;
        }
      }
      setBlindWrap({
        partnerUserId,
        partnerName,
        partnerAvatarUrl,
        transcript,
        theirCard,
        revealed,
        partnerLeft,
        elapsedSec,
      });
      blindLeavingRef.current = false;
    },
    [blindSend, id, leave, user?.id],
  );

  useEffect(() => {
    blindActionsRef.current = {
      start: maybeStartBlindClock,
      reveal: revealNow,
      extend: resolveExtension,
      finish: finishBlindDate,
    };
  }, [maybeStartBlindClock, revealNow, resolveExtension, finishBlindDate]);

  // The half-second heartbeat that runs the date: readiness handshake,
  // shared-clock convergence, auto-reveal at the mark, the deck, time's up.
  useEffect(() => {
    if (!speedDate) return;
    let tick = 0;
    const me = user?.id ?? "";
    const t = window.setInterval(() => {
      const b = blindRef.current;
      if (blindWrapRef.current || blindLeavingRef.current) return;
      tick += 1;
      if (b.startedAt == null) {
        if (b.myReady && tick % 4 === 0) blindSend(BLIND_WIRE.ready, { userId: me });
        maybeStartBlindClock();
        return;
      }
      if (tick % 10 === 0) blindSend(BLIND_WIRE.state, b.statePayload());
      if (tick % 20 === 0 && b.deck.length > 0 && b.deckAt > 0) {
        blindSend(BLIND_WIRE.prompts, { prompts: encodeBlindDeck(b.deck), byUserId: me, at: b.deckAt });
      }
      if (!b.revealed && b.elapsed >= b.revealAtSec) revealNow(false);
      if (!blindDeckRequestedRef.current) {
        blindDeckRequestedRef.current = true;
        void buildBlindDeck();
      }
      if (!b.timeUp && b.remaining <= 0) {
        b.timeUp = true;
        bumpBlind();
        window.setTimeout(() => void finishBlindDate(false), 1400);
      }
    }, 500);
    return () => window.clearInterval(t);
  }, [speedDate, user?.id, blindSend, maybeStartBlindClock, revealNow, buildBlindDeck, finishBlindDate, bumpBlind]);

  // Meetings are an immersive canvas, not a scrollable document. Locking the
  // browser viewport keeps the video stage, controls, and PIP anchored even on
  // mobile address-bar changes and trackpad scrolls.
  useEffect(() => {
    if (!joined || minimized) return;
    const body = document.body;
    const root = document.documentElement;
    const originalBodyOverflow = body.style.overflow;
    const originalBodyOverscroll = body.style.overscrollBehavior;
    const originalRootOverflow = root.style.overflow;
    body.style.overflow = "hidden";
    body.style.overscrollBehavior = "none";
    root.style.overflow = "hidden";
    return () => {
      body.style.overflow = originalBodyOverflow;
      body.style.overscrollBehavior = originalBodyOverscroll;
      root.style.overflow = originalRootOverflow;
    };
  }, [joined, minimized]);

  // The LIVE meeting stage is pitch black. The dark design tokens are
  // scoped to `:root.pitch-black` (the <html> element) and every modal
  // portals to <body>, so the class must go on the document root — a class
  // on the meeting wrapper reaches neither, which is why in-call sheets
  // rendered white-on-white. The previous appearance is restored on exit —
  // and the post-meeting NOTES review is a document, not a stage, so it
  // keeps the app's normal (light) appearance instead of a black page.
  const notesMode = hasEnded || notes !== null;
  useEffect(() => {
    if (notesMode || minimized) return;
    const root = document.documentElement;
    // Dark appearances deepen to true black for the stage (OLED, matches
    // iOS). LIGHT appearance keeps its palette — the stage reads the
    // off-white tokens instead, so the meeting is never forced dark.
    if (!root.classList.contains("dark")) return;
    const hadPitch = root.classList.contains("pitch-black");
    root.classList.add("pitch-black");
    return () => {
      if (!hadPitch) root.classList.remove("pitch-black");
    };
  }, [notesMode, minimized]);

  // If the meeting ends while minimized, bring the room back so the user
  // sees the summary instead of a frozen corner tile.
  useEffect(() => {
    if (minimized && notesMode) {
      navigate(`/meet/${id}`);
      meetingHost.restore();
    }
  }, [minimized, notesMode, navigate, id, meetingHost]);

  // Keep the screen awake for the whole call — FaceTime-style. Re-acquired
  // when the tab becomes visible again (the OS releases wake locks on hide).
  useEffect(() => {
    if (!joined) return;
    let sentinel: { release: () => Promise<void> } | null = null;
    let cancelled = false;
    const acquire = async (): Promise<void> => {
      try {
        const wakeLock = (navigator as Navigator & {
          wakeLock?: { request: (type: "screen") => Promise<{ release: () => Promise<void> }> };
        }).wakeLock;
        if (!cancelled && wakeLock && document.visibilityState === "visible") {
          sentinel = await wakeLock.request("screen");
        }
      } catch {
        /* unsupported or denied — non-fatal */
      }
    };
    void acquire();
    const onVisibility = (): void => {
      if (document.visibilityState === "visible") void acquire();
    };
    document.addEventListener("visibilitychange", onVisibility);
    return () => {
      cancelled = true;
      document.removeEventListener("visibilitychange", onVisibility);
      void sentinel?.release().catch(() => undefined);
      sentinel = null;
    };
  }, [joined]);

  // Register the local camera stream with the host so the minimized corner
  // tile shows a live self-preview while the user browses the app.
  const registerPreview = meetingHost.setPreviewStream;
  useEffect(() => {
    if (!joined) {
      registerPreview(null);
      return;
    }
    const selfId = rtcRef.current?.localPeerId ?? "";
    const self = participants.find((p) => p.peerId === selfId);
    registerPreview(self?.remoteStream ?? null);
    return () => registerPreview(null);
  }, [joined, participants, registerPreview]);

  // Coach heart-rate overlay — poll participants' Jasper snapshots every 15s
  // while in the call and show a pulsing bpm chip on their tiles.
  const isCoach = !!profile?.is_coach;
  useEffect(() => {
    if (!joined || !isCoach) return;
    let cancelled = false;
    const poll = async (): Promise<void> => {
      const ids = participants
        .map((p) => p.userId)
        .filter((uid) => uid && uid !== user?.id);
      if (ids.length === 0) return;
      const rates = await fetchHeartRates(ids);
      if (!cancelled) setHeartRates(rates);
    };
    void poll();
    const timer = setInterval(() => void poll(), 15000);
    return () => {
      cancelled = true;
      clearInterval(timer);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [joined, isCoach, participants.length]);

  // Fetch verification badges + profile info for all participants so we
  // can show the correct badge icon next to each person's name.
  useEffect(() => {
    if (!joined || participants.length === 0) return;
    const usernames = participants
      .map((p) => p.name)
      .filter((n) => n && n !== "You" && n !== "Guest");
    if (usernames.length === 0) return;
    let cancelled = false;
    void (async () => {
      const [badges, profiles] = await Promise.all([
        fetchVerificationBadges(usernames),
        supabase
          .from("whisper_profiles")
          .select("username,is_coach,is_recruiter,is_athlete,is_verified,profile_image_url")
          .in("username", usernames.map((u) => u.toLowerCase())),
      ]);
      if (cancelled) return;
      setBadgeMap(badges);
      const pMap: Record<string, { is_coach?: boolean; is_recruiter?: boolean; is_athlete?: boolean; is_verified?: boolean; profile_image_url?: string | null }> = {};
      for (const row of (profiles.data as { username: string; is_coach?: boolean; is_recruiter?: boolean; is_athlete?: boolean; is_verified?: boolean; profile_image_url?: string | null }[] | null) ?? []) {
        if (row.username) pMap[row.username.toLowerCase()] = row;
      }
      setProfileMap(pMap);
    })();
    return () => { cancelled = true; };
  }, [joined, participants]);

  // Recruiter prospect pipeline for the in-meeting recruiter tools panel.
  const isRecruiter = !!profile?.is_recruiter;
  const prospectsQuery = useQuery({
    queryKey: ["meeting-prospects", user?.id ?? ""],
    queryFn: () => fetchProspects(user!.id),
    enabled: !!user && isRecruiter && showRecruiterTools,
  });

  // Coach client roster for the in-meeting coach tools panel.
  const coachRequestsQuery = useQuery({
    queryKey: ["meeting-coach-clients", user?.id ?? ""],
    queryFn: () => fetchCoachRequests(user!.id),
    enabled: !!user && isCoach && showCoachTools,
  });

  // 1:1 coach call — the live Jasper read on the person you're talking to.
  // RLS only returns a snapshot to their accepted coach, so the presence of
  // data doubles as the permission check; everyone else never sees a panel.
  const [vitalsOpen, setVitalsOpen] = useState<boolean>(true);
  const callPeerUserId = useMemo(
    () => participants.find((p) => p.userId && p.userId !== user?.id)?.userId ?? null,
    [participants, user?.id],
  );
  const callVitalsQuery = useQuery({
    queryKey: ["call-vitals", callPeerUserId ?? ""],
    queryFn: () => fetchClientSnapshot(callPeerUserId!),
    enabled: !!user && joined && !!callWith && !!callPeerUserId,
    refetchInterval: 20000,
  });
  const callVitals = callVitalsQuery.data?.snapshot ?? null;
  const callVitalsLive =
    !!callPeerUserId &&
    Date.now() - (liveVitalsAtRef.current[callPeerUserId] ?? 0) < 25000;
  const callVitalsBpm: number | null = callPeerUserId
    ? heartRates[callPeerUserId] ??
      (callVitals && callVitals.restingHeartRate > 0
        ? Math.round(callVitals.restingHeartRate)
        : null)
    : null;

  // Feed the live snapshot into Jasper's meeting brain (coach 1:1s only).
  useEffect(() => {
    callVitalsCtxRef.current =
      callWith && callVitals ? buildClientVitalsContext(callWith, callVitals) : null;
  }, [callWith, callVitals]);

  /** Coach: broadcast the client's live stats card into the meeting — it
   *  renders on everyone's stage wearing the same Jasper look. */
  const shareClientCard = useCallback((): void => {
    if (!callWith || !callVitals) return;
    const w = callVitals.recentWorkouts[0];
    const payload: Omit<SharedClientCard, "at"> = {
      name: profile?.username ?? "coach",
      client: callWith,
      bpm: callVitalsBpm,
      sleep: callVitals.sleepHours,
      steps: callVitals.steps,
      calories: Math.round(callVitals.caloriesToday),
      caloriesGoal: Math.round(callVitals.caloriesGoal),
      protein: Math.round(callVitals.proteinToday),
      proteinGoal: Math.round(callVitals.proteinGoal),
      training: w ? `${w.type} · ${Math.round(w.durationMinutes)}m` : null,
    };
    rtcRef.current?.sendAppEvent("client-card", payload);
    // App events don't echo back — show it locally too.
    setSharedClientCard({ ...payload, at: Date.now() });
    toast.success("Client card shared with the meeting");
  }, [callWith, callVitals, callVitalsBpm, profile?.username]);



  /** Every participant as a mosaic source — the pop-out shows the ROOM,
   *  never just you. */
  const mosaicSources = useCallback((roster: LiveParticipantInfo[]): PipMosaicSource[] => {
    const selfPeer = rtcRef.current?.localPeerId ?? "";
    return roster.map((p) => ({
      id: p.peerId,
      name: p.name,
      stream: p.remoteStream,
      hasVideo: p.hasVideo,
      isSelf: p.peerId === selfPeer || p.name === "You",
      isScreenShare: p.isScreenSharing,
      isSpeaking: p.isSpeaking,
      micOn: p.micOn,
    }));
  }, []);

  /** The (lazily created) mosaic, synced to the current roster and running. */
  const ensureMosaic = useCallback((): MeetPipMosaic => {
    let mosaic = pipMosaicRef.current;
    if (!mosaic) {
      mosaic = new MeetPipMosaic();
      pipMosaicRef.current = mosaic;
    }
    mosaic.update(mosaicSources(participantsRef.current));
    mosaic.start();
    return mosaic;
  }, [mosaicSources]);

  // PiP: when someone is sharing their screen and you switch browser tabs,
  // request Picture-in-Picture so the shared screen stays visible — like
  // Google Meet. The hidden element plays the ROOM MOSAIC (the shared
  // screen large, everyone else beside it) rather than one raw stream. This
  // must be a top-level hook (before any conditional returns) so React's
  // hook count stays stable.
  useEffect(() => {
    if (!joined || !("pictureInPictureEnabled" in document)) return;
    if (manualPipRef.current) return; // user-driven pop-out owns the element
    const sharer = participants.find((p) => p.isScreenSharing && p.name !== "You");
    const el = pipVideoRef.current;
    if (!el) return;
    if (sharer && sharer.remoteStream) {
      const mosaic = ensureMosaic();
      if (el.srcObject !== mosaic.mediaStream) {
        el.srcObject = mosaic.mediaStream;
        void el.play().catch(() => undefined);
      }
      // Enter PiP if not already (requires a user gesture on some browsers,
      // but screen-share start counts for Chrome).
      if (document.pictureInPictureElement !== el) {
        el.requestPictureInPicture?.().catch(() => undefined);
      }
    } else {
      // No screen share — exit PiP.
      if (document.pictureInPictureElement === el) {
        document.exitPictureInPicture?.().catch(() => undefined);
      }
      if (!document.pictureInPictureElement) {
        el.srcObject = null;
        pipMosaicRef.current?.stop();
      }
    }
  }, [joined, participants, ensureMosaic]);

  // Manual fallback PiP bookkeeping — hands the hidden element back to the
  // auto screen-share behavior when the browser closes the PiP window.
  useEffect(() => {
    const el = pipVideoRef.current;
    if (!el) return;
    const onLeave = (): void => {
      manualPipRef.current = false;
      pipMosaicRef.current?.stop();
      setDocPipOpen(false);
    };
    el.addEventListener("leavepictureinpicture", onLeave);
    return () => el.removeEventListener("leavepictureinpicture", onLeave);
  }, [joined]);

  // ─── Autoplay audio rescue ─── Stricter browsers (Safari, Firefox) can
  // refuse unmuted playback of remote streams; tiles fall back to muted video
  // and raise this flag — the next tap/keypress unmutes everything at once.
  const [audioBlocked, setAudioBlocked] = useState<boolean>(false);
  useEffect(() => {
    const onBlocked = (): void => setAudioBlocked(true);
    window.addEventListener("whisper-audio-blocked", onBlocked);
    return () => window.removeEventListener("whisper-audio-blocked", onBlocked);
  }, []);
  useEffect(() => {
    if (!audioBlocked) return;
    let alive = true;
    const unlock = (): void => {
      const elements = Array.from(document.querySelectorAll<HTMLAudioElement>('[data-meeting-stage] audio[data-autoplay-muted="1"]'));
      void Promise.all(elements.map(async (el) => {
        const source = el.srcObject;
        el.muted = false;
        try { await el.play(); if (el.srcObject === source) delete el.dataset.autoplayMuted; }
        catch { if (el.srcObject === source) el.dataset.autoplayMuted = "1"; }
      })).then(() => {
        if (alive) setAudioBlocked(!!document.querySelector('[data-meeting-stage] audio[data-autoplay-muted="1"]'));
      });
    };
    window.addEventListener("pointerdown", unlock, true);
    window.addEventListener("keydown", unlock, true);
    return () => {
      alive = false;
      window.removeEventListener("pointerdown", unlock, true);
      window.removeEventListener("keydown", unlock, true);
    };
  }, [audioBlocked]);

  // ── Audio output routing — parity with the iOS speaker/Bluetooth picker.
  const sinkSupported = useMemo(
    () => typeof HTMLMediaElement !== "undefined" && "setSinkId" in HTMLMediaElement.prototype,
    [],
  );
  const [audioOutputs, setAudioOutputs] = useState<MediaDeviceInfo[]>([]);
  const [sinkId, setSinkId] = useState<string | null>(null);
  const [sinkMenuOpen, setSinkMenuOpen] = useState<boolean>(false);
  const loadAudioOutputs = useCallback(async (): Promise<void> => {
    try {
      const devices = await navigator.mediaDevices.enumerateDevices();
      setAudioOutputs(devices.filter((device) => device.kind === "audiooutput" && device.deviceId));
    } catch {
      setAudioOutputs([]);
    }
  }, []);
  // Apply the chosen output to every meeting media element (the per-peer
  // audio sinks carry the voices; videos are muted but routed too so a
  // browser that plays tile audio anyway follows the same speaker).
  // Re-applied when participants change so late joiners inherit the route.
  useEffect(() => {
    if (!sinkSupported || sinkId === null) return;
    const apply = (): void => {
      document
        .querySelectorAll<HTMLMediaElement>("[data-meeting-stage] audio, [data-meeting-stage] video")
        .forEach((el) => {
          const sinkable = el as HTMLMediaElement & { setSinkId?: (deviceId: string) => Promise<void> };
          void sinkable.setSinkId?.(sinkId).catch(() => undefined);
        });
    };
    apply();
    const retry = window.setTimeout(apply, 900);
    return () => window.clearTimeout(retry);
  }, [sinkSupported, sinkId, participants]);

  /** Imperatively (re)render the Document PiP mini-stage — the PiP window
   *  holds plain DOM; React stays in the main tab. */
  const renderDocPip = useCallback((): void => {
    const win = docPipWindowRef.current;
    if (!win || win.closed) return;
    const root = win.document.getElementById("pip-root");
    if (!root) return;
    const tiles = pipTilesRef.current;
    const roster = participantsRef.current.slice(0, 9);
    const seen = new Set<string>();
    for (const participant of roster) {
      seen.add(participant.peerId);
      let tile = tiles.get(participant.peerId);
      if (!tile) {
        const wrap = win.document.createElement("div");
        wrap.className = "tile";
        const video = win.document.createElement("video");
        video.autoplay = true;
        video.muted = true;
        video.playsInline = true;
        const fallback = win.document.createElement("div");
        fallback.className = "fallback";
        const label = win.document.createElement("div");
        label.className = "label";
        wrap.appendChild(video);
        wrap.appendChild(fallback);
        wrap.appendChild(label);
        root.appendChild(wrap);
        tile = { wrap, video, fallback, label };
        tiles.set(participant.peerId, tile);
      }
      const displayName = participant.name === "You" ? "You" : `@${participant.name}`;
      tile.label.textContent = participant.micOn ? displayName : `${displayName} · muted`;
      tile.fallback.textContent = (participant.name || "?").slice(0, 1).toUpperCase();
      tile.wrap.classList.toggle("speaking", participant.isSpeaking);
      const stream = participant.hasVideo ? participant.remoteStream : null;
      if (stream) {
        if (tile.video.srcObject !== stream) {
          tile.video.srcObject = stream;
          void tile.video.play().catch(() => undefined);
        }
        tile.video.style.display = "block";
        tile.fallback.style.display = "none";
        const mirror = participant.name === "You" && !participant.isScreenSharing;
        tile.video.style.transform = mirror ? "scaleX(-1)" : "none";
        tile.video.style.objectFit = participant.isScreenSharing ? "contain" : "cover";
      } else {
        tile.video.srcObject = null;
        tile.video.style.display = "none";
        tile.fallback.style.display = "flex";
      }
    }
    for (const [peerId, tile] of Array.from(tiles.entries())) {
      if (!seen.has(peerId)) {
        tile.wrap.remove();
        tiles.delete(peerId);
      }
    }
    root.style.gridTemplateColumns =
      roster.length <= 1 ? "1fr" : roster.length <= 4 ? "1fr 1fr" : "1fr 1fr 1fr";
  }, []);

  // Live participants mirror for the PiP renderers (and re-render on change).
  useEffect(() => {
    participantsRef.current = participants;
    if (participants.length > 1) everHadCompanyRef.current = true;
    renderDocPipRef.current?.();
    const mosaic = pipMosaicRef.current;
    if (mosaic?.running) mosaic.update(mosaicSources(participants));
  }, [participants, mosaicSources]);
  useEffect(() => {
    renderDocPipRef.current = renderDocPip;
  }, [renderDocPip]);

  /** Any pop-out support at all (Chrome Document PiP or classic video PiP). */
  const pipSupported = useMemo<boolean>(
    () =>
      typeof window !== "undefined" &&
      ("documentPictureInPicture" in window ||
        document.pictureInPictureEnabled === true),
    [],
  );

  /** Pop the meeting into an always-on-top mini window so the room stays
   *  visible while you're on another tab (e.g. while screen sharing). */
  const openMeetingPip = useCallback(async (): Promise<void> => {
    const docPip = (window as Window & DocumentPipWindowHost).documentPictureInPicture;
    if (docPip?.requestWindow) {
      if (docPipWindowRef.current && !docPipWindowRef.current.closed) return;
      try {
        const win = await docPip.requestWindow({ width: 420, height: 330 });
        docPipWindowRef.current = win;
        win.document.title = meeting?.title ?? "Whisper meeting";
        const style = win.document.createElement("style");
        style.textContent = PIP_WINDOW_CSS;
        win.document.head.appendChild(style);
        const root = win.document.createElement("div");
        root.id = "pip-root";
        win.document.body.appendChild(root);
        win.addEventListener("pagehide", () => {
          pipTilesRef.current.clear();
          docPipWindowRef.current = null;
          setDocPipOpen(false);
        });
        setDocPipOpen(true);
        renderDocPipRef.current?.();
        return;
      } catch {
        // Document PiP can be blocked (embedded previews, permissions
        // policy, non-Chromium browsers) even when the API exists.
        // Fall through to classic single-video PiP instead of giving up.
      }
    }
    // Fallback: classic video PiP playing the ROOM MOSAIC — everyone in the
    // meeting composited into one stream (classic PiP can only show one
    // <video>, which is why it used to show a single person).
    const el = pipVideoRef.current;
    if (!el || !document.pictureInPictureEnabled) {
      toast("Pop-out is blocked in this browser — the meeting stays live in this tab");
      return;
    }
    if (participantsRef.current.length === 0) {
      toast("No one to pop out yet");
      return;
    }
    const mosaic = ensureMosaic();
    try {
      manualPipRef.current = true;
      if (el.srcObject !== mosaic.mediaStream) {
        el.srcObject = mosaic.mediaStream;
        await el.play().catch(() => undefined);
      }
      await el.requestPictureInPicture?.();
      setDocPipOpen(true);
    } catch {
      manualPipRef.current = false;
      mosaic.stop();
      toast("Pop-out is blocked here — the meeting keeps running in this tab");
    }
  }, [meeting?.title, ensureMosaic]);

  /** Close whichever pop-out is active (Document PiP or video PiP). */
  const closeMeetingPip = useCallback((): void => {
    const win = docPipWindowRef.current;
    docPipWindowRef.current = null;
    pipTilesRef.current.clear();
    if (win && !win.closed) win.close();
    manualPipRef.current = false;
    if (document.pictureInPictureElement) {
      void document.exitPictureInPicture?.().catch(() => undefined);
    }
    pipMosaicRef.current?.stop();
    setDocPipOpen(false);
  }, []);

  /** Host-only: broadcast a kick; the target's own client leaves itself. */
  const kickParticipant = useCallback((p: LiveParticipantInfo) => {
    if (!isHost || p.peerId === rtcRef.current?.localPeerId) return;
    rtcRef.current?.sendAppEvent("meeting-kick", {
      targetUserId: p.userId,
      targetPeerId: p.peerId,
    });
    rtcRef.current?.forgetParticipant(p.peerId);
    toast(`Removed ${p.name} from the meeting`);
  }, [isHost]);

  // ── Google-Meet-grammar controls — same wire names as the iOS call service ──
  const selfHandKey = (user?.id ?? rtcRef.current?.localPeerId ?? "guest").toLowerCase();
  const myHandUp = !!raisedHands[selfHandKey];

  const toggleHand = useCallback((): void => {
    const rtc = rtcRef.current;
    if (!rtc) return;
    const up = !raisedHands[selfHandKey];
    rtc.sendAppEvent("call-hand", { up, userId: selfHandKey, byName: selfName });
    setRaisedHands((current) => {
      const next = { ...current };
      if (up) next[selfHandKey] = selfName;
      else delete next[selfHandKey];
      return next;
    });
  }, [raisedHands, selfHandKey, selfName]);

  const sendReaction = useCallback(
    (emoji: string): void => {
      if (!roomPolicy.reactions && !isHost) {
        toast("Reactions are turned off by the host");
        return;
      }
      rtcRef.current?.sendAppEvent("call-react", { emoji, byName: selfName });
      pushFloatingReaction(emoji, selfName);
    },
    [isHost, pushFloatingReaction, roomPolicy.reactions, selfName],
  );

  const sendRoomChat = useCallback(
    (text: string): void => {
      if (!roomPolicy.chat && !isHost) return;
      const msgId = `${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
      const at = Date.now();
      rtcRef.current?.sendAppEvent("call-chat", { id: msgId, text, byName: selfName, at });
      setRoomChat((current) => [...current.slice(-199), { id: msgId, name: selfName, text, at, self: true }]);
    },
    [isHost, roomPolicy.chat, selfName],
  );

  const muteEveryone = useCallback((): void => {
    rtcRef.current?.sendAppEvent("call-mute-all", { byName: selfName });
    toast("Everyone was asked to mute");
  }, [selfName]);

  const mutePeer = useCallback((p: MeetPanelParticipant): void => {
    rtcRef.current?.sendAppEvent("call-mute", { targetUserId: p.id.toLowerCase() });
    toast(`Asked ${p.username} to mute`);
  }, []);

  const updatePolicy = useCallback(
    (patch: Partial<{ chat: boolean; reactions: boolean; present: boolean; quickAccess: boolean }>): void => {
      if (currentHostIdRef.current?.toLowerCase() !== selfId.toLowerCase()) return;
      const next = { ...roomPolicyRef.current, ...patch };
      roomPolicyRef.current = next;
      setRoomPolicy(next);
      rtcRef.current?.sendAppEvent("call-policy", next);
    },
    [selfId],
  );

  // ─── Answering the door (host side) ───
  const answerKnock = useCallback((knock: MeetKnock, admit: boolean): void => {
    rtcRef.current?.sendAppEvent(admit ? "meeting-admit" : "meeting-deny", {
      knockId: knock.knockId,
      byName: selfNameRef.current,
    });
    setPendingKnocks((current) => current.filter((k) => k.knockId !== knock.knockId));
    if (admit) toast(`${knock.name} is joining`);
  }, []);
  const admitAllKnocks = useCallback((): void => {
    for (const knock of pendingKnocks) {
      rtcRef.current?.sendAppEvent("meeting-admit", { knockId: knock.knockId, byName: selfNameRef.current });
    }
    if (pendingKnocks.length > 0) toast(`Admitted ${pendingKnocks.length} ${pendingKnocks.length === 1 ? "person" : "people"}`);
    setPendingKnocks([]);
  }, [pendingKnocks]);

  const togglePanel = useCallback((tab: MeetPanelTab): void => {
    setPanelTab((current) => (current === tab ? null : tab));
  }, []);

  const toggleFullscreen = useCallback((): void => {
    if (document.fullscreenElement) {
      void document.exitFullscreen().catch(() => undefined);
    } else {
      void document.documentElement
        .requestFullscreen()
        .catch(() => toast("Full screen isn't available in this browser"));
    }
  }, []);

  useEffect(() => {
    const onChange = (): void => setIsFullscreen(!!document.fullscreenElement);
    document.addEventListener("fullscreenchange", onChange);
    return () => document.removeEventListener("fullscreenchange", onChange);
  }, []);

  // Opening the chat panel clears its unread badge.
  useEffect(() => {
    if (panelTab === "chat") setChatUnread(0);
  }, [panelTab, roomChat.length]);

  // The Settings dialog's speaker choice routes the room's audio output.
  useEffect(() => {
    if (meetPrefs.speakerId) setSinkId(meetPrefs.speakerId);
  }, [meetPrefs.speakerId]);

  // Meet keyboard shortcuts: ⌘/Ctrl+D mic · ⌘/Ctrl+E camera · ⌘/Ctrl+Alt+H hand.
  useEffect(() => {
    const onKey = (e: KeyboardEvent): void => {
      const target = e.target as HTMLElement | null;
      if (target && (target.tagName === "INPUT" || target.tagName === "TEXTAREA" || target.isContentEditable)) return;
      if (!(e.ctrlKey || e.metaKey)) return;
      const key = e.key.toLowerCase();
      if (key === "d") {
        e.preventDefault();
        void toggleMic();
      } else if (key === "e" && !isAudioCall) {
        e.preventDefault();
        void toggleCam();
      } else if (key === "h" && e.altKey) {
        e.preventDefault();
        toggleHand();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [isAudioCall, toggleCam, toggleHand, toggleMic]);

  const [clockLabel, setClockLabel] = useState<string>(() =>
    new Date().toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }),
  );
  useEffect(() => {
    const timer = window.setInterval(() => {
      setClockLabel(new Date().toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }));
    }, 15_000);
    return () => window.clearInterval(timer);
  }, []);

  // Kicked by the host → the post-call screen says so.
  useEffect(() => {
    if (!kickedOut) return;
    setKickedOut(false);
    setPostCall("removed");
  }, [kickedOut]);

  // Any post-call reason while still connected: the end ding, then the
  // engine tears down and the post-call screen takes over. (The explicit
  // leave flow tears down first and plays its own ding, so this is a no-op
  // there.)
  useEffect(() => {
    if (!postCall) return;
    if (!rtcRef.current) return;
    playMeetEndDing();
    void leave();
  }, [postCall, leave]);

  const policyHostPeerKey = participants.filter((participant) => participant.userId === hostUserId)
    .map((participant) => participant.peerId).sort().join("|");
  useEffect(() => {
    if (!joined || !policyHostPeerKey || isHost) return;
    const rtc = rtcRef.current;
    const request = (): void => { if (rtcRef.current === rtc) rtc?.sendAppEvent("present-sync-request", {}); };
    request();
    const retry = window.setTimeout(request, 1200);
    return () => window.clearTimeout(retry);
  }, [joined, policyHostPeerKey, isHost]);

  // Join / leave chimes for OTHER people — Meet's soft two-note cue. (My own
  // landing chime plays in join().) Keyed on roster presence, not connection
  // state, so an ICE blip can never re-chime.
  useEffect(() => {
    if (!joined) {
      seenPeerIdsRef.current = null;
      return;
    }
    const mine = rtcRef.current?.localPeerId ?? "";
    const ids = new Set(participants.filter((p) => p.peerId !== mine).map((p) => p.peerId));
    const prev = seenPeerIdsRef.current;
    if (prev) {
      let someoneJoined = false;
      let someoneLeft = false;
      ids.forEach((pid) => {
        if (!prev.has(pid)) someoneJoined = true;
      });
      prev.forEach((pid) => {
        if (!ids.has(pid)) someoneLeft = true;
      });
      if (someoneJoined) playMeetJoinChime();
      else if (someoneLeft) playMeetLeaveChime();
    }
    seenPeerIdsRef.current = ids;
  }, [participants, joined]);

  // HOST LIFECYCLE — Meet's rules. The owner is the host while present; when
  // they leave without ending the call, the room is handed to the longest-
  // present participant (the `call-host` wire). If that wire never arrives
  // (a crash, a closed laptop), every client elects the SAME person after a
  // short grace — the lowest userId still in the room — so the room always
  // has someone who can end it. The owner reclaims the room on return, and
  // an election only ever REPLACES a host who was here (a guest arriving
  // before the owner must not crown themselves).
  useEffect(() => {
    if (!joined || !meeting) return;
    const owner = meeting.host_id;
    const ownerHere = participants.some((p) => p.userId === owner);
    if (ownerHere) {
      hostSeenRef.current = true;
      if (actingHostId && actingHostId !== owner) setActingHostId(null);
      return;
    }
    if (!hostSeenRef.current) return;
    if (hostUserId && participants.some((p) => p.userId === hostUserId)) return;
    const timer = window.setTimeout(() => {
      const candidates = participants
        .map((p) => p.userId)
        .filter((uid): uid is string => !!uid)
        .sort();
      const elected = candidates[0];
      if (elected) setActingHostId(elected);
    }, 4000);
    return () => window.clearTimeout(timer);
  }, [participants, joined, meeting, hostUserId, actingHostId]);

  // ALONE IN THE ROOM — Meet asks "Are you still there?" after five minutes
  // alone and ends the call two minutes later if nobody answers, so an
  // abandoned room never runs forever. Anyone joining resets the clock.
  useEffect(() => {
    if (!joined || callWith || speedDateRoom || postCall) {
      setAlonePrompt(false);
      return;
    }
    const mine = rtcRef.current?.localPeerId ?? "";
    if (participants.some((p) => p.peerId !== mine)) {
      setAlonePrompt(false);
      return;
    }
    const prompt = window.setTimeout(() => {
      setAloneSecondsLeft(120);
      setAlonePrompt(true);
    }, 5 * 60_000);
    const autoLeave = window.setTimeout(() => setPostCall("alone"), 7 * 60_000);
    return () => {
      window.clearTimeout(prompt);
      window.clearTimeout(autoLeave);
    };
  }, [participants, joined, callWith, speedDateRoom, postCall, aloneEpoch]);

  // The prompt's countdown (display only — the auto-leave timer above rules).
  useEffect(() => {
    if (!alonePrompt) return;
    const tick = window.setInterval(() => {
      setAloneSecondsLeft((s) => (s > 0 ? s - 1 : 0));
    }, 1000);
    return () => window.clearInterval(tick);
  }, [alonePrompt]);

  // Google-Meet-style dock: switching browser tabs mid-meeting pops the
  // room into the mini picture-in-picture window (bottom-right); coming
  // back closes it. Manual pop-outs are respected and never auto-closed.
  // Desktop only — on phones the page goes hidden for the permission
  // prompt, the app switcher, and screen lock; auto-popping PiP there
  // just detaches the remote video mid-connect.
  useEffect(() => {
    if (!joined || !pipSupported) return;
    if (typeof window !== "undefined" && window.matchMedia("(pointer: coarse)").matches) return;
    const onVis = (): void => {
      if (document.hidden) {
        if (docPipOpen || manualPipRef.current || document.pictureInPictureElement) return;
        autoPipRef.current = true;
        openMeetingPip().catch(() => {
          autoPipRef.current = false;
        });
      } else if (autoPipRef.current) {
        autoPipRef.current = false;
        closeMeetingPip();
      }
    };
    document.addEventListener("visibilitychange", onVis);
    return () => document.removeEventListener("visibilitychange", onVis);
  }, [joined, pipSupported, docPipOpen, openMeetingPip, closeMeetingPip]);

  /** Host ends the meeting for everyone and generates the notes;
   *  everyone else simply leaves. */
  const handleEnd = async (opts: { everyone?: boolean } = {}): Promise<void> => {
    if (!id) return;
    if (speedDateRef.current) {
      // Dating rooms end on the wrap, never the meeting recap.
      await finishBlindDate(false);
      return;
    }
    setLeaveMenuOpen(false);
    const mine = rtcRef.current?.localPeerId ?? "";
    const others = participants.filter((p) => p.peerId !== mine);
    // Meet's rule: a host alone ends the meeting; a host with people in the
    // room chooses from the leave menu — "just leave" hands the room over to
    // the longest-present participant and the meeting keeps going.
    // EXCEPT a host nobody ever joined: stepping out then keeps the room
    // open, so the link they just sent still works when people click it.
    const endForEveryone =
      isHost && (opts.everyone ?? (others.length === 0 && everHadCompanyRef.current));
    if (endForEveryone) endedByMeRef.current = true;
    setEnding(true);
    if (endForEveryone) {
      rtcRef.current?.sendAppEvent("call-end", { byName: selfName });
      // Let the broadcast leave the socket before the channel drops.
      await new Promise((resolve) => setTimeout(resolve, 280));
    } else if (isHost && others[0]?.userId) {
      const successor = others[0];
      rtcRef.current?.sendAppEvent("call-host", {
        userId: successor.userId,
        name: successor.name,
        byName: selfName,
      });
      await new Promise((resolve) => setTimeout(resolve, 200));
    }
    playMeetEndDing();
    await leave();
    if (!endForEveryone) {
      setEnding(false);
      setPostCall("left");
      return;
    }
    try { await endMeeting(id); }
    catch (error) { toast.error(error instanceof Error ? error.message : "Couldn't confirm the shared room ended."); }
    setPostCall(null);
    setEnding(false);
    setGenerating(true);
    await transcriptFinalizationRef.current;
    const finalSession = await supabase.auth.getSession();
    if (!user || finalSession.data.session?.user.id !== user.id) { setGenerating(false); return; }
    try { await flushTranscriptOutbox(user.id); }
    catch { setGenerating(false); toast('Meeting ended. Some speech is still waiting to save; refresh the transcript before generating notes.'); return; }
    const result = await generateMeetingNotes(id).catch((error: unknown) => { toast.error(error instanceof Error ? error.message : 'Notes could not be prepared.'); return ({
      summary: null,
      segmentCount: -1,
    }); });
    setGenerating(false);
    setNotes(result.summary);
    if (!result.summary) {
      toast(
        result.segmentCount === 0
          ? "No saved transcript is available yet. Some captured speech may still be waiting to save; refresh the original meeting notes."
          : "Meeting ended. AI notes couldn't be generated or saved. Reopen the original meeting notes and retry before relying on the recap.",
      );
    }
    // Sharing and prospect updates require an explicit action after review.
    // Recruiter hosts: finalize Jasper's pitch deck from the FULL
    // transcript — replaces the mid-meeting draft, persists to the deck
    // table, and surfaces on the notes screen. Fire-and-forget so the
    // recap never waits on it.
    if (user && profile?.is_recruiter) {
      const recruiterName = profile.username ?? "";
      setDeckBusy(true);
      void (async () => {
        try {
          const segs = await fetchTranscript(id);
          const full = segs
            .map((s) => `${s.username || "speaker"}: ${s.text}`)
            .join("\n");
          if (full.length >= 300) {
            const finalDeck = await generatePitchDeck({
              meetingId: id,
              meetingTitle: meeting?.title ?? "Meeting",
              transcript: full,
              recruiterUsername: recruiterName,
              prospectHint: evalHintRef.current,
            });
            if (finalDeck) {
              setPitchDeck(finalDeck);
              await savePitchDeck(finalDeck);
            }
          }
        } catch {
          /* the mid-meeting draft (if any) still stands */
        } finally {
          setDeckBusy(false);
        }
      })();
    }
    setEnding(false);
    void meetingQuery.refetch();
    void transcriptQuery.refetch();
  };

  /** Build (or rebuild) Jasper's pitch deck from the saved transcript. */
  const buildDeckNow = useCallback(async (): Promise<void> => {
    if (!id || deckBusy) return;
    setDeckBusy(true);
    try {
      const segs = await fetchTranscript(id);
      const full = segs
        .map((s) => `${s.username || "speaker"}: ${s.text}`)
        .join("\n");
      if (full.length < 200) {
        toast("Not enough conversation was captured to build a deck yet.");
        return;
      }
      const built = await generatePitchDeck({
        meetingId: id,
        meetingTitle: meeting?.title ?? "Meeting",
        transcript: full,
        recruiterUsername: profile?.username ?? "",
        prospectHint: evalHintRef.current,
      });
      if (built) {
        // The inline deck appears right where the build card was.
        setPitchDeck(built);
        void savePitchDeck(built);
      } else {
        toast.error("Jasper couldn't build the deck right now — try again.");
      }
    } finally {
      setDeckBusy(false);
    }
  }, [id, deckBusy, meeting?.title, profile?.username]);

  const copyLink = (): void => {
    void navigator.clipboard.writeText(invitationLink);
    toast("Meeting link copied — paste it in any chat to share");
  };

  /** Invite by email from the room — the Calendar-grade invite (Join button,
   *  joining info, .ics) through the backend, never a bare mailto. */
  const sendInviteEmail = async (): Promise<void> => {
    const email = inviteEmail.trim();
    if (!isLikelyEmail(email) || inviteEmailBusy || !meeting) return;
    setInviteEmailBusy(true);
    try {
      const inviter = profile?.username ? `@${profile.username}` : "Someone";
      const result = await sendMeetingInviteEmails({
        emails: [email],
        title: meeting.title || "Meeting",
        link: invitationLink,
        hostUsername: profile?.username ?? meeting.host_username,
        startsAt: meeting.status === "scheduled" ? meeting.scheduled_at : null,
        code: meetingId && !isMeetingUuid(meetingId) ? meetingId : null,
        note:
          meeting.status === "scheduled"
            ? `${inviter} invited you to a Whisper Meet.`
            : `${inviter} is inviting you to a Whisper Meet that's happening right now.`,
      });
      if (result.ok) {
        toast.success(`Invite emailed to ${email}`);
        setInviteEmail("");
      } else if (result.error === "not_configured") {
        toast.error("Email invites aren't set up on this deployment yet — copy the link instead.");
      } else if (result.error === "sign_in_required") {
        toast.error("Sign in to send email invites.");
      } else {
        toast.error("Couldn't send the invite — try again.");
      }
    } catch {
      toast.error("Couldn't send the invite — try again.");
    } finally {
      setInviteEmailBusy(false);
    }
  };

  /** Email the finished notes through the backend — a branded, formatted
   *  Whisper email (Resend), not a bare mailto dump. */
  const sendNotesEmail = async (): Promise<void> => {
    if (!id || !meeting || !notes || notesEmailSending) return;
    const emails = notesEmails
      .split(/[\n,;]+/)
      .map((e) => e.trim())
      .filter((e) => /.+@.+\..+/.test(e));
    if (emails.length === 0) {
      toast.error("Add at least one email address.");
      return;
    }
    setNotesEmailSending(true);
    try {
      const { data } = await supabase.auth.getSession();
      const token = data.session?.access_token ?? "";
      const res = await fetch(`${BACKEND_URL}/meetings/notes-email`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        body: JSON.stringify({
          meetingId: meetingId,
          link: invitationLink,
          title: meeting.title,
          hostUsername: profile?.username ?? meeting.host_username,
          notes,
          emails,
          // The FULL transcript always rides along with the notes.
          transcript: (transcriptQuery.data ?? [])
            .map((s) => `${s.username || "Speaker"}: ${s.text}`)
            .join("\n"),
        }),
      });
      const result = (await res.json()) as {
        ok?: boolean;
        sent?: number;
        error?: string;
      };
      if (!res.ok || !result.ok) {
        if (result.error === "not_configured") {
          // Email isn't wired on this deployment — fall back to the mail app.
          window.location.href = `mailto:?subject=${encodeURIComponent(`Meeting notes — ${meeting.title}`)}&body=${encodeURIComponent(notesDmText(meeting.title, notes, invitationLink).slice(0, 1800))}`;
          setNotesEmailOpen(false);
          return;
        }
        throw new Error(result.error ?? "send_failed");
      }
      const count = result.sent ?? emails.length;
      toast.success(
        `Notes emailed to ${count} recipient${count === 1 ? "" : "s"}`,
      );
      setNotesEmailOpen(false);
      setNotesEmails("");
    } catch {
      toast.error("Couldn't send the email — try again.");
    } finally {
      setNotesEmailSending(false);
    }
  };

  /** Send a meeting invite DM to a user — the link renders as a rich
   *  "Join meeting" card in their inbox (DmEmbedCard detects the URL). */
  const sendInvite = async (toUserId: string, toUsername: string): Promise<void> => {
    if (!user || !id) return;
    setInviting(true);
    try {
      await sendMessage(
        user.id,
        profile?.username ?? "you",
        toUserId,
        toUsername,
        invitationLink,
      );
      toast.success(`Invite sent to @${toUsername}`);
    } catch {
      toast.error(`Couldn't invite @${toUsername} — try again`);
    } finally {
      setInviting(false);
    }
  };

  const toggleScreenShare = async (): Promise<void> => {
    const rtc = rtcRef.current;
    if (!rtc) return;
    if (rtc.isScreenSharing || rtc.isStartingScreenShare) {
      await rtc.stopScreenShare();
      if (rtcRef.current !== rtc) return;
      setSharing(rtc.isScreenSharing);
    } else {
      if (!roomPolicyRef.current.present && currentHostIdRef.current?.toLowerCase() !== selfId.toLowerCase()) {
        toast("The host has turned screen sharing off.");
        return;
      }
      if (rtc.isChangingScreenShare) return;
      const ok = await rtc.startScreenShare();
      if (rtcRef.current !== rtc) return;
      setSharing(rtc.isScreenSharing);
      if (!ok) {
        toast("Screen share was cancelled or isn't available.");
      } else if (pipSupported && !docPipOpen) {
        toast("Sharing your screen", {
          description: "Pop out the meeting to keep everyone visible on other tabs.",
          action: { label: "Pop out", onClick: () => void openMeetingPip() },
          duration: 9000,
        });
      }
    }
  };

  if (meetingQuery.isLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <Loader2 className="h-7 w-7 animate-spin text-muted-foreground" />
      </div>
    );
  }

  // Blind dates need an account (cards, decisions, the match) — a rose
  // sign-in door instead of the guest-name form.
  if (!user && speedDateRoom) {
    if (authLoading) {
      return (
        <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-[#290611] via-[#4C0F26] to-[#230409]">
          <Loader2 className="h-7 w-7 animate-spin text-white/70" />
        </div>
      );
    }
    return (
      <div className="flex min-h-screen flex-col items-center justify-center gap-4 bg-gradient-to-br from-[#290611] via-[#4C0F26] to-[#230409] px-6 text-center text-white">
        <EmberMascot
          size={92}
          palette={{ accent: "#F5B8CC", softAccent: "#FFEDF2", deepAccent: "#E68FAD" }}
          smitten
          expression="delighted"
        />
        <p className="text-[11px] font-black uppercase tracking-[0.28em] text-rose-300">Blind date</p>
        <h1 className="text-[26px] font-black leading-tight">
          You've been invited
          <br />
          to a blind date 💘
        </h1>
        <p className="mx-auto max-w-[330px] text-[13px] leading-snug text-white/70">
          Sign in to Whisper to step in — your dating card, the reveal, and the
          match all live on your account.
        </p>
        <div className="w-full max-w-xs">
          <a
            href={`/welcome?next=${encodeURIComponent(`/meet/${meetingId}?sd=1`)}`}
            className="flex h-12 w-full items-center justify-center rounded-full bg-gradient-to-r from-rose-500 to-pink-500 text-[15px] font-black text-white shadow-xl shadow-rose-500/30 transition-transform active:scale-95"
          >
            Sign in to join 💘
          </a>
          <OpenInAppButton invitationLink={invitationLink} idOrCode={meetingId} speedDate tone="rose" />
        </div>
      </div>
    );
  }

  if (!user && !guestReady) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center gap-5 px-6 text-center">
        <span className="flex h-16 w-16 items-center justify-center rounded-3xl bg-foreground text-background">
          <Video className="h-7 w-7" />
        </span>
        <div>
          <h1 className="text-[22px] font-extrabold">Join this meeting</h1>
          <p className="mt-1 max-w-sm text-[13.5px] text-muted-foreground">
            Enter a name to join as a guest — or sign in for captions, AI
            notes, and your meeting history.
          </p>
        </div>
        <form
          onSubmit={(e) => {
            e.preventDefault();
            const name = guestDraft.trim().slice(0, 40);
            if (!name) return;
            setGuestName(name);
            try {
              localStorage.setItem("whisper_guest_name", name);
            } catch {
              /* storage unavailable */
            }
            setGuestReady(true);
          }}
          className="flex w-full max-w-xs flex-col gap-2.5"
        >
          <input
            value={guestDraft}
            onChange={(e) => setGuestDraft(e.target.value)}
            placeholder="Your name"
            autoFocus
            maxLength={40}
            className="h-12 rounded-full border border-border bg-card px-5 text-center text-[15px] outline-none transition-colors focus:border-foreground/50"
          />
          <button
            type="submit"
            disabled={!guestDraft.trim()}
            className="h-12 rounded-full bg-foreground text-sm font-bold text-background transition-opacity disabled:opacity-40"
          >
            Join as guest
          </button>
        </form>
        <a
          href={`/welcome?next=${encodeURIComponent(`/meet/${meetingId}` + (invitationLink ? new URL(invitationLink).search : ""))}`}
          className="text-[13.5px] font-bold text-foreground underline-offset-4 hover:underline"
        >
          Sign in to Whisper instead
        </a>
        <div className="w-full max-w-xs">
          <OpenInAppButton invitationLink={invitationLink} idOrCode={meetingId} speedDate={false} />
        </div>
      </div>
    );
  }

  if (!meetingAccessReady) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <Loader2 className="h-7 w-7 animate-spin text-muted-foreground" />
      </div>
    );
  }

  // Real database failures get truthful copy — never a fake "not found".
  if (meetingQuery.isError) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center gap-4 px-6 text-center">
        <span className="flex h-14 w-14 items-center justify-center rounded-3xl bg-amber-500/15 text-amber-500">
          <AlertTriangle className="h-6 w-6" />
        </span>
        <div>
          <h1 className="text-[19px] font-extrabold">Can't open this meeting</h1>
          <p className="mx-auto mt-1.5 max-w-sm text-[13px] leading-relaxed text-muted-foreground">
            {meetingQuery.error instanceof Error
              ? meetingQuery.error.message
              : "Something went wrong loading the meeting."}
          </p>
        </div>
        <div className="flex gap-2.5">
          <Button className="rounded-full" onClick={() => void meetingQuery.refetch()}>
            <RefreshCw className="h-4 w-4" />
            Try again
          </Button>
          <Button
            variant="outline"
            className="rounded-full"
            onClick={() => exitTo("/meetings")}
          >
            {user ? "Back to meetings" : "Leave"}
          </Button>
        </div>
      </div>
    );
  }

  if (!meeting) {
    // The join RPC found the meeting but it has ENDED (and this database
    // keeps ended rows unreadable for non-members). The link is still
    // real — offer to start it again instead of a false "not found".
    if (user && joinRefusal === "unavailable") {
      return (
        <div className="flex min-h-screen flex-col items-center justify-center gap-4 px-6 text-center">
          <span className="flex h-14 w-14 items-center justify-center rounded-3xl bg-secondary text-foreground">
            <Video className="h-6 w-6" />
          </span>
          <div>
            <p className="text-lg font-bold">This meeting has ended</p>
            <p className="mx-auto mt-1.5 max-w-sm text-[13px] leading-relaxed text-muted-foreground">
              The link is still good — start it again and everyone with the link can join you.
            </p>
          </div>
          <div className="flex gap-2.5">
            <Button className="rounded-full" onClick={() => void startAgain()} disabled={reopening}>
              {reopening ? <Loader2 className="h-4 w-4 animate-spin" /> : <Video className="h-4 w-4" />}
              Start it again
            </Button>
            <Button variant="outline" className="rounded-full" onClick={() => exitTo(homePath)}>
              {speedDateRoom ? "Back to Dating" : "Back to meetings"}
            </Button>
          </div>
        </div>
      );
    }
    // A code room with no row yet — a guest beat every signed-in member
    // here — or a GUEST on a uuid link (their read waits on the host) — or
    // a signed-in member still inside the grace window. The query above
    // keeps polling; the room opens on its own. A dead "Meeting not found"
    // is reserved for signed-in members on a uuid that truly has no row.
    if (isCodeRoom || !user || !graceOver) {
      const opening = !!user && !isCodeRoom;
      return (
        <div className="flex min-h-screen flex-col items-center justify-center gap-4 px-6 text-center">
          <Loader2 className="h-7 w-7 animate-spin text-muted-foreground" />
          <div>
            <p className="text-lg font-bold">{opening ? "Opening the meeting…" : "Waiting for this room to open"}</p>
            <p className="mx-auto mt-1.5 max-w-sm text-[13px] leading-relaxed text-muted-foreground">
              {opening
                ? "One moment — checking the room."
                : "You're in the right place — the room unlocks the moment the host (or any signed-in member) joins from their side. Keep this tab open."}
            </p>
          </div>
          <div className="w-full max-w-xs">
            <Button
              variant="outline"
              className="w-full rounded-full"
              onClick={() => exitTo(homePath)}
            >
              {user ? (speedDateRoom ? "Back to Dating" : "Back to meetings") : "Leave"}
            </Button>
            <OpenInAppButton invitationLink={invitationLink} idOrCode={meetingId} speedDate={speedDateRoom} />
          </div>
        </div>
      );
    }
    return (
      <div className="flex min-h-screen flex-col items-center justify-center gap-3 px-6 text-center">
        <p className="text-lg font-bold">Meeting not found</p>
        <p className="mx-auto max-w-sm text-[13px] leading-relaxed text-muted-foreground">
          This link doesn't point at a meeting anymore — it may have been deleted,
          or the link was copied incompletely.
        </p>
        <Button className="rounded-full" onClick={() => exitTo(homePath)}>
          {speedDateRoom ? "Back to Dating" : "Back to meetings"}
        </Button>
      </div>
    );
  }

  // ─── Ended: the full-screen notes experience — the exact same screen the
  //     Meetings list opens, with the room's extras riding along below. ───────
  if (postCall) {
    // Meet's post-call page — rendered inside the room shell so the exit
    // never flashes the lobby first. Hosts who END the call for everyone go
    // to the notes recap instead (postCall stays null on that path).
    return (
      <MeetPostCallScreen
        reason={postCall}
        byName={endedByRef.current}
        title={meeting.title}
        canRejoin={postCall !== "host-ended" && postCall !== "removed" && !endedByMeRef.current && !ending && !generating && !leaving && recordingCapture.state.update?.state !== "saving"}
        onRejoin={() => {
          setPostCall(null);
          setAlonePrompt(false);
          setAloneEpoch((n) => n + 1);
        }}
        onHome={() => exitTo(MEET_PORTAL ? "/" : callWith ? "/messages" : "/meetings")}
        onNotebook={user ? () => exitTo(`/notebook?portal=workspace&meeting=${encodeURIComponent(id ?? "")}`) : undefined}
        onRate={() => toast("Rating noted for this visit")}
      />
    );
  }

  if (hasEnded || notes || generating) {
    return (
      <div>
        {hasEnded && !endedByMeRef.current && !generating && user && (
          <div className="pointer-events-none fixed inset-x-0 top-[max(0.75rem,env(safe-area-inset-top))] z-[60] flex justify-center px-4">
            <div className="pointer-events-auto flex items-center gap-2 rounded-full border border-border bg-card/95 py-1.5 pl-4 pr-1.5 shadow-xl backdrop-blur">
              <span className="text-[12.5px] font-semibold text-muted-foreground">This meeting has ended</span>
              <button
                type="button"
                onClick={() => void startAgain()}
                disabled={reopening}
                className="flex h-8 items-center gap-1.5 rounded-full bg-foreground px-3.5 text-[12.5px] font-bold text-background transition-opacity hover:opacity-90 disabled:opacity-50"
              >
                {reopening ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Video className="h-3.5 w-3.5" />}
                Start it again
              </button>
            </div>
          </div>
        )}
        <MeetingNotesScreen
          meetingId={id}
          title={meeting.title}
          notes={notes}
          loading={generating}
          subtitle={transcriptFinishing ? 'Call ended · finishing captured speech. Keep this tab open.' : undefined}
          onClose={() => exitTo("/meetings")}
          footnote={
            isHost && notes
              ? "This is the original shared recap. Private Jasper additions stay separate below."
              : undefined
          }
          emptyContent={
            <div className="rounded-3xl border border-dashed border-border p-10 text-center">
              <p className="text-[14px] font-semibold text-muted-foreground">
                No notes were generated for this meeting.
              </p>
              {isHost && (
                <Button
                  variant="outline"
                  className="mt-4 rounded-full"
                  disabled={transcriptFinishing}
                  onClick={async () => {
                    if (user) { try { await flushTranscriptOutbox(user.id); } catch { toast.error('Some speech is still waiting to save. Refresh the transcript first.'); return; } }
                    setGenerating(true);
                    const result = await generateMeetingNotes(meeting.id).catch(() => ({
                      summary: null,
                      segmentCount: -1,
                    }));
                    setGenerating(false);
                    setNotes(result.summary);
                    if (!result.summary) {
                      toast(
                        result.segmentCount === 0
                          ? "No saved speech was returned yet. Refresh to check for late transcript uploads."
                          : "Notes couldn't be generated right now — the transcript below is still saved.",
                      );
                    }
                  }}
                >
                  <Sparkles className="h-4 w-4" />
                  Try generating notes
                </Button>
              )}
            </div>
          }
          actions={
            <div className="grid grid-cols-3 gap-2 pt-0.5">
                <button
                  type="button"
                  onClick={() => setShowNotesShare(true)}
                  className="flex h-11 items-center justify-center gap-1.5 rounded-full bg-foreground text-[12.5px] font-bold text-background transition-opacity hover:opacity-90"
                >
                  <Send className="h-3.5 w-3.5" />
                  Send via DM
                </button>
                <button
                  type="button"
                  onClick={() => {
                    if (user) {
                      setNotesEmailOpen(true);
                    } else {
                      window.location.href = `mailto:?subject=${encodeURIComponent(`Meeting notes — ${meeting.title}`)}&body=${encodeURIComponent(notesDmText(meeting.title, notes, invitationLink).slice(0, 1800))}`;
                    }
                  }}
                  className="flex h-11 items-center justify-center gap-1.5 rounded-full border border-border text-[12.5px] font-bold transition-colors hover:bg-accent"
                >
                  <Mail className="h-3.5 w-3.5" />
                  Email
                </button>
                <button
                  type="button"
                  onClick={() => {
                    void navigator.clipboard?.writeText(
                      notesDmText(meeting.title, notes, invitationLink, transcriptPlainText(transcriptQuery.data ?? [])),
                    );
                    toast("Notes copied");
                  }}
                  className="flex h-11 items-center justify-center gap-1.5 rounded-full border border-border text-[12.5px] font-bold transition-colors hover:bg-accent"
                >
                  <Copy className="h-3.5 w-3.5" />
                  Copy
                </button>
            </div>
          }
        >
          {/* Recruiter-only: Jasper's pitch deck — the close plan, living
              right IN the notes as an inline flip-through notebook. */}
          {!!profile?.is_recruiter && !generating && (
            <div className="mt-7">
              <div className="mb-2.5 flex items-center gap-2">
                <NotebookPen className="h-4 w-4 text-muted-foreground" />
                <p className="text-[12px] font-bold uppercase tracking-wider text-muted-foreground">
                  Jasper's pitch deck
                </p>
              </div>
              {pitchDeck ? (
                <PitchDeckInline deck={pitchDeck} />
              ) : (
                <div
                  className="flex items-center gap-3 rounded-3xl p-4"
                  style={{
                    background: "#FBF7EC",
                    border: "1px solid rgba(14,159,118,0.35)",
                    boxShadow: "0 14px 40px rgba(0,0,0,0.18)",
                    animation: "ember-pop-in 360ms cubic-bezier(0.34, 1.3, 0.64, 1) both",
                  }}
                >
                  <EmberMascot size={40} coachMode={loadCoachMode()} isActive={deckBusy} expression="calm" />
                  <div className="min-w-0 flex-1">
                    <p className="text-[14px] font-extrabold leading-tight" style={{ color: "#20242B" }}>
                      Build the close plan
                    </p>
                    <p className="mt-0.5 text-[11.5px] leading-snug" style={{ color: "#5C5A50" }}>
                      {deckBusy
                        ? "Jasper is building the deck from the transcript…"
                        : "Jasper turns this meeting into a pitch deck — the prospect's interests, close odds, and your plan. It appears right here."}
                    </p>
                  </div>
                  <button
                    type="button"
                    onClick={() => void buildDeckNow()}
                    disabled={deckBusy}
                    className="flex h-9 shrink-0 items-center gap-1.5 rounded-full px-4 text-[12px] font-black text-white transition-transform active:scale-95 disabled:opacity-50"
                    style={{ background: "#0E9F76" }}
                  >
                    {deckBusy ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : null}
                    {deckBusy ? "Building…" : "Build deck"}
                  </button>
                </div>
              )}
            </div>
          )}

          {/* Recruiter-only: Jasper's full prospect evaluation from the call. */}
          {!!profile?.is_recruiter && !generating && (
            <div className="mt-7">
              <div className="mb-2.5 flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <TrendingUp className="h-4 w-4 text-muted-foreground" />
                  <p className="text-[12px] font-bold uppercase tracking-wider text-muted-foreground">
                    Prospect evaluation
                  </p>
                </div>
                <button
                  type="button"
                  onClick={() => void runFinalEval()}
                  disabled={finalEvalBusy}
                  className="flex items-center gap-1.5 rounded-full border border-border px-3 py-1.5 text-[11px] font-bold transition-colors hover:bg-accent disabled:opacity-50"
                >
                  {finalEvalBusy ? (
                    <Loader2 className="h-3 w-3 animate-spin" />
                  ) : (
                    <RefreshCw className="h-3 w-3" />
                  )}
                  {finalEval ? "Re-run" : "Generate"}
                </button>
              </div>
              {finalEval ? (
                <div
                  className="overflow-hidden rounded-3xl border border-cyan-300/25 bg-zinc-950 p-5 text-white shadow-[0_18px_50px_rgba(0,0,0,0.35)]"
                  style={{ animation: "ember-pop-in 360ms cubic-bezier(0.34, 1.3, 0.64, 1) both" }}
                >
                  <div className="flex items-center gap-1.5">
                    <Sparkles className="h-3.5 w-3.5 text-cyan-300" />
                    <p className="text-[9px] font-black uppercase tracking-[0.14em] text-cyan-200">
                      Jasper's read on this prospect
                    </p>
                  </div>
                  <div className="mt-3 flex items-center gap-4">
                    <p className="text-[44px] font-black leading-none">
                      {finalEval.score}
                      <span className="ml-1 text-[13px] font-bold text-white/40">/100</span>
                    </p>
                    <div className="min-w-0 flex-1">
                      <div className="h-2 overflow-hidden rounded-full bg-white/10">
                        <div
                          className="h-full rounded-full transition-[width] duration-700"
                          style={{
                            width: `${Math.min(100, Math.max(4, finalEval.score))}%`,
                            background: scoreColor(finalEval.score),
                          }}
                        />
                      </div>
                      <p className="mt-1.5 text-[10px] font-bold uppercase tracking-wide text-white/45">
                        {finalEval.confidence}% confidence · recruiting potential
                      </p>
                    </div>
                  </div>
                  <div className="mt-4">
                    <p className="mb-1.5 text-[9px] font-black uppercase tracking-[0.12em] text-white/40">
                      Recommended placement
                    </p>
                    <PlacementChips placement={finalEval.placement} />
                  </div>
                  <p className="mt-3.5 text-[13.5px] leading-relaxed text-white/90">
                    {finalEval.summary}
                  </p>
                  {finalEval.strengths.length > 0 && (
                    <div className="mt-4">
                      <p className="mb-1.5 text-[9px] font-black uppercase tracking-[0.12em] text-emerald-300/80">
                        Strengths
                      </p>
                      <ul className="space-y-1">
                        {finalEval.strengths.map((s, i) => (
                          <li key={i} className="flex items-start gap-2 text-[12.5px] leading-snug text-white/85">
                            <Check className="mt-0.5 h-3.5 w-3.5 shrink-0 text-emerald-300" />
                            {s}
                          </li>
                        ))}
                      </ul>
                    </div>
                  )}
                  {finalEval.concerns.length > 0 && (
                    <div className="mt-3">
                      <p className="mb-1.5 text-[9px] font-black uppercase tracking-[0.12em] text-amber-300/80">
                        Watch-outs
                      </p>
                      <ul className="space-y-1">
                        {finalEval.concerns.map((c, i) => (
                          <li key={i} className="flex items-start gap-2 text-[12.5px] leading-snug text-white/85">
                            <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0 text-amber-300" />
                            {c}
                          </li>
                        ))}
                      </ul>
                    </div>
                  )}
                  <p className="mt-4 text-center text-[9.5px] font-bold uppercase tracking-[0.12em] text-white/30">
                    Only visible to you
                  </p>
                </div>
              ) : (
                <div className="rounded-2xl border border-dashed border-border p-6 text-center">
                  <p className="text-[13px] leading-relaxed text-muted-foreground">
                    No live read was captured during this call. Generate one from the
                    transcript to score this prospect and get a placement recommendation.
                  </p>
                </div>
              )}
            </div>
          )}

          {/* Raw transcript — who said what, even when AI notes are missing. */}
          <div className="mt-7">
            <div className="mb-2.5 flex items-center justify-between">
              <div className="flex items-center gap-2">
                <Captions className="h-4 w-4 text-muted-foreground" />
                <p className="text-[12px] font-bold uppercase tracking-wider text-muted-foreground">
                  Transcript
                </p>
              </div>
              {(transcriptQuery.data?.length ?? 0) > 0 && (
                <span className="text-[11.5px] font-semibold text-muted-foreground">
                  {transcriptQuery.data!.length} segment
                  {transcriptQuery.data!.length === 1 ? "" : "s"}
                </span>
              )}
            </div>
            {transcriptQuery.isLoading ? (
              <div className="flex justify-center rounded-3xl border border-border py-10">
                <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
              </div>
            ) : (transcriptQuery.data?.length ?? 0) === 0 ? (
              <div className="rounded-2xl border border-dashed border-border p-6 text-center">
                <p className="text-[13px] leading-relaxed text-muted-foreground">
                  No speech was captured during this meeting. Captions record only
                  while your own microphone is on.
                </p>
              </div>
            ) : (
              <div className="max-h-[26rem] space-y-3 overflow-y-auto rounded-3xl border border-border bg-card p-5">
                {transcriptQuery.data!.map((segment) => (
                  <div key={segment.id}>
                    <p className="text-[12px] font-bold">
                      @{segment.username || "speaker"}
                      {segment.spoken_at && (
                        <span className="ml-2 font-medium text-muted-foreground">
                          {new Date(segment.spoken_at).toLocaleTimeString([], {
                            hour: "numeric",
                            minute: "2-digit",
                          })}
                        </span>
                      )}
                    </p>
                    <p className="mt-0.5 text-[13.5px] leading-relaxed text-foreground/90">
                      {segment.text}
                    </p>
                  </div>
                ))}
              </div>
            )}
          </div>

        </MeetingNotesScreen>

        {/* Branded email share — recipients get formatted Whisper notes. */}
        {notesEmailOpen && notes && (
          <div
            className="fixed inset-0 z-[80] flex items-start justify-center overflow-y-auto bg-black/30 p-4 pt-[14vh] backdrop-blur-[2px]"
            onClick={() => setNotesEmailOpen(false)}
          >
            <div
              className="w-full max-w-[420px] rounded-[28px] border border-border bg-card p-6 shadow-[0_20px_70px_rgba(0,0,0,0.15)]"
              onClick={(event) => event.stopPropagation()}
            >
              <div className="flex items-center justify-between">
                <p className="text-[17px] font-extrabold">Email the notes</p>
                <button
                  type="button"
                  onClick={() => setNotesEmailOpen(false)}
                  className="flex h-9 w-9 items-center justify-center rounded-full bg-secondary transition-colors hover:bg-secondary/70"
                  aria-label="Close"
                >
                  <X className="h-4 w-4" />
                </button>
              </div>
              <p className="mt-1 text-[12.5px] text-muted-foreground">
                Recipients get a branded Whisper email with the formatted
                notes and a link back to the meeting.
              </p>
              <textarea
                value={notesEmails}
                onChange={(e) => setNotesEmails(e.target.value)}
                placeholder="name@example.com, teammate@company.com"
                rows={3}
                autoFocus
                className="mt-3 w-full resize-none rounded-2xl border border-border bg-background px-4 py-3 text-[14px] outline-none transition-colors focus:border-foreground"
              />
              <button
                type="button"
                onClick={() => void sendNotesEmail()}
                disabled={notesEmailSending}
                className="mt-3 flex h-12 w-full items-center justify-center gap-2 rounded-full bg-foreground font-bold text-background transition-all active:scale-[0.98] disabled:opacity-50"
              >
                {notesEmailSending ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <Mail className="h-4 w-4" />
                )}
                {notesEmailSending ? "Sending…" : "Send notes"}
              </button>
            </div>
          </div>
        )}

        {/* Send-notes-via-DM picker. */}
        {showNotesShare && notes && (
          <div
            className="fixed inset-0 z-[80] flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm"
            onClick={() => setShowNotesShare(false)}
          >
            <div
              className="flex h-full max-h-[560px] w-full max-w-sm flex-col overflow-hidden rounded-[24px] border border-border bg-card shadow-2xl"
              onClick={(event) => event.stopPropagation()}
            >
              <div className="flex items-center justify-between border-b border-border px-4 py-3">
                <div className="flex items-center gap-2">
                  <Send className="h-4 w-4" />
                  <p className="text-[15px] font-bold">Send notes via DM</p>
                </div>
                <button
                  type="button"
                  onClick={() => setShowNotesShare(false)}
                  className="flex h-7 w-7 items-center justify-center rounded-full text-muted-foreground transition-colors hover:bg-accent"
                  aria-label="Close"
                >
                  <X className="h-4 w-4" />
                </button>
              </div>
              <div className="border-b border-border px-4 py-2.5">
                <div className="flex items-center gap-2 rounded-full bg-secondary px-3.5 py-2">
                  <Search className="h-4 w-4 shrink-0 text-muted-foreground" />
                  <input
                    value={inviteQuery}
                    onChange={(event) => setInviteQuery(event.target.value)}
                    placeholder="Search people…"
                    className="min-w-0 flex-1 bg-transparent text-[14px] outline-none placeholder:text-muted-foreground"
                  />
                </div>
              </div>
              <div className="flex-1 overflow-y-auto py-1">
                {followingQuery.isLoading ? (
                  <div className="flex justify-center py-10">
                    <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
                  </div>
                ) : filteredFollowing.length === 0 ? (
                  <p className="px-6 py-12 text-center text-[14px] font-semibold text-muted-foreground">
                    {following.length === 0
                      ? "Follow people to send them the notes."
                      : "No one matches your search."}
                  </p>
                ) : (
                  filteredFollowing.map((f) => (
                    <button
                      key={f.userId}
                      type="button"
                      onClick={() => void sendNotesDm(f.userId, f.username)}
                      disabled={notesSending}
                      className="flex w-full items-center gap-3 px-4 py-2.5 text-left transition-colors hover:bg-accent disabled:opacity-50"
                    >
                      <Avatar
                        url={f.profile?.profile_image_url ?? null}
                        name={f.username}
                        size={40}
                      />
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-[14px] font-bold">
                          {f.profile?.display_name || f.username}
                        </p>
                        <p className="truncate text-[12px] text-muted-foreground">
                          @{f.username}
                        </p>
                      </div>
                      <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-foreground text-background">
                        <Send className="h-3.5 w-3.5" />
                      </span>
                    </button>
                  ))
                )}
              </div>
            </div>
          </div>
        )}
      </div>
    );
  }

  // ─── Pre-join lobby ────────────────────────────────────────────────────────
  // Blind date wrap — the decision + Jasper's recap after a date, never the
  // meeting recap (it renders over the lobby the room falls back to).
  if (blindWrap && user) {
    return (
      <BlindDateWrap
        roomKey={blindRecordKey(id ?? "")}
        userId={user.id}
        myName={profile?.username ?? "you"}
        myAvatarUrl={profile?.profile_image_url}
        partnerUserId={blindWrap.partnerUserId}
        partnerName={blindWrap.partnerName}
        partnerAvatarUrl={blindWrap.partnerAvatarUrl}
        transcript={blindWrap.transcript}
        theirCard={blindWrap.theirCard}
        revealed={blindWrap.revealed}
        partnerLeft={blindWrap.partnerLeft}
        elapsedSec={blindWrap.elapsedSec}
        onClose={() => exitTo("/c/dating")}
      />
    );
  }

  if (!joined) {
    // The Join click → the room: one honest setup screen instead of a lobby
    // that looks frozen while devices and the connection come up. Blind
    // dates keep their own rose flow.
    if (joinBusy && !speedDateRoom) {
      return (
        <JoinSetupScreen
          title={meeting?.title ?? (callWith ? "Your call" : "Meeting")}
          audioOnly={isAudioCall}
        />
      );
    }
    // 1:1 calls skip the lobby — a connecting screen while auto-join runs.
    if (callWith && !lobbyBlocked) {
      return (
        <div className="flex min-h-screen flex-col items-center justify-center gap-5 px-6 text-center">
          <span className="relative flex h-24 w-24 items-center justify-center">
            <span className="call-ring" aria-hidden />
            <span className="call-ring" style={{ animationDelay: "0.6s" }} aria-hidden />
            <span className="flex h-16 w-16 items-center justify-center rounded-3xl bg-foreground text-background">
              <PhoneCall className="h-7 w-7" />
            </span>
          </span>
          <div>
            <h1 className="text-[20px] font-extrabold">{meeting.title}</h1>
            <p className="mt-1 text-[13px] text-muted-foreground">
              {joinBusy ? "Connecting your call…" : "Starting the call…"}
            </p>
          </div>
          <div className="flex gap-2.5">
            {!joinBusy && (
              <Button
                className="h-11 rounded-full px-6 font-bold"
                onClick={() => void join("full")}
              >
                <PhoneCall className="h-4 w-4" />
                Connect now
              </Button>
            )}
            <Button
              variant="outline"
              className="h-11 rounded-full px-5"
              onClick={() => exitTo("/messages")}
            >
              Cancel
            </Button>
          </div>
        </div>
      );
    }
    // ─── The blind-date pre-join — the rose screen, never the generic lobby.
    //     Entering marks me ready (the room's handshake), so the in-room
    //     welcome takeover is skipped and the curtain stage opens directly.
    if (speedDateRoom) {
      const myCard = user ? loadDatingCardLocal(user.id) : null;
      const cardReady = !!myCard && hasDatingCard(myCard);
      const paired = blindPairedPartner(id ?? "");
      return (
        <div className="relative flex min-h-screen flex-col items-center overflow-y-auto bg-gradient-to-br from-[#290611] via-[#4C0F26] to-[#230409] px-5 pb-8 pt-[max(1rem,env(safe-area-inset-top))] text-white">
          <div className="flex w-full max-w-md flex-1 flex-col">
            <div className="flex items-center justify-between">
              <button
                type="button"
                onClick={() => exitTo("/c/dating")}
                className="flex h-10 w-10 items-center justify-center rounded-full bg-white/10 transition-colors hover:bg-white/20"
                aria-label="Back to Dating"
              >
                <X className="h-4.5 w-4.5" />
              </button>
              <button
                type="button"
                onClick={copyLink}
                className="flex h-10 items-center gap-2 rounded-full bg-white/10 px-4 text-[13px] font-bold transition-colors hover:bg-white/20"
              >
                <Copy className="h-3.5 w-3.5" />
                Copy invite
              </button>
            </div>

            <div className="mt-6 flex flex-col items-center text-center">
              <EmberMascot
                size={96}
                palette={{ accent: "#F5B8CC", softAccent: "#FFEDF2", deepAccent: "#E68FAD" }}
                smitten
                expression="delighted"
              />
              <p className="mt-4 text-[11px] font-black uppercase tracking-[0.28em] text-rose-300">
                Blind date
              </p>
              <h1 className="mt-1 text-[26px] font-black leading-tight">
                {paired ? (
                  <>
                    It's a date with
                    <br />@{paired} 💘
                  </>
                ) : isHost ? (
                  <>
                    Your blind date
                    <br />
                    is set up 💘
                  </>
                ) : (
                  <>
                    You've been invited
                    <br />
                    to a blind date 💘
                  </>
                )}
              </h1>
              <p className="mx-auto mt-2 max-w-[330px] text-[13px] leading-snug text-white/70">
                Five minutes, face to face. You'll hear each other first — cameras stay
                behind the curtain until you both reveal (or at the two-minute mark).
                Jasper hosts with prompts built from both your cards.
              </p>
            </div>

            <div className="mt-5 grid grid-cols-3 gap-2">
              {[
                ["🎧", "Voices first", "Cameras stay hidden"],
                ["⏱", "5 minutes", "One shared clock"],
                ["💘", "Reveal together", "Or at 2:00"],
              ].map(([glyph, title, sub]) => (
                <div key={title} className="rounded-2xl bg-white/[0.08] px-2.5 py-3 text-center">
                  <p className="text-[18px] leading-none">{glyph}</p>
                  <p className="mt-1.5 truncate text-[11.5px] font-black">{title}</p>
                  <p className="mt-0.5 truncate text-[10px] text-white/55">{sub}</p>
                </div>
              ))}
            </div>

            <div className="mt-4 flex items-center justify-between gap-3 rounded-2xl bg-white/10 px-4 py-3">
              <div className="min-w-0">
                <p className="truncate text-[13px] font-bold">
                  {cardReady ? "✓ Your dating card is ready" : "No dating card yet"}
                </p>
                <p className="truncate text-[11px] text-white/60">
                  Jasper builds the prompts from both cards.
                </p>
              </div>
              <button
                type="button"
                onClick={() => setRoomCardEditor(true)}
                className="shrink-0 whitespace-nowrap rounded-full border border-white/25 bg-white/10 px-3.5 py-2 text-[12.5px] font-bold transition-transform active:scale-95"
              >
                {cardReady ? "Edit card" : "Fill my card"}
              </button>
            </div>

            <div className="mt-5 flex items-center justify-center gap-8">
              <button
                type="button"
                onClick={() => {
                  const next = !joinPrefMic;
                  joinPrefMicRef.current = next;
                  setJoinPrefMic(next);
                }}
                className="flex flex-col items-center gap-1.5"
                aria-pressed={!joinPrefMic}
                aria-label={joinPrefMic ? "Join with mic on" : "Join muted"}
              >
                <span
                  className={cn(
                    "flex h-14 w-14 items-center justify-center rounded-full transition-colors",
                    joinPrefMic ? "bg-white text-[#4C0F26]" : "bg-red-500 text-white",
                  )}
                >
                  {joinPrefMic ? <Mic className="h-5 w-5" /> : <MicOff className="h-5 w-5" />}
                </span>
                <span className="text-[11px] font-bold text-white/70">
                  {joinPrefMic ? "Mic on" : "Mic off"}
                </span>
              </button>
              <button
                type="button"
                onClick={() => {
                  const next = !joinPrefCam;
                  joinPrefCamRef.current = next;
                  setJoinPrefCam(next);
                }}
                className="flex flex-col items-center gap-1.5"
                aria-pressed={!joinPrefCam}
                aria-label={joinPrefCam ? "Camera ready for the reveal" : "Camera off"}
              >
                <span
                  className={cn(
                    "flex h-14 w-14 items-center justify-center rounded-full transition-colors",
                    joinPrefCam ? "bg-white text-[#4C0F26]" : "bg-red-500 text-white",
                  )}
                >
                  {joinPrefCam ? <Video className="h-5 w-5" /> : <VideoOff className="h-5 w-5" />}
                </span>
                <span className="text-[11px] font-bold text-white/70">
                  {joinPrefCam ? "Camera for reveal" : "Camera off"}
                </span>
              </button>
            </div>

            {lobbyBlocked && (
              <p className="mt-4 rounded-2xl bg-white/10 px-4 py-2.5 text-center text-[12px] text-white/80">
                Allow your microphone and camera in the browser, then try again.
              </p>
            )}

            <div className="mt-auto pt-6">
              <button
                type="button"
                disabled={joinBusy}
                onClick={() => {
                  if (id) markBlindReady(id);
                  blindRef.current.myReady = true;
                  void join("full");
                }}
                className="flex h-13 w-full items-center justify-center gap-2 rounded-full bg-gradient-to-r from-rose-500 to-pink-500 py-3.5 text-[15px] font-black text-white shadow-xl shadow-rose-500/30 transition-transform active:scale-95 disabled:opacity-60"
              >
                {joinBusy && <Loader2 className="h-4 w-4 animate-spin" />}
                {lobbyBlocked ? "Try again" : "Enter the date 💘"}
              </button>
              <OpenInAppButton invitationLink={invitationLink} idOrCode={meetingId} speedDate tone="rose" />
              <p className="mt-3 text-center text-[11px] text-white/45">
                Your side of the conversation is transcribed so Jasper can write the recap.
                Only the two of you ever see it.
              </p>
            </div>
          </div>
          {user && (
            <DatingCardEditor
              open={roomCardEditor}
              onOpenChange={setRoomCardEditor}
              userId={user.id}
              onSaved={() => {
                // Re-encode on join so the fresh card rides the wire.
                myDatingWireRef.current = null;
              }}
            />
          )}
        </div>
      );
    }

    const isScheduled = meeting.status === "scheduled";
    const scheduledLabel = meeting.scheduled_at
      ? new Date(meeting.scheduled_at).toLocaleString([], {
          month: "short",
          day: "numeric",
          hour: "numeric",
          minute: "2-digit",
        })
      : null;
    return (
      <div className="flex min-h-screen flex-col items-center bg-background px-5 pb-8 pt-[max(1rem,env(safe-area-inset-top))]">
        <div className="flex w-full max-w-md flex-1 flex-col md:max-w-lg">
          <div className="flex items-center justify-between">
            <button
              type="button"
              onClick={() => exitTo(homePath)}
              className="flex h-10 w-10 items-center justify-center rounded-full bg-secondary transition-colors hover:bg-accent"
              aria-label="Leave lobby"
            >
              <X className="h-4.5 w-4.5" />
            </button>
            <button
              type="button"
              onClick={copyLink}
              className="flex h-10 items-center gap-2 rounded-full bg-secondary px-4 text-[13px] font-bold transition-colors hover:bg-accent"
            >
              <Copy className="h-3.5 w-3.5" />
              Copy link
            </button>
          </div>

          <div className="mt-5 text-center">
            <p className="text-[10.5px] font-black uppercase tracking-[0.22em] text-muted-foreground">
              Ready when you are
            </p>
            <h1 className="mt-1.5 text-[24px] font-extrabold leading-tight">{meeting.title}</h1>
            <p className="mt-1 text-[13px] text-muted-foreground">
              Hosted by @{meeting.host_username}
            </p>
          </div>

          {isScheduled && (
            <div className="mt-3 flex flex-wrap items-center justify-center gap-x-2 gap-y-1 self-center rounded-full border border-border bg-card px-4 py-2 text-[12.5px] font-semibold">
              <CalendarClock className="h-4 w-4 text-muted-foreground" />
              <span>{scheduledLabel ? `Scheduled · ${scheduledLabel}` : "Scheduled"}</span>
              <span className="font-medium text-muted-foreground">
                {isHost ? "— joining starts it for everyone" : "— the host hasn't started it yet"}
              </span>
            </div>
          )}

          {!isAudioCall && (
            <div className="relative mt-5 min-h-[240px] flex-1 overflow-hidden rounded-[28px] border border-border bg-[#0b0b0c]">
              {joinPrefCam && (
                <video
                  ref={lobbyVideoRef}
                  autoPlay
                  playsInline
                  muted
                  className={cn(
                    "absolute inset-0 h-full w-full -scale-x-100 object-cover transition-opacity",
                    lobbyCamState === "ready" ? "opacity-100" : "opacity-0",
                  )}
                />
              )}
              {(!joinPrefCam || lobbyCamState !== "ready") && (
                <div className="absolute inset-0 flex flex-col items-center justify-center gap-2 px-8 text-center">
                  {joinPrefCam && lobbyCamState === "loading" ? (
                    <Loader2 className="h-6 w-6 animate-spin text-white/40" />
                  ) : (
                    <>
                      <VideoOff className="h-7 w-7 text-white/45" />
                      <p className="text-[14px] font-bold text-white">
                        {joinPrefCam ? "Camera unavailable" : "Camera off"}
                      </p>
                      <p className="text-[12px] text-white/50">
                        {joinPrefCam
                          ? "Your browser blocked the camera. Try again — it will ask permission — or allow it in site settings."
                          : "You'll join without video — flip it back on anytime."}
                      </p>
                      {joinPrefCam && (
                        <button
                          type="button"
                          onClick={() => setLobbyCamRetry((n) => n + 1)}
                          className="mt-1 flex items-center gap-1.5 rounded-full bg-white/15 px-4 py-2 text-[12px] font-bold text-white transition-colors hover:bg-white/25"
                        >
                          <RotateCw className="h-3.5 w-3.5" />
                          Try camera again
                        </button>
                      )}
                    </>
                  )}
                </div>
              )}
              <span className="absolute left-1/2 top-3 -translate-x-1/2 rounded-full bg-black/55 px-3 py-1 text-[12px] font-bold text-white backdrop-blur-md">
                @{profile?.username ?? selfName}
              </span>
              <span className="absolute bottom-3 left-3 flex items-center gap-1.5 rounded-full bg-black/55 px-3 py-1.5 text-[10px] font-black uppercase tracking-[0.08em] text-white backdrop-blur-md">
                <User className="h-3 w-3" />
                {fxMode === "none" ? "No effect" : fxMode === "blur" ? "Blur" : "Backdrop"}
              </span>
              <button
                type="button"
                onClick={() => setEffectsOpen(true)}
                className="absolute bottom-3 right-3 flex h-11 w-11 items-center justify-center rounded-full bg-black/55 text-white backdrop-blur-md transition-colors hover:bg-black/75"
                aria-label="Backgrounds & effects"
              >
                <Wand2 className="h-4.5 w-4.5" />
              </button>
            </div>
          )}

          {!isAudioCall && (
            <p className="mt-3 text-center text-[12px] text-muted-foreground">
              Tap the wand to blur your background or have Jasper paint you a new one.
            </p>
          )}

          {lobbyBlocked && mediaState && (
            <div className="mt-4 w-full rounded-3xl border border-amber-500/25 bg-amber-500/[0.06] p-4 text-left">
              <div className="flex items-center gap-2">
                <AlertTriangle className="h-4 w-4 shrink-0 text-amber-500" />
                <p className="text-[13.5px] font-bold">Camera & microphone unavailable</p>
              </div>
              <ul className="mt-2 space-y-1.5 text-[12.5px] leading-relaxed text-muted-foreground">
                <li>{describeMediaBlock(mediaState.audioError ?? "unknown", "microphone")}</li>
                <li>{describeMediaBlock(mediaState.videoError ?? "unknown", "camera")}</li>
              </ul>
              {isEmbedded && (
                <button
                  type="button"
                  onClick={() => window.open(window.location.href, "_blank", "noopener")}
                  className="mt-3 flex w-full items-center justify-center gap-2 rounded-full bg-foreground py-2.5 text-[13px] font-bold text-background transition-opacity hover:opacity-90"
                >
                  <ExternalLink className="h-4 w-4" />
                  Open in a browser tab
                </button>
              )}
              <button
                type="button"
                onClick={() => {
                  // A fresh full join from THIS click re-runs the device
                  // request on a real user gesture — Safari re-prompts here
                  // where the automatic attempt was silently denied.
                  setLobbyBlocked(false);
                  void requestToJoin("full");
                }}
                disabled={joinBusy || knockState !== null}
                className="mt-3 flex w-full items-center justify-center gap-2 rounded-full bg-foreground py-2.5 text-[13px] font-bold text-background transition-opacity hover:opacity-90 disabled:opacity-60"
              >
                <RotateCw className="h-4 w-4" />
                Try camera & mic again
              </button>
              <button
                type="button"
                onClick={() => void requestToJoin("listen")}
                disabled={joinBusy || knockState !== null}
                className="mt-2 flex w-full items-center justify-center gap-2 rounded-full border border-border py-2.5 text-[13px] font-bold transition-colors hover:bg-accent disabled:opacity-60"
              >
                <Headphones className="h-4 w-4" />
                Join listen-only
              </button>
            </div>
          )}

          <div className="mt-4 flex items-start justify-center gap-8">
            <button
              type="button"
              onClick={() => {
                const next = !joinPrefMic;
                joinPrefMicRef.current = next;
                setJoinPrefMic(next);
              }}
              className="flex flex-col items-center gap-1.5"
              aria-pressed={!joinPrefMic}
              aria-label={joinPrefMic ? "Join with mic on" : "Join muted"}
            >
              <span
                className={cn(
                  "flex h-14 w-14 items-center justify-center rounded-full transition-colors",
                  joinPrefMic ? "bg-foreground text-background" : "bg-red-500 text-white",
                )}
              >
                {joinPrefMic ? <Mic className="h-5 w-5" /> : <MicOff className="h-5 w-5" />}
              </span>
              <span className="text-[11px] font-bold text-muted-foreground">
                {joinPrefMic ? "Mic on" : "Mic off"}
              </span>
            </button>
            {!isAudioCall && (
              <button
                type="button"
                onClick={() => {
                  const next = !joinPrefCam;
                  joinPrefCamRef.current = next;
                  setJoinPrefCam(next);
                }}
                className="flex flex-col items-center gap-1.5"
                aria-pressed={!joinPrefCam}
                aria-label={joinPrefCam ? "Join with camera on" : "Join with camera off"}
              >
                <span
                  className={cn(
                    "flex h-14 w-14 items-center justify-center rounded-full transition-colors",
                    joinPrefCam ? "bg-foreground text-background" : "bg-red-500 text-white",
                  )}
                >
                  {joinPrefCam ? <Video className="h-5 w-5" /> : <VideoOff className="h-5 w-5" />}
                </span>
                <span className="text-[11px] font-bold text-muted-foreground">
                  {joinPrefCam ? "Camera on" : "Camera off"}
                </span>
              </button>
            )}
          </div>

          <div className="mt-5">
            {knockState ? (
              <MeetAskingToJoin
                state={knockState}
                hostName={knockHostName}
                onCancel={cancelKnock}
                onRetry={() => {
                  cancelKnock();
                  window.setTimeout(() => void requestToJoin("full"), 50);
                }}
              />
            ) : (
              <Button
                className="h-12 w-full rounded-full font-bold"
                onClick={() => void requestToJoin("full")}
                disabled={joinBusy}
              >
                {joinBusy ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <Video className="h-4 w-4" />
                )}
                {lobbyBlocked
                  ? "Try again"
                  : isHost && isScheduled
                    ? "Start meeting"
                    : !user
                      ? "Ask to join"
                      : "Join meeting"}
              </Button>
            )}
            {!knockState && !user && (
              <p className="mt-2 text-center text-[11.5px] text-muted-foreground">
                Guests ask to join — the host lets you in.
              </p>
            )}
          </div>
          <OpenInAppButton invitationLink={invitationLink} idOrCode={meetingId} speedDate={false} />
          <p className="mt-3 text-center text-[11px] text-muted-foreground">
            Your own speech is transcribed during the call to create shared AI notes. Everyone sees the caption indicator when notes are active.
          </p>
        </div>

        <BackgroundsPanel
          open={effectsOpen}
          mode={fxMode}
          imageUrl={fxImage}
          onClose={() => setEffectsOpen(false)}
          onSelect={(m, url) => void applyVideoEffect(m, url)}
          previewTrack={() => videoFx.outputTrack ?? lobbyStreamRef.current?.getVideoTracks()[0] ?? null}
        />
      </div>
    );
  }

  // ─── In-call ───────────────────────────────────────────────────────────────

  // Screen shares always win. Manual focus is next, then the remote person
  // currently speaking. The local camera stays stable in a PIP rather than
  // jumping into the stage as the user talks.
  const localPeerId = rtcRef.current?.localPeerId ?? "";
  const selfParticipant = participants.find((p) => p.peerId === localPeerId)
    ?? participants.find((p) => p.name === "You")
    ?? null;
  const remoteParticipantsAll = participants.filter((p) => p.peerId !== selfParticipant?.peerId);
  // "Hide tiles without video" (Adjust view) — never hides the whole room.
  const remoteWithVideo = remoteParticipantsAll.filter((p) => p.hasVideo || p.isScreenSharing);
  const remoteParticipants =
    meetPrefs.hideNoVideo && remoteWithVideo.length > 0 ? remoteWithVideo : remoteParticipantsAll;
  const screenSharer = remoteParticipants.find((p) => p.isScreenSharing) ?? null;
  const manuallyPinned = spotlightId
    ? remoteParticipants.find((p) => p.peerId === spotlightId) ?? null
    : null;
  const activeSpeaker = remoteParticipants.find((p) => p.isSpeaking) ?? null;
  const focusedParticipant = screenSharer ?? manuallyPinned ?? activeSpeaker ?? remoteParticipants[0] ?? selfParticipant;
  // Layout preference: Spotlight/Sidebar always feature someone; Tiled never
  // auto-features (even with one guest); Auto keeps the original behaviour.
  const layoutFeatures = meetPrefs.layout === "spotlight" || meetPrefs.layout === "sidebar";
  const spotlightParticipant =
    screenSharer ??
    manuallyPinned ??
    (meetPrefs.layout === "tiled"
      ? null
      : (remoteParticipants.length === 1 || (layoutFeatures && remoteParticipants.length > 0))
        ? focusedParticipant
        : null);
  const stageParticipants = remoteParticipants.filter((p) => p.peerId !== spotlightParticipant?.peerId);
  const focusedPeerId = focusedParticipant?.peerId ?? null;
  const avatarUrlFor = (participant: LiveParticipantInfo): string | null =>
    profileMap[participant.name.toLowerCase()]?.profile_image_url ?? null;
  const panelParticipants: MeetPanelParticipant[] = participants.map((p) => ({
    id: p.userId,
    peerId: p.peerId,
    username: p.name,
    avatarUrl: avatarUrlFor(p),
    isSelf: p.peerId === localPeerId,
    isHost: !!meeting && p.userId === meeting.host_id,
    micOn: p.micOn,
    camOn: p.hasVideo,
    handRaised: !!raisedHands[p.userId.toLowerCase()],
    isSpeaking: p.isSpeaking,
  }));
  const raisedNames = Object.values(raisedHands);
  const readyCardVisible =
    isHost && remoteParticipantsAll.length === 0 && !readyCardDismissed && !speedDateRoom && !callWith && !emberPanelOpen;
  const emberModeInfo = coachModeInfo(emberMode);
  /** The phone-shaped mini profile docks inside the presenter's frame — the
   *  presenter's own copy floats above the controls instead. */
  const presentedFor = (
    p: LiveParticipantInfo | null | undefined,
  ): PresentedClientPayload | null =>
    presentation &&
    p &&
    p.userId === presentation.presenterUserId &&
    presentation.presenterUserId !== user?.id
      ? presentation
      : null;
  /** Seconds since the last live-read refresh (re-rendered by the eval tick). */
  const evalAgo = liveEval
    ? Math.max(0, Math.round((evalNow - liveEval.updatedAt) / 1000))
    : null;

  return (
    <div data-meeting-stage="" className="fixed inset-0 z-40 isolate flex h-[100dvh] flex-col overflow-hidden overscroll-none bg-[color:var(--meet-stage)] text-[color:var(--meet-ink)]">
      {/* Every remote voice, independent of the tiles (see RemoteAudioSink). */}
      <div className="pointer-events-none fixed bottom-0 right-0 h-0 w-0 overflow-hidden opacity-0" aria-hidden="true">
        {remoteParticipantsAll.map((p) => (
          <RemoteAudioSink key={p.peerId} stream={p.remoteStream} sinkId={sinkId} />
        ))}
      </div>
      {!speedDateRoom && <div className="pointer-events-none absolute left-3 right-3 top-[max(4rem,calc(env(safe-area-inset-top)+3.5rem))] z-40 flex justify-center"><MeetingRecordingControls session={recordingCapture.session} state={recordingCapture.state} isHost={isHost} open={recordingOpen && !minimized} onOpenChange={openRecording} asPanel meetingId={id} onBack={() => { setRecordingOpen(false); setActivitiesOpen(true); }} /></div>}
      {/* Hidden browser PiP element for screen-share continuation. */}
      <video
        ref={pipVideoRef}
        className="pointer-events-none fixed bottom-0 right-0 h-0 w-0 opacity-0"
        playsInline
        muted
      />

      {/* Meet's top bar — flat on the stage: minimize · clock | title · ⓘ on the
          left; role tools · invite · people (count) · your account on the right. */}
      <header className="pointer-events-none absolute inset-x-0 top-0 z-30 px-2 pt-[max(0.375rem,env(safe-area-inset-top))] sm:px-4">
        <div className="pointer-events-auto flex h-12 items-center justify-between gap-3">
          <div className="flex min-w-0 items-center gap-1">
            <button
              type="button"
              onClick={minimizeToTile}
              className="grid h-10 w-10 shrink-0 place-items-center rounded-full text-[color:var(--meet-ink-soft)] transition-colors hover:bg-[color:var(--meet-ink-faint)] hover:text-[color:var(--meet-ink)]"
              aria-label="Minimize call"
              title="Minimize — the call keeps going"
            >
              <ChevronDown className="h-5 w-5" />
            </button>
            <span className="hidden shrink-0 pl-1 text-[14px] font-medium text-[color:var(--meet-ink)] sm:inline">{clockLabel}</span>
            <span className="hidden px-1.5 text-[color:var(--meet-divider)] sm:inline">|</span>
            <MeetingTitleButton meeting={meeting} owner={user?.id} />
            <button
              type="button"
              onClick={() => togglePanel("details")}
              className={cn(
                "grid h-9 w-9 shrink-0 place-items-center rounded-full text-[color:var(--meet-ink-soft)] transition-colors hover:bg-[color:var(--meet-ink-faint)] hover:text-[color:var(--meet-ink)]",
                panelTab === "details" && "bg-[color:var(--meet-ink-faint-2)] text-[color:var(--meet-ink)]",
              )}
              aria-label="Meeting details"
              title="Meeting details"
            >
              <Info className="h-[18px] w-[18px]" />
            </button>
          </div>
          <div className="flex shrink-0 items-center gap-0.5">
            {!speedDate && <button type="button" onClick={() => setActivitiesOpen(true)} className="flex h-11 items-center gap-2 rounded-full px-3 text-xs font-medium text-[color:var(--meet-ink)] hover:bg-[color:var(--meet-ink-faint)]" aria-label="Meeting tools"><LayoutGrid className="h-4 w-4" /><span className="hidden sm:inline">Tools</span></button>}
            <button
              type="button"
              onClick={() => setShowInvite(true)}
              className="grid h-10 w-10 place-items-center rounded-full text-[color:var(--meet-ink)] transition-colors hover:bg-[color:var(--meet-ink-faint)]"
              aria-label="Invite people"
              title="Add others"
            >
              <UserPlus className="h-[18px] w-[18px]" />
            </button>
            <button
              type="button"
              onClick={() => togglePanel("people")}
              className={cn(
                "relative grid h-10 w-10 place-items-center rounded-full text-[color:var(--meet-ink)] transition-colors hover:bg-[color:var(--meet-ink-faint)]",
                panelTab === "people" && "bg-[color:var(--meet-ink-faint-2)]",
              )}
              aria-label={`People · ${participants.length}`}
              title="People"
            >
              <Users className="h-[18px] w-[18px]" />
              <span className="absolute -right-0.5 top-0 grid h-[17px] min-w-[17px] place-items-center rounded-full bg-[color:var(--meet-ink)] px-1 text-[10px] font-bold text-[color:var(--meet-stage)]">
                {participants.length}
              </span>
              {isDoorkeeper && pendingKnocks.length > 0 && (
                <span className="absolute -left-0.5 top-0 h-2.5 w-2.5 rounded-full bg-[#a8c7fa] ring-2 ring-[color:var(--meet-stage)]" />
              )}
            </button>
            <span className="ml-1 hidden sm:block" title={selfName}>
              <Avatar
                url={user && profile?.username ? profileMap[profile.username.toLowerCase()]?.profile_image_url ?? null : null}
                name={selfName}
                size={30}
              />
            </span>
          </div>
        </div>
      </header>

      <MeetingWorkspace open={!minimized && notebookOpen} drawer={user && id && <MeetingSidekick docked key={`${user.id}:${id}`} owner={user.id} meetingID={id} title={meeting?.title ?? "Meeting"} visible={!minimized && notebookOpen} captureStatus={!micOn ? "Your microphone is muted" : sidekickCaptureStatus} interim={micOn ? sidekickInterim : ""} onRetryCapture={() => { if (transcriptionPausedRef.current) { toast('Finish your private Jasper voice question before restarting meeting transcription.'); return; } if (!micOn) { toast("Unmute your microphone to transcribe your speech."); return; } void flushTranscriptOutbox(user.id).catch(() => toast('Captured speech is still waiting to save.')); void stopTranscription().then(() => startTranscription()); }} onHide={() => setNotebookOpen(false)} />}>
      <main data-recording-stage className={cn("h-full min-h-0 w-full", (activitiesOpen || recordingOpen) && "lg:pr-[390px] xl:pr-[390px]")}>
        {spotlightParticipant ? (
          <div className="flex h-full min-h-0 flex-col gap-3 lg:flex-row">
            <div className="min-h-0 flex-1">
              <Tile
                participant={spotlightParticipant}
                stream={spotlightParticipant.remoteStream}
                bpm={isCoach ? heartRates[spotlightParticipant.userId] ?? null : null}
                badge={badgeMap[spotlightParticipant.name.toLowerCase()] ?? "none"}
                profileMap={profileMap}
                avatarUrl={avatarUrlFor(spotlightParticipant)}
                isSpotlight
                isFocused={spotlightParticipant.peerId === focusedPeerId}
                aspect="fit"
                onPin={() => setSpotlightId(null)}
                onKick={
                  isHost && spotlightParticipant.peerId !== localPeerId
                    ? () => kickParticipant(spotlightParticipant)
                    : undefined
                }
                presentedClient={presentedFor(spotlightParticipant)}
                onExpandPresentation={() => setPresentationExpanded(true)}
              />
            </div>
            {stageParticipants.length > 0 && (
              <div className="flex h-28 shrink-0 gap-2 overflow-x-auto pb-1 lg:h-full lg:w-56 lg:flex-col lg:overflow-y-auto lg:overflow-x-hidden xl:w-64">
                {stageParticipants.map((participant) => (
                  <div key={participant.peerId} className="h-full w-36 shrink-0 lg:h-32 lg:w-full xl:h-36">
                    <Tile
                      participant={participant}
                      stream={participant.remoteStream}
                      bpm={isCoach ? heartRates[participant.userId] ?? null : null}
                      badge={badgeMap[participant.name.toLowerCase()] ?? "none"}
                      profileMap={profileMap}
                      avatarUrl={avatarUrlFor(participant)}
                      isFocused={participant.peerId === focusedPeerId}
                      compact
                      aspect="fill"
                      onPin={() => setSpotlightId((current) => current === participant.peerId ? null : participant.peerId)}
                      onKick={isHost ? () => kickParticipant(participant) : undefined}
                      presentedClient={presentedFor(participant)}
                      onExpandPresentation={() => setPresentationExpanded(true)}
                    />
                  </div>
                ))}
              </div>
            )}
          </div>
        ) : remoteParticipants.length === 0 ? (
          <div className="mx-auto flex h-full w-full max-w-6xl items-center justify-center">
            {selfParticipant && sharing ? (
              <div className="h-full w-full max-w-2xl">
                <SelfPresentingCard onStop={() => void toggleScreenShare()} />
              </div>
            ) : selfParticipant ? (
              <Tile
                participant={selfParticipant}
                stream={selfParticipant.remoteStream}
                bpm={null}
                badge="none"
                profileMap={profileMap}
                isSelf
                aspect="fit"
                presentedClient={presentedFor(selfParticipant)}
                onExpandPresentation={() => setPresentationExpanded(true)}
              />
            ) : (
              <div className="flex h-full w-full items-center justify-center rounded-3xl border border-[color:var(--meet-ink-faint)] bg-[color:var(--meet-ink-faint)] text-sm font-semibold text-[color:var(--meet-ink-soft)]">
                Starting your camera…
              </div>
            )}
          </div>
        ) : (
          <StageGrid
            participants={remoteParticipants}
            maxTiles={meetPrefs.maxTiles}
            renderTile={(participant) => (
              <div className="h-full w-full min-h-0">
                <Tile
                  participant={participant}
                  stream={participant.remoteStream}
                  bpm={isCoach ? heartRates[participant.userId] ?? null : null}
                  badge={badgeMap[participant.name.toLowerCase()] ?? "none"}
                  profileMap={profileMap}
                  avatarUrl={avatarUrlFor(participant)}
                  isFocused={participant.peerId === focusedPeerId}
                  aspect="fill"
                  onPin={() => setSpotlightId((current) => current === participant.peerId ? null : participant.peerId)}
                  onKick={isHost ? () => kickParticipant(participant) : undefined}
                  presentedClient={presentedFor(participant)}
                  onExpandPresentation={() => setPresentationExpanded(true)}
                />
              </div>
            )}
          />
        )}
      </main>

      {selfParticipant && remoteParticipants.length > 0 && (
        <div data-recording-dock className={cn("absolute bottom-3 right-3 z-30 w-[88px] sm:w-[112px] lg:w-[136px]", (activitiesOpen || recordingOpen) && "lg:right-[400px]", notebookOpen && "max-md:w-[60px]")}>
          {sharing ? (
            <SelfPresentingCard compact onStop={() => void toggleScreenShare()} />
          ) : (
            <Tile
              participant={selfParticipant}
              stream={selfParticipant.remoteStream}
              bpm={null}
              badge="none"
              profileMap={profileMap}
              isSelf
              compact
              aspect="portrait"
            />
          )}
        </div>
      )}

      {showCaptions && captionText && (
        <div className="pointer-events-none absolute bottom-3 left-3 right-28 z-30 rounded-2xl bg-black/75 px-3 py-2 text-center text-xs font-medium leading-relaxed text-white shadow-xl backdrop-blur-xl">
          {captionText}
        </div>
      )}

      </MeetingWorkspace>
      {user && !minimized && !emberPanelOpen && <MeetingJasperButton mode={emberMode} open={notebookOpen} draft={jasperAsk} onDraftChange={setJasperAsk} busy={emberBusy} onToggle={() => setEmberPanelOpen(true)} onSubmit={(question) => { setJasperAsk(''); void askEmber(question); }} />}

      {/* Voice auto-schedule — a spoken date became a one-tap calendar prompt. */}
      {scheduleSuggest && !scheduleOpen && (
        <div className="absolute bottom-44 left-1/2 z-40 w-[min(30rem,calc(100%-2rem))] -translate-x-1/2 sm:bottom-52">
          <div
            className="flex items-center gap-3 rounded-2xl border bg-black/80 py-2.5 pl-3 pr-2 shadow-[0_14px_40px_rgba(0,0,0,0.5)] backdrop-blur-xl"
            style={{ borderColor: `${SCHEDULE_TYPE_COLORS[scheduleSuggest.eventType]}55` }}
          >
            <span
              className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl"
              style={{
                backgroundColor: `${SCHEDULE_TYPE_COLORS[scheduleSuggest.eventType]}24`,
                color: SCHEDULE_TYPE_COLORS[scheduleSuggest.eventType],
              }}
            >
              <CalendarPlus className="h-[18px] w-[18px]" />
            </span>
            <div className="min-w-0 flex-1">
              <p className="text-[12.5px] font-bold text-white">
                Add to your shared calendar?
              </p>
              <p className="truncate text-[11px] font-medium text-white/60">
                {formatSpokenDate(scheduleSuggest.dateMs)} · {SCHEDULE_TYPE_LABELS[scheduleSuggest.eventType]}
              </p>
            </div>
            <button
              type="button"
              onClick={openScheduleModal}
              className="h-8 shrink-0 rounded-full bg-white px-3.5 text-[11.5px] font-black text-black transition-transform active:scale-95"
            >
              Add
            </button>
            <button
              type="button"
              onClick={() => setScheduleSuggest(null)}
              aria-label="Dismiss schedule suggestion"
              className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-white/55 transition-colors hover:bg-white/10"
            >
              <X className="h-3.5 w-3.5" />
            </button>
          </div>
        </div>
      )}

      {/* Schedule-from-the-call modal — confirms before anything is created. */}
      {scheduleOpen && scheduleSuggest && (
        <div className="fixed inset-0 z-[80] flex items-end justify-center bg-black/70 p-4 backdrop-blur-sm sm:items-center">
          <div className="w-full max-w-md rounded-3xl border border-white/12 bg-[#111116] p-5 shadow-2xl">
            <div className="mb-1 flex items-center justify-between">
              <h3 className="text-[15px] font-black text-white">Schedule from the call</h3>
              <button
                type="button"
                onClick={() => setScheduleOpen(false)}
                aria-label="Close"
                className="flex h-8 w-8 items-center justify-center rounded-full text-white/60 transition-colors hover:bg-white/10"
              >
                <X className="h-4 w-4" />
              </button>
            </div>
            <p className="mb-4 truncate text-[11.5px] italic text-white/45">
              “{scheduleSuggest.snippet}”
            </p>

            <label className="mb-1 block text-[10px] font-black tracking-[0.1em] text-white/45">
              TITLE
            </label>
            <input
              value={scheduleTitle}
              onChange={(e) => setScheduleTitle(e.target.value)}
              placeholder="Event title"
              className="mb-3.5 w-full rounded-xl border border-white/12 bg-white/5 px-3.5 py-2.5 text-sm font-medium text-white outline-none placeholder:text-white/30 focus:border-white/30"
            />

            <label className="mb-1 block text-[10px] font-black tracking-[0.1em] text-white/45">
              WHEN
            </label>
            <input
              type="datetime-local"
              value={scheduleWhen}
              onChange={(e) => setScheduleWhen(e.target.value)}
              className="mb-3.5 w-full rounded-xl border border-white/12 bg-white/5 px-3.5 py-2.5 text-sm font-medium text-white outline-none [color-scheme:dark] focus:border-white/30"
            />

            <label className="mb-1.5 block text-[10px] font-black tracking-[0.1em] text-white/45">
              CATEGORY · AUTO-DETECTED
            </label>
            <div className="mb-4 flex flex-wrap gap-1.5">
              {(Object.keys(SCHEDULE_TYPE_LABELS) as CalendarEventType[]).map((type) => (
                <button
                  key={type}
                  type="button"
                  onClick={() => setScheduleType(type)}
                  className={cn(
                    "flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-[11.5px] font-bold transition-colors",
                    scheduleType === type
                      ? "border-white bg-white text-black"
                      : "border-white/15 bg-white/5 text-white/75 hover:bg-white/10",
                  )}
                >
                  <span
                    className="h-1.5 w-1.5 rounded-full"
                    style={{ backgroundColor: SCHEDULE_TYPE_COLORS[type] }}
                  />
                  {SCHEDULE_TYPE_LABELS[type]}
                </button>
              ))}
            </div>

            <button
              type="button"
              onClick={() => setScheduleAttach((v) => !v)}
              className="mb-4 flex w-full items-center justify-between rounded-2xl border border-white/10 bg-white/5 px-3.5 py-3 text-left"
            >
              <span>
                <span className="block text-[13px] font-bold text-white">
                  Attach a Whisper meeting
                </span>
                <span className="block text-[11px] text-white/50">
                  A scheduled room is linked on the event — everyone joins with one tap.
                </span>
              </span>
              <span
                className={cn(
                  "relative ml-3 inline-flex h-6 w-10 shrink-0 rounded-full transition-colors",
                  scheduleAttach ? "bg-emerald-500" : "bg-white/15",
                )}
              >
                <span
                  className={cn(
                    "absolute top-0.5 h-5 w-5 rounded-full bg-white transition-transform",
                    scheduleAttach ? "translate-x-[18px]" : "translate-x-0.5",
                  )}
                />
              </span>
            </button>

            <p className="mb-4 text-[11px] leading-relaxed text-white/45">
              Goes on the shared Whisper calendar — everyone in this call is tagged
              and gets the invite card in DMs.
            </p>

            <button
              type="button"
              onClick={() => void submitSchedule()}
              disabled={scheduleBusy}
              className="flex h-12 w-full items-center justify-center gap-2 rounded-full bg-white text-[14px] font-black text-black transition-transform active:scale-[0.99] disabled:opacity-60"
            >
              {scheduleBusy ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <CalendarPlus className="h-4 w-4" />
              )}
              {scheduleBusy ? "Scheduling…" : "Add to shared calendar"}
            </button>
          </div>
        </div>
      )}

      {/* Device recovery — shown when a camera/mic is blocked, with a real retry. */}
      {mediaState && !deviceBannerDismissed &&
        ((!mediaState.hasAudio && mediaState.audioError) ||
          (!mediaState.hasVideo && mediaState.videoError)) && (
        <div className="absolute left-1/2 top-[4.6rem] z-30 w-[min(26rem,calc(100%-8rem))] -translate-x-1/2 sm:top-[5.4rem]">
          <div className="flex items-center gap-2.5 rounded-2xl border border-amber-300/20 bg-black/70 py-2 pl-3 pr-1.5 shadow-[0_10px_32px_rgba(0,0,0,0.4)] backdrop-blur-xl">
            <AlertTriangle className="h-4 w-4 shrink-0 text-amber-300" />
            <p className="min-w-0 flex-1 text-[11.5px] font-medium leading-snug text-white/85">
              {!mediaState.hasAudio && mediaState.audioError
                ? describeMediaBlock(mediaState.audioError, "microphone")
                : describeMediaBlock(mediaState.videoError, "camera")}
            </p>
            <button
              type="button"
              onClick={() => void retryDevices()}
              disabled={mediaBusy}
              className="flex h-8 shrink-0 items-center gap-1.5 rounded-full bg-white/12 px-3 text-[11px] font-bold text-white transition-colors hover:bg-white/22 disabled:opacity-60"
            >
              {mediaBusy ? (
                <Loader2 className="h-3.5 w-3.5 animate-spin" />
              ) : (
                <RefreshCw className="h-3.5 w-3.5" />
              )}
              Retry
            </button>
            {isEmbedded && (
              <button
                type="button"
                onClick={() => window.open(window.location.href, "_blank", "noopener")}
                className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-white/12 text-white transition-colors hover:bg-white/22"
                aria-label="Open the meeting in a browser tab"
                title="Open in a browser tab"
              >
                <ExternalLink className="h-3.5 w-3.5" />
              </button>
            )}
            <button
              type="button"
              onClick={() => setDeviceBannerDismissed(true)}
              className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-white/50 transition-colors hover:text-white"
              aria-label="Dismiss device warning"
            >
              <X className="h-3.5 w-3.5" />
            </button>
          </div>
        </div>
      )}

      {/* Ember — a living companion docked beside the controls. Tapping the
          ghost ALWAYS opens the ask panel (voice + typed input), the reply
          bubble is a tinted cinematic card in the active mode's hue with an
          RGB shimmer while thinking, and answers can be shared with the
          whole meeting. Private to the tapper, like Ask Gemini. */}
      {joined && user && emberPanelOpen && (
        <div
          className={cn(
            "pointer-events-none absolute z-[45] flex flex-col gap-2",
            // Phones: the mint pill centered above the controls.
            "inset-x-0 bottom-[5.75rem] items-center px-3 sm:bottom-[6.6rem]",
            // Desktop: Meet's bottom-left zone — the dock IS the Ask Jasper box,
            // sitting where Meet parks "Ask Gemini", the mascot peeking over it.
            "lg:inset-x-auto lg:bottom-[max(0.75rem,env(safe-area-inset-bottom))] lg:left-4 lg:items-start lg:px-0",
          )}
        >
          <JasperKitKeyframes />
          {emberPanelOpen && (
            <div
              className="pointer-events-auto relative mt-7 w-[min(23.75rem,calc(100vw-1.5rem))] origin-bottom lg:origin-bottom-left"
              style={{ animation: "jasper-dock-open 450ms cubic-bezier(0.34, 1.3, 0.5, 1) both" }}
            >
              {/* The living mascot peeks from BEHIND the box's top edge — the
                  same pill-to-box language as iOS (the pill floats up into the
                  header, Jasper stays peeking). On desktop he peeks from the
                  left, right where he sat over the input bar. */}
              <span className="pointer-events-none absolute -top-6 left-1/2 z-0 -translate-x-1/2 lg:left-[2.6rem]">
                {(emberBusy || emberVoice === "connecting") && (
                  <span className="ember-rgb-halo" aria-hidden />
                )}
                {(emberHearing || emberSpeaking) && (
                  <span
                    className="absolute inset-0 animate-ping rounded-full"
                    style={{ background: `${emberModeInfo.accent}2e` }}
                    aria-hidden
                  />
                )}
                <span
                  className="block"
                  style={{ animation: "jasper-mascot-bob 1.7s ease-in-out infinite" }}
                >
                  <EmberMascot
                    size={50}
                    coachMode={emberMode}
                    isActive={emberBusy || emberHearing || emberSpeaking || emberVoice === "connecting"}
                    expression={
                      emberBusy
                        ? "thinking"
                        : emberHearing
                          ? "attentive"
                          : emberSpeaking
                            ? "happy"
                            : emberError
                              ? "concerned"
                              : emberReply
                                ? emberModeInfo.signatureExpression
                                : "calm"
                    }
                  />
                </span>
              </span>
              <div
                className="relative overflow-hidden rounded-[24px] pb-2.5"
                style={jasperGlassShellStyle(emberModeInfo.accent)}
              >
                {/* MintShell header — the collapsed pill floats up into this. */}
                <div
                  className="mx-2.5 mt-2.5 flex h-9 items-center justify-between rounded-full pl-4 pr-[7px]"
                  style={jasperMintShellStyle(emberMode)}
                >
                  <span
                    className="flex min-w-0 items-center gap-1.5 truncate text-[14px] font-black"
                    style={{ color: jasperPillPalette(emberMode).ink }}
                  >
                    {emberVoice === "connecting"
                      ? "Connecting…"
                      : emberBusy
                        ? "Thinking…"
                        : emberSpeaking
                          ? "Jasper speaking"
                          : emberHearing
                            ? "Listening…"
                            : emberVoice === "live"
                              ? "Live voice"
                              : emberReply
                                ? `${emberModeInfo.shortTitle} mode`
                                : "Ask Jasper"}
                    {emberSpeaking && (
                      <AudioLines
                        className="h-3 w-3 shrink-0 animate-pulse"
                        style={{ color: emberModeInfo.deepAccent }}
                      />
                    )}
                  </span>
                  <button
                    type="button"
                    aria-label="Close Jasper"
                    className="flex h-[22px] w-[22px] shrink-0 items-center justify-center rounded-full transition-colors"
                    style={{
                      background: `${jasperPillPalette(emberMode).ink}14`,
                      color: `${jasperPillPalette(emberMode).ink}8C`,
                    }}
                    onClick={() => {
                      stopEmberVoice();
                      setEmberPanelOpen(false);
                      setEmberReply(null);
                      setEmberBlocks([]);
                      setEmberPitchOffer(false);
                      setEmberError(false);
                    }}
                  >
                    <X className="h-2.5 w-2.5" strokeWidth={3.2} />
                  </button>
                </div>
                {emberVoice === "connecting" && (
                  <p className="flex items-center gap-1.5 px-3.5 pt-1.5 text-[12px] text-white/70">
                    <Loader2 className="h-3 w-3 animate-spin" />
                    Warming up Jasper's voice…
                  </p>
                )}
                {emberUserInterim && (
                  <p className="px-3.5 pt-1.5 text-[12px] italic leading-relaxed text-white/75">
                    “{emberUserInterim}”
                  </p>
                )}
                {!emberUserInterim && emberVoice === "live" && !emberReply && !emberBusy && (
                  <p className="px-3.5 pt-1.5 text-[12px] italic leading-relaxed text-white/60">
                    {emberMicMuted ? "Mic muted — type below." : "Listening — just talk to me…"}
                  </p>
                )}
                {emberBusy && (
                  <div className="px-3 pt-2">
                    <JasperThinkingRail mode={emberMode} />
                  </div>
                )}
                {emberVoiceHint && !emberBusy && (
                  <p className="px-3.5 pt-1.5 text-[11px] leading-snug text-white/55">
                    {emberVoiceHint}
                  </p>
                )}
                {emberReply && (
                  <div className="px-3 pt-2">
                    <JasperReplyCard mode={emberMode} text={emberReply} />
                  </div>
                )}
                {emberBlocks.length > 0 && (
                  <div className="max-h-[42vh] space-y-2 overflow-y-auto px-2.5 pt-2">
                    {emberBlocks.map((block, index) => (
                      <div
                        key={`${block.kind}-${index}`}
                        style={{ animation: "ember-pop-in 300ms cubic-bezier(0.34, 1.45, 0.64, 1) both" }}
                      >
                        <EmberBlockCard block={block} />
                      </div>
                    ))}
                  </div>
                )}
                {emberPitchOffer && (
                  <button
                    type="button"
                    onClick={() => setShowPitchDeck(true)}
                    className="mx-3.5 mt-2.5 flex h-9 w-[calc(100%-1.75rem)] items-center justify-center gap-1.5 rounded-full text-[11.5px] font-bold text-slate-950 transition-opacity hover:opacity-90"
                    style={{ background: emberModeInfo.accent }}
                  >
                    <BookOpen className="h-3.5 w-3.5" />
                    Open the full pitch deck
                  </button>
                )}
                {(emberReply || emberBlocks.length > 0) && !emberBusy && (
                  <div className="mt-2 flex items-center gap-3 px-3.5">
                    {emberError && lastEmberQuestionRef.current ? (
                      <button
                        type="button"
                        className="flex items-center gap-1 text-[9.5px] font-bold uppercase tracking-wide transition-opacity hover:opacity-80"
                        style={{ color: emberModeInfo.softAccent }}
                        onClick={() => void askEmber(lastEmberQuestionRef.current)}
                      >
                        <RefreshCw className="h-3 w-3" />
                        Retry
                      </button>
                    ) : (
                      <button
                        type="button"
                        className="flex items-center gap-1 text-[9.5px] font-bold uppercase tracking-wide transition-opacity hover:opacity-80"
                        style={{ color: emberModeInfo.softAccent }}
                        onClick={shareEmberAnswer}
                      >
                        <Share2 className="h-3 w-3" />
                        Share with meeting
                      </button>
                    )}
                  </div>
                )}
                <div className="mt-2.5 flex flex-wrap items-center gap-1.5 px-3.5">
                  {user && (
                    <button
                      type="button"
                      onClick={() => startDeckTourRef.current?.()}
                      className="flex h-7 items-center gap-1 rounded-full bg-orange-500/15 px-2.5 text-[10.5px] font-bold text-orange-300 transition-colors hover:bg-orange-500/25"
                      title="Jasper reads the deck out loud to everyone"
                    >
                      <Presentation className="h-3 w-3" />
                      Walk the deck
                    </button>
                  )}
                  <button
                    type="button"
                    onClick={() => setWppOpen(true)}
                    className="flex h-7 items-center gap-1 rounded-full bg-white/10 px-2.5 text-[10.5px] font-bold text-white/85 transition-colors hover:bg-white/18"
                  >
                    <Calculator className="h-3 w-3" />
                    WPP calculator
                  </button>
                  <button
                    type="button"
                    onClick={() => setBrandCardsOpen(true)}
                    className="flex h-7 items-center gap-1 rounded-full bg-white/10 px-2.5 text-[10.5px] font-bold text-white/85 transition-colors hover:bg-white/18"
                  >
                    <Briefcase className="h-3 w-3" />
                    Brand cards
                  </button>
                </div>
                {/* Coach 1:1 — quick prompts grounded in the client's live
                    snapshot (the same data the vitals panel shows). */}
                {callWith && callVitals && (
                  <div className="no-scrollbar mt-2 flex gap-1.5 overflow-x-auto px-2.5">
                    {[
                      `How is @${callWith} trending this week?`,
                      "Readiness check for today's session",
                      "What should we train today?",
                      "Any red flags in their recovery?",
                    ].map((q) => (
                      <button
                        key={q}
                        type="button"
                        onClick={() => void askEmber(q)}
                        className="flex h-7 shrink-0 items-center gap-1 rounded-full bg-white/10 px-2.5 text-[10.5px] font-bold text-white/85 transition-colors hover:bg-white/18"
                      >
                        <Sparkles className="h-3 w-3" />
                        {q}
                      </button>
                    ))}
                  </div>
                )}
                <div className="mx-3 mt-3 rounded-2xl bg-white/10 p-3 text-xs text-white/70">Ask Jasper a question. For cited answers from saved meeting speech, open Jasper Sidekick explicitly in Tools.</div>
                <form
                  onSubmit={(event) => {
                    event.preventDefault();
                    submitEmberDraft();
                  }}
                  className="mt-2.5 flex items-center gap-1.5 px-2.5"
                >
                  <input
                    value={emberDraft}
                    onChange={(event) => setEmberDraft(event.target.value)}
                    placeholder="Ask Jasper anything…"
                    className="h-9 min-w-0 flex-1 rounded-full bg-white/10 px-3.5 text-[12px] text-white outline-none placeholder:text-white/35"
                  />
                  <button
                    type="button"
                    onClick={() => {
                      if (emberVoice === "off") {
                        startEmberVoice();
                      } else if (emberVoice === "live") {
                        const next = !emberMicMuted;
                        setEmberMicMuted(next);
                        emberSessionRef.current?.setMicEnabled(!next);
                      }
                    }}
                    aria-label={
                      emberVoice === "off"
                        ? "Start live voice"
                        : emberMicMuted
                          ? "Unmute Jasper's mic"
                          : "Mute Jasper's mic"
                    }
                    className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full transition-colors"
                    style={{
                      background:
                        emberVoice === "live" && !emberMicMuted
                          ? emberModeInfo.accent
                          : "rgba(255,255,255,0.1)",
                      color:
                        emberVoice === "live" && !emberMicMuted ? "#0f172a" : "#ffffff",
                    }}
                  >
                    {emberVoice === "connecting" ? (
                      <Loader2 className="h-3.5 w-3.5 animate-spin" />
                    ) : emberVoice === "off" || emberMicMuted ? (
                      <MicOff className="h-3.5 w-3.5" />
                    ) : (
                      <Mic className="h-3.5 w-3.5" />
                    )}
                  </button>
                  <button
                    type="submit"
                    disabled={!emberDraft.trim() || emberBusy}
                    aria-label="Send question"
                    className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-slate-950 transition-opacity disabled:opacity-40"
                    style={{ background: emberModeInfo.accent }}
                  >
                    <Send className="h-3.5 w-3.5" />
                  </button>
                </form>
              </div>
            </div>
          )}
          {/* The new Jasper look — the living mascot peeking from BEHIND the
              pale mint pill (personality-tinted tracing + glow, bold ink
              status text). Hidden while the box is open — the pill floats up
              INTO the box header, exactly like iOS. */}
          {/* Desktop collapsed dock — the Ask Jasper INPUT is the pill: the
              mint shell, the living mascot peeking over its top-left edge (tap
              him for voice), type + Enter to ask. The bar's left zone. */}
          {!emberPanelOpen && (
            <div
              className="pointer-events-auto relative mt-7 hidden w-[320px] lg:block"
              style={{ animation: "jasper-peek-in 750ms cubic-bezier(0.34, 1.45, 0.64, 1) 350ms both" }}
            >
              <button
                type="button"
                onClick={() => {
                  setEmberPanelOpen(true);
                  setEmberError(false);
                  startEmberVoice();
                }}
                className="absolute -top-[26px] left-[2.6rem] z-0 -translate-x-1/2 rounded-full transition-transform duration-300 hover:scale-105 active:scale-95 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/50"
                aria-label="Talk to Jasper"
                title="Talk to Jasper"
              >
                {(emberBusy || emberVoice === "connecting") && (
                  <span className="ember-rgb-halo" aria-hidden />
                )}
                {(emberHearing || emberSpeaking) && (
                  <span
                    className="absolute inset-0 animate-ping rounded-full"
                    style={{ background: `${emberModeInfo.accent}2e` }}
                    aria-hidden
                  />
                )}
                <span
                  className="block"
                  style={{ animation: "jasper-mascot-bob 1.7s ease-in-out infinite" }}
                >
                  <EmberMascot
                    size={50}
                    coachMode={emberMode}
                    isActive={
                      emberBusy ||
                      emberHearing ||
                      emberSpeaking ||
                      emberTranscribing ||
                      emberVoice === "connecting"
                    }
                    expression={
                      emberBusy
                        ? "thinking"
                        : emberHearing
                          ? "attentive"
                          : emberSpeaking
                            ? "happy"
                            : emberError
                              ? "concerned"
                              : emberReply
                                ? emberModeInfo.signatureExpression
                                : "calm"
                    }
                    cyclesExpressions={
                      !emberBusy && !emberHearing && !emberSpeaking && !emberReply && !emberTranscribing
                    }
                  />
                </span>
              </button>
              <form
                onSubmit={(e) => {
                  e.preventDefault();
                  const q = jasperAsk.trim();
                  if (!q || emberBusy) return;
                  setJasperAsk("");
                  void askEmber(q);
                }}
                className="relative z-10 flex h-11 items-center gap-1.5 rounded-full pl-4 pr-1.5 transition-shadow focus-within:shadow-[0_0_0_2px_rgba(255,255,255,0.35)]"
                style={jasperMintShellStyle(emberMode)}
              >
                <input
                  value={jasperAsk}
                  onChange={(e) => setJasperAsk(e.target.value)}
                  placeholder={
                    emberVoice === "connecting"
                      ? "Connecting…"
                      : emberBusy
                        ? "Thinking…"
                        : emberTranscribing
                          ? "Noting…"
                          : emberReply
                            ? `${emberModeInfo.shortTitle} mode — ask again`
                            : "Ask Jasper"
                  }
                  disabled={emberBusy}
                  className="min-w-0 flex-1 bg-transparent text-[14px] font-bold outline-none placeholder:text-inherit placeholder:opacity-75 disabled:opacity-70"
                  style={{ color: jasperPillPalette(emberMode).ink }}
                  aria-label="Ask Jasper about this meeting"
                />
                <button
                  type="submit"
                  disabled={!jasperAsk.trim() || emberBusy}
                  aria-label="Send to Jasper"
                  className="grid h-8 w-8 shrink-0 place-items-center rounded-full transition-opacity hover:opacity-80 disabled:opacity-35"
                  style={{
                    background: `${jasperPillPalette(emberMode).ink}1a`,
                    color: jasperPillPalette(emberMode).ink,
                  }}
                >
                  <ArrowUp className="h-4 w-4" strokeWidth={2.6} />
                </button>
              </form>
            </div>
          )}
          {/* Phones keep the mint pill (the panel opens above the controls). */}
          {!emberPanelOpen && (
          <div
            className="pointer-events-auto relative mt-7 lg:hidden"
            style={{ animation: "jasper-peek-in 750ms cubic-bezier(0.34, 1.45, 0.64, 1) 350ms both" }}
          >
            <button
              type="button"
              onClick={() => {
                if (emberPanelOpen) {
                  stopEmberVoice();
                  setEmberPanelOpen(false);
                  setEmberReply(null);
                  setEmberBlocks([]);
                  setEmberPitchOffer(false);
                  setEmberError(false);
                } else {
                  setEmberPanelOpen(true);
                  setEmberError(false);
                  startEmberVoice();
                }
              }}
              className="group relative block rounded-full transition-transform duration-300 hover:scale-105 active:scale-95 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/50"
              aria-label={emberPanelOpen ? "Close Jasper" : "Ask Jasper"}
              aria-pressed={emberPanelOpen}
            >
              <span className="pointer-events-none absolute -top-[26px] left-1/2 z-0 -translate-x-1/2">
                {(emberBusy || emberVoice === "connecting") && (
                  <span className="ember-rgb-halo" aria-hidden />
                )}
                {(emberHearing || emberSpeaking) && (
                  <span
                    className="absolute inset-0 animate-ping rounded-full"
                    style={{ background: `${emberModeInfo.accent}2e` }}
                    aria-hidden
                  />
                )}
                <span
                  className="block"
                  style={{ animation: "jasper-mascot-bob 1.7s ease-in-out infinite" }}
                >
                  <EmberMascot
                    size={50}
                    coachMode={emberMode}
                    isActive={
                      emberBusy ||
                      emberHearing ||
                      emberSpeaking ||
                      emberTranscribing ||
                      emberVoice === "connecting"
                    }
                    expression={
                      emberBusy
                        ? "thinking"
                        : emberHearing
                          ? "attentive"
                          : emberSpeaking
                            ? "happy"
                            : emberError
                              ? "concerned"
                              : emberReply
                                ? emberModeInfo.signatureExpression
                                : "calm"
                    }
                    cyclesExpressions={
                      !emberBusy && !emberHearing && !emberSpeaking && !emberReply && !emberTranscribing
                    }
                  />
                </span>
              </span>
              <span
                className="relative z-10 flex h-[34px] items-center rounded-full px-5 text-[14px] font-black transition-colors"
                style={{
                  ...jasperMintShellStyle(emberMode),
                  color: jasperPillPalette(emberMode).ink,
                }}
              >
                {emberVoice === "connecting" ? (
                  "Connecting…"
                ) : emberBusy ? (
                  <span className="ember-rgb-text">Thinking…</span>
                ) : emberSpeaking ? (
                  "Speaking…"
                ) : emberHearing ? (
                  "Listening…"
                ) : emberVoice === "live" ? (
                  "Live — just talk"
                ) : emberTranscribing ? (
                  "Noting…"
                ) : emberReply ? (
                  `${emberModeInfo.shortTitle} mode`
                ) : (
                  "Ask Jasper"
                )}
              </span>
            </button>
          </div>
          )}
        </div>
      )}

      {/* The presented-client dock — EVERYONE in the call sees this card
          above the controls while a presentation runs (plus the mini copy
          inside the presenter's frame). The presenter gets the stop button;
          the lagging dock payload lets the exit animation play. */}
      {dockPayload && (
        <DraggableFloat
          storageKey="whisper_float_present"
          className="absolute bottom-[6.9rem] left-1/2 z-30 -translate-x-1/2 sm:bottom-[7.6rem]"
        >
          <MiniClientPhoneCard
            client={dockPayload}
            leaving={dockLeaving}
            onExpand={() => setPresentationExpanded(true)}
            onStop={dockPayload.presenterUserId === user?.id ? stopPresenting : null}
          />
        </DraggableFloat>
      )}

      {/* The creator analytics dock — everyone sees the live card while a
          creator shares; the presenter gets the stop control. */}
      {creatorCard && (
        <DraggableFloat
          storageKey="whisper_float_creator"
          className="absolute bottom-[11.6rem] left-1/2 z-30 -translate-x-1/2 sm:bottom-[12.4rem]"
        >
          <CreatorAnalyticsMiniCard
            card={creatorCard}
            mine={creatorCard.presenterUserId === user?.id}
            onExpand={() => setCreatorExpanded(true)}
            onStop={creatorCard.presenterUserId === user?.id ? stopCreatorCard : null}
          />
        </DraggableFloat>
      )}

      {/* The speed-date WELCOME — the invited side's custom join screen. */}
      {speedDateWelcome && (
        <div className="absolute inset-0 z-[70] flex flex-col items-center justify-center overflow-y-auto bg-gradient-to-br from-[#290611] via-[#4C0F26] to-[#230409] p-6 text-center text-white">
          <EmberMascot
            size={88}
            palette={{ accent: "#F5B8CC", softAccent: "#FFEDF2", deepAccent: "#E68FAD" }}
            smitten
            expression="delighted"
          />
          <p className="mt-4 text-[11px] font-black uppercase tracking-[0.28em] text-rose-300">
            Blind date
          </p>
          <h2 className="mt-1 text-[26px] font-black leading-tight">
            {blindPairedPartner(id ?? "") ? (
              <>
                It's a date with
                <br />@{blindPairedPartner(id ?? "")} 💘
              </>
            ) : (
              <>
                You've been invited
                <br />
                to a blind date 💘
              </>
            )}
          </h2>
          <p className="mx-auto mt-2 max-w-[330px] text-[13px] leading-snug text-white/70">
            Five minutes. You'll hear each other first — cameras stay behind the curtain until
            you both reveal (or at the two-minute mark). Jasper hosts with prompts built from
            both your cards.
          </p>
          <span className="mt-4 rounded-full bg-white/10 px-3 py-1.5 text-[12px] font-bold">
            {user && hasDatingCard(loadDatingCardLocal(user.id))
              ? "✓ Your dating card is ready"
              : "No dating card yet"}
          </span>
          <button
            onClick={() => setRoomCardEditor(true)}
            className="mt-2.5 rounded-full border border-white/25 bg-white/10 px-4 py-2 text-[13px] font-bold text-white transition-transform active:scale-95"
          >
            {user && hasDatingCard(loadDatingCardLocal(user.id)) ? "Edit my card" : "Fill my card"}
          </button>
          <button
            onClick={() => {
              if (id) markBlindReady(id);
              blindRef.current.myReady = true;
              blindSend(BLIND_WIRE.ready, { userId: user?.id ?? "" });
              maybeStartBlindClock();
              bumpBlind();
              setSpeedDateWelcome(false);
            }}
            className="mt-6 flex w-full max-w-xs items-center justify-center gap-2 rounded-full bg-gradient-to-r from-rose-500 to-pink-500 py-3.5 text-[15px] font-black text-white shadow-xl shadow-rose-500/30 transition-transform active:scale-95"
          >
            I'm ready 💘
          </button>
        </div>
      )}
      {user && (
        <DatingCardEditor
          open={roomCardEditor}
          onOpenChange={setRoomCardEditor}
          userId={user.id}
          onSaved={() => {
            // The card may be brand new — put it on the wire for the date.
            myDatingWireRef.current = null;
            activateSpeedDateRef.current();
          }}
        />
      )}

      {/* Blind date — the curtain over the video until the reveal, a slim
          HUD after; the welcome takeover sits above it while it's showing. */}
      {speedDate &&
        !speedDateWelcome &&
        (() => {
          const me = user?.id ?? "";
          const partner = participants.find((p) => p.userId && p.userId !== me);
          const b = blindRef.current;
          const fallbackName = b.partnerName || Object.values(datingCards)[0]?.username || "your date";
          return (
            <BlindDateStage
              session={b}
              tick={blindTick}
              myName={profile?.username ?? "you"}
              myAvatarUrl={profile?.profile_image_url}
              partnerName={partner?.name ?? fallbackName}
              partnerAvatarUrl={partner ? avatarUrlFor(partner) : null}
              onReveal={blindTapReveal}
              onExtend={blindTapExtend}
              onPrompt={blindStepPrompt}
            />
          );
        })()}

      {/* Business+ company card — everyone sees it while a business presents;
          the presenter gets End, viewers can hide it locally. */}
      {bizCard && (
        <DraggableFloat
          storageKey="whisper_float_bizcard"
          className="absolute bottom-[15.6rem] left-1/2 z-30 -translate-x-1/2 sm:bottom-[16.4rem]"
        >
          <div className="w-[300px] rounded-[20px] border border-indigo-400/40 bg-[#101126]/95 p-3.5 text-white shadow-2xl backdrop-blur">
            <div className="flex items-center gap-2.5">
              {bizCard.logoUrl ? (
                <img
                  src={bizCard.logoUrl}
                  alt=""
                  className="h-10 w-10 shrink-0 rounded-xl object-cover"
                />
              ) : (
                <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-indigo-500/30 text-[15px] font-black text-indigo-200">
                  {bizCard.company.slice(0, 1).toUpperCase()}
                </span>
              )}
              <div className="min-w-0 flex-1">
                <p className="truncate text-[14px] font-extrabold">{bizCard.company}</p>
                <p className="truncate text-[11px] text-indigo-200/80">
                  {bizCard.industry ? `${bizCard.industry} · ` : ""}presented by @
                  {bizCard.presenterName}
                </p>
              </div>
              {bizCard.presenterUserId === user?.id ? (
                <button
                  onClick={stopBusinessCard}
                  className="shrink-0 rounded-full bg-white/10 px-2.5 py-1 text-[11px] font-bold transition-colors hover:bg-white/20"
                >
                  End
                </button>
              ) : (
                <button
                  onClick={() => setBizCard(null)}
                  className="shrink-0 rounded-full bg-white/10 p-1.5 transition-colors hover:bg-white/20"
                  aria-label="Hide company card"
                >
                  <X className="h-3.5 w-3.5" />
                </button>
              )}
            </div>
            {bizCard.mode === "company" && bizCard.about && (
              <p className="mt-2 line-clamp-2 text-[11.5px] leading-snug text-white/75">
                {bizCard.about}
              </p>
            )}
            {bizCard.mode === "company" && bizCard.positions.length > 0 && (
              <div className="mt-2 flex flex-wrap items-center gap-1">
                <span className="rounded-full bg-emerald-400/15 px-2 py-0.5 text-[10px] font-black uppercase tracking-wide text-emerald-300">
                  Hiring
                </span>
                {bizCard.positions.map((t) => (
                  <span
                    key={t}
                    className="rounded-full bg-white/10 px-2 py-0.5 text-[10.5px] font-semibold text-white/85"
                  >
                    {t}
                  </span>
                ))}
              </div>
            )}
            {bizCard.mode === "roles" && (
              <div className="mt-2 space-y-1">
                <span className="inline-block rounded-full bg-emerald-400/15 px-2 py-0.5 text-[10px] font-black uppercase tracking-wide text-emerald-300">
                  We're hiring
                </span>
                {bizCard.roles.map((r) => (
                  <div key={r.title} className="rounded-xl bg-white/5 px-2.5 py-1.5">
                    <p className="text-[11.5px] font-bold">{r.title}</p>
                    {r.blurb && (
                      <p className="mt-0.5 line-clamp-1 text-[10.5px] text-white/60">
                        {r.blurb}
                      </p>
                    )}
                  </div>
                ))}
                {bizCard.roles.length === 0 && (
                  <p className="text-[11px] text-white/60">
                    No open roles right now — but say hi anyway.
                  </p>
                )}
              </div>
            )}
            {bizCard.mode === "team" && bizCard.team.length > 0 && (
              <div className="mt-2 space-y-1">
                {bizCard.team.slice(0, 5).map((m) => (
                  <div
                    key={m.username}
                    className="flex items-center gap-2 rounded-xl bg-white/5 px-2.5 py-1.5"
                  >
                    <span
                      className="h-2.5 w-2.5 shrink-0 rounded-full"
                      style={{ background: m.accent }}
                    />
                    <span className="min-w-0 flex-1 truncate text-[11.5px] font-bold">
                      @{m.username}
                    </span>
                    <span className="max-w-[110px] truncate text-[9.5px] font-black uppercase tracking-wide text-indigo-200/80">
                      {m.roleTitle}
                    </span>
                  </div>
                ))}
                {bizCard.team.length > 5 && (
                  <p className="text-[10.5px] text-indigo-200/70">
                    +{bizCard.team.length - 5} more on the team
                  </p>
                )}
              </div>
            )}
            {bizCard.presenterUserId === user?.id ? (
              bizInterested.length > 0 && (
                <p className="mt-2 rounded-xl bg-emerald-400/10 px-2.5 py-1.5 text-[11px] font-bold text-emerald-300">
                  👋 {bizInterested.length} interested —{" "}
                  {bizInterested.slice(0, 3).map((u) => `@${u}`).join(", ")}
                  {bizInterested.length > 3
                    ? ` +${bizInterested.length - 3} more`
                    : ""}
                </p>
              )
            ) : (
              <div className="mt-2.5 flex items-center gap-1.5">
                {bizCard.applyUrl &&
                  (bizCard.positions.length > 0 || bizCard.roles.length > 0) && (
                    <a
                      href={bizCard.applyUrl}
                      target="_blank"
                      rel="noreferrer"
                      className="flex-1 rounded-full bg-emerald-400/90 py-1.5 text-center text-[11.5px] font-black text-emerald-950 transition-transform active:scale-95"
                    >
                      Apply
                    </a>
                  )}
                <button
                  onClick={raiseBusinessHand}
                  disabled={bizHandRaised}
                  className={cn(
                    "flex-1 rounded-full py-1.5 text-[11.5px] font-black transition-transform active:scale-95",
                    bizHandRaised
                      ? "bg-white/10 text-white/50"
                      : "bg-indigo-400/90 text-indigo-950",
                  )}
                >
                  {bizHandRaised ? "Hand raised ✓" : "👋 I'm interested"}
                </button>
              </div>
            )}
          </div>
        </DraggableFloat>
      )}
      {!bizCard && myBizPlus && (
        <div className="absolute bottom-[11.6rem] right-3 z-30 flex flex-col items-end gap-1.5 sm:bottom-[12.4rem]">
          {bizMenuOpen && (
            <div className="w-60 overflow-hidden rounded-2xl border border-indigo-400/40 bg-[#101126]/95 p-1.5 shadow-2xl backdrop-blur">
              {(
                [
                  {
                    mode: "company" as const,
                    label: "Company card",
                    hint: "Who you are + what you do",
                    Icon: BusinessPlusMark,
                  },
                  {
                    mode: "roles" as const,
                    label: "We're hiring",
                    hint: "Open roles + your apply link",
                    Icon: Briefcase,
                  },
                  {
                    mode: "team" as const,
                    label: "Meet the team",
                    hint: "Everyone with their role",
                    Icon: Users,
                  },
                ]
              ).map((opt) => (
                <button
                  key={opt.mode}
                  onClick={() => void presentBusinessCard(opt.mode)}
                  className="flex w-full items-center gap-2.5 rounded-xl px-2.5 py-2 text-left transition-colors hover:bg-white/10"
                >
                  <opt.Icon className="h-4 w-4 shrink-0 text-indigo-300" />
                  <span className="min-w-0">
                    <span className="block text-[12.5px] font-bold text-white">
                      {opt.label}
                    </span>
                    <span className="block text-[10.5px] text-indigo-200/70">
                      {opt.hint}
                    </span>
                  </span>
                </button>
              ))}
            </div>
          )}
          <button
            onClick={() => setBizMenuOpen((v) => !v)}
            className="flex items-center gap-1.5 rounded-full border border-indigo-400/40 bg-[#101126]/90 px-3 py-2 text-[12px] font-bold text-indigo-100 shadow-lg backdrop-blur transition-transform active:scale-95"
          >
            <BusinessPlusMark className="h-4 w-4" strokeWidth={2.6} />
            Present
          </button>
        </div>
      )}

      {/* 1:1 call — ringing state until the other person answers. */}
      {joined && callWith && remoteParticipants.length === 0 && (
        <div className="pointer-events-none absolute inset-0 z-[45] flex items-center justify-center px-6">
          <div
            className="pointer-events-auto flex w-full max-w-xs flex-col items-center gap-4 rounded-[28px] border border-white/12 bg-black/70 px-7 py-7 text-center shadow-[0_24px_70px_rgba(0,0,0,0.6)] backdrop-blur-2xl"
            style={{ animation: "ember-pop-in 340ms cubic-bezier(0.34, 1.45, 0.64, 1) both" }}
          >
            <div className="relative flex h-20 w-20 items-center justify-center">
              <span className="call-ring" aria-hidden />
              <span className="call-ring" style={{ animationDelay: "0.6s" }} aria-hidden />
              <span className="flex h-16 w-16 items-center justify-center rounded-full bg-emerald-400/12">
                <PhoneCall className="h-7 w-7 text-emerald-300" />
              </span>
            </div>
            <div>
              <p className="text-[16px] font-extrabold text-white">Ringing @{callWith}…</p>
              <p className="mt-1 text-[12px] leading-snug text-white/55">
                They just got a call card in your chat — this connects the moment they answer.
              </p>
            </div>
            <button
              type="button"
              onClick={() => void handleEnd()}
              className="flex h-11 w-full items-center justify-center gap-2 rounded-full bg-red-500 text-[13px] font-bold text-white transition-colors hover:bg-red-400"
            >
              <PhoneOff className="h-4 w-4" />
              Cancel call
            </button>
          </div>
        </div>
      )}

      {/* A Jasper answer someone shared with the whole meeting — the mascot
          peeks over the mint shell like every other Jasper surface. */}
      {sharedEmber && joined && (
        <DraggableFloat
          storageKey="whisper_float_shared"
          className="absolute left-1/2 top-[4.6rem] z-40 w-[min(22rem,calc(100vw-1.5rem))] -translate-x-1/2 sm:top-[5.4rem]"
        >
          <div key={sharedEmber.at} className="relative pt-6">
            <span
              className="pointer-events-none absolute right-7 top-0 z-0"
              style={{ animation: "jasper-mascot-bob 1.7s ease-in-out infinite" }}
            >
              <EmberMascot
                size={52}
                coachMode={emberMode}
                isActive={false}
                expression="happy"
              />
            </span>
            <div
              className="relative z-10 overflow-hidden rounded-[22px] pb-3"
              style={{
                ...jasperMintShellStyle(emberMode),
                animation: "ember-pop-in 340ms cubic-bezier(0.34, 1.45, 0.64, 1) both",
              }}
            >
              <div className="flex items-center justify-between gap-2 px-3.5 pt-2.5">
                <span className="flex min-w-0 items-center gap-1.5">
                  <Sparkles
                    className="h-3 w-3 shrink-0"
                    style={{ color: jasperPillPalette(emberMode).badge }}
                  />
                  <span
                    className="truncate text-[9px] font-black uppercase tracking-[0.14em]"
                    style={{ color: jasperPillPalette(emberMode).ink }}
                  >
                    @{sharedEmber.name} shared Jasper's answer
                  </span>
                  <span
                    className="shrink-0 rounded-full px-1.5 py-0.5 text-[8px] font-black uppercase tracking-wide"
                    style={{
                      background: `${jasperPillPalette(emberMode).glow}2E`,
                      color: jasperPillPalette(emberMode).ink,
                    }}
                  >
                    {emberModeInfo.shortTitle}
                  </span>
                </span>
                <button
                  type="button"
                  aria-label="Dismiss shared answer"
                  className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full transition-colors"
                  style={{
                    background: `${jasperPillPalette(emberMode).ink}14`,
                    color: `${jasperPillPalette(emberMode).ink}8C`,
                  }}
                  onClick={() => setSharedEmber(null)}
                >
                  <X className="h-3 w-3" />
                </button>
              </div>
              {sharedEmber.text && (
                <p
                  className="px-3.5 pt-1.5 text-[12.5px] leading-relaxed"
                  style={{ color: jasperPillPalette(emberMode).ink }}
                >
                  {sharedEmber.text}
                </p>
              )}
              {sharedEmber.block && (
                <div className="px-2.5 pt-2">
                  <EmberBlockCard block={sharedEmber.block} />
                </div>
              )}
            </div>
          </div>
        </DraggableFloat>
      )}

      {/* A live client stats card a coach shared with the whole meeting —
          wears the same Jasper mint look as the shared answer. */}
      {sharedClientCard && joined && (
        <DraggableFloat
          storageKey="whisper_float_client_card"
          className="absolute left-1/2 top-[4.6rem] z-40 w-[min(20rem,calc(100vw-1.5rem))] -translate-x-1/2 sm:top-[5.4rem]"
        >
          <div key={sharedClientCard.at} className="relative pt-6">
            <span
              className="pointer-events-none absolute right-7 top-0 z-0"
              style={{ animation: "jasper-mascot-bob 1.7s ease-in-out infinite" }}
            >
              <EmberMascot
                size={52}
                coachMode={emberMode}
                isActive={false}
                expression="attentive"
              />
            </span>
            <div
              className="relative z-10 overflow-hidden rounded-[22px] pb-3"
              style={{
                ...jasperMintShellStyle(emberMode),
                animation: "ember-pop-in 340ms cubic-bezier(0.34, 1.45, 0.64, 1) both",
              }}
            >
              <div className="flex items-center justify-between gap-2 px-3.5 pt-2.5">
                <span className="flex min-w-0 items-center gap-1.5">
                  <HeartPulse
                    className="h-3 w-3 shrink-0"
                    style={{ color: jasperPillPalette(emberMode).badge }}
                  />
                  <span
                    className="truncate text-[9px] font-black uppercase tracking-[0.14em]"
                    style={{ color: jasperPillPalette(emberMode).ink }}
                  >
                    @{sharedClientCard.name} shared @{sharedClientCard.client}'s stats
                  </span>
                </span>
                <button
                  type="button"
                  aria-label="Dismiss client card"
                  className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full transition-colors"
                  style={{
                    background: `${jasperPillPalette(emberMode).ink}14`,
                    color: `${jasperPillPalette(emberMode).ink}8C`,
                  }}
                  onClick={() => setSharedClientCard(null)}
                >
                  <X className="h-3 w-3" />
                </button>
              </div>
              <div
                className="mt-1.5 grid grid-cols-3 gap-1.5 px-3.5"
                style={{ color: jasperPillPalette(emberMode).ink }}
              >
                {[
                  {
                    label: "BPM",
                    value: sharedClientCard.bpm != null ? `${sharedClientCard.bpm}` : "--",
                  },
                  {
                    label: "Sleep",
                    value:
                      sharedClientCard.sleep > 0
                        ? `${sharedClientCard.sleep.toFixed(1)}h`
                        : "--",
                  },
                  {
                    label: "Steps",
                    value:
                      sharedClientCard.steps > 0
                        ? sharedClientCard.steps.toLocaleString()
                        : "--",
                  },
                ].map((tile) => (
                  <div
                    key={tile.label}
                    className="rounded-xl px-2 py-1.5"
                    style={{ background: `${jasperPillPalette(emberMode).ink}0D` }}
                  >
                    <p className="text-[7.5px] font-black uppercase tracking-wide opacity-55">
                      {tile.label}
                    </p>
                    <p className="truncate text-[13px] font-black">{tile.value}</p>
                  </div>
                ))}
              </div>
              <div
                className="mt-2 space-y-1.5 px-3.5"
                style={{ color: jasperPillPalette(emberMode).ink }}
              >
                {[
                  {
                    label: "Calories",
                    now: sharedClientCard.calories,
                    goal: sharedClientCard.caloriesGoal,
                  },
                  {
                    label: "Protein",
                    now: sharedClientCard.protein,
                    goal: sharedClientCard.proteinGoal,
                  },
                ].map((m) => (
                  <div key={m.label}>
                    <div className="flex items-baseline justify-between">
                      <span className="text-[9px] font-bold uppercase tracking-wide opacity-55">
                        {m.label}
                      </span>
                      <span className="text-[10px] font-bold opacity-85">
                        {m.now}
                        {m.goal > 0 ? ` / ${m.goal}` : ""}
                      </span>
                    </div>
                    <div
                      className="mt-0.5 h-1 overflow-hidden rounded-full"
                      style={{ background: `${jasperPillPalette(emberMode).ink}14` }}
                    >
                      <div
                        className="h-full rounded-full transition-[width] duration-700"
                        style={{
                          width: `${m.goal > 0 ? Math.min(100, Math.max(3, Math.round((m.now / m.goal) * 100))) : 0}%`,
                          background: jasperPillPalette(emberMode).glow,
                        }}
                      />
                    </div>
                  </div>
                ))}
              </div>
              {sharedClientCard.training && (
                <p
                  className="mt-2 px-3.5 text-[10px] font-semibold leading-snug opacity-70"
                  style={{ color: jasperPillPalette(emberMode).ink }}
                >
                  Last training: {sharedClientCard.training}
                </p>
              )}
            </div>
          </div>
        </DraggableFloat>
      )}

      {/* 1:1 coach call — live client vitals: heart rate plus the same
          Jasper data the coach dashboard tracks, refreshing while you talk.
          Only renders when RLS proves you're this person's coach. */}
      {joined && callWith && vitalsOpen && callVitals && (
        <DraggableFloat
          storageKey="whisper_float_vitals"
          className="absolute left-2.5 top-[4.6rem] z-30 sm:left-5 sm:top-[5.4rem]"
        >
          <div
            className="w-[15rem] overflow-hidden rounded-[22px] border pb-3 shadow-[0_16px_48px_rgba(0,0,0,0.55)] backdrop-blur-2xl"
            style={{
              borderColor: "rgba(251,146,60,0.32)",
              background:
                "linear-gradient(155deg, rgba(251,146,60,0.18) 0%, rgba(251,146,60,0.05) 34%, rgba(10,12,16,0.92) 66%)",
              animation: "ember-pop-in 340ms cubic-bezier(0.34, 1.45, 0.64, 1) both",
            }}
          >
            <div className="flex items-center justify-between gap-2 px-3.5 pt-2.5">
              <span className="flex min-w-0 items-center gap-1.5">
                <HeartPulse className="h-3 w-3 shrink-0 text-orange-300" />
                <span className="truncate text-[9px] font-black uppercase tracking-[0.14em] text-orange-200">
                  @{callWith} · Live vitals
                </span>
              </span>
              <span className="flex shrink-0 items-center gap-1">
                <button
                  type="button"
                  aria-label="Share client card with the meeting"
                  title="Share live stats into the meeting"
                  className="flex h-6 items-center gap-1 rounded-full bg-white/10 px-2 text-[9px] font-black uppercase tracking-[0.1em] text-white/80 transition-colors hover:bg-white/20"
                  onClick={shareClientCard}
                >
                  <Send className="h-2.5 w-2.5" />
                  Share
                </button>
                <button
                  type="button"
                  aria-label="Hide client vitals"
                  className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-white/45 transition-colors hover:bg-white/10 hover:text-white"
                  onClick={() => setVitalsOpen(false)}
                >
                  <X className="h-3 w-3" />
                </button>
              </span>
            </div>
            <div className="mt-1.5 flex items-end justify-between px-3.5">
              <p className="text-[30px] font-black leading-none text-white">
                {callVitalsBpm ?? "--"}
                <span className="ml-1 text-[11px] font-bold text-white/40">bpm</span>
              </p>
              <span
                className={cn(
                  "mb-0.5 flex items-center gap-1 rounded-full px-2 py-0.5",
                  callVitalsLive ? "bg-red-500/15" : "bg-white/8",
                )}
              >
                <span
                  className={cn(
                    "h-1.5 w-1.5 rounded-full",
                    callVitalsLive ? "animate-pulse bg-red-400" : "bg-white/35",
                  )}
                />
                <span
                  className={cn(
                    "text-[8px] font-black uppercase tracking-wide",
                    callVitalsLive ? "text-red-300" : "text-white/45",
                  )}
                >
                  {callVitalsLive ? "Live" : "Resting"}
                </span>
              </span>
            </div>
            {(callVitals.caloriesGoal > 0 || callVitals.caloriesToday > 0) && (
              <div className="mt-2.5 space-y-1.5 px-3.5">
                {[
                  {
                    label: "Calories",
                    now: callVitals.caloriesToday,
                    goal: callVitals.caloriesGoal,
                    color: "#fb923c",
                  },
                  {
                    label: "Protein",
                    now: callVitals.proteinToday,
                    goal: callVitals.proteinGoal,
                    color: "#34d399",
                  },
                ].map((m) => (
                  <div key={m.label}>
                    <div className="flex items-baseline justify-between">
                      <span className="text-[9px] font-bold uppercase tracking-wide text-white/50">
                        {m.label}
                      </span>
                      <span className="text-[10px] font-bold text-white/80">
                        {Math.round(m.now)}
                        {m.goal > 0 ? ` / ${Math.round(m.goal)}` : ""}
                      </span>
                    </div>
                    <div className="mt-0.5 h-1 overflow-hidden rounded-full bg-white/10">
                      <div
                        className="h-full rounded-full transition-[width] duration-700"
                        style={{
                          width: `${m.goal > 0 ? Math.min(100, Math.max(3, Math.round((m.now / m.goal) * 100))) : 0}%`,
                          background: m.color,
                        }}
                      />
                    </div>
                  </div>
                ))}
              </div>
            )}
            <div className="mt-2.5 grid grid-cols-2 gap-1.5 px-3.5">
              {[
                {
                  icon: <Footprints className="h-3 w-3 text-emerald-300" />,
                  label: "Steps",
                  value: callVitals.steps > 0 ? callVitals.steps.toLocaleString() : "--",
                },
                {
                  icon: <Moon className="h-3 w-3 text-indigo-300" />,
                  label: "Sleep",
                  value: callVitals.sleepHours > 0 ? `${callVitals.sleepHours.toFixed(1)}h` : "--",
                },
                {
                  icon: <Droplets className="h-3 w-3 text-sky-300" />,
                  label: "Water",
                  value: callVitals.waterCount > 0 ? `${callVitals.waterCount} cups` : "--",
                },
                {
                  icon: <Dumbbell className="h-3 w-3 text-orange-300" />,
                  label: "Weight",
                  value: callVitals.bodyMassLbs > 0 ? `${Math.round(callVitals.bodyMassLbs)} lb` : "--",
                },
              ].map((tile) => (
                <div
                  key={tile.label}
                  className="flex items-center gap-1.5 rounded-xl bg-white/6 px-2 py-1.5"
                >
                  {tile.icon}
                  <div className="min-w-0">
                    <p className="text-[7.5px] font-black uppercase tracking-wide text-white/40">
                      {tile.label}
                    </p>
                    <p className="truncate text-[11px] font-bold text-white">{tile.value}</p>
                  </div>
                </div>
              ))}
            </div>
            {callVitals.recentWorkouts.length > 0 && (
              <p className="mt-2 px-3.5 text-[10px] leading-snug text-white/55">
                Last workout: {callVitals.recentWorkouts[0].type} ·{" "}
                {Math.round(callVitals.recentWorkouts[0].durationMinutes)}m ·{" "}
                {Math.round(callVitals.recentWorkouts[0].calories)} cal
              </p>
            )}
            <p className="mt-1.5 px-3.5 text-[8.5px] font-bold uppercase tracking-[0.12em] text-white/25">
              Only you can see this
            </p>
          </div>
        </DraggableFloat>
      )}

      {/* Recruiter-only: Jasper drafted the pitch deck mid-meeting —
          a quiet popup invites the recruiter to flip through it. */}
      {joined && isRecruiter && !speedDate && deckToast && pitchDeck && (
        <div className="absolute bottom-24 left-1/2 z-40 -translate-x-1/2">
          <div
            className="flex items-center gap-2.5 rounded-full border py-1.5 pl-2 pr-1.5 shadow-[0_18px_50px_rgba(0,0,0,0.55)] backdrop-blur-xl"
            style={{
              borderColor: "rgba(141,240,201,0.4)",
              background:
                "linear-gradient(155deg, rgba(14,159,118,0.28) 0%, rgba(8,12,11,0.94) 60%)",
              animation: "ember-pop-in 420ms cubic-bezier(0.34, 1.45, 0.64, 1) both",
            }}
          >
            <EmberMascot size={30} coachMode={loadCoachMode()} isActive expression="calm" />
            <div className="min-w-0">
              <p className="text-[12px] font-black leading-tight text-white">
                Jasper drafted your pitch deck
              </p>
              <p className="text-[10px] font-semibold text-emerald-100/70">
                {pitchDeck.prospectName} · {pitchDeck.closeRate.withPlan}% with the plan
              </p>
            </div>
            <button
              type="button"
              onClick={() => {
                setShowRecruiterTools(true);
                setDeckToast(false);
              }}
              className="ml-1 flex h-8 shrink-0 items-center rounded-full px-3.5 text-[11.5px] font-black text-slate-950 transition-transform active:scale-95"
              style={{ background: "#8DF0C9" }}
            >
              View
            </button>
            <button
              type="button"
              aria-label="Dismiss the deck popup"
              onClick={() => setDeckToast(false)}
              className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-white/50 transition-colors hover:bg-white/10 hover:text-white"
            >
              <X className="h-3.5 w-3.5" />
            </button>
          </div>
        </div>
      )}

      {/* Recruiter-only: Ember's live prospect read — appears automatically
          the moment you join (listening state), then refreshes on its own as
          the room talks. Score, placement, confidence + freshness. */}
      {joined && isRecruiter && !speedDate && !liveEvalDismissed && (
        <DraggableFloat
          storageKey="whisper_float_eval"
          className="absolute bottom-[5.25rem] right-3 z-30 sm:right-4"
        >
          {liveEvalCollapsed ? (
            // Collapsed — a Meet-style chip: the Jasper spark, the score, the label.
            <div className="flex h-11 items-center gap-1 rounded-full bg-[#303134] py-1 pl-1.5 pr-1 text-white shadow-lg ring-1 ring-white/10">
              <button
                type="button"
                onClick={() => setLiveEvalCollapsed(false)}
                className="flex items-center gap-2 rounded-full py-1 pl-1 pr-2 transition-colors hover:bg-white/8"
                aria-label="Show Jasper's live prospect read"
              >
                <span className="grid h-7 w-7 place-items-center rounded-full bg-gradient-to-br from-[#F22659] via-[#FF7340] to-[#FFA94D]">
                  <Sparkles className="h-3.5 w-3.5 text-white" />
                </span>
                {liveEval ? (
                  <span className="text-[15px] font-semibold" style={{ color: scoreColor(liveEval.score) }}>
                    {liveEval.score}
                  </span>
                ) : (
                  <span className="flex items-center gap-0.5">
                    {[0, 1, 2].map((i) => (
                      <span
                        key={i}
                        className="eval-dot h-1.5 w-1.5 rounded-full bg-white/70"
                        style={{ animationDelay: `${i * 180}ms` }}
                      />
                    ))}
                  </span>
                )}
                <span className="text-[13px] font-medium text-white/80">Live read</span>
              </button>
              <button
                type="button"
                onClick={() => setLiveEvalDismissed(true)}
                className="grid h-8 w-8 place-items-center rounded-full text-white/55 transition-colors hover:bg-white/10 hover:text-white"
                aria-label="Dismiss the live read for this meeting"
                title="Dismiss for this meeting"
              >
                <X className="h-3.5 w-3.5" />
              </button>
            </div>
          ) : (
            // Expanded — the Meet card grammar (the "Gemini is available" card):
            // a flat dark card, one header row, the number as the hero, a
            // brand-gradient bar, then plain-language lines.
            <div
              key={liveEval?.updatedAt ?? "listening"}
              className="w-[300px] rounded-2xl bg-[#303134] p-4 text-white shadow-[0_16px_48px_rgba(0,0,0,0.5)] ring-1 ring-white/10"
              style={{ animation: "ember-pop-in 340ms cubic-bezier(0.34, 1.45, 0.64, 1) both" }}
            >
              <div className="flex items-center gap-2.5">
                <span className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-gradient-to-br from-[#F22659] via-[#FF7340] to-[#FFA94D]">
                  <Sparkles className="h-4 w-4 text-white" />
                </span>
                <div className="min-w-0 flex-1">
                  <p className="text-[14px] font-medium leading-tight">Jasper's live read</p>
                  <p className="truncate text-[11.5px] text-white/55">
                    {evalPhase === "evaluating"
                      ? "Re-reading the room…"
                      : liveEval
                        ? evalAgo !== null && evalAgo < 12
                          ? "Updated just now"
                          : `Updated ${evalAgo}s ago`
                        : "Listening to the room…"}
                  </p>
                </div>
                <button
                  type="button"
                  aria-label="Collapse live read"
                  title="Collapse"
                  className="grid h-8 w-8 place-items-center rounded-full text-white/60 transition-colors hover:bg-white/10 hover:text-white"
                  onClick={() => setLiveEvalCollapsed(true)}
                >
                  <ChevronDown className="h-4 w-4" />
                </button>
                <button
                  type="button"
                  aria-label="Dismiss the live read for this meeting"
                  title="Dismiss for this meeting"
                  className="grid h-8 w-8 place-items-center rounded-full text-white/60 transition-colors hover:bg-white/10 hover:text-white"
                  onClick={() => setLiveEvalDismissed(true)}
                >
                  <X className="h-4 w-4" />
                </button>
              </div>
              {liveEval ? (
                <>
                  <div className="mt-4 flex items-end justify-between gap-3">
                    <div>
                      <p className="text-[10.5px] font-medium uppercase tracking-[0.08em] text-white/50">
                        Prospect score
                      </p>
                      <p
                        className="mt-0.5 text-[40px] font-semibold leading-none tracking-tight"
                        style={{ color: scoreColor(liveEval.score) }}
                      >
                        {liveEval.score}
                      </p>
                    </div>
                    <div className="text-right">
                      <p className="text-[10.5px] font-medium uppercase tracking-[0.08em] text-white/50">
                        Confidence
                      </p>
                      <p className="mt-0.5 text-[22px] font-semibold leading-none">{liveEval.confidence}%</p>
                    </div>
                  </div>
                  <div className="relative mt-3 h-1.5 overflow-hidden rounded-full bg-white/10">
                    <div
                      className="h-full rounded-full bg-gradient-to-r from-[#F22659] via-[#FF7340] to-[#FFA94D] transition-[width] duration-700"
                      style={{ width: `${Math.min(100, Math.max(4, liveEval.score))}%` }}
                    />
                    {evalPhase === "evaluating" && <span className="score-sheen" aria-hidden />}
                  </div>
                  <div className="mt-3.5">
                    <PlacementChips placement={liveEval.placement} compact />
                  </div>
                  <p className="mt-3 text-[13px] leading-snug text-white/85">{liveEval.summary}</p>
                  {(applicantQuestionsQuery.data?.length ?? 0) > 0 && (
                    <div className="mt-3.5 rounded-xl bg-white/[0.06] px-3 py-2.5">
                      <div className="flex items-center justify-between">
                        <p className="text-[12px] font-medium text-white/80">Application questions</p>
                        <p className="text-[12px] text-white/55">
                          {Object.keys(appCapAnswers).length}/{applicantQuestionsQuery.data!.length} captured
                        </p>
                      </div>
                      <div className="mt-2 h-1 overflow-hidden rounded-full bg-white/10">
                        <div
                          className="h-full rounded-full bg-white/70 transition-[width] duration-500"
                          style={{
                            width: `${Math.round(
                              (Object.keys(appCapAnswers).length / Math.max(1, applicantQuestionsQuery.data!.length)) * 100,
                            )}%`,
                          }}
                        />
                      </div>
                      <div className="mt-2 space-y-1">
                        {applicantQuestionsQuery.data!.slice(0, 3).map((q) => {
                          const captured = !!appCapAnswers[q.id];
                          return (
                            <div key={q.id} className="flex items-center gap-2">
                              {captured ? (
                                <Check className="h-3 w-3 shrink-0 text-[#a8c7fa]" strokeWidth={3} />
                              ) : (
                                <span className="h-2.5 w-2.5 shrink-0 rounded-full border border-dashed border-white/35" />
                              )}
                              <span
                                className={cn(
                                  "min-w-0 flex-1 truncate text-[12px]",
                                  captured ? "text-white/85" : "text-white/45",
                                )}
                              >
                                {q.question}
                              </span>
                            </div>
                          );
                        })}
                        {applicantQuestionsQuery.data!.length > 3 && (
                          <p className="text-[11px] text-white/40">
                            +{applicantQuestionsQuery.data!.length - 3} more
                          </p>
                        )}
                      </div>
                    </div>
                  )}
                  <p className="mt-3 text-[11px] text-white/45">Only you can see this</p>
                </>
              ) : (
                <>
                  <div className="mt-4 flex items-center gap-2 text-[13px] text-white/80">
                    <span className="flex items-center gap-1">
                      {[0, 1, 2].map((i) => (
                        <span
                          key={i}
                          className="eval-dot h-1.5 w-1.5 rounded-full bg-white/70"
                          style={{ animationDelay: `${i * 180}ms` }}
                        />
                      ))}
                    </span>
                    {evalPhase === "evaluating" ? "Reading the room…" : "Listening to the room…"}
                  </div>
                  <p className="mt-2 text-[12.5px] leading-snug text-white/55">
                    A live prospect read — score, best placement, and confidence — appears as the
                    conversation gets going.
                  </p>
                  <p className="mt-3 text-[11px] text-white/45">Only you can see this</p>
                </>
              )}
            </div>
          )}
        </DraggableFloat>
      )}

      {/* Expanded presented profile — the full card over the call. */}
      {presentation && presentationExpanded && (
        <div
          className="fixed inset-0 z-[65] overflow-y-auto bg-black/72 px-4 pb-24 pt-[max(4rem,env(safe-area-inset-top))] backdrop-blur-md"
          onClick={() => setPresentationExpanded(false)}
        >
          <div
            className="mx-auto w-full max-w-md"
            style={{ animation: "ember-pop-in 320ms cubic-bezier(0.34, 1.45, 0.64, 1) both" }}
            onClick={(event) => event.stopPropagation()}
          >
            <ClientProfileCard
              client={presentation}
              live
              footer={
                presentation.presenterUserId === user?.id ? (
                  <div className="flex gap-2">
                    <button
                      type="button"
                      onClick={stopPresenting}
                      className="flex h-11 flex-1 items-center justify-center gap-2 rounded-full bg-red-500 text-[13px] font-bold text-white transition-colors hover:bg-red-400"
                    >
                      <X className="h-4 w-4" />
                      Stop presenting
                    </button>
                    <button
                      type="button"
                      onClick={() => {
                        setPresentationExpanded(false);
                        setShowRecruiterTools(true);
                      }}
                      className="flex h-11 items-center justify-center gap-2 rounded-full bg-white/10 px-4 text-[13px] font-bold text-white transition-colors hover:bg-white/20"
                    >
                      <TrendingUp className="h-4 w-4" />
                      Switch
                    </button>
                  </div>
                ) : (
                  <div className="flex flex-col gap-2">
                    {(presentation.username || presentation.userId) && (
                      <div className="flex gap-2">
                        {presentation.username && (
                          <button
                            type="button"
                            onClick={() =>
                              window.open(`/u/${presentation.username}`, "_blank", "noopener")
                            }
                            className="flex h-11 flex-1 items-center justify-center gap-2 rounded-full bg-white/10 text-[13px] font-bold text-white transition-colors hover:bg-white/20"
                          >
                            <ExternalLink className="h-4 w-4" />
                            View profile
                          </button>
                        )}
                        {presentation.userId && presentation.username && (
                          <button
                            type="button"
                            onClick={() =>
                              window.open(
                                `/messages?to=${presentation.userId}&u=${encodeURIComponent(presentation.username ?? "")}`,
                                "_blank",
                                "noopener",
                              )
                            }
                            className="flex h-11 flex-1 items-center justify-center gap-2 rounded-full bg-white/10 text-[13px] font-bold text-white transition-colors hover:bg-white/20"
                          >
                            <MessageCircle className="h-4 w-4" />
                            Message
                          </button>
                        )}
                      </div>
                    )}
                    <button
                      type="button"
                      onClick={() => setPresentationExpanded(false)}
                      className="flex h-11 w-full items-center justify-center gap-2 rounded-full bg-white/10 text-[13px] font-bold text-white transition-colors hover:bg-white/20"
                    >
                      Minimize — keep it in the frame
                    </button>
                  </div>
                )
              }
            />
          </div>
        </div>
      )}

      <BackgroundsPanel
        open={effectsOpen}
        mode={fxMode}
        imageUrl={fxImage}
        onClose={() => setEffectsOpen(false)}
        onSelect={(m, url) => void applyVideoEffect(m, url)}
        previewTrack={() => videoFx.outputTrack ?? rtcRef.current?.localVideoTrack ?? null}
      />

      {/* Reactions strip — floats above the bar while open (Meet grammar). */}
      {reactionsOpen && (
        <div className="pointer-events-none absolute inset-x-0 bottom-[76px] z-40 flex justify-center px-3">
          <MeetReactionsStrip onPick={(emoji) => sendReaction(emoji)} />
        </div>
      )}

      {/* Someone's at the door — Meet's "wants to join this call" prompt for
          the doorkeeper (under the top bar, right side; the People panel
          carries the full list). */}
      {isDoorkeeper && pendingKnocks.length > 0 && panelTab !== "people" && (
        <div className="pointer-events-none absolute right-3 top-[60px] z-[57] flex justify-end sm:right-4">
          <MeetKnockPrompt
            knocks={pendingKnocks}
            onAdmit={(k) => answerKnock(k, true)}
            onDeny={(k) => answerKnock(k, false)}
            onAdmitAll={admitAllKnocks}
            onViewAll={() => setPanelTab("people")}
          />
        </div>
      )}

      {raisedNames.length > 0 && (
        <div className="pointer-events-none absolute inset-x-0 top-[64px] z-30 flex justify-center px-3">
          <div className="flex items-center gap-2 rounded-full bg-black/60 px-3.5 py-1.5 text-[12.5px] font-medium text-white shadow-lg backdrop-blur">
            <Hand className="h-3.5 w-3.5 text-[#fdd663]" />
            {raisedNames.length === 1
              ? `${raisedNames[0]} raised a hand`
              : `${raisedNames.slice(0, 2).join(", ")}${raisedNames.length > 2 ? ` +${raisedNames.length - 2}` : ""} raised their hands`}
          </div>
        </div>
      )}

      {/* Meet's bottom bar — flat on the stage. Left: the Jasper dock lives
          here on desktop (the mascot peeking over the Ask Jasper input —
          rendered above, this spacer keeps the center cluster centered).
          Center: mic · camera · present · reactions · captions · hand · ⋮ ·
          leave. Right: chat · activities · host controls. */}
      <div className="pointer-events-none absolute inset-x-0 bottom-0 z-40 flex items-center justify-between gap-3 px-3 pb-[max(0.75rem,env(safe-area-inset-bottom))] sm:px-4">
        <div className="hidden min-w-0 flex-1 lg:block" aria-hidden />

        <div className="pointer-events-auto flex max-w-full items-center gap-2">
          {/* Mic — Meet's split pill: the caret opens audio settings, the body toggles. */}
          <div
            className={cn(
              "flex h-12 shrink-0 items-center rounded-full transition-colors",
              micOn ? "bg-[color:var(--meet-ctl)] text-[color:var(--meet-ink)]" : "bg-[#ea4335] text-white",
            )}
          >
            <button
              type="button"
              onClick={() => {
                setMeetSettingsTab("audio");
                setMeetSettingsOpen(true);
              }}
              className="hidden h-12 w-8 items-center justify-center rounded-l-full opacity-80 transition-colors hover:bg-[color:var(--meet-ink-faint)] hover:opacity-100 sm:flex"
              aria-label="Audio settings"
              title="Audio settings"
            >
              <ChevronUp className="h-4 w-4" />
            </button>
            <button
              type="button"
              onClick={() => void toggleMic()}
              disabled={mediaBusy}
              className="flex h-12 w-12 items-center justify-center rounded-full transition-colors hover:bg-[color:var(--meet-ink-faint)] disabled:opacity-70"
              aria-label={micOn ? "Turn off microphone" : "Turn on microphone"}
              title={micOn ? "Turn off microphone (Ctrl+D)" : "Turn on microphone (Ctrl+D)"}
            >
              {micOn ? <Mic className="h-4.5 w-4.5" /> : <MicOff className="h-4.5 w-4.5" />}
            </button>
          </div>
          {!isAudioCall && (
            <div
              className={cn(
                "flex h-12 shrink-0 items-center rounded-full transition-colors",
                camOn ? "bg-[color:var(--meet-ctl)] text-[color:var(--meet-ink)]" : "bg-[#ea4335] text-white",
              )}
            >
              <button
                type="button"
                onClick={() => {
                  setMeetSettingsTab("video");
                  setMeetSettingsOpen(true);
                }}
                className="hidden h-12 w-8 items-center justify-center rounded-l-full opacity-80 transition-colors hover:bg-[color:var(--meet-ink-faint)] hover:opacity-100 sm:flex"
                aria-label="Video settings"
                title="Video settings"
              >
                <ChevronUp className="h-4 w-4" />
              </button>
              <button
                type="button"
                onClick={() => void toggleCam()}
                disabled={mediaBusy}
                className="flex h-12 w-12 items-center justify-center rounded-full transition-colors hover:bg-[color:var(--meet-ink-faint)] disabled:opacity-70"
                aria-label={camOn ? "Turn off camera" : "Turn on camera"}
                title={camOn ? "Turn off camera (Ctrl+E)" : "Turn on camera (Ctrl+E)"}
              >
                {camOn ? <Video className="h-4.5 w-4.5" /> : <VideoOff className="h-4.5 w-4.5" />}
              </button>
            </div>
          )}
          {!isAudioCall && (
            <button
              type="button"
              onClick={() => void toggleScreenShare()}
              disabled={!roomPolicy.present && !isHost && !sharing}
              className={cn(
                "flex h-12 w-12 shrink-0 items-center justify-center rounded-full transition-colors disabled:opacity-40",
                sharing
                  ? "bg-[#a8c7fa] text-[#062e6f] hover:bg-[#b8d2fb]"
                  : "bg-[color:var(--meet-ctl)] text-[color:var(--meet-ink)] hover:bg-[color:var(--meet-ctl-hover)]",
              )}
              aria-label={sharing ? "Stop presenting" : "Present now"}
              title={sharing ? "Stop presenting" : "Present now"}
            >
              {sharing ? <MonitorOff className="h-4.5 w-4.5" /> : <Monitor className="h-4.5 w-4.5" />}
            </button>
          )}
          <button
            type="button"
            onClick={() => setReactionsOpen((open) => !open)}
            disabled={!roomPolicy.reactions && !isHost}
            className={cn(
              "flex h-12 w-12 shrink-0 items-center justify-center rounded-full transition-colors disabled:opacity-40",
              reactionsOpen
                ? "bg-[#a8c7fa] text-[#062e6f] hover:bg-[#b8d2fb]"
                : "bg-[color:var(--meet-ctl)] text-[color:var(--meet-ink)] hover:bg-[color:var(--meet-ctl-hover)]",
            )}
            aria-label="Send a reaction"
            aria-pressed={reactionsOpen}
            title="Send a reaction"
          >
            <Smile className="h-4.5 w-4.5" />
          </button>
          <button
            type="button"
            onClick={() => setShowCaptions((visible) => !visible)}
            className={cn(
              "flex h-12 w-12 shrink-0 items-center justify-center rounded-full transition-colors",
              showCaptions
                ? "bg-[#a8c7fa] text-[#062e6f] hover:bg-[#b8d2fb]"
                : "bg-[color:var(--meet-ctl)] text-[color:var(--meet-ink)] hover:bg-[color:var(--meet-ctl-hover)]",
            )}
            aria-label={showCaptions ? "Turn off captions" : "Turn on captions"}
            aria-pressed={showCaptions}
            title={showCaptions ? "Turn off captions" : "Turn on captions"}
          >
            <Captions className="h-4.5 w-4.5" />
          </button>
          <button
            type="button"
            onClick={toggleHand}
            className={cn(
              "flex h-12 w-12 shrink-0 items-center justify-center rounded-full transition-colors",
              myHandUp
                ? "bg-[#a8c7fa] text-[#062e6f] hover:bg-[#b8d2fb]"
                : "bg-[color:var(--meet-ctl)] text-[color:var(--meet-ink)] hover:bg-[color:var(--meet-ctl-hover)]",
            )}
            aria-label={myHandUp ? "Lower hand" : "Raise hand"}
            aria-pressed={myHandUp}
            title={myHandUp ? "Lower hand (Ctrl+Alt+H)" : "Raise hand (Ctrl+Alt+H)"}
          >
            <Hand className="h-4.5 w-4.5" />
          </button>
          {callWith && callVitals && (
            <button
              type="button"
              onClick={() => setVitalsOpen((visible) => !visible)}
              className={cn(
                "flex h-12 w-12 shrink-0 items-center justify-center rounded-full transition-colors",
                vitalsOpen
                  ? "bg-[#a8c7fa] text-[#062e6f] hover:bg-[#b8d2fb]"
                  : "bg-[color:var(--meet-ctl)] text-[color:var(--meet-ink)] hover:bg-[color:var(--meet-ctl-hover)]",
              )}
              aria-label={vitalsOpen ? "Hide client vitals" : "Show client vitals"}
              aria-pressed={vitalsOpen}
            >
              <HeartPulse className="h-4.5 w-4.5" />
            </button>
          )}
          <button
            type="button"
            onClick={() => { setActivitiesOpen(false); setRecordingOpen(false); setMoreOpen((open) => !open); }}
            className={cn(
              "flex h-12 w-12 shrink-0 items-center justify-center rounded-full transition-colors",
              moreOpen
                ? "bg-[#a8c7fa] text-[#062e6f] hover:bg-[#b8d2fb]"
                : "bg-[color:var(--meet-ctl)] text-[color:var(--meet-ink)] hover:bg-[color:var(--meet-ctl-hover)]",
            )}
            aria-label="More options"
            aria-expanded={moreOpen}
            title="More options"
          >
            <MoreVertical className="h-4.5 w-4.5" />
          </button>
          {/* Leave — Meet's red pill. A host with people in the room gets the
              choice (leave and hand the room over, or end it for everyone). */}
          <div className="relative shrink-0">
            <button
              type="button"
              onClick={() => {
                setActivitiesOpen(false); setRecordingOpen(false);
                const mine = rtcRef.current?.localPeerId ?? "";
                const others = participants.filter((p) => p.peerId !== mine);
                if (isHost && others.length > 0 && !speedDateRoom) {
                  setLeaveMenuOpen((open) => !open);
                } else {
                  void handleEnd();
                }
              }}
              disabled={ending}
              className="ml-0.5 flex h-12 w-[4.25rem] items-center justify-center rounded-full bg-[#ea4335] text-white transition-colors hover:bg-[#f04a3c] disabled:opacity-60"
              aria-label={isHost ? "Leave or end the call" : "Leave call"}
              title={isHost ? "Leave or end the call" : "Leave call"}
              aria-expanded={leaveMenuOpen}
            >
              {ending ? <Loader2 className="h-4.5 w-4.5 animate-spin" /> : <PhoneOff className="h-4.5 w-4.5" />}
            </button>
            {leaveMenuOpen && (
              <>
                <button
                  type="button"
                  aria-label="Close"
                  onClick={() => setLeaveMenuOpen(false)}
                  className="fixed inset-0 z-[58] cursor-default"
                />
                <div className="absolute bottom-[3.6rem] right-0 z-[59] w-72 overflow-hidden rounded-2xl bg-[#303134] py-1.5 text-white shadow-[0_16px_48px_rgba(0,0,0,0.55)] ring-1 ring-white/10">
                  <button
                    type="button"
                    onClick={() => void handleEnd({ everyone: false })}
                    className="flex w-full flex-col items-start px-4 py-3 text-left transition-colors hover:bg-white/8"
                  >
                    <span className="text-[14px] font-medium">Leave the call</span>
                    <span className="text-[12px] text-white/60">
                      {remoteParticipantsAll[0]
                        ? `${remoteParticipantsAll[0].name || "Someone"} becomes the host — the meeting keeps going`
                        : "The meeting keeps going without you"}
                    </span>
                  </button>
                  <button
                    type="button"
                    onClick={() => void handleEnd({ everyone: true })}
                    className="flex w-full flex-col items-start px-4 py-3 text-left transition-colors hover:bg-white/8"
                  >
                    <span className="text-[14px] font-medium text-[#f28b82]">End the call for everyone</span>
                    <span className="text-[12px] text-white/60">Everyone leaves and Jasper writes the notes</span>
                  </button>
                </div>
              </>
            )}
          </div>
        </div>

        {/* Right cluster — Meet's chat · activities · host controls. */}
        <div className="pointer-events-auto hidden flex-1 items-center justify-end gap-1 lg:flex">
          <button
            type="button"
            onClick={() => togglePanel("chat")}
            className={cn(
              "relative grid h-11 w-11 place-items-center rounded-full text-[color:var(--meet-ink)] transition-colors",
              panelTab === "chat" ? "bg-[color:var(--meet-ink-faint-2)]" : "hover:bg-[color:var(--meet-ink-faint)]",
            )}
            aria-label="In-call messages"
            title="Chat with everyone"
          >
            <MessageSquare className="h-5 w-5" />
            {chatUnread > 0 && panelTab !== "chat" && (
              <span className="absolute right-1.5 top-1.5 h-2.5 w-2.5 rounded-full bg-[#a8c7fa] ring-2 ring-[color:var(--meet-stage)]" />
            )}
          </button>
          <button
            type="button"
            onClick={() => { setActivitiesOpen((value) => !value); setRecordingOpen(false); setPanelTab(null); }}
            className="grid h-11 w-11 place-items-center rounded-full text-[color:var(--meet-ink)] transition-colors hover:bg-[color:var(--meet-ink-faint)]"
            aria-label="Activities"
            title="Activities"
          >
            <LayoutGrid className="h-5 w-5" />
          </button>
          {isHost && (
            <button
              type="button"
              onClick={() => togglePanel("host")}
              className={cn(
                "grid h-11 w-11 place-items-center rounded-full text-[color:var(--meet-ink)] transition-colors",
                panelTab === "host" ? "bg-[color:var(--meet-ink-faint-2)]" : "hover:bg-[color:var(--meet-ink-faint)]",
              )}
              aria-label="Host controls"
              title="Host controls"
            >
              <Lock className="h-5 w-5" />
            </button>
          )}
        </div>
      </div>

      {activitiesOpen && !minimized && <MeetingActivities onClose={() => setActivitiesOpen(false)} onRecording={!speedDateRoom ? () => openRecording(true) : undefined} onNotes={user && !speedDateRoom ? () => { setActivitiesOpen(false); setNotebookOpen(true); } : undefined} onLayout={() => { setActivitiesOpen(false); setAdjustOpen(true); }} tools={[
        { title: 'Ask Jasper', hint: 'Questions, voice and presentation help', icon: Mic, action: () => setEmberPanelOpen(true) },
        ...(!speedDate && isRecruiter ? [{ title: "Recruiter tools", hint: "Live read, pitch deck and applications", icon: TrendingUp, action: () => { setActivitiesOpen(false); setShowRecruiterTools(true); } }] : []),
        ...(!speedDate && isCoach ? [{ title: "Coach tools", hint: "Client context and meeting tools", icon: HeartPulse, action: () => { setActivitiesOpen(false); setShowCoachTools(true); } }] : []),
        ...(!speedDate && isCreatorRole ? [{ title: "Creator tools", hint: "Analytics and presenting", icon: Sparkles, action: () => { setActivitiesOpen(false); setShowCreatorTools(true); } }] : []),
      ]} />}
      <MeetMoreMenu
        open={moreOpen}
        onClose={() => setMoreOpen(false)}
        items={[
          ...(!speedDateRoom ? [{ id: "recording", label: "Recording", icon: Video, onClick: () => openRecording(true) }] : []),
          ...(!isAudioCall
            ? [{ id: "fx", label: "Apply visual effects", icon: Wand2, onClick: () => setEffectsOpen(true), hint: fxMode !== "none" ? "On" : undefined }]
            : []),
          { id: "layout", label: "Change layout", icon: LayoutGrid, onClick: () => setAdjustOpen(true) },
          {
            id: "fullscreen",
            label: isFullscreen ? "Exit full screen" : "Full screen",
            icon: isFullscreen ? Minimize2 : Maximize2,
            onClick: toggleFullscreen,
          },
          ...(pipSupported
            ? [{
                id: "pip",
                label: docPipOpen ? "Close pop-out view" : "Pop out meeting",
                icon: PictureInPicture2,
                onClick: () => (docPipOpen ? closeMeetingPip() : void openMeetingPip()),
              }]
            : []),
          ...(sinkSupported
            ? [{
                id: "speaker",
                label: "Choose speaker",
                icon: Volume2,
                onClick: () => {
                  void loadAudioOutputs();
                  setSinkMenuOpen(true);
                },
              }]
            : []),
          ...(user && !speedDateRoom ? [{ id: "personal-notebook", label: "Jasper sidekick · private", icon: NotebookPen, onClick: () => setNotebookOpen(true) }] : []),
          { id: "details", label: "Meeting details", icon: Info, onClick: () => setPanelTab("details") },
          { id: "people", label: "People", icon: Users, onClick: () => setPanelTab("people"), hint: String(participants.length) },
          { id: "chat", label: "In-call messages", icon: MessageSquare, onClick: () => setPanelTab("chat"), hint: chatUnread > 0 ? `${chatUnread} new` : undefined },
          ...(isHost ? [{ id: "host", label: "Host controls", icon: Shield, onClick: () => setPanelTab("host") }] : []),
          { id: "settings", label: "Settings", icon: Settings, onClick: () => setMeetSettingsOpen(true) },
          {
            id: "report",
            label: "Report a problem",
            icon: AlertTriangle,
            onClick: () => setBugReportOpen(true),
          },
        ] as MeetMenuItem[]}
      />

      {sinkMenuOpen && sinkSupported && (
        <>
          <button
            type="button"
            aria-label="Close speaker menu"
            onClick={() => setSinkMenuOpen(false)}
            className="fixed inset-0 z-[58] cursor-default"
          />
          <div className="absolute bottom-[92px] left-1/2 z-[59] w-64 -translate-x-1/2 overflow-hidden rounded-2xl border border-white/12 bg-black/85 py-1.5 shadow-[0_16px_48px_rgba(0,0,0,0.55)] backdrop-blur-2xl">
            <p className="px-3.5 pb-1 pt-1.5 text-[10px] font-black uppercase tracking-[0.14em] text-white/45">
              Speaker
            </p>
            <button
              type="button"
              onClick={() => {
                setSinkId("");
                setSinkMenuOpen(false);
              }}
              className="flex w-full items-center justify-between px-3.5 py-2 text-left text-[12.5px] font-semibold text-white transition-colors hover:bg-white/10"
            >
              System default
              {(sinkId === null || sinkId === "") && <Check className="h-3.5 w-3.5 text-emerald-300" />}
            </button>
            {audioOutputs
              .filter((device) => device.deviceId !== "default")
              .map((device) => (
                <button
                  key={device.deviceId}
                  type="button"
                  onClick={() => {
                    setSinkId(device.deviceId);
                    setSinkMenuOpen(false);
                  }}
                  className="flex w-full items-center justify-between gap-2 px-3.5 py-2 text-left text-[12.5px] font-semibold text-white transition-colors hover:bg-white/10"
                >
                  <span className="truncate">{device.label || "Speaker"}</span>
                  {sinkId === device.deviceId && <Check className="h-3.5 w-3.5 shrink-0 text-emerald-300" />}
                </button>
              ))}
            {audioOutputs.length === 0 && (
              <p className="px-3.5 py-2 text-[11.5px] text-white/45">No other outputs found</p>
            )}
          </div>
        </>
      )}

      <FloatingReactionsLayer items={floatingReactions} />

      <MeetSidePanel
        open={panelTab !== null}
        tab={panelTab ?? "people"}
        onTab={setPanelTab}
        onClose={() => setPanelTab(null)}
        isHost={isHost}
        participants={panelParticipants}
        onMute={isHost ? mutePeer : undefined}
        onMuteAll={isHost ? muteEveryone : undefined}
        waiting={isDoorkeeper ? pendingKnocks : []}
        onAdmit={isDoorkeeper ? (k) => answerKnock(k, true) : undefined}
        onDeny={isDoorkeeper ? (k) => answerKnock(k, false) : undefined}
        onAdmitAll={isDoorkeeper ? admitAllKnocks : undefined}
        onSpotlight={
          isHost
            ? (p) => {
                if (p.peerId) setSpotlightId((current) => (current === p.peerId ? null : p.peerId ?? null));
              }
            : undefined
        }
        onKick={
          isHost
            ? (p) => {
                const target = participants.find((x) => x.peerId === p.peerId);
                if (target) kickParticipant(target);
              }
            : undefined
        }
        messages={roomChat}
        onSendChat={sendRoomChat}
        chatDisabled={!roomPolicy.chat && !isHost}
        details={{
          title: meeting?.title ?? "Meeting",
          code: meetingId && !isMeetingUuid(meetingId) ? meetingId : null,
          link: invitationLink,
          startedAt: meeting?.started_at ?? null,
          hostName: meeting?.host_username ?? "",
        }}
        hostControls={
          isHost
            ? {
                chatLocked: !roomPolicy.chat,
                onToggleChatLock: () => updatePolicy({ chat: !roomPolicy.chat }),
                reactionsLocked: !roomPolicy.reactions,
                onToggleReactionsLock: () => updatePolicy({ reactions: !roomPolicy.reactions }),
                presentLocked: !roomPolicy.present,
                onTogglePresentLock: () => updatePolicy({ present: !roomPolicy.present }),
                quickAccess: roomPolicy.quickAccess,
                onToggleQuickAccess: () => updatePolicy({ quickAccess: !roomPolicy.quickAccess }),
              }
            : undefined
        }
      />

      <AdjustViewDialog open={adjustOpen} onClose={() => setAdjustOpen(false)} />
      <MeetSettingsDialog
        open={meetSettingsOpen}
        onClose={() => setMeetSettingsOpen(false)}
        context="room"
        callStream={participants.find((participant) => participant.peerId === rtcRef.current?.localPeerId)?.remoteStream ?? null}
        initialTab={meetSettingsTab}
      />
      <ReportBugDialog
        open={bugReportOpen}
        onOpenChange={setBugReportOpen}
        defaultCategory="audio-video"
        context={{ surface: "meeting-room", meetingId: id ?? null, path: window.location.pathname }}
      />
      <MeetStillThereDialog
        open={alonePrompt}
        secondsLeft={aloneSecondsLeft}
        onStay={() => {
          setAlonePrompt(false);
          setAloneEpoch((n) => n + 1);
        }}
        onLeave={() => {
          setAlonePrompt(false);
          setPostCall("alone");
        }}
      />

      {readyCardVisible && (
        <div className="pointer-events-none absolute bottom-[5.25rem] left-3 z-30 sm:left-4 lg:bottom-[7.75rem]">
          <MeetingReadyCard
            link={invitationLink}
            onInvite={() => setShowInvite(true)}
            onClose={() => setReadyCardDismissed(true)}
          />
        </div>
      )}

      {/* Add people — Meet's side panel, not a centered modal: the people you
          follow (a DM with the rich join card) or an email invite (the
          Calendar-grade email with a Join button + .ics). */}
      {showInvite && (
        <MeetSideDrawer
          title="Add people"
          icon={UserPlus}
          onClose={() => setShowInvite(false)}
          header={
            <div className="flex items-center gap-2 rounded-full bg-white/10 px-3.5 py-2">
              <Search className="h-4 w-4 shrink-0 text-white/40" />
              <input
                value={inviteQuery}
                onChange={(e) => setInviteQuery(e.target.value)}
                placeholder="Search people you follow…"
                className="min-w-0 flex-1 bg-transparent text-[14px] text-white outline-none placeholder:text-white/40"
              />
              {inviteQuery && (
                <button
                  type="button"
                  onClick={() => setInviteQuery("")}
                  className="text-white/40 hover:text-white"
                  aria-label="Clear search"
                >
                  <X className="h-3.5 w-3.5" />
                </button>
              )}
            </div>
          }
          footer={
            <div className="space-y-2.5">
              <form
                onSubmit={(e) => {
                  e.preventDefault();
                  void sendInviteEmail();
                }}
                className="flex h-11 items-center gap-2 rounded-full bg-white/10 pl-3.5 pr-1.5 ring-1 ring-transparent transition-shadow focus-within:ring-white/25"
              >
                <Mail className="h-4 w-4 shrink-0 text-white/40" />
                <input
                  value={inviteEmail}
                  onChange={(e) => setInviteEmail(e.target.value)}
                  type="email"
                  inputMode="email"
                  autoComplete="off"
                  placeholder="Invite by email"
                  className="min-w-0 flex-1 bg-transparent text-[14px] text-white outline-none placeholder:text-white/40"
                  aria-label="Invite by email"
                />
                <button
                  type="submit"
                  disabled={!isLikelyEmail(inviteEmail) || inviteEmailBusy}
                  className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-[#a8c7fa] text-[#062e6f] transition-opacity disabled:opacity-35"
                  aria-label="Send email invite"
                >
                  {inviteEmailBusy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-3.5 w-3.5" />}
                </button>
              </form>
              <button
                type="button"
                onClick={copyLink}
                className="flex w-full items-center justify-center gap-2 rounded-full bg-white/10 py-2.5 text-[13px] font-bold text-white transition-colors hover:bg-white/15"
              >
                <Copy className="h-3.5 w-3.5" />
                Copy meeting link
              </button>
            </div>
          }
        >
          <div className="-mx-2">
              {followingQuery.isLoading ? (
                <div className="flex justify-center py-10">
                  <Loader2 className="h-6 w-6 animate-spin text-white/40" />
                </div>
              ) : filteredFollowing.length === 0 ? (
                <div className="px-6 py-12 text-center">
                  <p className="text-[14px] font-semibold text-white/60">
                    {following.length === 0
                      ? "Follow people to invite them to meetings."
                      : "No friends match your search."}
                  </p>
                </div>
              ) : (
                filteredFollowing.map((f) => (
                  <button
                    key={f.userId}
                    onClick={() => void sendInvite(f.userId, f.username)}
                    disabled={inviting}
                    className="flex w-full items-center gap-3 px-4 py-2.5 text-left transition-colors hover:bg-white/8 disabled:opacity-50"
                  >
                    <Avatar
                      url={f.profile?.profile_image_url ?? null}
                      name={f.username}
                      size={40}
                    />
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-[14px] font-bold text-white">
                        {f.profile?.display_name || f.username}
                      </p>
                      <p className="truncate text-[12px] text-white/50">
                        @{f.username}
                      </p>
                    </div>
                    <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-white/15 text-white">
                      <Send className="h-3.5 w-3.5" />
                    </span>
                  </button>
                ))
              )}
          </div>
        </MeetSideDrawer>
      )}

      {/* Recruiter tools — Meet's side panel: prospect pipeline + numbers */}
      {showRecruiterTools && (
        <MeetSideDrawer
          title="Recruiter tools"
          icon={TrendingUp}
          accent="#22d3ee"
          onClose={() => setShowRecruiterTools(false)}
        >
          <div>
              {/* The live read lives here when it's been dismissed from the stage. */}
              <div className="mb-4 flex items-center justify-between gap-3 rounded-2xl border border-cyan-300/20 bg-cyan-300/[0.05] px-3.5 py-3">
                <div className="min-w-0">
                  <p className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-[0.12em] text-cyan-200">
                    <TrendingUp className="h-3 w-3" />
                    Jasper live read
                  </p>
                  <p className="mt-0.5 text-[11px] leading-snug text-white/55">
                    {liveEvalDismissed
                      ? "Hidden for this meeting — nothing is scored while it's off."
                      : liveEvalCollapsed
                        ? "Collapsed on the stage — tap the pill to expand it."
                        : "Floating over the stage. Only you can see it."}
                  </p>
                </div>
                <button
                  type="button"
                  onClick={() => {
                    if (liveEvalDismissed) {
                      setLiveEvalDismissed(false);
                      setLiveEvalCollapsed(false);
                    } else {
                      setLiveEvalDismissed(true);
                    }
                  }}
                  className="shrink-0 rounded-full bg-white/10 px-3 py-1.5 text-[12px] font-bold text-white transition-colors hover:bg-white/18"
                >
                  {liveEvalDismissed ? "Show" : "Hide"}
                </button>
              </div>
              {/* Jasper's pitch deck — the close plan from this meeting,
                  flipped through right here (its real home is the notes). */}
              <div className="mb-4 rounded-2xl border border-emerald-300/25 bg-emerald-300/[0.06] p-3.5">
                <div className="flex items-center gap-1.5">
                  <NotebookPen className="h-3.5 w-3.5 text-emerald-300" />
                  <span className="text-[10px] font-black uppercase tracking-[0.12em] text-emerald-200">
                    Jasper pitch deck
                  </span>
                  {deckBusy && <Loader2 className="h-3 w-3 animate-spin text-emerald-300" />}
                </div>
                {pitchDeck ? (
                  <div className="mt-2.5">
                    <PitchDeckInline deck={pitchDeck} />
                  </div>
                ) : (
                  <>
                    <p className="mt-1.5 text-[11px] leading-snug text-white/55">
                      Jasper listens and builds the close plan — the prospect's interests,
                      highlighted key moments, close odds with vs without the plan, and your
                      highest-impact lines. It lives right in your notes when the meeting ends.
                    </p>
                    <div className="mt-2.5 flex items-center gap-2">
                      <button
                        type="button"
                        onClick={() => void buildDeckNow()}
                        disabled={deckBusy}
                        className="flex h-9 flex-1 items-center justify-center gap-1.5 rounded-full bg-emerald-300 text-[11.5px] font-black text-slate-950 transition-colors hover:bg-emerald-200 disabled:opacity-40"
                      >
                        {deckBusy ? "Drafting…" : "Draft it now"}
                      </button>
                      <button
                        type="button"
                        onClick={() => setDeckSampleOpen((v) => !v)}
                        className="flex h-9 items-center justify-center rounded-full border border-white/15 px-3.5 text-[11.5px] font-bold text-white transition-colors hover:bg-white/10"
                      >
                        {deckSampleOpen ? "Hide sample" : "See a sample"}
                      </button>
                    </div>
                    {deckSampleOpen && (
                      <div className="mt-3">
                        <PitchDeckInline deck={SAMPLE_PITCH_DECK} />
                      </div>
                    )}
                  </>
                )}
              </div>
              {/* Application capture — Ember answers the standard application
                  questions from the live conversation and files them. */}
              <div className="mb-4 rounded-2xl border border-cyan-400/20 bg-cyan-400/[0.06] p-3.5">
                <div className="flex items-center justify-between gap-2">
                  <span className="flex items-center gap-1.5">
                    <NotebookPen className="h-3.5 w-3.5 text-cyan-300" />
                    <span className="text-[10px] font-black uppercase tracking-[0.12em] text-cyan-200">
                      Application capture
                    </span>
                    {appCapBusy && <Loader2 className="h-3 w-3 animate-spin text-cyan-300" />}
                  </span>
                  <button
                    type="button"
                    onClick={() => setAppCapOn((on) => !on)}
                    className={cn(
                      "rounded-full px-3 py-1.5 text-[10.5px] font-black uppercase tracking-wide transition-colors",
                      appCapOn
                        ? "bg-cyan-400 text-slate-950"
                        : "bg-white/10 text-white hover:bg-white/20",
                    )}
                  >
                    {appCapOn ? "Capturing…" : "Start"}
                  </button>
                </div>
                <p className="mt-1.5 text-[11px] leading-snug text-white/55">
                  Ask your usual questions out loud — Jasper fills the standard
                  application from the conversation and saves it to your applicants,
                  scored like a QR questionnaire.
                </p>
                <input
                  value={appCapName}
                  onChange={(e) => {
                    setAppCapName(e.target.value);
                    appCapNameRef.current = e.target.value;
                  }}
                  placeholder="Prospect name…"
                  className="mt-2.5 h-9 w-full rounded-full bg-white/10 px-3.5 text-[12.5px] text-white outline-none placeholder:text-white/35"
                />
                {Object.keys(appCapAnswers).length > 0 && (
                  <div className="mt-2.5 max-h-40 space-y-2 overflow-y-auto pr-1">
                    {Object.values(appCapAnswers).map((qa, index) => (
                      <div key={index} className="rounded-xl bg-white/[0.06] px-3 py-2">
                        <p className="truncate text-[10px] font-bold text-white/45">{qa.question}</p>
                        <p className="mt-0.5 line-clamp-2 text-[11.5px] leading-snug text-white/90">
                          {qa.answer}
                        </p>
                      </div>
                    ))}
                  </div>
                )}
                <div className="mt-2.5 flex items-center gap-2">
                  <button
                    type="button"
                    onClick={() => void saveApplicationCapture()}
                    disabled={appCapSaving || Object.keys(appCapAnswers).length === 0}
                    className="flex h-9 flex-1 items-center justify-center gap-1.5 rounded-full bg-cyan-400 text-[11.5px] font-black text-slate-950 transition-colors hover:bg-cyan-300 disabled:opacity-40"
                  >
                    {appCapSaving ? (
                      <Loader2 className="h-3.5 w-3.5 animate-spin" />
                    ) : (
                      <ClipboardCheck className="h-3.5 w-3.5" />
                    )}
                    Save{" "}
                    {Object.keys(appCapAnswers).length > 0
                      ? `${Object.keys(appCapAnswers).length} answer${Object.keys(appCapAnswers).length === 1 ? "" : "s"}`
                      : "answers"}{" "}
                    to applicants
                  </button>
                  {appCapSavedAt && (
                    <span className="flex items-center gap-1 text-[10px] font-bold uppercase tracking-wide text-emerald-300">
                      <Check className="h-3 w-3" />
                      Saved
                    </span>
                  )}
                </div>
              </div>
              {prospectsQuery.isLoading ? (
                <div className="flex justify-center py-10">
                  <Loader2 className="h-6 w-6 animate-spin text-white/40" />
                </div>
              ) : prospectsQuery.data && prospectsQuery.data.length > 0 ? (
                <>
                  <div className="mb-4 grid grid-cols-3 gap-2">
                    {(() => {
                      const prospects = prospectsQuery.data;
                      const counts = {
                        discovered: prospects.filter((p) => p.status === "discovered").length,
                        contacted: prospects.filter((p) => p.status === "contacted").length,
                        interested: prospects.filter((p) => p.status === "interested").length,
                        meeting: prospects.filter((p) => p.status === "meeting").length,
                        ready: prospects.filter((p) => p.status === "ready").length,
                      };
                      return [
                        { label: "Discovered", value: counts.discovered, color: "text-gray-400" },
                        { label: "Contacted", value: counts.contacted, color: "text-blue-400" },
                        { label: "Interested", value: counts.interested, color: "text-purple-400" },
                        { label: "In Meeting", value: counts.meeting, color: "text-amber-400" },
                        { label: "Ready", value: counts.ready, color: "text-emerald-400" },
                        { label: "Total", value: prospects.length, color: "text-white" },
                      ].map((stat) => (
                        <div key={stat.label} className="rounded-xl bg-white/5 p-3 text-center">
                          <p className={cn("text-[20px] font-black", stat.color)}>{stat.value}</p>
                          <p className="text-[10px] font-semibold uppercase tracking-wide text-white/50">{stat.label}</p>
                        </div>
                      ));
                    })()}
                  </div>
                  <p className="mb-2 text-[12px] font-bold uppercase tracking-wider text-white/50">
                    Prospects · tap one for the full profile
                  </p>
                  <div className="space-y-2">
                    {prospectsQuery.data.slice(0, 20).map((p: Prospect) => (
                      <div
                        key={p.id}
                        className="flex items-center gap-3 rounded-xl bg-white/5 p-3 transition-colors hover:bg-white/10"
                      >
                        <button
                          type="button"
                          onClick={() => setSelectedProspect(p)}
                          className="flex min-w-0 flex-1 items-center gap-3 text-left"
                          title="Open client profile"
                        >
                          <Avatar
                            url={p.prospect_image_url ?? null}
                            name={p.prospect_username ?? p.prospect_display_name ?? "?"}
                            size={36}
                          />
                          <div className="min-w-0 flex-1">
                            <p className="truncate text-[13px] font-bold text-white">
                              {p.prospect_display_name ?? p.prospect_username ?? "Unknown"}
                            </p>
                            <p className="truncate text-[11px] text-white/50">
                              @{p.prospect_username ?? "unknown"} · {p.niche ?? "No niche"}
                            </p>
                          </div>
                        </button>
                        <button
                          onClick={() => presentProspect(p)}
                          className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-cyan-400/15 text-cyan-300 transition-colors hover:bg-cyan-400/30"
                          title="Present to everyone"
                        >
                          <Presentation className="h-3 w-3" />
                        </button>
                        <button
                          onClick={() => shareProspect(p)}
                          className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-white/10 text-white/60 transition-colors hover:bg-white/20 hover:text-white"
                          title="Copy details"
                        >
                          <Send className="h-3 w-3" />
                        </button>
                        <span className={cn(
                          "rounded-full px-2 py-0.5 text-[9px] font-bold uppercase",
                          p.status === "discovered" && "bg-gray-500/20 text-gray-400",
                          p.status === "contacted" && "bg-blue-500/20 text-blue-400",
                          p.status === "interested" && "bg-purple-500/20 text-purple-400",
                          p.status === "meeting" && "bg-amber-500/20 text-amber-400",
                          p.status === "ready" && "bg-emerald-500/20 text-emerald-400",
                          p.status === "passed" && "bg-red-500/20 text-red-400",
                        )}>
                          {p.status}
                        </span>
                      </div>
                    ))}
                  </div>
                </>
              ) : (
                <div className="px-6 py-12 text-center">
                  <TrendingUp className="mx-auto mb-3 h-8 w-8 text-white/20" />
                  <p className="text-[14px] font-semibold text-white/60">
                    No prospects in your pipeline yet.
                  </p>
                </div>
              )}
          </div>
        </MeetSideDrawer>
      )}

      {/* Client detail — the presenter's local preview with the Present action. */}
      {selectedProspect && user && (
        <div
          className="fixed inset-0 z-[60] overflow-y-auto bg-black/70 p-4 backdrop-blur-sm"
          onClick={() => setSelectedProspect(null)}
        >
          <div
            className="mx-auto flex min-h-full w-full max-w-md items-center"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="w-full">
              <ClientProfileCard
                client={payloadFromProspect(
                  selectedProspect,
                  user?.id ?? "",
                  profile?.username ?? "presenter",
                  matchApplication(
                    selectedProspect,
                    applicantResponsesQuery.data ?? [],
                  ),
                )}
                footer={
                  <div className="flex flex-col gap-2">
                    <button
                      type="button"
                      onClick={() => presentProspect(selectedProspect)}
                      className="flex h-12 w-full items-center justify-center gap-2 rounded-full bg-cyan-400 text-[14px] font-black text-slate-950 transition-colors hover:bg-cyan-300"
                    >
                      <Presentation className="h-4 w-4" />
                      Present to everyone
                    </button>
                    <div className="flex gap-2">
                      <button
                        type="button"
                        onClick={() => shareProspect(selectedProspect)}
                        className="flex h-10 flex-1 items-center justify-center gap-2 rounded-full bg-white/10 text-[12.5px] font-bold text-white transition-colors hover:bg-white/20"
                      >
                        <Copy className="h-3.5 w-3.5" />
                        Copy details
                      </button>
                      <button
                        type="button"
                        onClick={() => setSelectedProspect(null)}
                        className="flex h-10 flex-1 items-center justify-center rounded-full bg-white/10 text-[12.5px] font-bold text-white transition-colors hover:bg-white/20"
                      >
                        Close
                      </button>
                    </div>
                  </div>
                }
              />
            </div>
          </div>
        </div>
      )}

      {/* Creator tools — Meet's side panel: share live analytics + grounded Jasper prompts */}
      {showCreatorTools && (
        <MeetSideDrawer
          title="Creator tools"
          icon={BarChart3}
          accent="#6ee7b7"
          onClose={() => setShowCreatorTools(false)}
        >
          <div className="space-y-4">
              {creatorCard?.presenterUserId === user?.id ? (
                <button
                  type="button"
                  onClick={stopCreatorCard}
                  className="flex w-full items-center gap-3 rounded-2xl border border-red-400/25 bg-red-500/10 p-3.5 text-left transition-colors hover:bg-red-500/20"
                >
                  <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-red-500/20 text-red-300">
                    <X className="h-4 w-4" />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block text-[13px] font-bold text-white">
                      Stop sharing my analytics
                    </span>
                    <span className="block text-[11px] text-white/50">
                      Take the live card off everyone's screen
                    </span>
                  </span>
                </button>
              ) : (
                <button
                  type="button"
                  onClick={() => void shareMyAnalytics()}
                  disabled={creatorBuilding}
                  className="flex w-full items-center gap-3 rounded-2xl border border-emerald-300/25 bg-emerald-400/10 p-3.5 text-left transition-colors hover:bg-emerald-400/20 disabled:opacity-60"
                >
                  <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-emerald-400/20 text-emerald-300">
                    {creatorBuilding ? (
                      <Loader2 className="h-4 w-4 animate-spin" />
                    ) : (
                      <Presentation className="h-4 w-4" />
                    )}
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block text-[13px] font-bold text-white">Share my analytics</span>
                    <span className="block text-[11px] text-white/50">
                      Your live Creator Studio card — score, momentum, top posts — pinned in the
                      call for everyone
                    </span>
                  </span>
                </button>
              )}
              <div>
                <p className="mb-2 text-[12px] font-bold uppercase tracking-wider text-white/50">
                  Ask Jasper — grounded in your live numbers
                </p>
                <div className="grid grid-cols-1 gap-2">
                  {[
                    "What should I post next?",
                    "Why did my engagement move this week?",
                    "Turn my top post into a series",
                    "Build me this week's content plan",
                  ].map((q) => (
                    <button
                      key={q}
                      type="button"
                      onClick={() => {
                        setShowCreatorTools(false);
                        void askEmber(q);
                      }}
                      className="flex items-center gap-2 rounded-xl bg-white/5 px-3 py-2.5 text-left text-[12px] font-semibold text-white/85 transition-colors hover:bg-white/10"
                    >
                      <Sparkles className="h-3.5 w-3.5 shrink-0 text-emerald-300" />
                      {q}
                    </button>
                  ))}
                </div>
              </div>
              <p className="text-center text-[10px] font-semibold leading-relaxed text-white/40">
                Jasper in this meeting already knows your live analytics — every answer cites
                your real numbers.
              </p>
          </div>
        </MeetSideDrawer>
      )}

      {/* Expanded creator analytics — the full breakdown, for everyone */}
      {creatorExpanded && creatorCard && (
        <CreatorAnalyticsModal
          card={creatorCard}
          mine={creatorCard.presenterUserId === user?.id}
          onClose={() => setCreatorExpanded(false)}
          onStop={creatorCard.presenterUserId === user?.id ? stopCreatorCard : null}
        />
      )}

      {/* Coach tools — Meet's side panel: client roster + needs */}
      {showCoachTools && (
        <MeetSideDrawer
          title="Coach tools"
          icon={Users}
          accent="#fb923c"
          onClose={() => setShowCoachTools(false)}
        >
          <div>
              {coachRequestsQuery.isLoading ? (
                <div className="flex justify-center py-10">
                  <Loader2 className="h-6 w-6 animate-spin text-white/40" />
                </div>
              ) : coachRequestsQuery.data ? (
                <>
                  <div className="mb-4 grid grid-cols-2 gap-2">
                    <div className="rounded-xl bg-white/5 p-3 text-center">
                      <p className="text-[20px] font-black text-orange-400">{coachRequestsQuery.data.myClients.length}</p>
                      <p className="text-[10px] font-semibold uppercase tracking-wide text-white/50">Active clients</p>
                    </div>
                    <div className="rounded-xl bg-white/5 p-3 text-center">
                      <p className="text-[20px] font-black text-amber-400">{coachRequestsQuery.data.incoming.filter((r) => r.status === "pending").length}</p>
                      <p className="text-[10px] font-semibold uppercase tracking-wide text-white/50">Pending requests</p>
                    </div>
                  </div>
                  <p className="mb-2 text-[12px] font-bold uppercase tracking-wider text-white/50">Your clients</p>
                  {coachRequestsQuery.data.myClients.length > 0 ? (
                    <div className="space-y-2">
                      {coachRequestsQuery.data.myClients.map((c: CoachRequest) => (
                        <div key={c.id} className="flex items-center gap-3 rounded-xl bg-white/5 p-3">
                          <Avatar name={c.client_username} size={36} />
                          <div className="min-w-0 flex-1">
                            <p className="truncate text-[13px] font-bold text-white">
                              {c.client_username}
                            </p>
                            <p className="truncate text-[11px] text-white/50">
                              {c.message ?? "No message"}
                            </p>
                          </div>
                          <button
                            onClick={() => presentCoachClient(c)}
                            className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-orange-400/15 text-orange-300 transition-colors hover:bg-orange-400/30"
                            title="Present to everyone"
                          >
                            <Presentation className="h-3 w-3" />
                          </button>
                          <button
                            onClick={() => shareClient(c)}
                            className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-white/10 text-white/60 transition-colors hover:bg-white/20 hover:text-white"
                            title="Share with meeting"
                          >
                            <Send className="h-3 w-3" />
                          </button>
                          <span className="rounded-full bg-emerald-500/20 px-2 py-0.5 text-[9px] font-bold uppercase text-emerald-400">
                            Active
                          </span>
                        </div>
                      ))}
                    </div>
                  ) : (
                    <p className="px-6 py-8 text-center text-[14px] font-semibold text-white/60">
                      No active clients yet.
                    </p>
                  )}
                  {coachRequestsQuery.data.incoming.filter((r) => r.status === "pending").length > 0 && (
                    <>
                      <p className="mb-2 mt-4 text-[12px] font-bold uppercase tracking-wider text-white/50">Pending requests</p>
                      <div className="space-y-2">
                        {coachRequestsQuery.data.incoming.filter((r) => r.status === "pending").slice(0, 10).map((r: CoachRequest) => (
                          <div key={r.id} className="flex items-center gap-3 rounded-xl bg-white/5 p-3">
                            <Avatar name={r.client_username} size={36} />
                            <div className="min-w-0 flex-1">
                              <p className="truncate text-[13px] font-bold text-white">{r.client_username}</p>
                              <p className="truncate text-[11px] text-white/50">{r.message ?? "Wants coaching"}</p>
                            </div>
                          </div>
                        ))}
                      </div>
                    </>
                  )}
                </>
              ) : (
                <div className="px-6 py-12 text-center">
                  <Users className="mx-auto mb-3 h-8 w-8 text-white/20" />
                  <p className="text-[14px] font-semibold text-white/60">
                    No coaching data available.
                  </p>
                </div>
              )}
          </div>
        </MeetSideDrawer>
      )}

      {/* Ember's interactive pitch tools — the REAL components, in-meeting. */}
      <WppCalculatorDialog open={wppOpen} onClose={() => setWppOpen(false)} />
      <BrandCardsDialog open={brandCardsOpen} onClose={() => setBrandCardsOpen(false)} />

      {/* Ember deck walkthrough — synced overlay; the driver's call audio
          carries Ember's narration so the whole room hears the same thing. */}
      {deckTour && !tourHidden && (
        <EmberDeckTourOverlay
          slideIndex={deckTour.slide}
          segmentIndex={deckTour.segment}
          playing={deckTour.playing}
          driverName={deckTour.driverName}
          isDriver={tourPosRef.current != null}
          voiceState={tourVoice}
          deviceNarration={deckTour.voice === "device"}
          onClose={() => {
            if (tourPosRef.current) stopDeckTourRef.current?.();
            else setTourHidden(true);
          }}
          onPrevSlide={() => tourGoToSlide(deckTour.slide - 1)}
          onNextSlide={() => tourGoToSlide(deckTour.slide + 1)}
          onTogglePlay={tourTogglePlay}
        />
      )}
      {audioBlocked && (
        <div className="pointer-events-none fixed left-1/2 top-[max(4.75rem,calc(env(safe-area-inset-top)+3.5rem))] z-[80] flex -translate-x-1/2 items-center gap-2 rounded-full border border-amber-300/40 bg-black/85 px-4 py-2 text-[12px] font-bold text-amber-200 shadow-xl backdrop-blur-md">
          <Volume2 className="h-3.5 w-3.5 animate-pulse" />
          Tap anywhere to enable meeting audio
        </div>
      )}
      {deckTour && tourHidden && (
        <button
          type="button"
          onClick={() => setTourHidden(false)}
          className="fixed bottom-28 left-1/2 z-[71] flex -translate-x-1/2 items-center gap-2 rounded-full border border-orange-400/40 bg-black/80 px-4 py-2 text-[12px] font-bold text-orange-300 shadow-xl backdrop-blur-md"
        >
          <Flame className="h-3.5 w-3.5 animate-pulse" />
          Jasper is presenting — tap to reopen
        </button>
      )}

      {/* Whisper pitch deck — Ember-offered launcher for the interactive decks. */}
      {showPitchDeck && (
        <div
          className="fixed inset-0 z-[70] flex items-center justify-center bg-black/70 p-4 backdrop-blur-sm"
          onClick={() => setShowPitchDeck(false)}
        >
          <div
            className="flex max-h-[82vh] w-full max-w-md flex-col overflow-hidden rounded-[24px] border border-white/15 bg-zinc-900 shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between border-b border-white/10 px-4 py-3">
              <div className="flex items-center gap-2">
                <BookOpen className="h-4 w-4 text-white" />
                <p className="text-[15px] font-bold text-white">Whisper pitch deck</p>
              </div>
              <button
                onClick={() => setShowPitchDeck(false)}
                className="flex h-7 w-7 items-center justify-center rounded-full text-white/60 transition-colors hover:bg-white/10 hover:text-white"
              >
                <X className="h-4 w-4" />
              </button>
            </div>
            <div className="flex-1 overflow-y-auto p-4">
              <div className="mb-4 grid grid-cols-3 gap-2">
                {[
                  { label: "Platform fee", value: "10%" },
                  { label: "WPP top RPM", value: "$2.20" },
                  { label: "Whisper One", value: "$14.99" },
                ].map((stat) => (
                  <div key={stat.label} className="rounded-xl bg-white/5 p-3 text-center">
                    <p className="text-[17px] font-black text-white">{stat.value}</p>
                    <p className="text-[9px] font-semibold uppercase tracking-wide text-white/50">
                      {stat.label}
                    </p>
                  </div>
                ))}
              </div>
              <p className="mb-2 text-[12px] font-bold uppercase tracking-wider text-white/50">
                Interactive decks — the real product with sample data
              </p>
              <div className="space-y-2">
                {PITCH_AUDIENCES.map((audience) => {
                  const Icon = audience.icon;
                  return (
                    <button
                      key={audience.id}
                      type="button"
                      onClick={() => window.open(`/pitch/${audience.id}`, "_blank", "noopener")}
                      className="flex w-full items-center gap-3 rounded-2xl bg-white/5 p-3 text-left transition-colors hover:bg-white/10"
                    >
                      <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-white/10 text-white">
                        <Icon className="h-4 w-4" />
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="block truncate text-[13.5px] font-bold text-white">
                          {audience.title}
                        </span>
                        <span className="block truncate text-[11px] text-white/50">
                          {audience.tagline}
                        </span>
                      </span>
                      <ExternalLink className="h-3.5 w-3.5 shrink-0 text-white/40" />
                    </button>
                  );
                })}
              </div>
              <p className="mt-3 text-center text-[10.5px] leading-relaxed text-white/40">
                Decks open in a new tab — share your screen to walk everyone through one.
              </p>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
