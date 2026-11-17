import { memo, useState } from "react";

import { cn } from "@/lib/utils";
import { initial } from "@/lib/format";
import { JASPER_ICON_SRC } from "@/components/JasperAppIcon";

interface AvatarProps {
  url?: string | null;
  name?: string | null;
  size?: number;
  className?: string;
}

/**
 * Circular avatar on the warm-orange Whisper brand disc (#FA9452). The
 * orange backdrop is always present — a photo sits on top when set, and the
 * white monogram shows through otherwise, exactly like `WhisperAvatar` on iOS.
 */
function AvatarBase({ url, name, size = 44, className }: AvatarProps) {
  const seed = name ?? "?";
  // Remote avatars (e.g. Instagram-proxied prospect photos) can 404 — hide
  // the broken image so the monogram disc shows instead of a broken icon.
  const [failedUrl, setFailedUrl] = useState<string | null>(null);
  // Jasper's own accounts wear THE Jasper icon — the one mark everywhere.
  const lower = seed.toLowerCase();
  const isJasper = lower === "ember" || lower === "jasper";
  if (isJasper) {
    return (
      <img
        src={JASPER_ICON_SRC}
        alt="Jasper"
        draggable={false}
        className={cn("shrink-0 rounded-full object-cover", className)}
        style={{ width: size, height: size }}
      />
    );
  }

  return (
    <div
      className={cn(
        "relative flex shrink-0 items-center justify-center overflow-hidden rounded-full bg-avatar",
        className
      )}
      style={{ width: size, height: size }}
    >
      <span
        className="font-bold text-white"
        style={{ fontSize: size * 0.42 }}
      >
        {initial(seed)}
      </span>
      {url && url !== failedUrl && (
        <img
          src={url}
          alt={seed}
          loading="lazy"
          onError={() => setFailedUrl(url)}
          className="absolute inset-0 h-full w-full object-cover"
        />
      )}
    </div>
  );
}

export const Avatar = memo(AvatarBase);
