import { useEffect, useState } from "react";
import { Link2 } from "lucide-react";

import { fetchLinkPreview, splitLinks, type LinkPreviewMeta } from "@/lib/linkPreview";
import { cn } from "@/lib/utils";

/**
 * Bubble text whose URLs are live anchors — the link inherits the bubble's
 * text color (own bubbles keep background-colored text on ink) and opens in a
 * new tab without triggering the bubble's own tap handlers.
 */
export function LinkedText({ text, className }: { text: string; className?: string }) {
  const parts = splitLinks(text);
  return (
    <p className={cn("whitespace-pre-wrap break-words", className)}>
      {parts.map((p, i) =>
        p.href ? (
          <a
            key={`${p.href}-${i}`}
            href={p.href}
            target="_blank"
            rel="noopener noreferrer"
            onClick={(e) => e.stopPropagation()}
            className="underline decoration-current/60 underline-offset-2 break-all hover:decoration-current"
          >
            {p.text}
          </a>
        ) : (
          <span key={`t-${i}`}>{p.text}</span>
        )
      )}
    </p>
  );
}

/**
 * The preview card under a link message — image on top when the page has
 * one, then title (semibold) and host (muted). Mirrors iOS `WhisperLinkPreviewCard`.
 */
export function LinkPreviewCard({ url, className }: { url: string; className?: string }) {
  const [meta, setMeta] = useState<LinkPreviewMeta | null>(null);
  const [imageFailed, setImageFailed] = useState<boolean>(false);

  useEffect(() => {
    let active = true;
    setMeta(null);
    setImageFailed(false);
    void fetchLinkPreview(url).then((m) => {
      if (active) setMeta(m);
    });
    return () => {
      active = false;
    };
  }, [url]);

  const host = meta?.siteName ?? safeHost(url);
  const image = meta?.image && !imageFailed ? meta.image : null;

  return (
    <a
      href={url}
      target="_blank"
      rel="noopener noreferrer"
      onClick={(e) => e.stopPropagation()}
      className={cn(
        "block w-[250px] max-w-full overflow-hidden rounded-2xl border border-border bg-secondary text-left transition-colors hover:bg-secondary/80",
        className
      )}
      aria-label={`Link preview: ${meta?.title ?? url}`}
    >
      {image && (
        <div className="h-[140px] w-full overflow-hidden bg-muted">
          <img
            src={image}
            alt=""
            loading="lazy"
            onError={() => setImageFailed(true)}
            className="h-full w-full object-cover"
          />
        </div>
      )}
      <div className="flex items-center gap-2.5 px-3 py-2.5">
        {!image && (
          <span className="flex h-[38px] w-[38px] shrink-0 items-center justify-center rounded-xl bg-background text-foreground">
            <Link2 className="h-4 w-4" strokeWidth={2.2} />
          </span>
        )}
        <div className="min-w-0 flex-1">
          {meta === null ? (
            <span className="mb-1 block h-3 w-[150px] rounded bg-border" />
          ) : meta.title ? (
            <p className="line-clamp-2 text-[14px] font-semibold leading-snug text-foreground">{meta.title}</p>
          ) : null}
          <p className="truncate text-[12px] text-muted-foreground">{host}</p>
        </div>
      </div>
    </a>
  );
}

function safeHost(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return url;
  }
}
