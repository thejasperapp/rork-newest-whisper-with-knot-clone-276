import { useQuery } from "@tanstack/react-query";
import { FlaskConical } from "lucide-react";

import { fetchBillingMode } from "@/lib/billing";

/**
 * Amber strip shown on checkout surfaces while Stripe runs on TEST keys.
 * Disappears automatically the moment live keys are configured — no code
 * change needed on switch day.
 */
export function TestModeBanner({ className }: { className?: string }) {
  const mode = useQuery({
    queryKey: ["billing-mode"],
    queryFn: fetchBillingMode,
    staleTime: 10 * 60 * 1000,
    retry: false,
  });
  if (!mode.data?.testMode) return null;
  return (
    <div
      className={
        "flex items-center gap-2 rounded-2xl border border-amber-500/40 bg-amber-500/10 px-3.5 py-2.5 text-left " +
        (className ?? "")
      }
    >
      <FlaskConical className="h-4 w-4 shrink-0 text-amber-600" />
      <p className="text-[12.5px] leading-snug text-amber-700 dark:text-amber-400">
        <span className="font-bold">Test mode.</span> Payments are in Stripe
        test mode — cards are never really charged. Use card 4242&nbsp;4242
        4242&nbsp;4242, any future date, any CVC.
      </p>
    </div>
  );
}
