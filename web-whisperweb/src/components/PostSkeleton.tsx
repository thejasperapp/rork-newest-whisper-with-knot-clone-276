import { cn } from "@/lib/utils";

/**
 * Whisper's loading language — soft bones with a synchronized ember shimmer
 * sweeping through them (mirrors the iOS `WhisperPostSkeleton`). Replaces
 * bare spinners and gray pulses on content surfaces.
 */

function SkeletonKeyframes() {
  return (
    <style>{`
@keyframes whisper-skel-sweep { from { transform: translateX(-120%); } to { transform: translateX(320%); } }
@keyframes whisper-skel-in { from { opacity: 0; transform: translateY(14px); } to { opacity: 1; transform: none; } }
`}</style>
  );
}

export function SkeletonBone({ className }: { className?: string }) {
  return (
    <div
      className={cn(
        "relative overflow-hidden rounded-lg bg-foreground/[0.06]",
        className
      )}
    >
      <div
        className="absolute inset-y-0 left-0 w-1/2"
        style={{
          background:
            "linear-gradient(90deg, transparent, rgba(255,148,66,0.10), rgba(128,128,138,0.14), transparent)",
          animation: "whisper-skel-sweep 1.6s linear infinite",
        }}
      />
    </div>
  );
}

/** One ghost post — header, caption lines, media block, action dots. */
export function PostSkeletonCard({
  showMedia = true,
  delayMs = 0,
}: {
  showMedia?: boolean;
  delayMs?: number;
}) {
  return (
    <div
      className="px-4 py-4"
      style={{
        animation: "whisper-skel-in 0.5s ease both",
        animationDelay: `${delayMs}ms`,
      }}
    >
      <div className="flex items-center gap-3">
        <SkeletonBone className="h-10 w-10 rounded-full" />
        <div className="space-y-1.5">
          <SkeletonBone className="h-2.5 w-28" />
          <SkeletonBone className="h-2 w-16" />
        </div>
      </div>
      <div className="mt-3 space-y-2">
        <SkeletonBone className="h-2.5 w-full" />
        <SkeletonBone className="h-2.5 w-2/3" />
      </div>
      {showMedia && <SkeletonBone className="mt-3 aspect-[4/3] w-full rounded-2xl" />}
      <div className="mt-3 flex items-center gap-3.5">
        <SkeletonBone className="h-6 w-6 rounded-full" />
        <SkeletonBone className="h-6 w-6 rounded-full" />
        <SkeletonBone className="h-6 w-6 rounded-full" />
      </div>
    </div>
  );
}

/** The loading column — a few ghost posts easing in with a stagger. */
export function PostSkeletonList({ count = 3 }: { count?: number }) {
  return (
    <div aria-label="Loading posts" role="status">
      <SkeletonKeyframes />
      {Array.from({ length: count }, (_, i) => (
        <div key={i} className={cn(i > 0 && "border-t border-border")}>
          <PostSkeletonCard showMedia={i !== 1} delayMs={i * 90} />
        </div>
      ))}
    </div>
  );
}
