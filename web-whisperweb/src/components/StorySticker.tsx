import { memo, useEffect, useRef, useState } from "react";
import { AtSign, MapPin, Music as MusicIcon, Check } from "lucide-react";

import { Avatar } from "@/components/Avatar";
import { cn } from "@/lib/utils";
import {
  jasperStickerName,
  sharedPostCardSize,
  photoShapeClipPath,
  type StorySticker as StoryStickerModel,
} from "@/lib/storyStickers";

function safeHex(hex: string | null | undefined, fallback: string): string {
  if (!hex) return fallback;
  const s = hex.startsWith("#") ? hex : `#${hex}`;
  return /^#[0-9a-fA-F]{6}$/.test(s) ? s : fallback;
}

export interface StoryStickerProps {
  sticker: StoryStickerModel;
  /** Viewer mode — enables votes, slider drag, question typing, taps. */
  interactive?: boolean;
  // Poll
  pollTally?: Record<string, number> | null;
  votedIndex?: number | null;
  pendingPollIndex?: number | null;
  onPickPoll?: (index: number) => void;
  // Slider
  pendingSliderValue?: number | null;
  onSlide?: (value: number) => void;
  // Question
  editableQuestion?: boolean;
  questionText?: string;
  onChangeQuestion?: (value: string) => void;
  // Generic tap (mention / location / begin question)
  onTap?: () => void;
  authorUsername?: string;
  authorAvatarUrl?: string | null;
}

/**
 * Renders a single story sticker overlay, matching the iOS
 * `WhisperStoryStickerView`. The caller positions it (absolute) and applies
 * scale/rotation; this component only draws the sticker body.
 */
function StoryStickerBase(props: StoryStickerProps) {
  const { sticker, interactive } = props;
  switch (sticker.kind) {
    case "text":
      return <TextBubble sticker={sticker} />;
    case "poll":
      return <PollCard {...props} />;
    case "slider":
      return props.onSlide ? <SliderCard {...props} /> : <Tappable interactive={interactive} onTap={props.onTap}><SliderCard {...props} interactive={false} /></Tappable>;
    case "question":
      return props.editableQuestion ? <QuestionCard {...props} /> : <Tappable interactive={interactive} onTap={props.onTap}><QuestionCard {...props} /></Tappable>;
    case "location":
      return (
        <Tappable interactive={interactive} onTap={props.onTap}>
          <LocationCard label={sticker.label ?? ""} />
        </Tappable>
      );
    case "mention":
      return (
        <Tappable interactive={interactive} onTap={props.onTap}>
          <PillCard icon={<AtSign className="h-4 w-4" />} text={sticker.label ?? ""} />
        </Tappable>
      );
    case "music":
      return <MusicChip sticker={sticker} />;
    case "gif":
    case "sticker":
    case "photo":
      return <ImageSticker sticker={sticker} />;
    case "wave":
      return (
        <SeePostWrap interactive={interactive} onOpen={props.onTap} label="Watch wave">
          <WaveCard sticker={sticker} interactive={interactive} />
        </SeePostWrap>
      );
    case "post":
      return (
        <SeePostWrap interactive={interactive} onOpen={props.onTap} label="See post">
          <PostCard sticker={sticker} />
        </SeePostWrap>
      );
    case "hashtag":
      return <HashtagCard label={sticker.label ?? ""} />;
    case "countdown":
      return <CountdownCard label={sticker.label ?? ""} target={sticker.text ?? null} />;
    default:
      return null;
  }
}

/** Instagram hashtag sticker — white pill, gradient tag text. */
function HashtagCard({ label }: { label: string }) {
  return (
    <span className="inline-block rounded-full bg-white px-4 py-1.5 shadow-lg">
      <span
        className="text-[22px] font-black tracking-tight"
        style={{
          backgroundImage: "linear-gradient(135deg, #405DE6, #833AB4, #E1306C)",
          WebkitBackgroundClip: "text",
          backgroundClip: "text",
          color: "transparent",
        }}
      >
        #{label.toUpperCase()}
      </span>
    </span>
  );
}

