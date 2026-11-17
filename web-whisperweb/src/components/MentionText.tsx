import { memo } from "react";
import { Link } from "react-router-dom";

import { cn } from "@/lib/utils";

/** Matches @handles and #hashtags as standalone tokens. */
const TOKEN = /(@[a-zA-Z0-9_]+|#[a-zA-Z0-9_]+)/g;

interface MentionTextProps {
  text: string;
  className?: string;
}

/**
 * Renders post/comment text with tappable @mentions (linking to the tagged
 * profile) and #hashtags (linking to search). Mirrors the iOS tappable
 * mention/hashtag behaviour so the tagging system works end-to-end on web.
 */
function MentionTextBase({ text, className }: MentionTextProps) {
  const parts = text.split(TOKEN);
  return (
    <span className={cn("whitespace-pre-wrap break-words", className)}>
      {parts.map((part, i) => {
        if (part.length > 1 && part.startsWith("@")) {
          return (
            <Link
              key={`${part}-${i}`}
              to={`/u/${part.slice(1)}`}
              onClick={(e) => e.stopPropagation()}
              className="font-semibold text-foreground hover:underline"
            >
              {part}
            </Link>
          );
        }
        if (part.length > 1 && part.startsWith("#")) {
          return (
            <Link
              key={`${part}-${i}`}
              to={`/search?q=${encodeURIComponent(part)}`}
              onClick={(e) => e.stopPropagation()}
              className="font-semibold text-foreground hover:underline"
            >
              {part}
            </Link>
          );
        }
        return <span key={`t-${i}`}>{part}</span>;
      })}
    </span>
  );
}

export const MentionText = memo(MentionTextBase);
