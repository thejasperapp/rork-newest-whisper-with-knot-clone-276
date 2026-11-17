import type { EmberCoachMode, EmberExpression } from "@/lib/emberBrain";
import { KnotMascot } from "@/components/Knot";

/** Compatibility wrapper: existing assistant hosts now share the native Knot artwork.
 * Legacy costume arguments remain accepted without recoloring the registered art.
 */
export function EmberMascot(props: {
  size?: number;
  isActive?: boolean;
  showsEyes?: boolean;
  expression?: EmberExpression;
  coachMode?: EmberCoachMode;
  cyclesExpressions?: boolean;
  palette?: { accent: string; softAccent: string; deepAccent: string };
  smitten?: boolean;
  className?: string;
}) {
  return <KnotMascot size={props.size} isActive={props.isActive} showsEyes={props.showsEyes} expression={props.expression} className={props.className} />;
}
