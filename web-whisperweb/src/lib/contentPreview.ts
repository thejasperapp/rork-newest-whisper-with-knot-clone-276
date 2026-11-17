const labels: Record<string, string> = { workout: "Workout", sharedpost: "Shared post", film: "Film", article: "Article", recipe: "Recipe", chart: "Chart", checkin: "Check-in", macros: "Nutrition", healthshare: "Health update", profileshare: "Shared profile", story: "Story", storytag: "Story mention", teams: "Team invitation", calendar: "Meet invitation", map: "Shared place", grocery: "Grocery list" };

/** Display-only sanitizer. Never use preview text as a payload or access authority. */
export function contentPreview(input: string | null | undefined, fallback = "Shared content", limit = 160): string {
  if (typeof input !== "string" || !input.trim()) return "";
  const raw = input.slice(0, 65536);
  const marker = /::whisper-([a-z0-9-]+)-v\d+::/gi;
  let out = "", cursor = 0, label = fallback;
  let match: RegExpExecArray | null;
  while ((match = marker.exec(raw))) {
    out += raw.slice(cursor, match.index);
    label = labels[match[1]] ?? label;
    let end = marker.lastIndex;
    while (raw[end] === " " || raw[end] === "\t") end++;
    if (raw[end] === "{" || raw[end] === "[") {
      const stack: string[] = []; let quoted = false, escaped = false, complete = false;
      for (; end < raw.length; end++) {
        const char = raw[end];
        if (quoted) { if (escaped) escaped = false; else if (char === "\\") escaped = true; else if (char === '"') quoted = false; continue; }
        if (char === '"') quoted = true;
        else if (char === "{" || char === "[") stack.push(char);
        else if (char === "}" || char === "]") { const open = stack.pop(); if ((char === "}" && open !== "{") || (char === "]" && open !== "[")) break; if (!stack.length) { end++; complete = true; break; } }
      }
      // A broken multiline envelope has no trustworthy end boundary.
      if (!complete) end = raw.length;
    } else {
      const newline = raw.indexOf("\n", end);
      end = newline < 0 ? raw.length : newline;
    }
    cursor = end; marker.lastIndex = end;
    out += " ";
  }
  out += raw.slice(cursor);
  out = out.replace(/\b(?:jasper|ember|whisper)-sticker:\/\/\S+/gi, "Sticker").replace(/\s+/g, " ").trim();
  // Retire incomplete reserved markers too; ordinary authored JSON is preserved.
  const incomplete = out.indexOf("::whisper-");
  if (incomplete >= 0) out = out.slice(0, incomplete).trim();
  return Array.from(out || label).slice(0, limit).join("");
}
