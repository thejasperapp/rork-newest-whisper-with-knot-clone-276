import {
  createContext,
  useContext,
  useEffect,
  useRef,
  useState,
  type ReactNode,
  type RefObject,
} from "react";
import { createPortal } from "react-dom";

import { cn } from "@/lib/utils";

interface PhoneFrameContextValue {
  /** Whether the simulator frame is currently active. */
  enabled: boolean;
  /** The simulator screen element (the inner rounded rectangle). */
  screenRef: RefObject<HTMLElement | null>;
  /** The scrollable content container inside the screen. */
  scrollRef: RefObject<HTMLElement | null>;
}

const PhoneFrameContext = createContext<PhoneFrameContextValue | null>(null);

export function usePhoneFrame(): PhoneFrameContextValue {
  const ctx = useContext(PhoneFrameContext);
  return ctx ?? { enabled: false, screenRef: { current: null }, scrollRef: { current: null } };
}

function StatusBarIcon({ children }: { children: ReactNode }) {
  return <span className="text-background/90">{children}</span>;
}

function SignalIcon() {
  return (
    <svg width="14" height="10" viewBox="0 0 14 10" fill="currentColor" className="opacity-90">
      <rect x="10" y="2" width="2" height="8" rx="1" />
      <rect x="7" y="4" width="2" height="6" rx="1" />
      <rect x="4" y="6" width="2" height="4" rx="1" />
      <rect x="1" y="8" width="2" height="2" rx="1" />
    </svg>
  );
}

function WifiIcon() {
  return (
    <svg width="14" height="10" viewBox="0 0 14 10" fill="none" stroke="currentColor" strokeWidth="1.5" className="opacity-90">
      <path d="M1 3.5C2.5 2.2 4.5 1.5 7 1.5s4.5.7 6 2" />
      <path d="M3 5.5c1-1 2.2-1.5 4-1.5s3 .5 4 1.5" />
      <path d="M5 7.5c.6-.5 1.2-.7 2-.7s1.4.2 2 .7" />
      <circle cx="7" cy="9" r="0.7" fill="currentColor" stroke="none" />
    </svg>
  );
}

function BatteryIcon() {
  return (
    <svg width="22" height="11" viewBox="0 0 22 11" fill="none" className="opacity-90">
      <rect x="0.5" y="0.5" width="19" height="10" rx="2.5" stroke="currentColor" strokeOpacity="0.8" />
      <rect x="2.5" y="2.5" width="14" height="6" rx="1" fill="currentColor" />
      <rect x="21" y="3.5" width="1" height="4" rx="0.5" fill="currentColor" />
    </svg>
  );
}

/**
 * A realistic phone simulator frame that wraps the live pitch deck content.
 * When enabled, sheets/modals inside the deck use <PitchSheet> so they fill the
 * simulator screen rather than the entire browser viewport.
 */
