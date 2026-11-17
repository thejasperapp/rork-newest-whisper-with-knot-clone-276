import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { Loader2, Minus, Plus } from "lucide-react";

/**
 * Instagram-style avatar cropper — drag to reposition, pinch/wheel/slider to
 * zoom, a circular mask previews the final avatar, and Save exports a square
 * 512px JPEG. Fully self-contained: give it a File, get back a cropped Blob.
 */

const VIEW = 280;
const EXPORT_SIZE = 512;
const MAX_ZOOM = 3;

interface AvatarCropDialogProps {
  file: File | null;
  busy?: boolean;
  onCancel: () => void;
  onCropped: (blob: Blob) => void;
}

export function AvatarCropDialog({
  file,
  busy = false,
  onCancel,
  onCropped,
}: AvatarCropDialogProps) {
  const [url, setUrl] = useState<string | null>(null);
  const [natural, setNatural] = useState<{ w: number; h: number } | null>(null);
  const [zoom, setZoom] = useState<number>(1);
  const [offset, setOffset] = useState<{ x: number; y: number }>({ x: 0, y: 0 });
  const [exporting, setExporting] = useState<boolean>(false);
  const imgRef = useRef<HTMLImageElement | null>(null);
  const drag = useRef<{ startX: number; startY: number; baseX: number; baseY: number } | null>(null);

  useEffect(() => {
    if (!file) {
      setUrl(null);
      setNatural(null);
      return;
    }
    const u = URL.createObjectURL(file);
    setUrl(u);
    setZoom(1);
    setOffset({ x: 0, y: 0 });
    return () => URL.revokeObjectURL(u);
  }, [file]);

  if (!file || !url) return null;

  // Cover-fit base scale — the image always fills the viewport.
  const baseScale = natural
    ? Math.max(VIEW / natural.w, VIEW / natural.h)
    : 1;
  const dispW = (natural?.w ?? VIEW) * baseScale * zoom;
  const dispH = (natural?.h ?? VIEW) * baseScale * zoom;

  const clampOffset = (x: number, y: number, z: number): { x: number; y: number } => {
    if (!natural) return { x: 0, y: 0 };
    const w = natural.w * baseScale * z;
    const h = natural.h * baseScale * z;
    const maxX = Math.max(0, (w - VIEW) / 2);
    const maxY = Math.max(0, (h - VIEW) / 2);
    return {
      x: Math.min(maxX, Math.max(-maxX, x)),
      y: Math.min(maxY, Math.max(-maxY, y)),
    };
  };

  const setZoomClamped = (z: number): void => {
    const next = Math.min(MAX_ZOOM, Math.max(1, z));
    setZoom(next);
    setOffset((o) => clampOffset(o.x, o.y, next));
  };

  const handlePointerDown = (e: React.PointerEvent<HTMLDivElement>): void => {
    e.currentTarget.setPointerCapture(e.pointerId);
    drag.current = {
      startX: e.clientX,
      startY: e.clientY,
      baseX: offset.x,
      baseY: offset.y,
    };
  };

  const handlePointerMove = (e: React.PointerEvent<HTMLDivElement>): void => {
    if (!drag.current) return;
    const dx = e.clientX - drag.current.startX;
    const dy = e.clientY - drag.current.startY;
    setOffset(clampOffset(drag.current.baseX + dx, drag.current.baseY + dy, zoom));
  };

  const handlePointerUp = (): void => {
    drag.current = null;
  };

  const exportCrop = async (): Promise<void> => {
    const img = imgRef.current;
    if (!img || !natural) return;
    setExporting(true);
    try {
      const canvas = document.createElement("canvas");
      canvas.width = EXPORT_SIZE;
      canvas.height = EXPORT_SIZE;
      const ctx = canvas.getContext("2d");
      if (!ctx) throw new Error("no-canvas");
      const k = EXPORT_SIZE / VIEW;
      // The drawn image's top-left corner in viewport coordinates.
      const tlx = VIEW / 2 + offset.x - dispW / 2;
      const tly = VIEW / 2 + offset.y - dispH / 2;
      ctx.fillStyle = "#000";
      ctx.fillRect(0, 0, EXPORT_SIZE, EXPORT_SIZE);
      ctx.drawImage(img, tlx * k, tly * k, dispW * k, dispH * k);
      const blob = await new Promise<Blob | null>((resolve) =>
        canvas.toBlob(resolve, "image/jpeg", 0.92)
      );
      if (blob) onCropped(blob);
    } finally {
      setExporting(false);
    }
  };

  const working = busy || exporting;

  return createPortal(
    <div className="fixed inset-0 z-[70] flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-black/70 backdrop-blur-sm" onClick={working ? undefined : onCancel} />
      <div className="relative w-full max-w-sm overflow-hidden rounded-3xl border border-border bg-background shadow-2xl">
        <div className="flex items-center justify-between border-b border-border px-4 py-3">
          <button
            onClick={onCancel}
            disabled={working}
            className="text-sm font-semibold text-muted-foreground transition-colors hover:text-foreground disabled:opacity-40"
          >
            Cancel
          </button>
          <span className="text-[15px] font-bold">Adjust photo</span>
          <button
            onClick={() => void exportCrop()}
            disabled={working || !natural}
            className="text-sm font-bold text-[#0095F6] transition-opacity hover:opacity-70 disabled:opacity-40"
          >
            {working ? <Loader2 className="h-4 w-4 animate-spin" /> : "Save"}
          </button>
        </div>

        <div className="flex flex-col items-center gap-4 p-5">
          {/* Crop stage — drag to pan, wheel to zoom, circle mask previews. */}
          <div
            className="relative touch-none select-none overflow-hidden rounded-2xl bg-black"
            style={{ width: VIEW, height: VIEW, cursor: drag.current ? "grabbing" : "grab" }}
            onPointerDown={handlePointerDown}
            onPointerMove={handlePointerMove}
            onPointerUp={handlePointerUp}
            onPointerCancel={handlePointerUp}
            onWheel={(e) => {
              e.preventDefault();
              setZoomClamped(zoom - e.deltaY * 0.0035);
            }}
          >
            <img
              ref={imgRef}
              src={url}
              alt=""
              draggable={false}
              onLoad={(e) =>
                setNatural({
                  w: e.currentTarget.naturalWidth,
                  h: e.currentTarget.naturalHeight,
                })
              }
              className="absolute left-1/2 top-1/2 max-w-none"
              style={{
                width: dispW,
                height: dispH,
                transform: `translate(calc(-50% + ${offset.x}px), calc(-50% + ${offset.y}px))`,
              }}
            />
            {/* Circular mask — everything outside the circle dims. */}
            <div
              className="pointer-events-none absolute inset-0"
              style={{
                background:
                  "radial-gradient(circle at center, transparent 0, transparent calc(50% - 1px), rgba(0,0,0,0.55) calc(50% - 1px))",
              }}
            />
            <div className="pointer-events-none absolute inset-0 rounded-full border border-white/60" style={{ margin: 0 }} />
          </div>

          {/* Zoom slider */}
          <div className="flex w-full items-center gap-3 px-1">
            <button
              onClick={() => setZoomClamped(zoom - 0.25)}
              className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-secondary text-foreground transition-transform active:scale-90"
              aria-label="Zoom out"
            >
              <Minus className="h-4 w-4" />
            </button>
            <input
              type="range"
              min={1}
              max={MAX_ZOOM}
              step={0.01}
              value={zoom}
              onChange={(e) => setZoomClamped(Number(e.target.value))}
              className="h-1.5 flex-1 cursor-pointer appearance-none rounded-full bg-secondary accent-foreground"
              aria-label="Zoom"
            />
            <button
              onClick={() => setZoomClamped(zoom + 0.25)}
              className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-secondary text-foreground transition-transform active:scale-90"
              aria-label="Zoom in"
            >
              <Plus className="h-4 w-4" />
            </button>
          </div>
          <p className="text-center text-[12px] text-muted-foreground">
            Drag to reposition · pinch or scroll to zoom
          </p>
        </div>
      </div>
    </div>,
    document.body
  );
}
