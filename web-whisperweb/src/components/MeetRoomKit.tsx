import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  Check,
  Copy,
  Hand,
  Info,
  LayoutGrid,
  Loader2,
  MessageSquare,
  Mic,
  MicOff,
  Pin,
  Send,
  Shield,
  Star,
  UserCheck,
  Users,
  UserX,
  X,
} from "lucide-react";

import { cn } from "@/lib/utils";
import { Avatar } from "@/components/Avatar";
import {
  MEET_MAX_TILE_STOPS,
  useMeetPrefs,
  type MeetLayout,
} from "@/lib/meetPrefs";

// ─── Reactions ──────────────────────────────────────────────────────────────

/** Google Meet's reaction set, in its order. */
export const MEET_REACTIONS: readonly string[] = [
  "💖",
  "👍",
  "🎉",
  "👏",
  "😂",
  "😮",
  "😢",
  "🤔",
];

export interface FloatingReaction {
  id: string;
  emoji: string;
  name: string;
  /** Horizontal start as a percentage of the stage width. */
  x: number;
}

/** Keeps a short-lived list of floating reactions (auto-expire after 3.6s). */
export function useFloatingReactions(): [
  FloatingReaction[],
  (emoji: string, name: string) => void,
] {
  const [items, setItems] = useState<FloatingReaction[]>([]);
  const push = useCallback((emoji: string, name: string): void => {
    const id = `${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
    const item: FloatingReaction = {
      id,
      emoji,
      name,
      x: 8 + Math.random() * 30,
    };
    setItems((prev) => [...prev.slice(-11), item]);
    window.setTimeout(() => {
      setItems((prev) => prev.filter((r) => r.id !== id));
    }, 3600);
  }, []);
  return [items, push];
}

/** Emojis drifting up the left side of the stage with the sender's name. */
export function FloatingReactionsLayer({
  items,
}: {
  items: FloatingReaction[];
}): JSX.Element | null {
  if (items.length === 0) return null;
  return (
    <div className="pointer-events-none absolute inset-0 z-[45] overflow-hidden">
      <style>{`
        @keyframes meet-react-rise {
          0% { transform: translate3d(0, 0, 0) scale(0.6); opacity: 0; }
          10% { opacity: 1; transform: translate3d(0, -24px, 0) scale(1.05); }
          60% { opacity: 1; }
          100% { transform: translate3d(var(--drift), -62vh, 0) scale(1); opacity: 0; }
        }
      `}</style>
      {items.map((r, i) => (
        <div
          key={r.id}
          className="absolute bottom-[112px] flex flex-col items-center"
          style={{
            left: `${r.x}%`,
            animation: "meet-react-rise 3.5s cubic-bezier(.2,.7,.2,1) forwards",
            ["--drift" as string]: `${(i % 2 === 0 ? 1 : -1) * (10 + (i % 3) * 8)}px`,
          }}
        >
          <span className="text-[44px] leading-none drop-shadow-[0_6px_16px_rgba(0,0,0,.45)]">
            {r.emoji}
          </span>
          <span className="mt-1 rounded-full bg-black/55 px-2 py-0.5 text-[11px] font-medium text-white/90">
            {r.name}
          </span>
        </div>
      ))}
    </div>
  );
}

/** The strip that sits above the control bar while reactions are open. */
export function MeetReactionsStrip({
  onPick,
}: {
  onPick: (emoji: string) => void;
}): JSX.Element {
  return (
    <div className="pointer-events-auto flex items-center gap-1 rounded-full border border-white/10 bg-[#1f2023]/95 px-2 py-1.5 shadow-2xl backdrop-blur">
      {MEET_REACTIONS.map((e) => (
        <button
          key={e}
          type="button"
          onClick={() => onPick(e)}
          aria-label={`React ${e}`}
          className="grid h-11 w-11 place-items-center rounded-full text-[26px] transition-transform hover:scale-125 hover:bg-white/10 active:scale-95"
        >
          {e}
        </button>
      ))}
    </div>
  );
}

// ─── Adjust view ────────────────────────────────────────────────────────────

const LAYOUTS: { id: MeetLayout; label: string; hint: string }[] = [
  { id: "auto", label: "Auto", hint: "Whisper picks the best layout" },
  { id: "tiled", label: "Tiled", hint: "Everyone in an even grid" },
  { id: "spotlight", label: "Spotlight", hint: "Speaker or presentation fills the stage" },
  { id: "sidebar", label: "Sidebar", hint: "Big stage with a strip on the side" },
];

function LayoutGlyph({ id, active }: { id: MeetLayout; active: boolean }): JSX.Element {
  const c = active ? "bg-[#a8c7fa]" : "bg-white/35";
  if (id === "tiled") {
    return (
      <div className="grid h-9 w-14 grid-cols-3 gap-[3px]">
        {Array.from({ length: 6 }).map((_, i) => (
          <span key={i} className={cn("rounded-[3px]", c)} />
        ))}
      </div>
    );
  }
  if (id === "spotlight") {
    return <div className={cn("h-9 w-14 rounded-[4px]", c)} />;
  }
  if (id === "sidebar") {
    return (
      <div className="flex h-9 w-14 gap-[3px]">
        <span className={cn("flex-1 rounded-[4px]", c)} />
        <span className="flex w-3 flex-col gap-[3px]">
          {Array.from({ length: 3 }).map((_, i) => (
            <span key={i} className={cn("flex-1 rounded-[2px]", c)} />
          ))}
        </span>
      </div>
    );
  }
  return (
    <div className="flex h-9 w-14 flex-col gap-[3px]">
      <span className={cn("flex-1 rounded-[4px]", c)} />
      <span className="flex h-3 gap-[3px]">
        {Array.from({ length: 4 }).map((_, i) => (
          <span key={i} className={cn("flex-1 rounded-[2px]", c)} />
        ))}
      </span>
    </div>
  );
}

/** Meet's "Change layout" dialog: layout radios + tiles slider + toggles. */
export function AdjustViewDialog({
  open,
  onClose,
}: {
  open: boolean;
  onClose: () => void;
}): JSX.Element | null {
  const [prefs, setPrefs] = useMeetPrefs();
  if (!open) return null;
  const stopIndex = Math.max(0, MEET_MAX_TILE_STOPS.indexOf(prefs.maxTiles));
  return (
    <div
      className="fixed inset-0 z-[70] flex items-center justify-center bg-black/55 p-4"
      role="dialog"
      aria-modal="true"
      aria-label="Change layout"
      onClick={onClose}
    >
      <div
        className="w-full max-w-[420px] rounded-[24px] bg-[#1f2023] p-5 text-white shadow-2xl ring-1 ring-white/10"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-1 flex items-center">
          <h2 className="text-[18px] font-semibold">Change layout</h2>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close"
            className="ml-auto grid h-9 w-9 place-items-center rounded-full text-white/70 hover:bg-white/10"
          >
            <X className="h-5 w-5" />
          </button>
        </div>
        <p className="mb-4 text-[12px] text-white/50">
          Selection is saved for future meetings
        </p>
        <div className="space-y-1">
          {LAYOUTS.map((l) => {
            const active = prefs.layout === l.id;
            return (
              <button
                key={l.id}
                type="button"
                onClick={() => setPrefs({ layout: l.id })}
                className={cn(
                  "flex w-full items-center gap-4 rounded-2xl px-3 py-2.5 text-left hover:bg-white/6",
                  active && "bg-white/8"
                )}
              >
                <span
                  className={cn(
                    "grid h-5 w-5 place-items-center rounded-full border-2",
                    active ? "border-[#a8c7fa]" : "border-white/40"
                  )}
                >
                  {active && <span className="h-2.5 w-2.5 rounded-full bg-[#a8c7fa]" />}
                </span>
                <div className="min-w-0 flex-1">
                  <div className="text-[14px] font-medium">{l.label}</div>
                  <div className="text-[12px] text-white/50">{l.hint}</div>
                </div>
                <LayoutGlyph id={l.id} active={active} />
              </button>
            );
          })}
        </div>

        <div className="mt-5 border-t border-white/10 pt-4">
          <div className="mb-2 flex items-center justify-between text-[13px]">
            <span className="text-white/80">Tiles</span>
            <span className="font-semibold">{prefs.maxTiles}</span>
          </div>
          <input
            type="range"
            min={0}
            max={MEET_MAX_TILE_STOPS.length - 1}
            step={1}
            value={stopIndex}
            onChange={(e) =>
              setPrefs({ maxTiles: MEET_MAX_TILE_STOPS[Number(e.target.value)] ?? 16 })
            }
            className="w-full accent-[#a8c7fa]"
            aria-label="Maximum tiles"
          />
          <div className="mt-1 flex justify-between text-[11px] text-white/40">
            {MEET_MAX_TILE_STOPS.map((s) => (
              <span key={s}>{s}</span>
            ))}
          </div>
        </div>

        <label className="mt-4 flex cursor-pointer items-center gap-3 rounded-2xl px-3 py-2.5 hover:bg-white/6">
          <input
            type="checkbox"
            checked={prefs.hideNoVideo}
            onChange={(e) => setPrefs({ hideNoVideo: e.target.checked })}
            className="h-4 w-4 accent-[#a8c7fa]"
          />
          <span className="text-[14px]">Hide tiles without video</span>
        </label>
      </div>
    </div>
  );
}

// ─── Side panel (People · Chat · Details · Host controls) ──────────────────

export type MeetPanelTab = "people" | "chat" | "details" | "host";

export interface MeetPanelParticipant {
  id: string;
  peerId?: string;
  username: string;
  avatarUrl?: string | null;
  isSelf: boolean;
  isHost: boolean;
  micOn: boolean;
  camOn: boolean;
  handRaised: boolean;
  isSpeaking?: boolean;
}

export interface MeetChatMessage {
  id: string;
  name: string;
  text: string;
  at: number;
  self: boolean;
}

/** Someone knocking on the room — Meet's "wants to join this call". */
export interface MeetKnock {
  knockId: string;
  name: string;
  avatarUrl?: string | null;
  isGuest: boolean;
  at: number;
}

interface MeetSidePanelProps {
  open: boolean;
  tab: MeetPanelTab;
  onTab: (tab: MeetPanelTab) => void;
  onClose: () => void;
  isHost: boolean;
  participants: MeetPanelParticipant[];
  onMute?: (p: MeetPanelParticipant) => void;
  onMuteAll?: () => void;
  onSpotlight?: (p: MeetPanelParticipant) => void;
  onKick?: (p: MeetPanelParticipant) => void;
  onLowerHand?: (p: MeetPanelParticipant) => void;
  /** People waiting at the door (hosts only) with admit / deny. */
  waiting?: MeetKnock[];
  onAdmit?: (knock: MeetKnock) => void;
  onDeny?: (knock: MeetKnock) => void;
  onAdmitAll?: () => void;
  messages: MeetChatMessage[];
  onSendChat: (text: string) => void;
  chatDisabled?: boolean;
  details: {
    title: string;
    code: string | null;
    link: string;
    startedAt: string | null;
    hostName: string;
  };
  hostControls?: {
    chatLocked: boolean;
    onToggleChatLock: () => void;
    reactionsLocked: boolean;
    onToggleReactionsLock: () => void;
    presentLocked: boolean;
    onTogglePresentLock: () => void;
    /** Meet's Quick access: on — members join without asking; off — everyone knocks. */
    quickAccess?: boolean;
    onToggleQuickAccess?: () => void;
  };
}

function formatClock(ms: number): string {
  return new Date(ms).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
}

/**
 * The right-hand panel Google Meet slides in for People / In-call messages /
 * Meeting details / Host controls. Full-height sheet on phones.
 */
export function MeetSidePanel(props: MeetSidePanelProps): JSX.Element | null {
  const {
    open,
    tab,
    onTab,
    onClose,
    isHost,
    participants,
    messages,
    onSendChat,
    chatDisabled,
    details,
    hostControls,
    waiting = [],
    onAdmit,
    onDeny,
    onAdmitAll,
  } = props;
  const [draft, setDraft] = useState<string>("");
  const [copied, setCopied] = useState<boolean>(false);
  const listRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (tab !== "chat") return;
    const el = listRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [messages.length, tab, open]);

  const raised = useMemo(
    () => participants.filter((p) => p.handRaised),
    [participants]
  );

  const copyLink = async (): Promise<void> => {
    try {
      await navigator.clipboard.writeText(details.link);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1600);
    } catch {
      // Clipboard blocked — the link is visible to select manually.
    }
  };

  if (!open) return null;

  const tabs: { id: MeetPanelTab; label: string; icon: typeof Users }[] = [
    { id: "people", label: "People", icon: Users },
    { id: "chat", label: "Chat", icon: MessageSquare },
    { id: "details", label: "Details", icon: Info },
    ...(isHost ? [{ id: "host" as MeetPanelTab, label: "Host", icon: Shield }] : []),
  ];

  const title: Record<MeetPanelTab, string> = {
    people: "People",
    chat: "In-call messages",
    details: "Meeting details",
    host: "Host controls",
  };

  return (
    <aside
      className="absolute inset-y-0 right-0 z-[55] flex w-full flex-col overflow-hidden bg-[#1f2023] text-white shadow-2xl ring-1 ring-white/10 sm:inset-y-4 sm:right-4 sm:w-[360px] sm:rounded-[16px]"
      style={{ paddingTop: "env(safe-area-inset-top)" }}
      aria-label="Meeting panel"
    >
      {/* Meet's grammar: the panel TITLE with the close button on its own
          row (always reachable — the old single row packed four labeled
          tabs beside the X and pushed it past the panel edge), then the
          section switcher underneath. */}
      <header className="shrink-0 px-4 pt-3">
        <div className="flex items-center gap-2">
          <h2 className="min-w-0 flex-1 truncate text-[18px] font-medium text-white">
            {title[tab]}
          </h2>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close panel"
            className="grid h-11 w-11 shrink-0 place-items-center rounded-full text-white/80 transition-colors hover:bg-white/10 hover:text-white"
          >
            <X className="h-5 w-5" />
          </button>
        </div>
        <div
          className="mt-2 flex gap-1 overflow-x-auto pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
          role="tablist"
        >
          {tabs.map((t) => {
            const Icon = t.icon;
            const active = tab === t.id;
            return (
              <button
                key={t.id}
                type="button"
                role="tab"
                aria-selected={active}
                onClick={() => onTab(t.id)}
                className={cn(
                  "flex h-9 shrink-0 items-center gap-1.5 rounded-full px-3 text-[13px] transition-colors",
                  active
                    ? "bg-[#a8c7fa] font-semibold text-[#062e6f]"
                    : "text-white/70 hover:bg-white/8 hover:text-white"
                )}
              >
                <Icon className="h-4 w-4" />
                <span>{t.label}</span>
                {t.id === "people" && (
                  <span className={cn("text-[11px]", active ? "text-[#062e6f]/70" : "text-white/55")}>
                    {participants.length}
                  </span>
                )}
              </button>
            );
          })}
        </div>
      </header>

      <div className="flex-1 overflow-y-auto px-3 pb-3 pt-3 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
        {tab === "people" && (
          <div className="space-y-4">
            {isHost && waiting.length > 0 && (
              <section className="rounded-2xl border border-[#a8c7fa]/30 bg-[#a8c7fa]/[0.08] p-3">
                <div className="mb-2 flex items-center justify-between gap-2 px-1">
                  <span className="text-[12px] font-semibold uppercase tracking-wide text-[#a8c7fa]">
                    Waiting to join · {waiting.length}
                  </span>
                  {waiting.length > 1 && onAdmitAll && (
                    <button
                      type="button"
                      onClick={onAdmitAll}
                      className="rounded-full bg-[#a8c7fa] px-3 py-1 text-[12px] font-semibold text-[#062e6f] hover:bg-[#b8d2fb]"
                    >
                      Admit all
                    </button>
                  )}
                </div>
                <ul className="space-y-1">
                  {waiting.map((k) => (
                    <li key={k.knockId} className="flex items-center gap-3 rounded-2xl px-2 py-2">
                      <Avatar url={k.avatarUrl ?? null} name={k.name} size={36} />
                      <div className="min-w-0 flex-1">
                        <div className="truncate text-[14px] font-medium">{k.name}</div>
                        <div className="text-[12px] text-white/45">{k.isGuest ? "Guest" : "Whisper member"} · asking to join</div>
                      </div>
                      {onDeny && (
                        <button
                          type="button"
                          onClick={() => onDeny(k)}
                          className="h-8 rounded-full px-3 text-[12.5px] font-semibold text-white/80 hover:bg-white/10"
                        >
                          Deny
                        </button>
                      )}
                      {onAdmit && (
                        <button
                          type="button"
                          onClick={() => onAdmit(k)}
                          className="h-8 rounded-full bg-[#a8c7fa] px-3 text-[12.5px] font-semibold text-[#062e6f] hover:bg-[#b8d2fb]"
                        >
                          Admit
                        </button>
                      )}
                    </li>
                  ))}
                </ul>
              </section>
            )}
            {isHost && participants.length > 1 && props.onMuteAll && (
              <button
                type="button"
                onClick={props.onMuteAll}
                className="flex w-full items-center gap-3 rounded-2xl border border-white/12 px-4 py-3 text-left text-[14px] font-medium hover:bg-white/6"
              >
                <MicOff className="h-4 w-4" />
                Mute everyone
              </button>
            )}
            {raised.length > 0 && (
              <section>
                <div className="mb-2 flex items-center gap-2 px-1 text-[12px] font-semibold uppercase tracking-wide text-white/55">
                  <Hand className="h-3.5 w-3.5" /> Raised hands · {raised.length}
                </div>
                <ul className="space-y-1">
                  {raised.map((p) => (
                    <PersonRow key={`hand-${p.id}`} p={p} isHost={isHost} {...props} />
                  ))}
                </ul>
              </section>
            )}
            <section>
              <div className="mb-2 px-1 text-[12px] font-semibold uppercase tracking-wide text-white/55">
                In call · {participants.length}
              </div>
              <ul className="space-y-1">
                {participants.map((p) => (
                  <PersonRow key={p.id} p={p} isHost={isHost} {...props} />
                ))}
              </ul>
            </section>
          </div>
        )}

        {tab === "chat" && (
          <div className="flex h-full flex-col">
            <div className="mb-3 rounded-2xl bg-white/6 px-4 py-3 text-[12px] leading-relaxed text-white/60">
              Messages are visible to everyone in the call and disappear when the
              call ends.
            </div>
            <div ref={listRef} className="flex-1 space-y-3 overflow-y-auto pr-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
              {messages.length === 0 && (
                <p className="px-1 text-[13px] text-white/45">No messages yet.</p>
              )}
              {messages.map((m) => (
                <div key={m.id} className="px-1">
                  <div className="flex items-baseline gap-2 text-[12px]">
                    <span className="font-semibold text-white/90">
                      {m.self ? "You" : m.name}
                    </span>
                    <span className="text-white/40">{formatClock(m.at)}</span>
                  </div>
                  <p className="mt-0.5 whitespace-pre-wrap break-words text-[14px] text-white/85">
                    {m.text}
                  </p>
                </div>
              ))}
            </div>
          </div>
        )}

        {tab === "details" && (
          <div className="space-y-4">
            <div>
              <div className="text-[12px] font-semibold uppercase tracking-wide text-white/55">
                Meeting
              </div>
              <div className="mt-1 text-[16px] font-semibold">{details.title}</div>
              <div className="text-[13px] text-white/55">
                Hosted by @{details.hostName}
                {details.startedAt
                  ? ` · started ${formatClock(new Date(details.startedAt).getTime())}`
                  : ""}
              </div>
            </div>
            <div className="rounded-2xl bg-white/6 p-4">
              <div className="text-[12px] font-semibold uppercase tracking-wide text-white/55">
                Joining info
              </div>
              <div className="mt-2 break-all text-[13px] text-white/85">{details.link}</div>
              {details.code && (
                <div className="mt-1 text-[13px] text-white/55">Code · {details.code}</div>
              )}
              <button
                type="button"
                onClick={() => void copyLink()}
                className="mt-3 flex items-center gap-2 rounded-full bg-white/10 px-4 py-2 text-[13px] font-medium hover:bg-white/15"
              >
                {copied ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
                {copied ? "Copied" : "Copy joining info"}
              </button>
            </div>
          </div>
        )}

        {tab === "host" && isHost && hostControls && (
          <div className="space-y-2">
            <p className="px-1 pb-2 text-[12px] leading-relaxed text-white/55">
              Use these host settings to keep control of your meeting. Only hosts
              have access to these controls.
            </p>
            {hostControls.onToggleQuickAccess && (
              <>
                <div className="px-1 text-[12px] font-semibold uppercase tracking-wide text-white/55">
                  Meeting access
                </div>
                <HostToggle
                  title="Quick access"
                  on={hostControls.quickAccess !== false}
                  onToggle={hostControls.onToggleQuickAccess}
                />
                <p className="px-3 pb-2 text-[12px] leading-relaxed text-white/50">
                  {hostControls.quickAccess !== false
                    ? "Signed-in Whisper members join without asking. Guests without an account always ask to join."
                    : "Everyone must ask to join — you'll see each request and choose who gets in."}
                </p>
              </>
            )}
            <div className="px-1 text-[12px] font-semibold uppercase tracking-wide text-white/55">
              Let everyone
            </div>
            <HostToggle
              title="Send chat messages"
              on={!hostControls.chatLocked}
              onToggle={hostControls.onToggleChatLock}
            />
            <HostToggle
              title="Send reactions"
              on={!hostControls.reactionsLocked}
              onToggle={hostControls.onToggleReactionsLock}
            />
            <HostToggle
              title="Share their screen"
              on={!hostControls.presentLocked}
              onToggle={hostControls.onTogglePresentLock}
            />
            {props.onMuteAll && (
              <button
                type="button"
                onClick={props.onMuteAll}
                className="mt-3 flex w-full items-center gap-3 rounded-2xl border border-white/12 px-4 py-3 text-left text-[14px] font-medium hover:bg-white/6"
              >
                <MicOff className="h-4 w-4" />
                Mute everyone now
              </button>
            )}
          </div>
        )}
      </div>

      {tab === "chat" && (
        <form
          className="flex items-center gap-2 border-t border-white/10 p-3"
          onSubmit={(e) => {
            e.preventDefault();
            const t = draft.trim();
            if (!t || chatDisabled) return;
            onSendChat(t);
            setDraft("");
          }}
        >
          <input
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            disabled={chatDisabled}
            placeholder={chatDisabled ? "Chat is turned off by the host" : "Send a message"}
            className="h-11 flex-1 rounded-full bg-white/8 px-4 text-[14px] text-white outline-none placeholder:text-white/40 focus:bg-white/12 disabled:opacity-50"
          />
          <button
            type="submit"
            disabled={!draft.trim() || chatDisabled}
            aria-label="Send"
            className="grid h-11 w-11 place-items-center rounded-full text-white/80 hover:bg-white/10 disabled:opacity-35"
          >
            <Send className="h-5 w-5" />
          </button>
        </form>
      )}
    </aside>
  );
}

function HostToggle({
  title,
  on,
  onToggle,
}: {
  title: string;
  on: boolean;
  onToggle: () => void;
}): JSX.Element {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={on}
      onClick={onToggle}
      className="flex w-full items-center gap-3 rounded-2xl px-3 py-3 text-left hover:bg-white/6"
    >
      <span className="flex-1 text-[14px]">{title}</span>
      <span
        className={cn(
          "relative h-6 w-11 rounded-full transition-colors",
          on ? "bg-[#a8c7fa]" : "bg-white/20"
        )}
      >
        <span
          className={cn(
            "absolute top-0.5 h-5 w-5 rounded-full bg-white transition-transform",
            on ? "translate-x-[22px]" : "translate-x-0.5"
          )}
        />
      </span>
    </button>
  );
}

function PersonRow({
  p,
  isHost,
  onMute,
  onSpotlight,
  onKick,
  onLowerHand,
}: {
  p: MeetPanelParticipant;
  isHost: boolean;
  onMute?: (p: MeetPanelParticipant) => void;
  onSpotlight?: (p: MeetPanelParticipant) => void;
  onKick?: (p: MeetPanelParticipant) => void;
  onLowerHand?: (p: MeetPanelParticipant) => void;
}): JSX.Element {
  return (
    <li className="group flex items-center gap-3 rounded-2xl px-2 py-2 hover:bg-white/6">
      <Avatar url={p.avatarUrl} name={p.username} size={36} />
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-1.5 text-[14px] font-medium">
          <span className="truncate">{p.isSelf ? `${p.username} (You)` : p.username}</span>
          {p.handRaised && <Hand className="h-3.5 w-3.5 text-[#fdd663]" />}
        </div>
        <div className="text-[12px] text-white/45">
          {p.isHost ? "Meeting host" : p.isSpeaking ? "Speaking" : "In call"}
        </div>
      </div>
      <div className="flex items-center gap-1">
        <span
          className={cn(
            "grid h-8 w-8 place-items-center rounded-full",
            p.micOn ? "text-white/70" : "bg-white/8 text-white/50"
          )}
          aria-label={p.micOn ? "Microphone on" : "Microphone off"}
        >
          {p.micOn ? <Mic className="h-4 w-4" /> : <MicOff className="h-4 w-4" />}
        </span>
        {isHost && !p.isSelf && (
          <div className="hidden items-center gap-0.5 group-hover:flex">
            {p.handRaised && onLowerHand && (
              <IconBtn label="Lower hand" onClick={() => onLowerHand(p)}>
                <Hand className="h-4 w-4" />
              </IconBtn>
            )}
            {p.micOn && onMute && (
              <IconBtn label="Mute" onClick={() => onMute(p)}>
                <MicOff className="h-4 w-4" />
              </IconBtn>
            )}
            {onSpotlight && (
              <IconBtn label="Spotlight" onClick={() => onSpotlight(p)}>
                <Pin className="h-4 w-4" />
              </IconBtn>
            )}
            {onKick && (
              <IconBtn label="Remove" onClick={() => onKick(p)} danger>
                <UserX className="h-4 w-4" />
              </IconBtn>
            )}
          </div>
        )}
      </div>
    </li>
  );
}

function IconBtn({
  label,
  onClick,
  danger,
  children,
}: {
  label: string;
  onClick: () => void;
  danger?: boolean;
  children: React.ReactNode;
}): JSX.Element {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={label}
      title={label}
      className={cn(
        "grid h-8 w-8 place-items-center rounded-full hover:bg-white/12",
        danger ? "text-[#f28b82]" : "text-white/80"
      )}
    >
      {children}
    </button>
  );
}

// ─── More menu ──────────────────────────────────────────────────────────────

export interface MeetMenuItem {
  id: string;
  label: string;
  icon: typeof LayoutGrid;
  onClick: () => void;
  hint?: string;
  danger?: boolean;
  disabled?: boolean;
}

/** The ⋮ "More options" popover anchored above the control bar. */
export function MeetMoreMenu({
  open,
  onClose,
  items,
}: {
  open: boolean;
  onClose: () => void;
  items: MeetMenuItem[];
}): JSX.Element | null {
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent): void => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose]);
  if (!open) return null;
  return (
    <>
      <button
        type="button"
        aria-label="Close menu"
        onClick={onClose}
        className="fixed inset-0 z-[58] cursor-default"
      />
      <div
        role="menu"
        className="absolute bottom-[92px] left-1/2 z-[59] w-[280px] -translate-x-1/2 overflow-hidden rounded-[18px] bg-[#1f2023] py-2 text-white shadow-2xl ring-1 ring-white/10"
      >
        {items.map((it) => {
          const Icon = it.icon;
          return (
            <button
              key={it.id}
              type="button"
              role="menuitem"
              disabled={it.disabled}
              onClick={() => {
                it.onClick();
                onClose();
              }}
              className={cn(
                "flex w-full items-center gap-3 px-4 py-2.5 text-left text-[14px] hover:bg-white/8 disabled:opacity-40",
                it.danger && "text-[#f28b82]"
              )}
            >
              <Icon className="h-[18px] w-[18px] shrink-0 text-white/75" />
              <span className="flex-1">{it.label}</span>
              {it.hint && <span className="text-[11px] text-white/40">{it.hint}</span>}
            </button>
          );
        })}
      </div>
    </>
  );
}

// ─── Post-call screen + "Are you still there?" ──────────────────────────────

/** Why the user is looking at the post-call screen. */
export type PostCallReason = "left" | "host-ended" | "removed" | "alone";

/**
 * Google Meet's post-call page: what happened, Rejoin / Return to home, and
 * the quick audio-video rating. Rendered inside the room shell so the exit
 * never flashes the lobby first.
 */
export function MeetPostCallScreen({
  reason,
  byName,
  title,
  canRejoin,
  onRejoin,
  onHome,
  onRate,
  onNotebook,
}: {
  reason: PostCallReason;
  byName?: string;
  title: string;
  canRejoin: boolean;
  onRejoin: () => void;
  onHome: () => void;
  onRate?: (stars: number) => void;
  onNotebook?: () => void;
}): JSX.Element {
  const [stars, setStars] = useState<number>(0);
  const [hover, setHover] = useState<number>(0);
  const headline: Record<PostCallReason, string> = {
    left: "You left the meeting",
    "host-ended": "The meeting was ended by the host",
    removed: "You were removed from the meeting",
    alone: "You were the only one in the meeting",
  };
  const detail: Record<PostCallReason, string> = {
    left: title,
    "host-ended": byName ? `${byName} ended “${title}” for everyone.` : `“${title}” was ended for everyone.`,
    removed: title,
    alone: "Nobody joined for a while, so we ended the call for you.",
  };
  return (
    <div className="fixed inset-0 z-40 flex flex-col items-center justify-center bg-[#202124] px-6 text-center text-white">
      <div className="flex w-full max-w-md flex-col items-center">
        <h1 className="text-[28px] font-normal leading-tight sm:text-[32px]">{headline[reason]}</h1>
        <p className="mt-2 text-[14px] text-white/65">{detail[reason]}</p>
        {onNotebook && <button type="button" className="mt-6 min-h-11 rounded-full bg-white px-6 text-sm font-semibold text-black" onClick={onNotebook}>Review in Notebook</button>}
        <div className="mt-8 flex items-center gap-3">
          {canRejoin && (
            <button
              type="button"
              onClick={onRejoin}
              className="h-10 rounded-full border border-white/25 px-6 text-[14px] font-medium text-[#a8c7fa] transition-colors hover:bg-white/8"
            >
              Rejoin
            </button>
          )}
          <button
            type="button"
            onClick={onHome}
            className="h-10 rounded-full bg-[#a8c7fa] px-6 text-[14px] font-medium text-[#062e6f] transition-colors hover:bg-[#b8d2fb]"
          >
            Return to home screen
          </button>
        </div>
        <div className="mt-10 w-full rounded-2xl bg-[#2b2c2f] px-5 py-4 ring-1 ring-white/8">
          <p className="text-[14px] font-medium">How was the audio and video?</p>
          <div className="mt-3 flex items-center justify-center gap-1" onMouseLeave={() => setHover(0)}>
            {[1, 2, 3, 4, 5].map((n) => {
              const lit = n <= (hover || stars);
              return (
                <button
                  key={n}
                  type="button"
                  onMouseEnter={() => setHover(n)}
                  onClick={() => {
                    setStars(n);
                    onRate?.(n);
                  }}
                  aria-label={`${n} star${n === 1 ? "" : "s"}`}
                  className="grid h-10 w-10 place-items-center rounded-full transition-colors hover:bg-white/8"
                >
                  <Star
                    className={cn("h-6 w-6 transition-colors", lit ? "fill-[#fdd663] text-[#fdd663]" : "text-white/40")}
                  />
                </button>
              );
            })}
          </div>
          <p className="mt-2 text-[12px] text-white/50">
            {stars > 0 ? "Thanks — that helps us tune the call quality." : "Your feedback stays anonymous."}
          </p>
        </div>
      </div>
    </div>
  );
}

/**
 * Meet's "Are you still there?" — shown after a long stretch alone; the call
 * ends by itself unless the user answers.
 */
export function MeetStillThereDialog({
  open,
  secondsLeft,
  onStay,
  onLeave,
}: {
  open: boolean;
  secondsLeft: number;
  onStay: () => void;
  onLeave: () => void;
}): JSX.Element | null {
  if (!open) return null;
  const m = Math.floor(Math.max(0, secondsLeft) / 60);
  const s = Math.max(0, secondsLeft) % 60;
  return (
    <div className="absolute inset-0 z-[70] flex items-center justify-center bg-black/55 p-4">
      <div className="w-full max-w-sm rounded-[24px] bg-[#2b2c2f] p-6 text-white shadow-2xl ring-1 ring-white/10">
        <h2 className="text-[20px] font-medium">Are you still there?</h2>
        <p className="mt-2 text-[14px] leading-relaxed text-white/70">
          You've been the only one in this meeting for a while. We'll end the call in{" "}
          <span className="font-semibold text-white">
            {m}:{String(s).padStart(2, "0")}
          </span>{" "}
          unless you'd like to stay.
        </p>
        <div className="mt-6 flex justify-end gap-2">
          <button
            type="button"
            onClick={onLeave}
            className="h-10 rounded-full px-4 text-[14px] font-medium text-[#a8c7fa] transition-colors hover:bg-white/8"
          >
            Leave
          </button>
          <button
            type="button"
            onClick={onStay}
            className="h-10 rounded-full bg-[#a8c7fa] px-5 text-[14px] font-medium text-[#062e6f] transition-colors hover:bg-[#b8d2fb]"
          >
            Stay in the meeting
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── "Your meeting's ready" card ────────────────────────────────────────────

/** The card Meet shows the first person in an empty room. */
export function MeetingReadyCard({
  link,
  onInvite,
  onClose,
}: {
  link: string;
  onInvite?: () => void;
  onClose: () => void;
}): JSX.Element {
  const [copied, setCopied] = useState<boolean>(false);
  const copy = async (): Promise<void> => {
    try {
      await navigator.clipboard.writeText(link);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1600);
    } catch {
      // Clipboard blocked — link is shown for manual copy.
    }
  };
  return (
    <div className="pointer-events-auto w-[340px] max-w-[calc(100vw-32px)] rounded-[20px] bg-[#f8f9fa] p-5 text-[#1f1f1f] shadow-2xl">
      <div className="flex items-start">
        <h3 className="text-[18px] font-semibold">Your meeting's ready</h3>
        <button
          type="button"
          onClick={onClose}
          aria-label="Dismiss"
          className="ml-auto grid h-8 w-8 place-items-center rounded-full text-[#444] hover:bg-black/6"
        >
          <X className="h-4 w-4" />
        </button>
      </div>
      {onInvite && (
        <button
          type="button"
          onClick={onInvite}
          className="mt-4 flex h-10 w-full items-center justify-center gap-2 rounded-full bg-[#0b57d0] text-[14px] font-medium text-white hover:bg-[#0a4fbe]"
        >
          <Users className="h-4 w-4" /> Add others
        </button>
      )}
      <p className="mt-4 text-[13px] text-[#444]">
        Or share this meeting link with others you want in the meeting
      </p>
      <div className="mt-2 flex items-center gap-2 rounded-xl bg-[#e9eef6] px-3 py-2">
        <span className="min-w-0 flex-1 truncate text-[13px]">{link}</span>
        <button
          type="button"
          onClick={() => void copy()}
          aria-label="Copy link"
          className="grid h-8 w-8 shrink-0 place-items-center rounded-full text-[#0b57d0] hover:bg-black/6"
        >
          {copied ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
        </button>
      </div>
      <p className="mt-3 flex items-center gap-1.5 text-[12px] text-[#444]">
        <Shield className="h-3.5 w-3.5" /> People who use this meeting link must get your
        permission before they can join.
      </p>
    </div>
  );
}

// ─── Side drawer (role tools · invite · anything that used to be a modal) ────

interface MeetSideDrawerProps {
  title: string;
  icon?: typeof Users;
  /** Accent for the title icon (e.g. cyan for recruiter tools). */
  accent?: string;
  onClose: () => void;
  children: React.ReactNode;
  /** Optional pinned footer (search, copy-link…). */
  footer?: React.ReactNode;
  /** Optional row under the title (a search field, tabs…). */
  header?: React.ReactNode;
}

/**
 * The same geometry as Meet's side panel — a right-hand sheet on desktop,
 * full-height on phones — for the tool surfaces that used to open as
 * centered modals (recruiter / coach / creator tools, invite). Scrollbars
 * are hidden (scrolling still works) and the X is always reachable.
 */
export function MeetSideDrawer({
  title,
  icon: Icon,
  accent,
  onClose,
  children,
  footer,
  header,
}: MeetSideDrawerProps): JSX.Element {
  return (
    <aside
      className="absolute inset-y-0 right-0 z-[56] flex w-full flex-col overflow-hidden bg-[#1f2023] text-white shadow-2xl ring-1 ring-white/10 sm:inset-y-4 sm:right-4 sm:w-[380px] sm:rounded-[16px]"
      style={{
        paddingTop: "env(safe-area-inset-top)",
        animation: "meet-drawer-in 260ms cubic-bezier(0.2, 0.8, 0.2, 1) both",
      }}
      aria-label={title}
      role="dialog"
    >
      <style>{`@keyframes meet-drawer-in{from{opacity:0;transform:translateX(24px)}to{opacity:1;transform:translateX(0)}}`}</style>
      <header className="shrink-0 px-4 pt-3">
        <div className="flex items-center gap-2.5">
          {Icon && (
            <span
              className="grid h-8 w-8 shrink-0 place-items-center rounded-full"
              style={{ background: `${accent ?? "#ffffff"}1f`, color: accent ?? "#ffffff" }}
            >
              <Icon className="h-4 w-4" />
            </span>
          )}
          <h2 className="min-w-0 flex-1 truncate text-[18px] font-medium text-white">{title}</h2>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close"
            className="grid h-11 w-11 shrink-0 place-items-center rounded-full text-white/80 transition-colors hover:bg-white/10 hover:text-white"
          >
            <X className="h-5 w-5" />
          </button>
        </div>
        {header && <div className="mt-2">{header}</div>}
      </header>
      <div className="min-h-0 flex-1 overflow-y-auto px-4 pb-4 pt-3 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
        {children}
      </div>
      {footer && <div className="shrink-0 border-t border-white/10 px-4 py-3">{footer}</div>}
    </aside>
  );
}

// ─── Knocking (Meet's "wants to join this call") ────────────────────────────

/**
 * The floating prompt hosts see when someone asks to join — Meet's grammar:
 * one person → "NAME wants to join this call · Deny entry · Admit"; several →
 * "N people want to join · View all · Admit all". Sits under the top bar.
 */
export function MeetKnockPrompt({
  knocks,
  onAdmit,
  onDeny,
  onAdmitAll,
  onViewAll,
}: {
  knocks: MeetKnock[];
  onAdmit: (knock: MeetKnock) => void;
  onDeny: (knock: MeetKnock) => void;
  onAdmitAll: () => void;
  onViewAll: () => void;
}): JSX.Element | null {
  if (knocks.length === 0) return null;
  const first = knocks[0];
  const many = knocks.length > 1;
  return (
    <div
      className="pointer-events-auto w-[min(22rem,calc(100vw-1.5rem))] rounded-2xl bg-[#303134] p-3.5 text-white shadow-[0_16px_48px_rgba(0,0,0,0.5)] ring-1 ring-white/10"
      style={{ animation: "meet-drawer-in 260ms cubic-bezier(0.2, 0.8, 0.2, 1) both" }}
      role="alertdialog"
      aria-live="polite"
    >
      <div className="flex items-start gap-3">
        {many ? (
          <div className="flex shrink-0 -space-x-2">
            {knocks.slice(0, 3).map((k) => (
              <span key={k.knockId} className="rounded-full ring-2 ring-[#303134]">
                <Avatar url={k.avatarUrl ?? null} name={k.name} size={32} />
              </span>
            ))}
          </div>
        ) : (
          <Avatar url={first.avatarUrl ?? null} name={first.name} size={40} />
        )}
        <div className="min-w-0 flex-1">
          <p className="text-[14px] font-medium leading-snug">
            {many ? `${knocks.length} people want to join this call` : `${first.name} wants to join this call`}
          </p>
          <p className="mt-0.5 text-[12px] text-white/55">
            {many
              ? knocks.slice(0, 3).map((k) => k.name).join(", ") + (knocks.length > 3 ? ` +${knocks.length - 3}` : "")
              : first.isGuest
                ? "Joining as a guest"
                : "Whisper member"}
          </p>
        </div>
      </div>
      <div className="mt-3 flex items-center justify-end gap-1.5">
        {many ? (
          <>
            <button
              type="button"
              onClick={onViewAll}
              className="h-9 rounded-full px-3.5 text-[13px] font-medium text-[#a8c7fa] hover:bg-white/8"
            >
              View all
            </button>
            <button
              type="button"
              onClick={onAdmitAll}
              className="h-9 rounded-full bg-[#a8c7fa] px-4 text-[13px] font-semibold text-[#062e6f] hover:bg-[#b8d2fb]"
            >
              Admit all
            </button>
          </>
        ) : (
          <>
            <button
              type="button"
              onClick={() => onDeny(first)}
              className="h-9 rounded-full px-3.5 text-[13px] font-medium text-white/85 hover:bg-white/8"
            >
              Deny entry
            </button>
            <button
              type="button"
              onClick={() => onAdmit(first)}
              className="flex h-9 items-center gap-1.5 rounded-full bg-[#a8c7fa] px-4 text-[13px] font-semibold text-[#062e6f] hover:bg-[#b8d2fb]"
            >
              <UserCheck className="h-4 w-4" /> Admit
            </button>
          </>
        )}
      </div>
    </div>
  );
}

export type MeetKnockState = "asking" | "waiting-host" | "denied" | "timeout";

/**
 * The knocker's side — replaces the Join button while the request is out.
 * "Asking to join…" once a host has been reached, "Waiting for the host"
 * when nobody in the room can answer yet, and honest end states.
 */
export function MeetAskingToJoin({
  state,
  hostName,
  onCancel,
  onRetry,
}: {
  state: MeetKnockState;
  hostName?: string | null;
  onCancel: () => void;
  onRetry: () => void;
}): JSX.Element {
  const busy = state === "asking" || state === "waiting-host";
  return (
    <div className="rounded-2xl border border-border bg-card px-4 py-4 text-center">
      {busy ? (
        <>
          <div className="mx-auto flex h-10 w-10 items-center justify-center rounded-full bg-foreground/[0.06]">
            <Loader2 className="h-5 w-5 animate-spin text-foreground/70" />
          </div>
          <p className="mt-2.5 text-[15px] font-bold">
            {state === "asking" ? "Asking to join…" : "Waiting for the host…"}
          </p>
          <p className="mt-1 text-[12.5px] leading-relaxed text-muted-foreground">
            {state === "asking"
              ? hostName
                ? `${hostName} has been notified — you'll join the moment they let you in.`
                : "You'll join the call when someone lets you in."
              : "Nobody in the room can let you in yet. Keep this tab open — your request is delivered the moment the host arrives."}
          </p>
          <button
            type="button"
            onClick={onCancel}
            className="mt-3 h-10 rounded-full border border-border px-5 text-[13px] font-bold hover:bg-secondary"
          >
            Cancel request
          </button>
        </>
      ) : state === "denied" ? (
        <>
          <div className="mx-auto flex h-10 w-10 items-center justify-center rounded-full bg-red-500/12 text-red-500">
            <UserX className="h-5 w-5" />
          </div>
          <p className="mt-2.5 text-[15px] font-bold">You can't join this call</p>
          <p className="mt-1 text-[12.5px] leading-relaxed text-muted-foreground">
            Someone in the call denied your request to join.
          </p>
        </>
      ) : (
        <>
          <div className="mx-auto flex h-10 w-10 items-center justify-center rounded-full bg-amber-500/12 text-amber-600">
            <Hand className="h-5 w-5" />
          </div>
          <p className="mt-2.5 text-[15px] font-bold">No one responded</p>
          <p className="mt-1 text-[12.5px] leading-relaxed text-muted-foreground">
            Nobody answered your request to join. You can ask again.
          </p>
          <button
            type="button"
            onClick={onRetry}
            className="mt-3 h-10 rounded-full bg-foreground px-5 text-[13px] font-bold text-background"
          >
            Ask to join again
          </button>
        </>
      )}
    </div>
  );
}
