import { useEffect, useRef, useState } from "react";

/** Native transport controls, no autoplay, and pause when hidden or outside the thread viewport. */
export function ChatVideo({ url }: { url: string }) {
  const ref = useRef<HTMLVideoElement | null>(null);
  const [failed, setFailed] = useState<boolean>(false);
  useEffect(() => {
    const video = ref.current;
    if (!video) return;
    const observer = new IntersectionObserver(([entry]) => { if (!entry?.isIntersecting) video.pause(); });
    observer.observe(video);
    const pause = (): void => { if (document.hidden) video.pause(); };
    document.addEventListener("visibilitychange", pause);
    return () => { video.pause(); observer.disconnect(); document.removeEventListener("visibilitychange", pause); };
  }, [url, failed]);
  return <div className="w-[240px] max-w-full overflow-hidden rounded-2xl bg-black">
    {failed ? <div className="space-y-3 p-5 text-sm text-white"><p>Couldn't play this video.</p><a href={url} target="_blank" rel="noopener noreferrer" className="underline">Open video</a><button className="ml-4 underline" onClick={() => setFailed(false)}>Retry</button></div> :
      <video ref={ref} src={url} controls playsInline preload="metadata" aria-label="Video attachment" className="max-h-[300px] min-h-[140px] w-full object-contain" onError={() => setFailed(true)} />}
  </div>;
}
