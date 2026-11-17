/** Whole leading token only. Historical commands remain compatible with iOS. */
export function knotCommandPrompt(text: string): string | null {
  const match = /^\/(?:knot|jasper|ember)(?=\s|$)\s*([\s\S]*)$/i.exec(text.trim());
  return match ? match[1].trim() : null;
}
