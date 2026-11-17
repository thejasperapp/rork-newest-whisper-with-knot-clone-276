import { useMemo, type CSSProperties, type ReactNode } from "react";
import { groupThemeColors, type GroupThemeDesign } from "@/lib/groupThemes";
import { cn } from "@/lib/utils";

/** Matte reading surfaces and large edge artwork shared with the native catalogue. */
export function GroupThemeSurface({ design, children, className, wallpaper }: { design: GroupThemeDesign; children: ReactNode; className?: string; wallpaper?: string }) {
  const colors = useMemo(() => groupThemeColors(design), [design]);
  const style = Object.fromEntries(Object.entries(colors).map(([key, value]) => [`--chat-${key}`, value])) as CSSProperties;
  const botanical = ["rose", "cherry", "forest", "wildflower", "lavender", "mint"].includes(design.preset);
  return <div style={style} className={cn("whisper-chat-surface relative isolate overflow-hidden rounded-2xl bg-[var(--chat-light)] text-[#202729] dark:bg-[var(--chat-dark)] dark:text-[#F3F3EE] [&_.group-outgoing]:bg-[var(--chat-sent)] [&_.group-outgoing]:text-[var(--chat-sentText)] dark:[&_.group-outgoing]:bg-[var(--chat-sentDark)] dark:[&_.group-outgoing]:text-[var(--chat-sentTextDark)] [&_.group-incoming]:bg-[var(--chat-received)] [&_.group-incoming]:text-[var(--chat-receivedText)] dark:[&_.group-incoming]:bg-[var(--chat-raised)] dark:[&_.group-incoming]:text-[var(--chat-receivedTextDark)]", className)}>
    {wallpaper && <div className="pointer-events-none absolute inset-0 -z-10 overflow-hidden [@media(prefers-contrast:more)]:hidden" aria-hidden="true"><img src={wallpaper} alt="" className="h-full w-full object-cover" /><div className="absolute inset-0 bg-white/75 dark:bg-black/70" /></div>}
    {!wallpaper && design.preset !== "classic" && <svg aria-hidden="true" viewBox="0 0 390 780" preserveAspectRatio="none" className="pointer-events-none absolute inset-0 -z-10 h-full w-full text-[var(--chat-accent)] opacity-[0.18] dark:text-[var(--chat-accentDark)] dark:opacity-25 [@media(prefers-contrast:more)]:hidden" fill="none" stroke="currentColor" strokeWidth="1">
      {botanical ? ["translate(-38 190) rotate(-24)", "translate(428 740) rotate(156)"].map(transform => <g key={transform} transform={transform}><path d="M0 0Q120 130 64 320" />{[0,1,2,3,4].map(i => <path key={i} transform={`translate(0 ${i * 54 + 12})`} d="M48 34Q-38 30 -18 -28Q50 -24 48 34" fill="currentColor" fillOpacity=".6" stroke="none" />)}</g>) : ["midnight", "nocturne", "sky"].includes(design.preset) ? <><circle cx="370" cy="170" r="90" fill="currentColor" fillOpacity=".6" stroke="none" />{[0,1,2].map(i => <circle key={i} cx={35+i*24} cy={675+i*24} r="215" strokeWidth=".8" />)}</> : ["lantern", "terracotta", "coffee"].includes(design.preset) ? <>{[0,1,2,3].map(i => <rect key={i} x={270+i*22} y={80+i*22} width={210-i*22} height="390" rx="105" />)}<circle cx="-5" cy="685" r="105" fill="currentColor" fillOpacity=".6" stroke="none" /></> : design.preset === "blueprint" ? Array.from({length: 12}, (_, x) => Array.from({length: 24}, (_, y) => <circle key={`${x}-${y}`} cx={20+x*32} cy={20+y*32} r=".7" fill="currentColor" stroke="none" />)) : [0,1,2,3,4].map(i => <path key={i} transform={`translate(0 ${i*24})`} d="M-90 470C155 250 205 900 470 760" />)}
    </svg>}
    {children}
  </div>;
}
