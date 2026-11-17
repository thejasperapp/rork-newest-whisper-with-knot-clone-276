import { Link, useLocation } from "react-router-dom";
import { ChevronDown, Menu, Presentation, X } from "lucide-react";
import { useEffect, useRef, useState } from "react";

import { WhisperLogo } from "./WhisperLogo";
import { useMarketingLayout } from "./MarketingLayout";
import { Avatar } from "@/components/Avatar";
import { useAuth } from "@/hooks/useAuth";
import { useMyBadge } from "@/hooks/useMyBadge";
import { canOpenPitchMode } from "@/lib/pitch";
import { cn } from "@/lib/utils";

interface NavLinkProps {
  to: string;
  label: string;
}

const TEAM_LINKS: NavLinkProps[] = [
  { to: "/coaches", label: "Coaches" },
  { to: "/creators", label: "Creators" },
  { to: "/recruiters", label: "Recruiters" },
];

const NAV_LINKS: NavLinkProps[] = [
  { to: "/articles", label: "Articles" },
  { to: "/films", label: "Film Friday" },
  { to: "/one", label: "Whisper One" },
  { to: "/monetization", label: "Monetization" },
  { to: "/about", label: "About" },
];;

/**
 * Public marketing header — a single compact floating glass pill. The logo,
 * section links, and auth actions all live inside one capsule so nothing
 * floats disconnected over the page.
 */
