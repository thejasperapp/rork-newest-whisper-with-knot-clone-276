import { useState } from "react";
import { Download, Loader2 } from "lucide-react";
import html2canvas from "html2canvas";
import jsPDF from "jspdf";
import { usePitch } from "@/components/pitch/PitchContext";

export function PitchExportPdf() {
  const { deckTitle, deckUrl } = usePitch();
  const [exporting, setExporting] = useState(false);

  const exportPdf = async () => {
    const el = document.getElementById("pitch-deck-content");
    if (!el) return;
    setExporting(true);
    try {
      const canvas = await html2canvas(el, {
        scale: 2,
        useCORS: true,
        ignoreElements: (node) => node.classList?.contains("no-print") ?? false,
      });
      const imgData = canvas.toDataURL("image/png");
      const pdf = new jsPDF({ orientation: "portrait", unit: "px", format: [canvas.width, canvas.height] });
      pdf.addImage(imgData, "PNG", 0, 0, canvas.width, canvas.height);
      pdf.setFontSize(24);
      pdf.text(deckTitle, 60, 80);
      pdf.setFontSize(14);
      pdf.setTextColor(120, 120, 120);
      pdf.text(deckUrl, 60, 120);
      pdf.save(`whisper-pitch-${deckTitle.toLowerCase().replace(/\s+/g, "-")}.pdf`);
    } finally {
      setExporting(false);
    }
  };

  return (
    <button
      onClick={exportPdf}
      disabled={exporting}
      className="flex h-9 items-center gap-1.5 rounded-full bg-secondary px-3 text-[11px] font-bold text-foreground transition-transform active:scale-95 disabled:opacity-50"
      title="Export deck to PDF"
    >
      {exporting ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Download className="h-3.5 w-3.5" />}
      <span className="hidden sm:inline">PDF</span>
    </button>
  );
}
