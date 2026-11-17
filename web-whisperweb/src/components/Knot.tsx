import { memo, useEffect, useState } from "react";
import type { EmberExpression } from "@/lib/emberBrain";
import { cn } from "@/lib/utils";
import "./knot.css";

const ART = "/knot-native-20261030/";

/** Original registered iOS artwork, with the same 647-point layer placement. */
export const KnotMascot = memo(function KnotMascot({ size = 120, isActive = false, expression = "calm", showsEyes = true, className }: {
  size?: number; isActive?: boolean; expression?: EmberExpression; showsEyes?: boolean; className?: string;
}) {
  const [blink, setBlink] = useState(false);
  const [reduced, setReduced] = useState(() => typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches);
  useEffect(() => {
    const media = window.matchMedia("(prefers-reduced-motion: reduce)");
    const sync = () => setReduced(media.matches);
    media.addEventListener("change", sync);
    return () => media.removeEventListener("change", sync);
  }, []);
  useEffect(() => {
    if (reduced || !showsEyes) return;
    let release: ReturnType<typeof setTimeout>;
    const timer = setInterval(() => {
      if (document.hidden) return;
      setBlink(true);
      release = setTimeout(() => setBlink(false), 140);
    }, 4300);
    return () => { clearInterval(timer); clearTimeout(release); setBlink(false); };
  }, [reduced, showsEyes]);
  const gaze = reduced ? [0, 0] : expression === "lookingDown" ? [0, 3.5] : ["thinking", "skeptical"].includes(expression) ? [1.8, -0.8] : expression === "curious" ? [-1.2, -1.4] : [0, 0];
  const eyeHeight = reduced ? 1 : blink ? 0.08 : ["happy", "delighted"].includes(expression) ? 0.88 : ["thinking", "skeptical", "focused"].includes(expression) ? 0.92 : 1;
  return <span aria-hidden="true" className={cn("knot-mascot", isActive && "knot-working", className)} style={{ width: size, height: size }}>
    {reduced && showsEyes ? <img src={`${ART}neutral.png`} alt="" className="knot-layer" /> : <>
      <img src={`${ART}hand-right.png`} alt="" className="knot-layer" />
      <img src={`${ART}hand-left.png`} alt="" className="knot-layer" />
      <img src={`${ART}torso.png`} alt="" className="knot-layer" />
      {showsEyes && ([{ name: "left", width: 134, x: 240 }, { name: "right", width: 131, x: 409.5 }] as const).map(eye => <img key={eye.name} src={`${ART}eye-${eye.name}.png`} alt="" className="knot-eye" style={{ width: `${eye.width / 647 * 100}%`, height: `${221 / 647 * 100}%`, left: `${eye.x / 647 * 100 + gaze[0]}%`, top: `${248.5 / 647 * 100 + gaze[1]}%`, transform: `translate(-50%, -50%) scaleY(${eyeHeight})` }} />)}
    </>}
  </span>;
});

export function KnotPortrait({ size = 60, expression = "calm" }: { size?: number; expression?: EmberExpression }) {
  return <span className="knot-portrait" style={{ width: size, height: size }}><KnotMascot size={size * .82} expression={expression} /></span>;
}

export function KnotWordmark({ width = 70 }: { width?: number }) {
  return <span className="knot-wordmark" style={{ width }}><img className="knot-wordmark-light" src={`${ART}wordmark-black.png`} alt="Knot" /><img className="knot-wordmark-dark" src={`${ART}wordmark-white.png`} alt="Knot" /></span>;
}
