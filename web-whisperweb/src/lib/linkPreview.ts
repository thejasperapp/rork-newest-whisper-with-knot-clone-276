import { BACKEND_URL, resolveBackend } from "@/lib/billing";

/**
 * LINKS IN CHAT — detection + unfurling, mirroring iOS `WhisperLinkDetector`.
 * A message carrying a URL renders it as a live link and unfurls a preview
 * card beneath the bubble; the metadata comes from the backend's
 * /link/preview route (browsers can't read a third-party page's Open Graph
 * tags cross-origin) and is cached per URL for the session.
 */

export interface LinkPreviewMeta {
  url: string;
  kind: "link" | "image";
  title: string | null;
  description?: string | null;
  image?: string | null;
  siteName?: string | null;
}

const URL_RE = /https?:\/\/[^\s<>"')\]]+/gi;
const IMAGE_EXT_RE = /\.(jpe?g|png|gif|webp|heic|heif)(\?|\/|$)/i;

/** Is this body ONLY a bare image URL (rendered as an image bubble already)? */
export function isBareImageUrl(body: string): boolean {
  const t = body.trim();
  return /^https?:\/\/\S+$/i.test(t) && IMAGE_EXT_RE.test(t);
}

/** The first http(s) URL inside a message body — nil for wire tokens and bare image URLs. */
export function firstLinkUrl(body: string): string | null {
  const t = body.trim();
  if (!t || t.startsWith("::") || t.startsWith("{") || t.startsWith("jasper-sticker://")) return null;
  const matches = t.match(URL_RE);
  if (!matches) return null;
  for (const raw of matches) {
    const cleaned = raw.replace(/[.,;:!?]+$/, "");
    if (IMAGE_EXT_RE.test(cleaned)) continue;
    try {
      const u = new URL(cleaned);
      if (u.protocol === "http:" || u.protocol === "https:") return u.toString();
    } catch {
      /* not a URL after all */
    }
  }
  return null;
}

/** Splits a body into text + link segments so URLs can render as anchors. */
export function splitLinks(body: string): { text: string; href: string | null }[] {
  const out: { text: string; href: string | null }[] = [];
  let last = 0;
  const re = new RegExp(URL_RE.source, "gi");
  let m: RegExpExecArray | null;
  while ((m = re.exec(body)) !== null) {
    const raw = m[0];
    const trailing = raw.match(/[.,;:!?]+$/)?.[0] ?? "";
    const clean = trailing ? raw.slice(0, raw.length - trailing.length) : raw;
    if (m.index > last) out.push({ text: body.slice(last, m.index), href: null });
    out.push({ text: clean, href: clean });
    if (trailing) out.push({ text: trailing, href: null });
    last = m.index + raw.length;
  }
  if (last < body.length) out.push({ text: body.slice(last), href: null });
  return out;
}

const cache = new Map<string, Promise<LinkPreviewMeta>>();

function hostOf(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return url;
  }
}

/** Unfurls one URL (session-cached; never throws — falls back to host-only). */
export function fetchLinkPreview(url: string): Promise<LinkPreviewMeta> {
  const hit = cache.get(url);
  if (hit) return hit;
  const task = (async (): Promise<LinkPreviewMeta> => {
    const fallback: LinkPreviewMeta = { url, kind: "link", title: null, siteName: hostOf(url) };
    try {
      const base = (await resolveBackend().catch(() => "")) || BACKEND_URL;
      const controller = new AbortController();
      const timer = window.setTimeout(() => controller.abort(), 9000);
      const res = await fetch(`${base}/link/preview?url=${encodeURIComponent(url)}`, {
        signal: controller.signal,
      });
      window.clearTimeout(timer);
      if (!res.ok) return fallback;
      const data = (await res.json()) as Partial<LinkPreviewMeta> & { error?: string };
      if (data.error) return fallback;
      return {
        url: typeof data.url === "string" ? data.url : url,
        kind: data.kind === "image" ? "image" : "link",
        title: typeof data.title === "string" && data.title.trim() ? data.title.trim() : null,
        description: typeof data.description === "string" ? data.description : null,
        image: typeof data.image === "string" && /^https?:\/\//.test(data.image) ? data.image : null,
        siteName: typeof data.siteName === "string" && data.siteName ? data.siteName : hostOf(url),
      };
    } catch {
      return fallback;
    }
  })();
  cache.set(url, task);
  return task;
}