/** Instagram countdown sticker — white card with the remaining time. */
function CountdownCard({ label, target }: { label: string; target: string | null }) {
  const ms = target ? Date.parse(target) : NaN;
  const s = Number.isFinite(ms) ? Math.max(0, Math.floor((ms - Date.now()) / 1000)) : 0;
  const days = Math.floor(s / 86_400);
  const hours = Math.floor((s % 86_400) / 3_600);
  const mins = Math.floor((s % 3_600) / 60);
  const remaining =
    s === 0
      ? "It's time!"
      : days > 0
        ? `${days}d ${String(hours).padStart(2, "0")}:${String(mins).padStart(2, "0")}`
        : `${String(hours).padStart(2, "0")}:${String(mins).padStart(2, "0")}`;
  return (
    <div className="rounded-2xl bg-white px-6 py-3.5 text-center shadow-lg">
      <p className="text-[11px] font-extrabold uppercase tracking-wider text-black/55">
        {label || "Countdown"}
      </p>
      <p
        className="text-[26px] font-black tabular-nums"
        style={{
          backgroundImage: "linear-gradient(135deg, #405DE6, #833AB4, #E1306C)",
          WebkitBackgroundClip: "text",
          backgroundClip: "text",
          color: "transparent",
        }}
      >
        {remaining}
      </p>
    </div>
  );
}

function Tappable({
  interactive,
  onTap,
  children,
}: {
  interactive?: boolean;
  onTap?: () => void;
  children: React.ReactNode;
}) {
  if (interactive && onTap) {
    return (
      <button type="button" onClick={onTap} className="block active:scale-95">
        {children}
      </button>
    );
  }
  return <>{children}</>;
}

function TextBubble({ sticker }: { sticker: StoryStickerModel }) {
  const s = sticker.style ?? 0;
  const fg = safeHex(sticker.color, "#FFFFFF");
  const bg = safeHex(sticker.background, "#000000");
  const base: React.CSSProperties = { color: fg };
  const fontSize = s === 5 ? 26 : s === 4 ? 30 : 28;
  const fontWeight = s === 4 ? 900 : (800 as const);
  const isMono = s === 5;
  const style: React.CSSProperties = {
    ...base,
    fontSize,
    fontWeight,
    fontFamily: isMono ? "ui-monospace, SFMono-Regular, Menlo, monospace" : undefined,
    padding: s === 0 ? 0 : "8px 14px",
    background:
      s === 1 || s === 2 ? "transparent" : s === 4 ? bg : s === 5 ? `${bg}e0` : "transparent",
    border: s === 2 ? `2px solid ${bg}` : undefined,
    borderRadius: s === 1 || s === 2 ? 999 : s === 4 ? 6 : s === 5 ? 4 : 0,
    textShadow:
      s === 0
        ? "0 1px 4px rgba(0,0,0,0.4)"
        : s === 3
          ? `0 0 6px ${fg}, 0 0 14px ${fg}99`
          : undefined,
    backgroundColor: s === 1 ? bg : undefined,
    lineHeight: 1.1,
    whiteSpace: "pre-wrap",
    textAlign: "center",
  };
  return <div style={style}>{sticker.text ?? ""}</div>;
}

