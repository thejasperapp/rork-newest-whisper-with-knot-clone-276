import { useEffect, useRef, useState } from "react";

/** Native banners store a vertical offset in points, not a normalized percentage. */
export function ProfileCover({ src, offset = 0 }: { src: string; offset?: number | null }) {
  const frame = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState({ width: 0, height: 0 });
  const [image, setImage] = useState({ src: "", width: 0, height: 0 });
  useEffect(() => {
    const node = frame.current;
    if (!node) return;
    const observer = new ResizeObserver(entries => {
      const rect = entries[0]?.contentRect;
      if (rect) setSize({ width: rect.width, height: rect.height });
    });
    observer.observe(node);
    return () => observer.disconnect();
  }, []);
  const loaded = image.src === src && image.width > 0 && image.height > 0;
  const scale = loaded ? Math.max(size.width / image.width, size.height / image.height) : 0;
  const overflow = Math.max(0, (image.height * scale - size.height) / 2);
  const points = Number.isFinite(offset) ? offset ?? 0 : 0;
  const shift = Math.max(-overflow, Math.min(overflow, points));
  return <div ref={frame} className="absolute inset-0 overflow-hidden">
    <img src={src} alt="" onLoad={event => setImage({ src, width: event.currentTarget.naturalWidth, height: event.currentTarget.naturalHeight })} className="absolute left-1/2 top-1/2 max-w-none" style={loaded && size.width > 0 ? { width: image.width * scale, height: image.height * scale, transform: `translate(-50%, calc(-50% + ${shift}px))` } : { width: "100%", height: "100%", objectFit: "cover", transform: "translate(-50%, -50%)" }} />
  </div>;
}