export function PitchPhoneFrame({ children, enabled }: { children: ReactNode; enabled: boolean }) {
  const frameRef = useRef<HTMLDivElement>(null);
  const screenRef = useRef<HTMLDivElement>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const [time, setTime] = useState<string>("9:41");

  useEffect(() => {
    const tick = () => {
      const now = new Date();
      setTime(
        now.toLocaleTimeString("en-US", {
          hour: "numeric",
          minute: "2-digit",
          hour12: true,
        })
      );
    };
    tick();
    const id = setInterval(tick, 30_000);
    return () => clearInterval(id);
  }, []);

  if (!enabled) {
    return <>{children}</>;
  }

  return (
    <PhoneFrameContext.Provider value={{ enabled: true, screenRef, scrollRef }}>
      <div className="flex justify-center py-6">
        <div
          ref={frameRef}
          className="relative flex flex-col overflow-hidden rounded-[52px] border-[10px] border-foreground bg-foreground shadow-2xl"
          style={{
            width: "100%",
            maxWidth: 390,
            maxHeight: "min(84vh, 850px)",
            aspectRatio: "9 / 19.5",
          }}
        >
          {/* Dynamic Island */}
          <div className="absolute left-1/2 top-3 z-30 h-7 w-28 -translate-x-1/2 rounded-full bg-black" />

          {/* Status bar */}
          <div className="pointer-events-none absolute inset-x-0 top-0 z-20 flex h-12 items-end justify-between px-7 pb-1 text-[11px] font-semibold tabular-nums text-background">
            <span>{time}</span>
            <div className="flex items-center gap-1.5">
              <StatusBarIcon>
                <SignalIcon />
              </StatusBarIcon>
              <StatusBarIcon>
                <WifiIcon />
              </StatusBarIcon>
              <StatusBarIcon>
                <BatteryIcon />
              </StatusBarIcon>
            </div>
          </div>

          {/* Side buttons */}
          <div className="absolute -left-[12px] top-[112px] h-[34px] w-[4px] rounded-l-[2px] bg-foreground/70" />
          <div className="absolute -left-[12px] top-[158px] h-[54px] w-[4px] rounded-l-[2px] bg-foreground/70" />
          <div className="absolute -right-[12px] top-[144px] h-[80px] w-[4px] rounded-r-[2px] bg-foreground/70" />

          {/* Screen */}
          <div
            ref={screenRef}
            className="relative h-full w-full overflow-hidden rounded-[42px] bg-background"
          >
            <div
              ref={scrollRef}
              className="h-full w-full overflow-y-auto overflow-x-hidden px-4 pb-8"
            >
              {children}
            </div>

            {/* Home indicator */}
            <div className="pointer-events-none absolute bottom-2 left-1/2 z-20 h-[5px] w-28 -translate-x-1/2 rounded-full bg-foreground/30" />

            {/* Subtle reflection overlay */}
            <div className="pointer-events-none absolute inset-0 z-10 rounded-[42px] bg-gradient-to-tr from-white/5 via-transparent to-black/5" />
          </div>
        </div>
      </div>
    </PhoneFrameContext.Provider>
  );
}

interface PitchSheetProps {
  open: boolean;
  onClose: () => void;
  children: ReactNode;
  /** z-index above the screen content (sheets are 80, apply sub-sheets are 90). */
  zIndex?: 80 | 90;
}

/**
 * Modal/sheet wrapper that adapts to the simulator frame. When the phone frame
 * is on, the sheet is rendered inside the simulator screen and fills it. When
 * the frame is off, it behaves as a normal full-viewport modal.
 */
export function PitchSheet({ open, onClose, children, zIndex = 80 }: PitchSheetProps) {
  const { enabled, screenRef, scrollRef } = usePhoneFrame();

  // Lock the screen scroll while the sheet is open in simulator mode.
  useEffect(() => {
    if (!open || !enabled || !scrollRef.current) return;
    const scroller = scrollRef.current;
    const original = scroller.style.overflow;
    scroller.style.overflow = "hidden";
    return () => {
      scroller.style.overflow = original;
    };
  }, [open, enabled, scrollRef]);

  // Lock the document body while the sheet is open in normal mode.
  useEffect(() => {
    if (!open || enabled) return;
    const original = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = original;
    };
  }, [open, enabled]);

  if (!open) return null;

  const zClass = zIndex === 90 ? "z-[90]" : "z-[80]";

  const sheet = (
    <div
      role="dialog"
      aria-modal="true"
      className={cn(
        "flex flex-col",
        zClass,
        enabled
          ? "absolute inset-0 overflow-hidden rounded-[42px]"
          : "fixed inset-0 items-end justify-center bg-black/50 backdrop-blur-sm sm:items-center"
      )}
    >
      {enabled && (
        <button
          aria-label="Close"
          onClick={onClose}
          className="absolute inset-0 bg-black/50 backdrop-blur-sm transition-opacity"
        />
      )}
      <div
        className={cn(
          "relative flex h-full w-full flex-col overflow-hidden bg-card shadow-2xl",
          !enabled && "h-[100dvh] max-w-md sm:h-auto sm:max-h-[92vh] sm:rounded-[24px]"
        )}
      >
        {children}
      </div>
    </div>
  );

  if (enabled && screenRef.current) {
    return createPortal(sheet, screenRef.current);
  }
  return sheet;
}
