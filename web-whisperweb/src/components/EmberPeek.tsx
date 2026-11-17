import { memo } from "react";

/**
 * Little Ember mascot that peeks up over the top edge of a composer — the web
 * port of the iOS `WhisperEmberPeek`. Mounted (with an entrance animation) only
 * while the draft is an `/ember …` command. It hangs from the top-right as a
 * sibling *behind* the composer card (which paints over it via `z-10`), so the
 * input bar covers his lower half and only his head peeks above — like iOS.
 */
function EmberPeekBase() {
  return (
    <div className="pointer-events-none absolute -top-9 right-6 z-0 animate-peek-in">
      <img
        src="/ember-mascot.png"
        alt=""
        width={52}
        height={52}
        draggable={false}
        className="ember-peek select-none object-contain"
        style={{ width: 52, height: 52 }}
      />
    </div>
  );
}

export const EmberPeek = memo(EmberPeekBase);
