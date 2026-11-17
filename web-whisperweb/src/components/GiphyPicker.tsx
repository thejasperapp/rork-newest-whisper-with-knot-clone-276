import { memo, useEffect, useState } from "react";
import { Search, X } from "lucide-react";

import { cn } from "@/lib/utils";

type Kind = "gifs" | "stickers";

interface GiphyImage {
  url: string;
}
interface GiphyResult {
  id: string;
  images: {
    fixed_height: GiphyImage;
    fixed_height_small?: GiphyImage;
    original: GiphyImage;
  };
}

const API_KEY = import.meta.env.EXPO_PUBLIC_GIPHY_API_KEY as string | undefined;

async function fetchGiphy(
  kind: Kind,
  query: string
): Promise<GiphyResult[]> {
  if (!API_KEY) return [];
  const base = `https://api.giphy.com/v1/${kind}`;
  const endpoint = query.trim()
    ? `${base}/search?api_key=${API_KEY}&q=${encodeURIComponent(
        query.trim()
      )}&limit=24&rating=pg-13`
    : `${base}/trending?api_key=${API_KEY}&limit=24&rating=pg-13`;
  const res = await fetch(endpoint);
  if (!res.ok) return [];
  const json = (await res.json()) as { data: GiphyResult[] };
  return json.data ?? [];
}

/**
 * Giphy-powered GIF + sticker picker used in the DM composer (matches the
 * iOS Ember message capabilities). Selecting an item returns its URL so the
 * caller can send it as a message that renders inline.
 */
function GiphyPickerBase({
  onSelect,
  onClose,
  inline = false,
}: {
  onSelect: (url: string) => void;
  onClose: () => void;
  /** When true the picker is a static inline panel (composer) rather than a
   * floating popover anchored above an input (DM bar). */
  inline?: boolean;
}) {
  const [kind, setKind] = useState<Kind>("gifs");
  const [query, setQuery] = useState<string>("");
  const [results, setResults] = useState<GiphyResult[]>([]);
  const [loading, setLoading] = useState<boolean>(true);

  useEffect(() => {
    let active = true;
    setLoading(true);
    const t = setTimeout(() => {
      void fetchGiphy(kind, query).then((data) => {
        if (active) {
          setResults(data);
          setLoading(false);
        }
      });
    }, 250);
    return () => {
      active = false;
      clearTimeout(t);
    };
  }, [kind, query]);

  return (
    <div
      className={cn(
        "overflow-hidden rounded-2xl border border-border bg-popover shadow-2xl",
        inline
          ? "w-full"
          : "absolute inset-x-0 bottom-full mx-2 mb-2"
      )}
    >
      <div className="flex items-center gap-2 border-b border-border p-2">
        <div className="flex items-center gap-1 rounded-full bg-secondary p-0.5">
          {(["gifs", "stickers"] as Kind[]).map((k) => (
            <button
              key={k}
              onClick={() => setKind(k)}
              className={cn(
                "rounded-full px-3 py-1 text-xs font-semibold capitalize transition-colors",
                kind === k
                  ? "bg-background text-foreground shadow-sm"
                  : "text-muted-foreground"
              )}
            >
              {k}
            </button>
          ))}
        </div>
        <div className="flex flex-1 items-center gap-1.5 rounded-full bg-secondary px-3 py-1.5">
          <Search className="h-4 w-4 text-muted-foreground" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={`Search ${kind}`}
            autoFocus
            className="w-full bg-transparent text-sm outline-none placeholder:text-muted-foreground"
          />
        </div>
        <button
          onClick={onClose}
          aria-label="Close"
          className="flex h-7 w-7 items-center justify-center rounded-full text-muted-foreground transition-colors hover:bg-secondary"
        >
          <X className="h-4 w-4" />
        </button>
      </div>

      <div className="h-64 overflow-y-auto p-2">
        {!API_KEY && (
          <p className="px-2 py-8 text-center text-sm text-muted-foreground">
            GIF search isn't configured.
          </p>
        )}
        {API_KEY && loading && (
          <p className="px-2 py-8 text-center text-sm text-muted-foreground">
            Loading…
          </p>
        )}
        {API_KEY && !loading && results.length === 0 && (
          <p className="px-2 py-8 text-center text-sm text-muted-foreground">
            Nothing found.
          </p>
        )}
        <div className="columns-3 gap-1.5 [&>*]:mb-1.5">
          {results.map((g) => (
            <button
              key={g.id}
              onClick={() => onSelect(g.images.original.url)}
              className="block w-full overflow-hidden rounded-lg bg-secondary"
            >
              <img
                src={(g.images.fixed_height_small ?? g.images.fixed_height).url}
                alt=""
                loading="lazy"
                className="w-full"
              />
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

export const GiphyPicker = memo(GiphyPickerBase);
