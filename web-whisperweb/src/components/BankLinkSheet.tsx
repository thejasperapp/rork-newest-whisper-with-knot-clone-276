import { useEffect, useRef, useState } from "react";
import { Loader2, X } from "lucide-react";
import {
  loadConnectAndInitialize,
  type StripeConnectInstance,
} from "@stripe/connect-js";
import {
  ConnectAccountOnboarding,
  ConnectComponentsProvider,
} from "@stripe/react-connect-js";

import { createConnectSession } from "@/lib/coachPay";

/**
 * In-app bank linking (Cash App / DoorDash style) — renders Stripe's
 * embedded onboarding inside a Whisper-styled sheet so coaches never leave
 * the app. Identity + bank collection stays fully PCI/KYC compliant because
 * Stripe still powers the form; we just host it inline.
 */
export function BankLinkSheet({
  onClose,
  onDone,
}: {
  onClose: () => void;
  onDone: () => void;
}) {
  const [instance, setInstance] = useState<StripeConnectInstance | null>(null);
  const [error, setError] = useState<string | null>(null);
  const startedRef = useRef<boolean>(false);

  useEffect(() => {
    if (startedRef.current) return;
    startedRef.current = true;
    let cancelled = false;

    (async () => {
      try {
        const first = await createConnectSession();
        if (cancelled) return;
        let usedFirst = false;
        const connect = loadConnectAndInitialize({
          publishableKey: first.publishableKey,
          fetchClientSecret: async () => {
            if (!usedFirst) {
              usedFirst = true;
              return first.clientSecret;
            }
            const next = await createConnectSession();
            return next.clientSecret;
          },
          appearance: {
            variables: {
              colorPrimary: "#f97316",
              buttonPrimaryColorBackground: "#f97316",
              buttonPrimaryColorText: "#ffffff",
              borderRadius: "12px",
              fontFamily: "inherit",
            },
          },
        });
        setInstance(connect);
      } catch (err) {
        if (cancelled) return;
        setError(
          err instanceof Error ? err.message : "Couldn't start bank linking."
        );
      }
    })();

    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <div className="fixed inset-0 z-[80] flex items-end justify-center sm:items-center">
      <button
        aria-label="Close"
        onClick={onClose}
        className="absolute inset-0 bg-black/50 backdrop-blur-sm"
      />
      <div className="relative flex h-[92dvh] w-full flex-col overflow-hidden rounded-t-[24px] border border-border bg-card shadow-2xl sm:h-[85vh] sm:max-w-lg sm:rounded-[24px]">
        <div className="flex items-center justify-between border-b border-border px-5 py-4">
          <div>
            <p className="text-[16px] font-extrabold">Add your bank</p>
            <p className="text-[12.5px] text-muted-foreground">
              Secured by Stripe · stays in the app · about a minute
            </p>
          </div>
          <button
            onClick={onClose}
            aria-label="Close"
            className="flex h-9 w-9 items-center justify-center rounded-full bg-secondary transition-transform active:scale-90"
          >
            <X className="h-4.5 w-4.5" />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto px-5 py-4">
          {error ? (
            <div className="flex h-full flex-col items-center justify-center text-center">
              <p className="text-[14px] font-semibold">{error}</p>
              <button
                onClick={onClose}
                className="mt-4 rounded-full bg-foreground px-5 py-2.5 text-[13.5px] font-bold text-background"
              >
                Close
              </button>
            </div>
          ) : instance ? (
            <ConnectComponentsProvider connectInstance={instance}>
              <ConnectAccountOnboarding onExit={onDone} />
            </ConnectComponentsProvider>
          ) : (
            <div className="flex h-full items-center justify-center">
              <Loader2 className="h-7 w-7 animate-spin text-muted-foreground" />
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
