/** Safe previews are applied before APNs, not only by the optional iOS extension. */
export function groupEnvelope(raw: string): { id: string; name: string; body: string } | null {
  if (raw.length > 262144) return null;
  const match = /^::wg-v1::([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})::([^]*?)::([^]*)$/i.exec(raw);
  return match ? { id: match[1].toLowerCase(), name: safePreview(match[2]), body: match[3] } : null;
}

export function safePreview(raw: string): string {
  if (raw.length > 262144) return "New message";
  const group = raw.startsWith("::wg-v1::") ? groupEnvelope(raw) : null;
  if (group) return group.body.includes("::wg-") ? "New message" : safePreview(group.body);
  const text = raw.trim();
  if (!text || text.includes("::wg-") || /^[{[]/.test(text)) return "New message";
  if (/(jasper|ember)-sticker:\/\//.test(text)) return "Sent a sticker";
  const marker = text.indexOf("::whisper-");
  if (marker >= 0) {
    const token = text.slice(marker + 10);
    const labels: [string, string][] = [
      ["callsummary-", "Call ended"], ["call-", "Incoming call"],
      ["postmeta-", "Shared a post"], ["post-", "Shared a post"],
      ["photo-", "Sent a photo"], ["video-", "Sent a video"],
      ["media-", "Sent an attachment"], ["voice-", "Sent a voice message"],
      ["audio-", "Sent audio"], ["program-", "Sent a program"],
      ["workout", "Sent a workout"], ["recipe-", "Shared a recipe"],
      ["meeting-", "Meeting invite"], ["calendar-", "Calendar event"],
      ["profile-", "Shared a profile"], ["film-", "Shared a film"],
      ["article-", "Shared an article"], ["jasper-", "Shared a Jasper answer"],
      ["ember-", "Shared a Jasper answer"], ["chart-", "Sent a chart"],
      ["map-", "Sent a map"], ["grocery-", "Sent a grocery list"],
    ];
    return labels.find(([prefix]) => token.startsWith(prefix))?.[1] ?? "New message";
  }
  if (text.startsWith("http") && text.includes("whisper-media")) return "Sent an attachment";
  return Array.from(text.replace(/\s+/g, " ")).slice(0, 180).join("");
}
