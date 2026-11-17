import { useState } from "react";
import { Hand } from "lucide-react";

import type { MatchmakerMatch, MatchmakerParsed } from "@/lib/matchmakerReply";

/**
 * The parsed matchmaker reply as cards inside the dock's glass box — one
 * tappable card per match (why-we-click + a ready opener), the one-line
 * read on top, the concrete move underneath. Mirrors iOS
 * `WhisperMatchmakerCardsView`.
 */
export function MatchmakerCards({
  parsed,
  accent,
  softAccent,
  avatarFor,
  onSayHi,
}: {
  parsed: MatchmakerParsed;
  accent: string;
  softAccent: string;
  avatarFor: (username: string) => string | null;
  onSayHi: (match: MatchmakerMatch) => void;
}) {
  const [copied, setCopied] = useState<string | null>(null);

  return (
    <div className="space-y-2.5">
      {parsed.read && (
        <p className="text-[13.5px] font-semibold leading-snug text-white">{parsed.read}</p>
      )}
      {parsed.matches.length === 0 && (
        <p className="text-[12px] leading-snug text-white/65">
          No clear match in the hub yet — the move below is the play.
        </p>
      )}
      {parsed.matches.map((m) => {
        const avatar = avatarFor(m.username);
        return (
          <div
            key={m.username.toLowerCase()}
            className="rounded-[14px] border p-2.5"
            style={{ borderColor: `${accent}59`, background: "rgba(255,255,255,0.08)" }}
          >
            <div className="flex items-center gap-2.5">
              <span
                className="flex h-[34px] w-[34px] shrink-0 items-center justify-center overflow-hidden rounded-full text-[14px] font-black text-white"
                style={{ background: `${accent}59`, boxShadow: `inset 0 0 0 1.5px ${softAccent}B3` }}
              >
                {avatar ? (
                  <img src={avatar} alt="" className="h-full w-full object-cover" />
                ) : (
                  m.username.slice(0, 1).toUpperCase()
                )}
              </span>
              <div className="min-w-0 flex-1">
                <p className="truncate text-[13.5px] font-extrabold text-white">@{m.username}</p>
                <p className="text-[9.5px] font-bold" style={{ color: softAccent }}>
                  💘 compatible
                </p>
              </div>
              <button
                type="button"
                onClick={() => {
                  if (m.opener) {
                    void navigator.clipboard?.writeText(m.opener).catch(() => undefined);
                    setCopied(m.username.toLowerCase());
                  }
                  onSayHi(m);
                }}
                className="flex shrink-0 items-center gap-1 rounded-full px-3 py-1.5 text-[11.5px] font-bold text-white transition-transform active:scale-95"
                style={{ background: accent }}
              >
                <Hand className="h-3 w-3" />
                Say hi
              </button>
            </div>
            {m.why && <p className="mt-2 text-[12px] leading-snug text-white/85">{m.why}</p>}
            {m.opener && (
              <div className="mt-2 flex gap-2">
                <span className="w-[2px] shrink-0 rounded-full" style={{ background: softAccent }} />
                <div className="min-w-0">
                  <p className="text-[12px] font-semibold italic leading-snug text-white/90">
                    “{m.opener}”
                  </p>
                  <p className="mt-0.5 text-[9.5px] font-semibold text-white/45">
                    {copied === m.username.toLowerCase()
                      ? "Copied — paste it in the chat"
                      : "Tap Say hi — the opener copies for you"}
                  </p>
                </div>
              </div>
            )}
          </div>
        );
      })}
      {parsed.move && (
        <div className="flex items-start gap-2 rounded-[12px] bg-white/[0.07] p-2.5">
          <span className="text-[13px]">🎯</span>
          <div>
            <p className="text-[8.5px] font-black uppercase tracking-[0.14em]" style={{ color: softAccent }}>
              Your move
            </p>
            <p className="text-[12.5px] font-semibold leading-snug text-white/90">{parsed.move}</p>
          </div>
        </div>
      )}
    </div>
  );
}
