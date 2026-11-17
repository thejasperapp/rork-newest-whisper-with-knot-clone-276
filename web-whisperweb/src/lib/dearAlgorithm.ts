/** Native-compatible, composer-only directives. Wishes never become public posts. */
export function dearAlgorithmWish(caption: string): string | null {
  const match = /^(?:@dear ember|dear ember|@dear knot|dear knot|@knot)(?=$|\s|[,:;.!?])([\s\S]*)$/i.exec(caption.trim());
  return match ? match[1].replace(/^[\s,:;.!?]+|[\s,:;.!?]+$/g, "") : null;
}
const stop = new Set("the a an of to in on for and or but is are was were be been being i you me my mine your yours want need please more less see show feed posts post ember knot dear with without about this that these those up down kind".split(" "));
function key(owner: string): string { return `whisper.dear-algorithm.v1:${owner.toLowerCase()}`; }
export function saveAlgorithmWish(owner: string, wish: string): void {
  if (!owner || !wish.trim()) throw new Error("Tell Knot what you’d like to see in your feed.");
  const keywords = [...new Set((wish.toLowerCase().replace(/#/g, "").match(/[\p{L}\p{N}]+/gu) ?? []).filter(token => token.length >= 3 && !stop.has(token)))].slice(0, 6);
  // Like native, tuning is local to this account and device. Do not adopt another owner's wishes.
  localStorage.setItem(key(owner), JSON.stringify({ wish: wish.trim(), keywords }));
}
export function algorithmKeywords(owner?: string | null): string[] {
  if (!owner) return [];
  try {
    const value: unknown = JSON.parse(localStorage.getItem(key(owner)) ?? "null");
    if (!value || typeof value !== "object" || !("keywords" in value) || !Array.isArray(value.keywords)) return [];
    return value.keywords.filter((item): item is string => typeof item === "string").slice(0, 6);
  } catch { return []; }
}
