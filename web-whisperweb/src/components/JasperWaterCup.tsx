import { memo, useEffect, useRef } from "react";

/**
 * Jasper's `water_cup` native look, drawn to the published spec: a tapered
 * tumbler (taper = width × 0.12 per side, 10pt quad base corners, 2pt outline
 * at 22% ink) with a live sine-wave surface (2.6pt amplitude, 1.6 rad/s,
 * ~24fps) and the official waterTint gradient (55% → 90%). Tint #338FDB in
 * light mode, #5CB3F2 in dark — resolved live so theme flips restyle it.
 */
function JasperWaterCupBase({
  level,
  width = 86,
  height = 118,
  className,
}: {
  /** 0…1 fill level. */
  level: number;
  width?: number;
  height?: number;
  className?: string;
}) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const levelRef = useRef<number>(level);
  levelRef.current = Math.min(1, Math.max(0, level));

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    canvas.width = width * dpr;
    canvas.height = height * dpr;
    ctx.scale(dpr, dpr);

    let raf = 0;
    let last = 0;
    let shown = levelRef.current;

    const glassPath = (): void => {
      const inset = 1.5;
      const taper = width * 0.12;
      const corner = Math.min(10, height * 0.12);
      ctx.beginPath();
      ctx.moveTo(inset, inset);
      ctx.lineTo(width - inset, inset);
      ctx.lineTo(width - inset - taper, height - inset - corner);
      ctx.quadraticCurveTo(
        width - inset - taper, height - inset,
        width - inset - taper - corner, height - inset
      );
      ctx.lineTo(inset + taper + corner, height - inset);
      ctx.quadraticCurveTo(inset + taper, height - inset, inset + taper, height - inset - corner);
      ctx.closePath();
    };

    const draw = (now: number): void => {
      raf = requestAnimationFrame(draw);
      // ~24fps is the spec's budget — skip frames above it.
      if (now - last < 1000 / 24) return;
      last = now;

      const dark = document.documentElement.classList.contains("dark");
      const tint = dark ? "92, 179, 242" : "51, 143, 219";
      const ink = dark ? "255, 255, 255" : "17, 17, 17";

      // Ease the displayed level toward the live target.
      shown += (levelRef.current - shown) * 0.12;
      const display = Math.min(1, Math.max(0, shown));

      ctx.clearRect(0, 0, width, height);

      if (display > 0.001) {
        const phase = (now / 1000) * 1.6;
        const amplitude = display >= 0.999 ? 1.2 : 2.6;
        const surfaceY = height * (1 - display);

        ctx.save();
        glassPath();
        ctx.clip();
        ctx.beginPath();
        ctx.moveTo(0, surfaceY + Math.sin(phase) * amplitude);
        for (let x = 0; x <= width; x += 3) {
          ctx.lineTo(x, surfaceY + Math.sin((x / width) * 2 * Math.PI + phase) * amplitude);
        }
        ctx.lineTo(width, height);
        ctx.lineTo(0, height);
        ctx.closePath();
        const gradient = ctx.createLinearGradient(0, surfaceY, 0, height);
        gradient.addColorStop(0, `rgba(${tint}, 0.55)`);
        gradient.addColorStop(1, `rgba(${tint}, 0.90)`);
        ctx.fillStyle = gradient;
        ctx.fill();
        ctx.restore();
      }

      glassPath();
      ctx.lineWidth = 2;
      ctx.lineJoin = "round";
      ctx.strokeStyle = `rgba(${ink}, 0.22)`;
      ctx.stroke();
    };

    raf = requestAnimationFrame(draw);
    return () => cancelAnimationFrame(raf);
  }, [width, height]);

  return (
    <canvas
      ref={canvasRef}
      className={className}
      style={{ width, height }}
      aria-hidden
    />
  );
}

export const JasperWaterCup = memo(JasperWaterCupBase);