export default function PublicNav() {
  const marketingLayout = useMarketingLayout();
  const location = useLocation();
  const { session, profile } = useAuth();
  const badge = useMyBadge();
  const canPitch = canOpenPitchMode(badge, !!profile?.is_recruiter);
  const [open, setOpen] = useState<boolean>(false);
  const [teamOpen, setTeamOpen] = useState<boolean>(false);
  const [scrolled, setScrolled] = useState<boolean>(false);
  const teamCloseTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const isActive = (path: string) => location.pathname === path;
  const teamActive =
    location.pathname === "/team" ||
    TEAM_LINKS.some((l) => location.pathname === l.to);
  const pitchActive = location.pathname.startsWith("/pitch");

  const openTeamMenu = (): void => {
    if (teamCloseTimer.current) clearTimeout(teamCloseTimer.current);
    setTeamOpen(true);
  };
  const scheduleTeamClose = (): void => {
    if (teamCloseTimer.current) clearTimeout(teamCloseTimer.current);
    teamCloseTimer.current = setTimeout(() => setTeamOpen(false), 150);
  };

  useEffect(() => {
    const onScroll = (): void => {
      setScrolled(window.scrollY > 12);
    };
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  useEffect(() => {
    setOpen(false);
    setTeamOpen(false);
  }, [location.pathname]);

  if (marketingLayout) return null;

  return (
    <header className="fixed inset-x-0 top-0 z-50 px-3 pt-3 sm:px-6 sm:pt-4">
      <div
        className={cn(
          "glass mx-auto flex h-[54px] max-w-4xl items-center rounded-full border pl-4 pr-2 transition-shadow duration-300",
          scrolled
            ? "border-border/70 shadow-[0_12px_40px_rgba(0,0,0,0.14)]"
            : "border-border/50 shadow-[0_6px_24px_rgba(0,0,0,0.08)]"
        )}
      >
        <Link
          to="/welcome"
          className="flex shrink-0 items-center"
          aria-label="Whisper website home"
        >
          <WhisperLogo size={24} />
        </Link>

        <span className="mx-3 hidden h-5 w-px bg-border md:block" />

        <nav className="hidden items-center gap-0.5 md:flex">
          {/* Our Team — link to /team with a hover submenu */}
          <div
            className="relative"
            onMouseEnter={openTeamMenu}
            onMouseLeave={scheduleTeamClose}
          >
            <Link
              to="/team"
              className={cn(
                "flex items-center gap-1 whitespace-nowrap rounded-full px-3 py-1.5 text-[13.5px] font-medium transition-colors",
                teamActive
                  ? "bg-secondary text-foreground"
                  : "text-muted-foreground hover:bg-secondary/60 hover:text-foreground"
              )}
            >
              Our Team
              <ChevronDown
                className={cn(
                  "h-3.5 w-3.5 transition-transform",
                  teamOpen && "rotate-180"
                )}
              />
            </Link>
            {teamOpen && (
              <div className="glass absolute left-0 top-full z-50 mt-2 w-44 rounded-[20px] border border-border/60 p-1.5 shadow-[0_18px_50px_rgba(0,0,0,0.16)]">
                <Link
                  to="/team"
                  className="block rounded-2xl px-3.5 py-2.5 text-[13.5px] font-semibold hover:bg-secondary/70"
                >
                  Meet the team
                </Link>
                <hr className="my-1 border-border/50" />
                {TEAM_LINKS.map((link) => (
                  <Link
                    key={link.to}
                    to={link.to}
                    className={cn(
                      "block rounded-2xl px-3.5 py-2.5 text-[13.5px] font-medium",
                      isActive(link.to)
                        ? "bg-secondary text-foreground"
                        : "text-muted-foreground hover:bg-secondary/70 hover:text-foreground"
                    )}
                  >
                    {link.label}
                  </Link>
                ))}
              </div>
            )}
          </div>

          {NAV_LINKS.map((link) => (
            <Link
              key={link.to}
              to={link.to}
              className={cn(
                "whitespace-nowrap rounded-full px-3 py-1.5 text-[13.5px] font-medium transition-colors",
                isActive(link.to)
                  ? "bg-secondary text-foreground"
                  : "text-muted-foreground hover:bg-secondary/60 hover:text-foreground"
              )}
            >
              {link.label}
            </Link>
          ))}
          {canPitch && (
            <Link
              to="/pitch"
              className={cn(
                "flex items-center gap-1.5 whitespace-nowrap rounded-full px-3 py-1.5 text-[13.5px] font-bold transition-colors",
                pitchActive
                  ? "bg-foreground text-background"
                  : "text-foreground hover:bg-secondary/60"
              )}
            >
              <Presentation className="h-3.5 w-3.5" />
              Pitch Mode
            </Link>
          )}
        </nav>

        <div className="ml-auto hidden items-center gap-1 md:flex">
          {session ? (
            <Link
              to="/"
              aria-label="Open Whisper"
              title={`@${profile?.username ?? "you"} — open Whisper`}
              className="rounded-full p-0.5 ring-2 ring-border transition-transform active:scale-95"
            >
              <Avatar
                url={profile?.profile_image_url}
                name={profile?.username ?? profile?.display_name}
                size={34}
              />
            </Link>
          ) : (
            <>
              <Link
                to="/auth"
                className="rounded-full px-3.5 py-2 text-[13.5px] font-medium text-muted-foreground transition-colors hover:text-foreground"
              >
                Sign in
              </Link>
              <Link
                to="/auth?mode=signup"
                className="rounded-full bg-primary px-4 py-2 text-[13.5px] font-semibold text-primary-foreground transition-transform active:scale-95"
              >
                Get started
              </Link>
            </>
          )}
        </div>

        {session && (
          <Link
            to="/"
            aria-label="Open Whisper"
            className="ml-auto mr-1.5 rounded-full p-0.5 ring-2 ring-border md:hidden"
          >
            <Avatar
              url={profile?.profile_image_url}
              name={profile?.username ?? profile?.display_name}
              size={30}
            />
          </Link>
        )}

        <button
          className={cn(
            "flex h-9 w-9 items-center justify-center rounded-full bg-secondary md:hidden",
            !session && "ml-auto"
          )}
          onClick={() => setOpen((o) => !o)}
          aria-label={open ? "Close menu" : "Open menu"}
        >
          {open ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
        </button>
      </div>

      {open && (
        <div className="glass mx-auto mt-2 max-w-4xl rounded-[24px] border border-border/60 p-2 shadow-[0_18px_50px_rgba(0,0,0,0.18)] md:hidden">
          <nav className="flex flex-col gap-1">
            <Link
              to="/team"
              onClick={() => setOpen(false)}
              className={cn(
                "rounded-2xl px-4 py-3 text-[15px] font-medium",
                isActive("/team")
                  ? "bg-secondary text-foreground"
                  : "text-muted-foreground hover:bg-secondary/60"
              )}
            >
              Our Team
            </Link>
            {TEAM_LINKS.map((link) => (
              <Link
                key={link.to}
                to={link.to}
                onClick={() => setOpen(false)}
                className={cn(
                  "ml-4 rounded-2xl px-4 py-2.5 text-[14px] font-medium",
                  isActive(link.to)
                    ? "bg-secondary text-foreground"
                    : "text-muted-foreground hover:bg-secondary/60"
                )}
              >
                {link.label}
              </Link>
            ))}
            {NAV_LINKS.map((link) => (
              <Link
                key={link.to}
                to={link.to}
                onClick={() => setOpen(false)}
                className={cn(
                  "rounded-2xl px-4 py-3 text-[15px] font-medium",
                  isActive(link.to)
                    ? "bg-secondary text-foreground"
                    : "text-muted-foreground hover:bg-secondary/60"
                )}
              >
                {link.label}
              </Link>
            ))}
            {canPitch && (
              <Link
                to="/pitch"
                onClick={() => setOpen(false)}
                className={cn(
                  "flex items-center gap-2 rounded-2xl px-4 py-3 text-[15px] font-bold",
                  pitchActive
                    ? "bg-foreground text-background"
                    : "text-foreground hover:bg-secondary/60"
                )}
              >
                <Presentation className="h-4 w-4" />
                Pitch Mode
              </Link>
            )}
            <hr className="my-1 border-border/60" />
            {session ? (
              <Link
                to="/"
                onClick={() => setOpen(false)}
                className="flex items-center gap-3 rounded-2xl bg-primary px-4 py-3 text-[15px] font-semibold text-primary-foreground"
              >
                <Avatar
                  url={profile?.profile_image_url}
                  name={profile?.username ?? profile?.display_name}
                  size={26}
                />
                Open Whisper
              </Link>
            ) : (
              <>
                <Link
                  to="/auth"
                  onClick={() => setOpen(false)}
                  className="rounded-2xl px-4 py-3 text-[15px] font-medium text-muted-foreground hover:bg-secondary/60"
                >
                  Sign in
                </Link>
                <Link
                  to="/auth?mode=signup"
                  onClick={() => setOpen(false)}
                  className="rounded-2xl bg-primary px-4 py-3 text-center text-[15px] font-semibold text-primary-foreground"
                >
                  Get started
                </Link>
              </>
            )}
          </nav>
        </div>
      )}
    </header>
  );
}
