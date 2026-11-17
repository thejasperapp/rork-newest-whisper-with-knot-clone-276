import { useCallback, useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { X } from "lucide-react";

import { Avatar } from "@/components/Avatar";

interface AvatarLightboxProps {
  open: boolean;
  onClose: () => void;
  url?: string | null;
  name?: string | null;
}

/**
 * Full-screen profile-picture viewer — the picture lifts onto a black stage
 * where you can ZOOM (scroll wheel / pinch on trackpads, or click to toggle
 * 1× ↔ 2.4×), drag to pan while zoomed, and Esc / click outside / ✕ to
 * close. Mirrors `WhisperAvatarZoomView` on iOS. Rendered through a portal
 * so an animated ancestor can never re-anchor it.
 */
export function AvatarLightbox({ open, onClose, url, name }: AvatarLightboxProps) {
  const [scale, setScale] = useState<number>(1);
  const [offset, setOffset] = useState<{ x: number; y: number }>({ x: 0, y: 0 });
  const [entered, setEntered] = useState<boolean>(false);
  const dragRef = useRef<{ x: number; y: number; ox: number; oy: number } | null>(null);
  const movedRef = useRef<boolean>(false);

  useEffect(() => {
    if (!open) {
      setEntered(false);
      return;
    }
    setScale(1);
    setOffset({ x: 0, y: 0 });
    const raf = window.requestAnimationFrame(() => setEntered(true));
    const onKey = (e: KeyboardEvent): void => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      window.cancelAnimationFrame(raf);
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = prevOverflow;
    };
  }, [open, onClose]);

  const clampScale = (s: number): number => Math.min(4, Math.max(1, s));

  const onWheel = useCallback((e: React.WheelEvent<HTMLDivElement>): void => {
    e.preventDefault();
    setScale((s) => {
      const next = clampScale(s - e.deltaY * 0.0035);
      if (next <= 1) setOffset({ x: 0, y: 0 });
      return next;
    });
  }, []);

  const onPointerDown = (e: React.PointerEvent<HTMLDivElement>): void => {
    if (scale <= 1) return;
    movedRef.current = false;
    dragRef.current = { x: e.clientX, y: e.clientY, ox: offset.x, oy: offset.y };
    (e.currentTarget as HTMLDivElement).setPointerCapture(e.pointerId);
  };
  const onPointerMove = (e: React.PointerEvent<HTMLDivElement>): void => {
    const d = dragRef.current;
    if (!d) return;
    const dx = e.clientX - d.x;
    const dy = e.clientY - d.y;
    if (Math.abs(dx) + Math.abs(dy) > 3) movedRef.current = true;
    setOffset({ x: d.ox + dx, y: d.oy + dy });
  };
  const onPointerUp = (): void => {
    dragRef.current = null;
  };

  const toggleZoom = (): void => {
    if (movedRef.current) {
      movedRef.current = false;
      return;
    }
    setScale((s) => {
      if (s > 1.05) {
        setOffset({ x: 0, y: 0 });
        return 1;
      }
      return 2.4;
    });
  };

  if (!open) return null;

  const side = "min(78vw, 78vh, 560px)";

  return createPortal(
    <div
      className="fixed inset-0 z-[120] flex items-center justify-center bg-black/95 transition-opacity duration-200"
      style={{ opacity: entered ? 1 : 0 }}
      onClick={onClose}
      onWheel={onWheel}
      role="dialog"
      aria-label={name ? `${name}'s profile picture` : "Profile picture"}
    >
      <div className="absolute inset-x-0 top-0 flex items-center justify-between p-4">
        {name && (
          <span className="rounded-full bg-white/10 px-3 py-1.5 text-[13px] font-semibold text-white/90">
            @{name}
          </span>
        )}
        <button
          type="button"
          onClick={onClose}
          aria-label="Close"
          className="ml-auto flex h-9 w-9 items-center justify-center rounded-full bg-white/10 text-white transition-transform active:scale-90"
        >
          <X className="h-4 w-4" strokeWidth={2.6} />
        </button>
      </div>

      <div
        className="select-none"
        style={{
          width: side,
          height: side,
          transform: `translate(${offset.x}px, ${offset.y}px) scale(${entered ? scale : 0.84})`,
          transition: dragRef.current ? "none" : "transform 220ms cubic-bezier(0.2, 0.8, 0.2, 1)",
          cursor: scale > 1 ? "grab" : "zoom-in",
          touchAction: "none",
        }}
        onClick={(e) => {
          e.stopPropagation();
          toggleZoom();
        }}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerUp}
      >
        {url ? (
          <img
            src={url}
            alt={name ?? ""}
            draggable={false}
            className="h-full w-full rounded-full object-cover shadow-[0_30px_80px_-20px_rgba(0,0,0,0.8)] ring-1 ring-white/10"
          />
        ) : (
          <Avatar name={name} size={560} className="!h-full !w-full" />
        )}
      </div>

      <p className="pointer-events-none absolute bottom-6 text-[11px] font-medium text-white/45">
        Scroll to zoom · click to toggle · Esc to close
      </p>
    </div>,
    document.body
  );
}
