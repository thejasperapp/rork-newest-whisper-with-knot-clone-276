import { memo, useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { MapPin, Music, Pause, Play, Users } from "lucide-react";

import { MarqueeText, EqualizerBars } from "@/components/MusicMarquee";
import { PollCard } from "@/components/PollCard";
import type { PostMeta } from "@/lib/postMeta";

/** Small music chip with artwork, scrolling title and a preview play button. */
function MusicChip({
  music,
}: {
  music: NonNullable<PostMeta["music"]>;
}) {
  const [playing, setPlaying] = useState<boolean>(false);
  const audioRef = useRef<HTMLAudioElement | null>(null);

  useEffect(() => {
    return () => {
      audioRef.current?.pause();
      audioRef.current = null;
    };
  }, []);

  const toggle = (): void => {
    if (!music.previewURL) return;
    if (playing) {
      audioRef.current?.pause();
      setPlaying(false);
      return;
    }
    const audio = audioRef.current ?? new Audio(music.previewURL);
    audio.volume = 0.85;
    audio.onended = () => setPlaying(false);
    audioRef.current = audio;
    void audio.play().catch(() => undefined);
    setPlaying(true);
  };

  return (
    <button
      onClick={toggle}
      disabled={!music.previewURL}
      className="mt-2 flex w-full max-w-[320px] items-center gap-2.5 rounded-2xl border border-border bg-secondary/50 px-2.5 py-2 text-left transition-colors hover:bg-secondary disabled:cursor-default"
    >
      <span className="relative flex h-10 w-10 shrink-0 items-center justify-center overflow-hidden rounded-lg bg-secondary">
        {music.artworkURL ? (
          <img src={music.artworkURL} alt="" className="h-full w-full object-cover" />
        ) : (
          <Music className="h-4 w-4 text-muted-foreground" />
        )}
        {music.previewURL && (
          <span className="absolute inset-0 flex items-center justify-center bg-black/35 text-white">
            {playing ? <Pause className="h-4 w-4" /> : <Play className="h-4 w-4" />}
          </span>
        )}
      </span>
      <span className="min-w-0 flex-1">
        <MarqueeText
          text={music.title}
          className="text-[13px] font-bold"
        />
        <span className="block truncate text-[12px] text-muted-foreground">
          {music.artist}
        </span>
      </span>
      {playing && <EqualizerBars color="#fa7321" size={14} />}
    </button>
  );
}

interface PostMetaViewProps {
  postId: string;
  meta: PostMeta;
}

/** Renders the optional rich attachments of a post (music, location, tags, poll). */
function PostMetaViewBase({ postId, meta }: PostMetaViewProps) {
  const tagged = meta.tagged ?? [];
  return (
    <div>
      {meta.location && (
        <span className="mt-1.5 inline-flex items-center gap-1 rounded-full bg-secondary px-2.5 py-1 text-[12px] font-medium text-muted-foreground">
          <MapPin className="h-3.5 w-3.5" />
          {meta.location}
        </span>
      )}

      {tagged.length > 0 && (
        <p className="mt-1.5 flex flex-wrap items-center gap-x-1 text-[13px] text-muted-foreground">
          <Users className="h-3.5 w-3.5" />
          <span>with</span>
          {tagged.map((u, i) => (
            <span key={u}>
              <Link
                to={`/u/${u}`}
                className="font-semibold text-foreground hover:underline"
              >
                @{u}
              </Link>
              {i < tagged.length - 1 ? "," : ""}
            </span>
          ))}
        </p>
      )}

      {meta.music && <MusicChip music={meta.music} />}

      {meta.poll && meta.poll.options.length >= 2 && (
        <PollCard postId={postId} poll={meta.poll} />
      )}
    </div>
  );
}

export const PostMetaView = memo(PostMetaViewBase);
