import { useState } from "react";
import { QRCodeSVG } from "qrcode.react";
import { Copy, QrCode, X } from "lucide-react";
import { usePitch } from "@/components/pitch/PitchContext";

export function PitchQrButton() {
  const { deckUrl } = usePitch();
  const [open, setOpen] = useState(false);

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        className="fixed right-4 top-24 z-[60] flex h-10 items-center gap-1.5 rounded-full border border-border bg-background/95 px-3 text-[11px] font-bold shadow-lg backdrop-blur-md transition-transform active:scale-95"
        title="Show deck QR code"
      >
        <QrCode className="h-4 w-4" />
        <span className="hidden sm:inline">QR</span>
      </button>

      {open && (
        <div className="fixed inset-0 z-[80] flex items-center justify-center p-4">
          <button
            onClick={() => setOpen(false)}
            className="absolute inset-0 bg-black/50 backdrop-blur-sm"
            aria-label="Close"
          />
          <div className="relative z-10 w-full max-w-xs rounded-[24px] bg-card p-6 shadow-2xl">
            <button
              onClick={() => setOpen(false)}
              className="absolute right-4 top-4 flex h-8 w-8 items-center justify-center rounded-full bg-secondary"
              aria-label="Close"
            >
              <X className="h-4 w-4" />
            </button>
            <p className="text-[16px] font-extrabold">Scan to open this deck</p>
            <p className="mt-1 text-[12px] text-muted-foreground">
              The prospect can open this exact page on their phone while you
              present on a bigger screen.
            </p>
            <div className="mt-4 flex justify-center rounded-2xl bg-white p-4">
              <QRCodeSVG value={deckUrl} size={200} level="M" includeMargin />
            </div>
            <div className="mt-4 flex items-center gap-2 rounded-xl border border-border bg-background p-2">
              <span className="min-w-0 flex-1 truncate text-[11px] text-muted-foreground">
                {deckUrl}
              </span>
              <button
                onClick={() => {
                  void navigator.clipboard.writeText(deckUrl);
                }}
                className="flex h-7 items-center gap-1 rounded-full bg-secondary px-2 text-[10px] font-bold"
              >
                <Copy className="h-3 w-3" /> Copy
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
