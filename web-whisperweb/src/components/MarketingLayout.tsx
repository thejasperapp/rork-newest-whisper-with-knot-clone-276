import { createContext, useContext, useEffect, useState, type ReactNode } from "react";
import { Link, useLocation } from "react-router-dom";
import { ArrowRight, ArrowUpRight, Menu, Moon, Sun, X } from "lucide-react";
import { useAuth } from "@/hooks/useAuth";
import { Splash } from "@/components/Splash";
import "@/pages/welcome-marketing.css";
import "@/pages/public-marketing.css";

const MarketingContext = createContext(false);
export const useMarketingLayout = () => useContext(MarketingContext);
const ART = "/marketing-20261029/";
let marketingAppearance: "light" | "dark" | undefined;

export function MarketingBrand() {
  return <span className="wm-brand"><span className="wm-mark"><img className="wm-light-art" src={`${ART}workspace-w-light-20260925.webp`} width={600} height={304} alt="" /><img className="wm-dark-art" src={`${ART}workspace-w-dark-20260925.webp`} width={600} height={304} alt="" /></span><span>whisper</span></span>;
}

const EXPLORE = [
  ["/welcome#experience", "The experience"], ["/for-creators", "Creator Studio"],
  ["/welcome#knot", "Knot"], ["/recruiters", "Recruiters"], ["/about", "Our story"],
];
const FOOTER = [
  { title: "MAKE IT YOURS", links: [["/welcome#connections", "Messages & communities"], ["/welcome#creativity", "Waves & stories"], ["/for-creators", "Creator Studio"], ["/welcome#knot", "Meet Knot"]] },
  { title: "GO A LITTLE FURTHER", links: [["/creators", "Creators"], ["/coaches", "Coaches"], ["/recruiters", "Recruiters"], ["/monetization", "Earning on Whisper"], ["/one", "Whisper One"]] },
  { title: "WHISPER, TOGETHER", links: [["/about", "Our story"], ["/team", "Our team"], ["/articles", "Articles"], ["/support", "Support"], ["/safety", "Safety"], ["/faq", "FAQs"], ["/policies", "Policies"]] },
];

/** Only selected public routes opt in. Never mutates document or member theme. */
export function MarketingLayout({ children, homepage = false, preserveMember = false }: { children: ReactNode; homepage?: boolean; preserveMember?: boolean }) {
  const { session, profile, loading } = useAuth();
  const location = useLocation();
  const [open, setOpen] = useState(false);
  const [appearance, setAppearance] = useState<"light" | "dark">(() => marketingAppearance ?? (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"));
  useEffect(() => { setOpen(false); }, [location.pathname, location.hash]);
  useEffect(() => {
    if (!open) return;
    const escape = (event: KeyboardEvent) => { if (event.key === "Escape") { setOpen(false); document.getElementById("wm-menu-toggle")?.focus(); } };
    window.addEventListener("keydown", escape);
    return () => window.removeEventListener("keydown", escape);
  }, [open]);
  useEffect(() => {
    if (!location.hash) return;
    const timer = window.setTimeout(() => document.getElementById(decodeURIComponent(location.hash.slice(1)))?.scrollIntoView({ block: "start" }), 100);
    return () => window.clearTimeout(timer);
  }, [location.pathname, location.hash]);
  if (preserveMember && loading) return <Splash />;
  if (preserveMember && session && profile?.username) return <>{children}</>;
  const links = EXPLORE.map(([to, label]) => <Link key={to} to={to} onClick={() => setOpen(false)} aria-current={location.pathname === to ? "page" : undefined}>{label}</Link>);
  return <MarketingContext.Provider value={true}><div className="whisper-marketing" data-appearance={appearance} id="wm-top">
    <a className="wm-skip" href="#wm-content">Skip to content</a>
    <header className="wm-header"><div className="wm-container wm-header-inner">
      <Link to="/welcome" aria-label="Whisper home"><MarketingBrand /></Link>
      <nav className="wm-desktop-nav" aria-label="Whisper navigation">{links}</nav>
      <div className="wm-header-actions"><button className="wm-icon-button" aria-label={`Use ${appearance === "light" ? "dark" : "light"} appearance`} onClick={() => { const next = appearance === "light" ? "dark" : "light"; marketingAppearance = next; setAppearance(next); }}>{appearance === "light" ? <Moon size={18} /> : <Sun size={18} />}</button>
        {session ? <Link to="/" className="wm-button wm-header-join">Open Whisper <ArrowRight size={14} /></Link> : <><Link to="/auth" className="wm-sign-in">Sign in</Link><Link to="/auth?mode=signup" className="wm-button wm-header-join">Join Whisper <ArrowUpRight size={14} /></Link></>}
        <button id="wm-menu-toggle" className="wm-icon-button wm-menu-button" aria-label={open ? "Close navigation" : "Open navigation"} aria-expanded={open} aria-controls="wm-mobile-nav" onClick={() => setOpen(!open)}>{open ? <X size={22} /> : <Menu size={22} />}</button>
      </div></div>{open && <nav id="wm-mobile-nav" className="wm-mobile-nav" aria-label="Mobile navigation">{links}<Link to={session ? "/" : "/auth?mode=signup"}>{session ? "Open Whisper" : "Join Whisper"} <ArrowUpRight size={15} /></Link></nav>}
    </header>
    <div id="wm-content" tabIndex={-1} className={homepage ? "wm-home-content" : "wm-public-content"}>{children}</div>
    <footer className="wm-footer wm-container"><div className="wm-footer-top"><div><Link to="/welcome" aria-label="Whisper home"><MarketingBrand /></Link><p>Small hellos. Real connections.</p><span className="wm-footer-note">A little more you.<br />A little closer to your people.</span></div>{FOOTER.map(group => <nav key={group.title} aria-label={group.title}><span className="wm-eyebrow">{group.title}</span>{group.links.map(([to, label]) => <Link to={to} key={to}>{label}</Link>)}</nav>)}</div><div className="wm-footer-bottom"><p>© {new Date().getFullYear()} Whisper. Make yourself at home.</p><div><Link to="/privacy">Privacy</Link><Link to="/terms">Terms</Link><a href="#wm-top">Back to top ↑</a></div></div></footer>
  </div></MarketingContext.Provider>;
}
