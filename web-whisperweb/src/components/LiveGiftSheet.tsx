import { useCallback, useEffect, useRef, useState } from "react";
import { Coins, Loader2, Plus, X } from "lucide-react";
import { toast } from "sonner";

import { EmbeddedCheckoutSheet } from "@/components/EmbeddedCheckoutSheet";
import {
  fetchGiftWallet,
  formatGiftCents,
  GIFT_PACK_CENTS,
  sendLiveGift,
  startGiftTopup,
  type GiftCatalogItem,
  type GiftWallet,
} from "@/lib/gifts";

/**
 * The live gift sheet — viewers pick a gift and it sends on the spot from
 * their prepaid credit balance; packs top the balance up through the
 * embedded Stripe checkout (the same rail as every other Whisper payment).
 * Everyone in the room sees the gift banner via realtime.
 */
export function LiveGiftSheet({
  roomId,
  onClose,
}: {
  roomId: string;
  onClose: () => void;
}) {
  const [wallet, setWallet] = useState<GiftWallet | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [qty, setQty] = useState<number>(1);
  const [sendingId, setSendingId] = useState<string | null>(null);
  const [startingPack, setStartingPack] = useState<number | null>(null);
  const [checkout, setCheckout] = useState<{
    clientSecret: string;
    publishableKey: string;
    amountCents: number;
  } | null>(null);
  const pollTimers = useRef<number[]>([]);

  const refresh = useCallback(async () => {
    try {
      const w = await fetchGiftWallet();
      setWallet(w);
    } catch {
      // Sends surface their own honest errors.
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void refresh();
    const timers = pollTimers.current;
    return () => {
      timers.forEach((t) => window.clearTimeout(t));
    };
  }, [refresh]);

  const send = async (gift: GiftCatalogItem) => {
    if (sendingId) return;
    setSendingId(gift.id);
    try {
      const res = await sendLiveGift({ roomId, giftId: gift.id, qty });
      setWallet((prev) =>
        prev ? { ...prev, balanceCents: res.balanceCents } : prev
      );
      toast.success(
        `Sent ${gift.emoji} ${gift.label}${qty > 1 ? ` ×${qty}` : ""}!`
      );
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Couldn't send that gift."
      );
    } finally {
      setSendingId(null);
    }
  };

  const buyPack = async (cents: number) => {
    if (startingPack !== null) return;
    setStartingPack(cents);
    try {
      const session = await startGiftTopup(cents);
      setCheckout({ ...session, amountCents: cents });
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Couldn't start checkout."
      );
    } finally {
      setStartingPack(null);
    }
  };

  const balance = wallet?.balanceCents ?? 0;
  const catalog = wallet?.catalog ?? [];
  const notReady = wallet !== null && !wallet.ready;

  return (
    <div className="fixed inset-0 z-[70] flex items-end justify-center sm:items-center">
      {checkout && (
        <EmbeddedCheckoutSheet
          clientSecret={checkout.clientSecret}
          publishableKey={checkout.publishableKey}
          brief={{
            title: "Whisper gift credits",
            price: formatGiftCents(checkout.amountCents),
            cadence: "one-time",
            note: "Credits land in your balance seconds after payment.",
            perks: [
              "Send gifts in any live room",
              "Hosts keep 70% of every gift",
              "Credits never expire",
            ],
            refundDays: 14,
          }}
          onClose={() => setCheckout(null)}
          onComplete={() => {
            setCheckout(null);
            toast.success("Payment received — credits land in a few seconds.");
            [1500, 4000, 8000].forEach((ms) => {
              pollTimers.current.push(
                window.setTimeout(() => void refresh(), ms)
              );
            });
          }}
        />
      )}
      <button
        aria-label="Close gifts"
        onClick={onClose}
        className="absolute inset-0 bg-black/50 backdrop-blur-sm"
      />
      <div className="relative max-h-[86dvh] w-full max-w-md overflow-y-auto rounded-t-[24px] border border-border bg-card p-5 shadow-2xl sm:rounded-[24px]">
        <div className="flex items-start justify-between">
          <div>
            <p className="text-[16px] font-extrabold">Send a gift</p>
            <p className="text-[12px] text-muted-foreground">
              Cheer this live — the host keeps 70%.
            </p>
          </div>
          <button
            onClick={onClose}
            aria-label="Close"
            className="flex h-9 w-9 items-center justify-center rounded-full bg-secondary"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {/* Balance pill */}
        <div className="mt-3 flex items-center justify-between rounded-2xl border border-pink-500/25 bg-pink-500/5 px-4 py-3">
          <div className="flex items-center gap-2">
            <span className="flex h-8 w-8 items-center justify-center rounded-full bg-pink-500/15">
              <Coins className="h-4 w-4 text-pink-500" />
            </span>
            <div>
              <p className="text-[10px] font-black uppercase tracking-wide text-muted-foreground">
                Gift credits
              </p>
              <p className="text-[16px] font-black tabular-nums">
                {loading ? "…" : formatGiftCents(balance)}
              </p>
            </div>
          </div>
          <div className="flex gap-1.5">
            {GIFT_PACK_CENTS.map((cents) => (
              <button
                key={cents}
                onClick={() => void buyPack(cents)}
                disabled={startingPack !== null || notReady}
                className="flex items-center gap-0.5 rounded-full border border-pink-500/40 px-2.5 py-1.5 text-[11.5px] font-bold text-pink-500 transition-transform active:scale-95 disabled:opacity-40"
              >
                {startingPack === cents ? (
                  <Loader2 className="h-3 w-3 animate-spin" />
                ) : (
                  <Plus className="h-3 w-3" />
                )}
                ${cents / 100}
              </button>
            ))}
          </div>
        </div>

        {notReady && (
          <p className="mt-3 rounded-xl border border-amber-500/40 bg-amber-500/5 px-3 py-2.5 text-[11.5px] leading-relaxed text-muted-foreground">
            Gifts aren't switched on yet — one-time setup pending (
            <code className="rounded bg-muted px-1">
              supabase/live-gifts.sql
            </code>
            ).
          </p>
        )}

        {/* Quantity */}
        <div className="mt-4 flex items-center gap-2">
          <p className="text-[11px] font-black uppercase tracking-wide text-muted-foreground">
            Amount
          </p>
          <div className="flex gap-1.5">
            {[1, 5, 10].map((n) => (
              <button
                key={n}
                onClick={() => setQty(n)}
                className={`rounded-full px-3 py-1 text-[12px] font-bold transition-colors ${
                  qty === n
                    ? "bg-pink-500 text-white"
                    : "border border-border text-muted-foreground"
                }`}
              >
                ×{n}
              </button>
            ))}
          </div>
        </div>

        {/* Gift grid */}
        <div className="mt-3 grid grid-cols-3 gap-2">
          {(catalog.length > 0
            ? catalog
            : ([] as GiftCatalogItem[])
          ).map((gift) => {
            const cost = gift.cents * qty;
            const canAfford = balance >= cost;
            return (
              <button
                key={gift.id}
                onClick={() => void send(gift)}
                disabled={sendingId !== null || notReady}
                className={`flex flex-col items-center gap-1 rounded-2xl border p-3 transition-all active:scale-95 disabled:opacity-60 ${
                  canAfford
                    ? "border-border bg-background hover:border-pink-400"
                    : "border-border bg-background opacity-70"
                }`}
              >
                {sendingId === gift.id ? (
                  <Loader2 className="h-7 w-7 animate-spin text-pink-500" />
                ) : (
                  <span className="text-[28px] leading-none">{gift.emoji}</span>
                )}
                <span className="text-[12px] font-bold">{gift.label}</span>
                <span
                  className={`text-[11px] font-bold tabular-nums ${
                    canAfford ? "text-pink-500" : "text-muted-foreground"
                  }`}
                >
                  {formatGiftCents(cost)}
                </span>
              </button>
            );
          })}
          {catalog.length === 0 && !loading && (
            <p className="col-span-3 py-6 text-center text-[12.5px] text-muted-foreground">
              Couldn't load the gift catalog — try again in a moment.
            </p>
          )}
        </div>

        <p className="mt-3 text-center text-[10.5px] leading-relaxed text-muted-foreground">
          Everyone in the room sees your gift · hosts keep 70% · credits never
          expire
        </p>
      </div>
    </div>
  );
}
