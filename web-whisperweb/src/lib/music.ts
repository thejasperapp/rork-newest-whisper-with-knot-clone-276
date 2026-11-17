/**
 * Lightweight music search for the "What's on your mind?" composer — the web
 * counterpart of the iOS `WhisperStoryMusicService`. Uses the public iTunes
 * Search API (no key required) so the song catalog stays in sync with the iOS
 * music picker. Returns title / artist / artwork / 30-second preview clips.
 */

export interface MusicTrack {
  id: string;
  title: string;
  artist: string;
  artworkURL: string | null;
  previewURL: string | null;
}

interface ITunesResult {
  trackId?: number;
  trackName?: string;
  artistName?: string;
  artworkUrl100?: string;
  previewUrl?: string;
}

function mapResults(results: ITunesResult[]): MusicTrack[] {
  const seen = new Set<string>();
  const tracks: MusicTrack[] = [];
  for (const r of results) {
    if (!r.trackName || !r.artistName) continue;
    const id = String(r.trackId ?? `${r.trackName}-${r.artistName}`);
    if (seen.has(id)) continue;
    seen.add(id);
    tracks.push({
      id,
      title: r.trackName,
      artist: r.artistName,
      // Upgrade the 100px thumbnail to a crisp 200px square.
      artworkURL: r.artworkUrl100?.replace("100x100", "200x200") ?? null,
      previewURL: r.previewUrl ?? null,
    });
  }
  return tracks;
}

async function itunes(term: string, limit: number): Promise<MusicTrack[]> {
  try {
    const url = `https://itunes.apple.com/search?media=music&entity=song&limit=${limit}&term=${encodeURIComponent(
      term
    )}`;
    const res = await fetch(url);
    if (!res.ok) return [];
    const json = (await res.json()) as { results?: ITunesResult[] };
    return mapResults(json.results ?? []);
  } catch {
    return [];
  }
}

/** A small "trending" seed list shown before the user searches. */
export async function trendingTracks(): Promise<MusicTrack[]> {
  return itunes("top hits", 25);
}

/** Search songs by free text. */
export async function searchTracks(query: string): Promise<MusicTrack[]> {
  const trimmed = query.trim();
  if (!trimmed) return [];
  return itunes(trimmed, 25);
}
