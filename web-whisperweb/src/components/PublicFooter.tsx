import { Link } from "react-router-dom";
import { useMarketingLayout } from "./MarketingLayout";

import { WhisperLogo } from "./WhisperLogo";

const FOOTER_LINKS: { to: string; label: string }[] = [
  { to: "/team", label: "Our Team" },
  { to: "/for-creators", label: "For Creators" },
  { to: "/articles", label: "Articles" },
  { to: "/one", label: "Whisper One" },
  { to: "/monetization", label: "Monetization" },
  { to: "/about", label: "About" },
  { to: "/safety", label: "Safety" },
  { to: "/support", label: "Support" },
  { to: "/terms", label: "Terms" },
  { to: "/privacy", label: "Privacy" },
  { to: "/auth", label: "Sign in" },
];

/** Shared marketing footer so every public page carries the same links. */
export default function PublicFooter() {
  const marketingLayout = useMarketingLayout();
  if (marketingLayout) return null;
  return (
    <footer className="border-t border-border px-4 py-10 sm:px-6 lg:px-8">
      <div className="mx-auto flex max-w-6xl flex-col items-center justify-between gap-5 lg:flex-row">
        <div className="flex items-center gap-2">
          <WhisperLogo size={22} />
          <span className="text-[14px] font-semibold">Whisper</span>
        </div>
        <nav className="flex flex-wrap items-center justify-center gap-x-5 gap-y-2 text-[14px] text-muted-foreground">
          {FOOTER_LINKS.map((link) => (
            <Link key={link.to} to={link.to} className="hover:text-foreground">
              {link.label}
            </Link>
          ))}
        </nav>
        <p className="text-[13px] text-muted-foreground">
          © {new Date().getFullYear()} Whisper. All rights reserved.
        </p>
      </div>
    </footer>
  );
}
