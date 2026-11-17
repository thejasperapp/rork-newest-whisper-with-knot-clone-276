import { QRCodeSVG } from "qrcode.react";
import { useState } from "react";
import { Link } from "react-router-dom";
import { ArrowLeft, QrCode, Copy, Check, Share2, Download } from "lucide-react";
import { toast } from "sonner";

import { useAuth } from "@/hooks/useAuth";
import { useQuery } from "@tanstack/react-query";
import { fetchOrCreateReferralCode } from "@/lib/recruiter";
import { recruiterApplicationLink } from "@/lib/site";

export default function RecruiterQR() {
  const { user, profile } = useAuth();
  const [copied, setCopied] = useState(false);

  const referralQuery = useQuery({
    queryKey: ["recruiter-referral", user?.id],
    queryFn: () => fetchOrCreateReferralCode(user!.id, profile?.username ?? "recruiter"),
    enabled: !!user,
  });

  const referral = referralQuery.data;
  const shareLink = referral ? recruiterApplicationLink(referral.code) : "";

  const copyLink = async () => {
    if (!shareLink) return;
    try {
      await navigator.clipboard.writeText(shareLink);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      toast("Couldn't copy — try manually");
    }
  };

  const shareCode = async () => {
    if (!referral || !shareLink) return;
    if (navigator.share) {
      try {
        await navigator.share({
          title: "Join Whisper",
          text: `Use my code ${referral.code} to join Whisper — the social network where talent gets discovered.`,
          url: shareLink,
        });
      } catch {
        // cancelled
      }
    } else {
      copyLink();
    }
  };

  const downloadQR = () => {
    const svg = document.getElementById("recruiter-qr-svg");
    if (!svg) return;
    const svgData = new XMLSerializer().serializeToString(svg);
    const canvas = document.createElement("canvas");
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    const img = new Image();
    img.onload = () => {
      canvas.width = 512;
      canvas.height = 512;
      ctx.fillStyle = "#ffffff";
      ctx.fillRect(0, 0, 512, 512);
      ctx.drawImage(img, 0, 0, 512, 512);
      const link = document.createElement("a");
      link.download = `whisper-qr-${referral?.code ?? "code"}.png`;
      link.href = canvas.toDataURL("image/png");
      link.click();
    };
    img.src = "data:image/svg+xml;base64," + btoa(unescape(encodeURIComponent(svgData)));
  };

  return (
    <div className="flex min-h-[100dvh] flex-col bg-background">
      <header className="sticky top-0 z-30 flex h-14 items-center gap-3 rounded-b-[22px] border-b border-border bg-background px-4">
        <Link
          to="/recruiter"
          className="flex h-10 w-10 items-center justify-center rounded-full transition-colors hover:bg-secondary"
        >
          <ArrowLeft className="h-5 w-5" />
        </Link>
        <h1 className="font-display text-base font-bold">Recruiter QR Code</h1>
      </header>

      <main className="mx-auto w-full max-w-md px-4 py-6">
        <div className="mb-6 flex items-center gap-4">
          <span className="flex h-14 w-14 items-center justify-center rounded-2xl bg-foreground text-background">
            <QrCode className="h-7 w-7" />
          </span>
          <div>
            <h2 className="text-xl font-bold">Your scan-to-join QR</h2>
            <p className="text-sm text-muted-foreground">
              Leads scan this to sign up with your code pre-filled.
            </p>
          </div>
        </div>

        {referralQuery.isLoading ? (
          <div className="flex justify-center py-20">
            <div className="h-8 w-8 animate-spin rounded-full border-2 border-foreground border-t-transparent" />
          </div>
        ) : referral ? (
          <div className="space-y-6">
            {/* QR Code card */}
            <div className="rounded-3xl border border-border bg-card p-8">
              <div className="flex flex-col items-center gap-4">
                <div className="rounded-2xl bg-white p-6 shadow-sm">
                  <QRCodeSVG
                    id="recruiter-qr-svg"
                    value={shareLink}
                    size={220}
                    level="M"
                    includeMargin={false}
                    imageSettings={{
                      src: "/whisper-logo.png",
                      height: 48,
                      width: 48,
                      excavate: true,
                    }}
                  />
                </div>
                <div className="text-center">
                  <p className="font-display text-3xl font-black tracking-[0.15em]">
                    {referral.code}
                  </p>
                  <p className="mt-1 text-xs text-muted-foreground">
                    {shareLink.replace("https://", "")}
                  </p>
                </div>
              </div>
            </div>

            {/* Action buttons */}
            <div className="space-y-2">
              <button
                onClick={downloadQR}
                className="flex w-full items-center justify-center gap-2 rounded-2xl bg-foreground py-3.5 text-sm font-bold text-background transition-transform active:scale-[0.98]"
              >
                <Download className="h-4 w-4" />
                Download QR image
              </button>
              <button
                onClick={copyLink}
                className="flex w-full items-center justify-center gap-2 rounded-2xl border border-border bg-card py-3.5 text-sm font-bold transition-colors hover:bg-secondary"
              >
                {copied ? (
                  <>
                    <Check className="h-4 w-4 text-emerald-500" />
                    Copied!
                  </>
                ) : (
                  <>
                    <Copy className="h-4 w-4" />
                    Copy link
                  </>
                )}
              </button>
              <button
                onClick={shareCode}
                className="flex w-full items-center justify-center gap-2 rounded-2xl border border-border bg-card py-3.5 text-sm font-bold transition-colors hover:bg-secondary"
              >
                <Share2 className="h-4 w-4" />
                Share
              </button>
            </div>

            {/* How it works */}
            <div className="rounded-2xl border border-emerald-500/20 bg-emerald-500/5 p-4">
              <p className="text-sm font-bold text-emerald-600">How it works</p>
              <ol className="mt-2 space-y-1.5 text-xs text-muted-foreground">
                <li>1. Print or display this QR code at events, gyms, or share digitally.</li>
                <li>2. Leads scan it → they land on mydailywhisper.com with your code pre-filled.</li>
                <li>3. They create an account and fill out the applicant questionnaire.</li>
                <li>4. You see their answers + position match scores in real-time on your dashboard.</li>
              </ol>
            </div>

            <Link
              to="/recruiter"
              className="block rounded-2xl bg-secondary py-3 text-center text-sm font-bold transition-colors hover:bg-secondary/80"
            >
              Back to dashboard
            </Link>
          </div>
        ) : (
          <p className="text-center text-sm text-muted-foreground">Couldn't load your QR code.</p>
        )}
      </main>
    </div>
  );
}
