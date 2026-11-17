import { forwardRef, useId } from "react";
import type { LucideProps } from "lucide-react";

const paths = {
  plane: "M23 12H78C94 12 97 19 88 30L54 87C49 96 41 94 39 84L30 54L12 35C2 24 8 12 23 12Z",
  share: "M13 39L82 11Q94 6 90 19L63 87Q58 99 52 87L39 61L13 49Q2 44 13 39ZM39 61L66 35",
  heart: "M50 86C32 74 10 58 10 35C10 9 38 6 50 24C62 6 90 9 90 35C90 58 68 74 50 86Z",
  comment: "M28 12H72C85 12 90 20 90 32V60Q90 78 70 78H44L19 91Q13 94 16 85L20 74Q10 70 10 57V32Q10 12 28 12Z",
  repost: "M87 39C78 5 36 4 14 29M14 8V31H37M13 61C22 95 64 96 86 71M86 92V69H63",
  home: "M13 48Q6 42 16 34L42 12Q50 5 58 12L84 34Q94 42 87 48L84 49V79Q84 88 74 88H61V65Q50 51 39 65V88H26Q16 88 16 79V49Z",
  search: "M72 40A31 31 0 1 1 10 40A31 31 0 1 1 72 40M64 64L88 88",
} as const;

/** Native normalized geometry, with the same rounded 2.2-point optical stroke. */
function glyph(kind: keyof typeof paths) {
  return forwardRef<SVGSVGElement, LucideProps>(function Glyph({ size = 24, strokeWidth = 2.2, fill = "none", children, ...props }, ref) {
    const id = useId().replace(/:/g, "");
    const selected = fill !== "none" && kind === "plane";
    return <svg ref={ref} width={size} height={size} viewBox="0 0 100 100" fill={fill} stroke="currentColor" strokeWidth={Number(strokeWidth) * 100 / 24} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" {...props}>
      {selected && <defs><mask id={id}><rect width="100" height="100" fill="white" stroke="none" /><path d="M25 57L66 34" fill="none" stroke="black" strokeWidth="9.5" /></mask></defs>}
      <g strokeWidth={Number(strokeWidth) * 100 / 24}>
        <path d={paths[kind]} mask={selected ? `url(#${id})` : undefined} />
        {kind === "plane" && !selected && <path d="M30 54L66 34" fill="none" />}
      </g>{children}
    </svg>;
  });
}
export const WhisperPlane = glyph("plane");
export const WhisperShare = glyph("share");
export const WhisperHeart = glyph("heart");
export const WhisperComment = glyph("comment");
export const WhisperRepost = glyph("repost");
export const WhisperHome = glyph("home");
export const WhisperSearch = glyph("search");
