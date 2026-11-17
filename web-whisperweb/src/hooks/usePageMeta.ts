import { useEffect } from "react";

const DEFAULT_TITLE = "Whisper — the social network built on real connection";
const DEFAULT_DESCRIPTION =
  "Whisper is a social network for real conversations and real communities — stories, reels, DMs, verified creators, and Jasper, your AI companion. With best-in-class fitness tools built in for when you want them.";

function setMeta(selector: string, attr: string, content: string): void {
  let tag = document.head.querySelector<HTMLMetaElement>(selector);
  if (!tag) {
    tag = document.createElement("meta");
    const [key, value] = attr.split("=");
    tag.setAttribute(key, value);
    document.head.appendChild(tag);
  }
  tag.setAttribute("content", content);
}

/**
 * Per-page SEO: sets the document title, meta description, and Open Graph
 * tags, restoring the site defaults when the page unmounts.
 */
export function usePageMeta(title?: string, description?: string): void {
  useEffect(() => {
    const fullTitle = title ? `${title} · Whisper` : DEFAULT_TITLE;
    const desc = description ?? DEFAULT_DESCRIPTION;

    document.title = fullTitle;
    setMeta('meta[name="description"]', "name=description", desc);
    setMeta('meta[property="og:title"]', "property=og:title", fullTitle);
    setMeta(
      'meta[property="og:description"]',
      "property=og:description",
      desc
    );

    return () => {
      document.title = DEFAULT_TITLE;
      setMeta('meta[name="description"]', "name=description", DEFAULT_DESCRIPTION);
      setMeta('meta[property="og:title"]', "property=og:title", DEFAULT_TITLE);
      setMeta(
        'meta[property="og:description"]',
        "property=og:description",
        DEFAULT_DESCRIPTION
      );
    };
  }, [title, description]);
}
