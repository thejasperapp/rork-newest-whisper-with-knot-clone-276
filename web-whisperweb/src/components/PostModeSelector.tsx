import { useNavigate } from "react-router-dom";
import { useAuth } from "@/hooks/useAuth";
import { canPostGrid } from "@/lib/accountAccess";

/** Grid is a peer in the same sliding composer control, never a detached CTA. */
export function PostModeSelector({ value, onChange, canLeave }: { value: "post" | "grid" | "story" | "reel"; onChange?: (mode: "post" | "story" | "reel") => void; canLeave?: () => boolean }) {
  const { profile } = useAuth();
  const navigate = useNavigate();
  const modes = ["post", ...(canPostGrid(profile) ? ["grid" as const] : []), "story", ...(value === "reel" ? ["reel" as const] : [])] as const;
  const active = modes.indexOf(value);
  return <div role="group" aria-label="Post format" className="relative inline-grid grid-flow-col auto-cols-fr rounded-full bg-secondary p-1">
    {active >= 0 && <span aria-hidden="true" className="pointer-events-none absolute bottom-1 left-1 top-1 rounded-full bg-background shadow-sm transition-transform duration-200 motion-reduce:transition-none" style={{ width: `calc((100% - 8px) / ${modes.length})`, transform: `translateX(${active * 100}%)` }} />}
    {modes.map(mode => <button type="button" key={mode} aria-pressed={value === mode} className={`relative z-10 min-h-11 rounded-full px-3 text-xs font-semibold ${value === mode ? "text-foreground" : "text-muted-foreground"}`} onClick={() => {
      if (value === mode) return;
      if ((mode === "grid" || !onChange) && canLeave && !canLeave()) return;
      if (mode === "grid") navigate("/compose/grid");
      else if (onChange) onChange(mode);
      else navigate(mode === "post" ? "/compose" : `/compose?mode=${mode}`);
    }}>{mode === "post" ? "Whisp" : mode === "grid" ? "Grid" : mode === "reel" ? "Reel" : "Story"}</button>)}
  </div>;
}