function PollCard(props: StoryStickerProps) {
  const { sticker, interactive, pollTally, votedIndex, pendingPollIndex, onPickPoll } = props;
  const options = sticker.pollOptions?.length ? sticker.pollOptions : ["Yes", "No"];
  const selected = pendingPollIndex ?? null;
  const showResults = !!pollTally;

  return (
    <div className="w-[min(240px,82vw)] rounded-[18px] bg-white px-3.5 py-3.5 text-black shadow-xl">
      <p className="text-center text-[11px] font-extrabold tracking-[0.12em] text-neutral-500">
        POLL
      </p>
      {sticker.text ? (
        <p className="mt-1 text-center text-[15px] font-bold leading-snug">{sticker.text}</p>
      ) : null}
      {showResults ? (
        <div className="mt-2.5 space-y-1.5">
          {options.map((opt, idx) => {
            const counts = pollTally ?? {};
            const total = Math.max(
              1,
              Object.values(counts).reduce((a, b) => a + b, 0)
            );
            const n = counts[opt] ?? 0;
            const pct = Math.round((n / total) * 100);
            const mine = votedIndex === idx;
            return (
              <div
                key={`${opt}-${idx}`}
                className="relative h-[34px] overflow-hidden rounded-[10px] bg-black/[0.06]"
              >
                <div
                  className={cn(
                    "absolute inset-y-0 left-0 rounded-[10px] transition-all duration-500",
                    mine ? "bg-green-500/30" : "bg-black/[0.16]"
                  )}
                  style={{ width: `${Math.max(8, pct)}%` }}
                />
                <div className="absolute inset-0 flex items-center gap-1.5 px-3">
                  <span className={cn("text-sm", mine ? "font-extrabold" : "font-semibold")}>
                    {opt}
                  </span>
                  {mine && <Check className="h-3.5 w-3.5 text-green-600" />}
                  <span className="ml-auto text-sm font-extrabold tabular-nums">{pct}%</span>
                </div>
              </div>
            );
          })}
        </div>
      ) : (
        <div className="mt-2.5 flex items-stretch">
          {options.map((opt, idx) => (
            <div key={`${opt}-${idx}`} className="flex flex-1 items-stretch">
              <button
                type="button"
                disabled={!interactive}
                onClick={() => onPickPoll?.(idx)}
                className={cn(
                  "flex flex-1 items-center justify-center gap-1 py-2.5 text-sm font-semibold transition-transform",
                  selected === idx ? "scale-105 bg-green-500/[0.18]" : ""
                )}
              >
                {opt}
                {selected === idx && <Check className="h-4 w-4 text-green-600" />}
              </button>
              {idx < options.length - 1 && <div className="my-1 w-px bg-black/10" />}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function SliderCard(props: StoryStickerProps) {
  const { sticker, interactive, pendingSliderValue, onSlide } = props;
  const value = pendingSliderValue ?? 0.5;
  const emoji = sticker.sliderEmoji || "❤️";
  const trackRef = useRef<HTMLDivElement>(null);

  const updateFromClientX = (clientX: number): void => {
    const el = trackRef.current;
    if (!el) return;
    const rect = el.getBoundingClientRect();
    const v = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
    onSlide?.(v);
  };

  return (
    <div className="w-[min(240px,82vw)] rounded-[18px] bg-gradient-to-b from-white to-neutral-100 p-3.5 text-black shadow-xl">
      <p className="text-center text-[11px] font-extrabold tracking-[0.12em] text-neutral-500">
        SLIDE TO RATE
      </p>
      <p className="mt-1 text-center text-[15px] font-bold leading-snug">
        {sticker.text || "Slide to rate"}
      </p>
      <div
        ref={trackRef}
        className="relative mt-3 h-12 select-none touch-none"
        onPointerDown={
          interactive
            ? (e) => {
                (e.target as HTMLElement).setPointerCapture?.(e.pointerId);
                updateFromClientX(e.clientX);
              }
            : undefined
        }
        onPointerMove={
          interactive
            ? (e) => {
                if (e.buttons === 1) updateFromClientX(e.clientX);
              }
            : undefined
        }
      >
        <div className="absolute left-0 right-0 top-1/2 h-2 -translate-y-1/2 rounded-full bg-gradient-to-r from-white to-neutral-300" />
        <span
          className="absolute top-1/2 -translate-x-1/2 -translate-y-1/2"
          style={{ left: `${value * 100}%`, fontSize: 24 + value * 24 }}
        >
          {emoji}
        </span>
      </div>
    </div>
  );
}

function QuestionCard(props: StoryStickerProps) {
  const { sticker, editableQuestion, questionText, onChangeQuestion, authorUsername, authorAvatarUrl } =
    props;
  const bg = safeHex(sticker.background, "#FFFFFF");
  const fg = safeHex(sticker.color, "#000000");
  const bakedAnswer = sticker.answer?.trim();
  const hasAnswer = !!bakedAnswer;
  const showAvatar = !hasAnswer && !!authorUsername;

  return (
    <div className="relative" style={{ width: editableQuestion ? 260 : 240 }}>
      {showAvatar && (
        <div className="absolute left-1/2 top-0 z-10 -translate-x-1/2 -translate-y-1/2">
          <div className="rounded-full border-[3px] border-white shadow-md">
            <Avatar name={authorUsername} url={authorAvatarUrl ?? undefined} size={50} />
          </div>
        </div>
      )}
      <div
        className="rounded-[18px] px-3.5 pb-3.5 shadow-xl"
        style={{ background: bg, color: fg, paddingTop: showAvatar ? 44 : 14 }}
      >
        <p
          className="text-center text-[11px] font-extrabold tracking-[0.1em]"
          style={{ color: `${fg}a6` }}
        >
          ASK ME ANYTHING
        </p>
        <p className="mt-2 text-center text-[15px] font-bold">
          {sticker.text || "Ask me anything…"}
        </p>
        {hasAnswer ? (
          <p className="mt-2.5 rounded-[12px] bg-black px-3.5 py-2.5 text-center text-[15px] font-extrabold text-white">
            {bakedAnswer}
          </p>
        ) : editableQuestion ? (
          <input
            autoFocus
            value={questionText ?? ""}
            onChange={(e) => onChangeQuestion?.(e.target.value)}
            placeholder="Type something…"
            className="mt-2.5 w-full rounded-[12px] px-3 py-2 text-sm font-semibold outline-none"
            style={{ background: `${fg}1f`, color: fg }}
          />
        ) : (
          <p
            className="mt-2.5 rounded-[10px] px-3 py-2 text-center text-xs"
            style={{ background: `${fg}14`, color: `${fg}8c` }}
          >
            Type something…
          </p>
        )}
      </div>
    </div>
  );
}

function LocationCard({ label }: { label: string }) {
  return (
    <div className="flex items-center gap-2.5 rounded-[16px] bg-white px-3 py-2 shadow-lg">
      <span className="flex h-8 w-8 items-center justify-center rounded-full bg-gradient-to-br from-[#ff5c66] to-[#ff8c33]">
        <MapPin className="h-4 w-4 text-white" />
      </span>
      <span className="flex flex-col leading-tight">
        <span className="text-sm font-extrabold uppercase tracking-wide text-black">{label}</span>
        <span className="text-[9px] font-bold tracking-wide text-neutral-500">Open in Maps</span>
      </span>
    </div>
  );
}

function PillCard({ icon, text }: { icon: React.ReactNode; text: string }) {
  return (
    <span className="inline-flex items-center gap-1.5 rounded-full bg-white px-3 py-2 text-black shadow-md">
      {icon}
      <span className="text-sm font-extrabold uppercase tracking-wide">{text}</span>
    </span>
  );
}

function MusicChip({ sticker }: { sticker: StoryStickerModel }) {
  return (
    <span className="inline-flex items-center gap-2.5 rounded-full border border-white/20 bg-black/55 px-2.5 py-1.5 text-white backdrop-blur">
      {sticker.musicArtwork ? (
        <img src={sticker.musicArtwork} alt="" className="h-[34px] w-[34px] rounded-md object-cover" />
      ) : (
        <span className="flex h-[34px] w-[34px] items-center justify-center rounded-md bg-white/20">
          <MusicIcon className="h-4 w-4" />
        </span>
      )}
      <span className="flex max-w-[160px] flex-col leading-tight">
        <span className="truncate text-xs font-bold">{sticker.musicTitle ?? ""}</span>
        <span className="truncate text-[11px] opacity-80">{sticker.musicArtist ?? ""}</span>
      </span>
      <MusicIcon className="h-3.5 w-3.5 opacity-70" />
    </span>
  );
}

function ImageSticker({ sticker }: { sticker: StoryStickerModel }) {
  const url = sticker.imageURL ?? "";
  if (!url) return null;
  // Bundled Jasper stickers aren't available on web — skip cleanly.
  if (jasperStickerName(url)) return null;
  const isPhoto = sticker.kind === "photo";
  const clip = isPhoto ? photoShapeClipPath(sticker.shape) : undefined;
  return (
    <img
      src={url}
      alt=""
      className={cn(
        "object-contain drop-shadow-lg",
        isPhoto ? "h-40 w-40 object-cover" : "h-32 w-32",
        isPhoto && !clip ? "rounded-[22px]" : ""
      )}
      style={clip ? { clipPath: clip, WebkitClipPath: clip } : undefined}
    />
  );
}

/**
 * Instagram's "Add reel to your story" card — a 9:16 rounded card with the
 * wave's cover (muted loop in the viewer), the author row beneath, and the
 * "Watch wave" pill. Identical geometry to the iOS card (186×330).
 */
function WaveCard({ sticker, interactive }: { sticker: StoryStickerModel; interactive: boolean }) {
  const cover = sticker.imageURL ?? null;
  const video = sticker.videoURL ?? null;
  return (
    <div className="flex w-[186px] flex-col drop-shadow-[0_8px_16px_rgba(0,0,0,0.35)]">
      <div className="relative h-[330px] w-[186px] overflow-hidden rounded-[18px] bg-black">
        {cover ? <img src={cover} alt="" className="absolute inset-0 h-full w-full object-cover" /> : null}
        {video && interactive ? (
          <video src={video} muted loop autoPlay playsInline className="absolute inset-0 h-full w-full object-cover" />
        ) : null}
        <div className="absolute inset-0 bg-gradient-to-b from-transparent via-transparent to-black/55" />
        <div className="absolute right-2.5 top-2.5 text-white drop-shadow">
          <svg viewBox="0 0 24 24" className="h-3.5 w-3.5" fill="currentColor">
            <path d="M4 5a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V5zm6 3v8l6-4-6-4z" />
          </svg>
        </div>
        {!interactive || !video ? (
          <div className="absolute inset-0 flex items-center justify-center">
            <svg viewBox="0 0 24 24" className="h-8 w-8 text-white/95 drop-shadow-lg" fill="currentColor">
              <path d="M8 5v14l11-7z" />
            </svg>
          </div>
        ) : null}
        <div className="absolute bottom-3 left-0 right-0 flex justify-center">
          <span className="flex items-center gap-1.5 rounded-full bg-white px-2.5 py-1.5 text-[11px] font-extrabold text-black">
            <svg viewBox="0 0 24 24" className="h-2.5 w-2.5" fill="currentColor"><path d="M8 5v14l11-7z" /></svg>
            Watch wave
          </span>
        </div>
      </div>
      <div className="mt-2 flex items-center gap-1.5 text-white">
        <span className="flex h-[22px] w-[22px] items-center justify-center rounded-full bg-white/20 text-[10px] font-bold">
          {(sticker.label ?? "?").slice(0, 1).toUpperCase()}
        </span>
        <span className="truncate text-[12px] font-bold">@{sticker.label ?? ""}</span>
        {sticker.text ? <span className="truncate text-[12px] text-white/80">· {sticker.text}</span> : null}
      </div>
    </div>
  );
}

/**
 * Instagram's two-tap grammar for shared posts and waves: the FIRST tap arms
 * a "See post ›" pill on the card (it fades after a few seconds); the pill's
 * tap opens the original. Mirrors iOS `WhisperStorySeePostWrap` exactly.
 */
function SeePostWrap({
  interactive,
  onOpen,
  label,
  children,
}: {
  interactive?: boolean;
  onOpen?: () => void;
  label: string;
  children: React.ReactNode;
}) {
  const [armed, setArmed] = useState<boolean>(false);
  const timer = useRef<number | null>(null);
  useEffect(() => () => { if (timer.current) window.clearTimeout(timer.current); }, []);
  if (!interactive || !onOpen) return <>{children}</>;
  return (
    <div className="relative">
      <button
        type="button"
        className="block text-left"
        onClick={(e) => {
          e.stopPropagation();
          setArmed(true);
          if (timer.current) window.clearTimeout(timer.current);
          timer.current = window.setTimeout(() => setArmed(false), 3200);
        }}
      >
        {children}
      </button>
      {armed ? (
        <button
          type="button"
          onClick={(e) => {
            e.stopPropagation();
            if (timer.current) window.clearTimeout(timer.current);
            onOpen();
          }}
          className="jasper-pill-in absolute -right-3 top-11 flex items-center gap-1 rounded-[10px] border border-white/15 bg-black/60 px-4 py-2.5 text-[15px] font-semibold text-white shadow-[0_4px_12px_rgba(0,0,0,0.3)] backdrop-blur-sm"
        >
          {label}
          <svg viewBox="0 0 24 24" className="h-3.5 w-3.5" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
            <path d="M9 6l6 6-6 6" />
          </svg>
        </button>
      ) : null}
    </div>
  );
}

/** Instagram's shared-post glyph — a small white rounded square with a notch. */
function SharedPostGlyph() {
  return (
    <span className="relative inline-flex h-6 w-6 items-center justify-center drop-shadow">
      <span className="absolute h-5 w-5 rounded-[6px] bg-white" />
      <span className="absolute bottom-0 right-0 h-[7px] w-[7px] rounded-full bg-white" />
      <span className="relative h-[9px] w-[9px] rounded-[3px] bg-black/85" />
    </span>
  );
}

/**
 * Instagram's shared-post grammar (the reference screenshots): the post's
 * PICTURE is the card — rounded corners, no white frame, no author row —
 * with the small white post glyph in its top-right corner and the author's
 * @handle credited BENEATH the card. Text-only posts render as a quiet ink
 * card carrying the author row + the words. Mirrors iOS `postCard`.
 */
function PostCard({ sticker }: { sticker: StoryStickerModel }) {
  const cardRef = useRef<HTMLDivElement>(null);
  const [stageWidth, setStageWidth] = useState<number>(390);
  useEffect(() => {
    const stage = cardRef.current?.closest<HTMLElement>("[data-story-stage]");
    if (!stage) return;
    const update = (): void => {
      const reference = Number(stage.dataset.storyReferenceWidth);
      setStageWidth(Number.isFinite(reference) && reference >= 100 && reference <= 4096 ? reference : stage.clientWidth);
    };
    update();
    const observer = new ResizeObserver(update);
    observer.observe(stage);
    const attributes = new MutationObserver(update);
    attributes.observe(stage, { attributes: true, attributeFilter: ["data-story-reference-width"] });
    return () => { observer.disconnect(); attributes.disconnect(); };
  }, []);
  const size = sharedPostCardSize(sticker, stageWidth);
  const cover = sticker.imageURL ?? null;
  const name = sticker.label ?? "";
  return (
    <div ref={cardRef} className="flex w-fit flex-col gap-2.5 drop-shadow-[0_10px_18px_rgba(0,0,0,0.3)]">
      {cover ? (
        <div className="relative overflow-hidden rounded-[14px] bg-[#1f1f1f]">
          <svg width={size.width} height={size.height} aria-hidden="true" className="block" />
          <img src={cover} alt="" className={cn("absolute inset-0 h-full w-full", sticker.mediaAspectRatio == null ? "object-cover" : "object-contain")} draggable={false} />
          <div className="absolute right-2.5 top-2.5">
            <SharedPostGlyph />
          </div>
        </div>
      ) : (
        <div className="w-[250px] space-y-2.5 rounded-[14px] border border-white/10 bg-[#171717]/95 p-3.5">
          <div className="flex items-center gap-2">
            <span className="flex h-[26px] w-[26px] items-center justify-center rounded-full bg-white/15 text-[10px] font-bold text-white">
              {name.slice(0, 1).toUpperCase() || "?"}
            </span>
            <span className="truncate text-[13px] font-bold text-white">{name}</span>
            <span className="ml-auto"><SharedPostGlyph /></span>
          </div>
          <p className="line-clamp-[8] whitespace-pre-wrap text-[16px] font-semibold leading-snug text-white">{sticker.text ?? ""}</p>
        </div>
      )}
      <span className="pl-1 text-[13.5px] font-semibold text-white/90 drop-shadow">@{name}</span>
    </div>
  );
}

export const StorySticker = memo(StoryStickerBase);
