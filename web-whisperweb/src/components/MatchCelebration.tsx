import { useEffect, useState } from "react";

/**
 * The full-screen "It's a match!" celebration — both profile pictures fly
 * in from the edges, LINK together under a heart seal, hearts drift up the
 * screen, and the names seal it. Shown once per dating thread when BOTH
 * people tap Match. Mirrors iOS `WhisperMatchCelebrationView` exactly.
 */

interface MatchCelebrationProps {
  myName: string;
  myAvatarUrl?: string | null;
  otherName: string;
  otherAvatarUrl?: string | null;
  onDismiss: () => void;
}

function Avatar({ url, name, side }: { url?: string | null; name: string; side: "left" | "right" }) {
  const initial = (name.replace(/^@/, "").charAt(0) || "?").toUpperCase();
  return (
    <div
      className={`wm-avatar wm-avatar-${side} relative h-24 w-24 overflow-hidden rounded-full border-[3px] border-white shadow-[0_10px_28px_rgba(0,0,0,0.35)]`}
      style={{ background: "linear-gradient(135deg, #E84A7D, #FA739E)" }}
    >
      <span className="absolute inset-0 flex items-center justify-center text-4xl font-black text-white/90">
        {initial}
      </span>
      {url && (
        <img
          src={url}
          alt={name}
          className="absolute inset-0 h-full w-full object-cover"
          draggable={false}
        />
      )}
    </div>
  );
}

export function MatchCelebration({
  myName,
  myAvatarUrl,
  otherName,
  otherAvatarUrl,
  onDismiss,
}: MatchCelebrationProps) {
  const [phase, setPhase] = useState<number>(0);

  useEffect(() => {
    const t1 = window.setTimeout(() => setPhase(1), 80); // avatars fly in
    const t2 = window.setTimeout(() => setPhase(2), 680); // heart seal
    const t3 = window.setTimeout(() => setPhase(3), 980); // text + button
    return () => {
      window.clearTimeout(t1);
      window.clearTimeout(t2);
      window.clearTimeout(t3);
    };
  }, []);

  return (
    <div
      className="fixed inset-0 z-[120] flex flex-col items-center justify-between overflow-hidden"
      style={{
        background:
          "radial-gradient(120% 90% at 50% 45%, #4C0F26 0%, #1F0512 70%, #14030B 100%)",
      }}
      role="dialog"
      aria-label="It's a match"
    >
      <style>{`
        .wm-avatar { transition: transform 0.62s cubic-bezier(0.2, 1.4, 0.35, 1); }
        .wm-avatar-left { transform: translateX(-70vw) rotate(-20deg); }
        .wm-avatar-right { transform: translateX(70vw) rotate(20deg); }
        .wm-in .wm-avatar-left { transform: translateX(0) rotate(-4deg); }
        .wm-in .wm-avatar-right { transform: translateX(0) rotate(4deg); }
        .wm-seal { transform: scale(0); transition: transform 0.42s cubic-bezier(0.2, 1.6, 0.4, 1); }
        .wm-sealed .wm-seal { transform: scale(1); }
        @keyframes wm-pulse {
          0% { transform: scale(0.55); opacity: 0.5; }
          100% { transform: scale(1.9); opacity: 0; }
        }
        .wm-sealed .wm-pulse { animation: wm-pulse 1.8s ease-out infinite; }
        @keyframes wm-rise {
          0% { transform: translateY(0); opacity: 0; }
          12% { opacity: var(--wm-op, 0.3); }
          100% { transform: translateY(-110vh); opacity: 0; }
        }
        .wm-heart { position: absolute; bottom: -40px; color: #FF9EBF; animation: wm-rise var(--wm-dur, 5s) linear infinite; animation-delay: var(--wm-delay, 0s); }
        .wm-text { opacity: 0; transform: translateY(14px); transition: opacity 0.45s ease-out, transform 0.45s ease-out; }
        .wm-texted .wm-text { opacity: 1; transform: translateY(0); }
      `}</style>

      {/* Hearts drifting up the whole screen. */}
      {phase >= 2 &&
        Array.from({ length: 12 }, (_, i) => (
          <span
            key={i}
            aria-hidden
            className="wm-heart"
            style={{
              left: `${(i * 8.3 + 4) % 100}%`,
              fontSize: `${10 + ((i * 7) % 13)}px`,
              ["--wm-dur" as string]: `${3.6 + ((i * 5) % 9) * 0.35}s`,
              ["--wm-delay" as string]: `${i * 0.28}s`,
              ["--wm-op" as string]: `${0.14 + ((i * 3) % 5) * 0.05}`,
            }}
          >
            ♥
          </span>
        ))}

      <div className="flex-1" />

      {/* The link — two avatars overlap, sealed by the heart. */}
      <div
        className={`relative flex flex-col items-center ${phase >= 1 ? "wm-in" : ""} ${
          phase >= 2 ? "wm-sealed" : ""
        } ${phase >= 3 ? "wm-texted" : ""}`}
      >
        <div className="relative flex items-center justify-center">
          <span
            aria-hidden
            className="wm-pulse absolute h-40 w-40 rounded-full border-2 border-[#FF9EBF]/45"
          />
          <div className="flex -space-x-4">
            <Avatar url={myAvatarUrl} name={myName} side="left" />
            <Avatar url={otherAvatarUrl} name={otherName} side="right" />
          </div>
          <span
            className="wm-seal absolute top-[70px] flex h-12 w-12 items-center justify-center rounded-full border-[2.5px] border-white/85 text-xl shadow-[0_6px_18px_rgba(232,74,125,0.6)]"
            style={{ background: "linear-gradient(135deg, #E84A7D, #FA739E)" }}
          >
            <span className="text-white">❤</span>
          </span>
        </div>

        <p className="wm-text mt-9 text-[11px] font-black uppercase tracking-[0.3em] text-[#FF9EBF]">
          Matched
        </p>
        <p className="wm-text mt-1 text-4xl font-black text-white" style={{ transitionDelay: "60ms" }}>
          It's a Match!
        </p>
        <p
          className="wm-text mt-2 px-8 text-center text-sm font-semibold text-white/75"
          style={{ transitionDelay: "120ms" }}
        >
          You and @{otherName.replace(/^@/, "")} liked each other 💘
        </p>
      </div>

      <div className="flex-1" />

      <div className={`w-full max-w-sm px-10 pb-12 ${phase >= 3 ? "wm-texted" : ""}`}>
        <button
          onClick={onDismiss}
          className="wm-text w-full rounded-full bg-white py-3.5 text-[15px] font-black text-[#E84A7D] shadow-[0_10px_30px_rgba(0,0,0,0.3)] transition-transform active:scale-95"
        >
          Keep chatting 💬
        </button>
      </div>
    </div>
  );
}
