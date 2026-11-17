import { memo } from "react";

/**
 * THE Jasper icon — the peach squircle with the dark ghost, served from
 * `/jasper-icon-v2.png`. This is the one mark used anywhere Jasper needs an
 * icon on web (settings rows, the Jasper nav item, the Intelligence header,
 * Jasper's chat avatar); iOS bundles the identical artwork.
 *
 * The art carries its own squircle and soft edge, so the element only sizes
 * it — no extra border radius bleed, no network-dependent fallback.
 */
export const JASPER_ICON_SRC = "/jasper-icon-v2.png";

function JasperAppIconBase({ size = 32, className }: { size?: number; className?: string }) {
  return (
    <img
      src={JASPER_ICON_SRC}
      alt=""
      aria-hidden
      width={size}
      height={size}
      draggable={false}
      className={className}
      style={{
        width: size,
        height: size,
        objectFit: "contain",
        flexShrink: 0,
        display: "inline-block",
      }}
    />
  );
}

export const JasperAppIcon = memo(JasperAppIconBase);
