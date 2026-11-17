import { memo, useEffect, useMemo, useState } from "react";
import { Link, useLocation } from "react-router-dom";
import {
  BadgeDollarSign,
  BarChart3,
  BookOpen,
  Building2,
  CalendarCheck,
  CalendarDays,
  ClipboardList,
  ExternalLink,
  Handshake,
  Inbox,
  LayoutGrid,
  ListChecks,
  LogOut,
  Megaphone,
  Menu,
  NotebookPen,
  QrCode,
  Send,
  Sparkles,
  SquareKanban,
  Users,
  Video,
  X,
} from "lucide-react";

import { BusinessPlusMark } from "@/components/BusinessPlusMark";
import { useAuth } from "@/hooks/useAuth";
import { Avatar } from "@/components/Avatar";
import { WhisperLogo } from "@/components/WhisperLogo";
import { PORTAL_META, openMeet, type Portal } from "@/lib/portal";

/**
 * Chrome for the standalone subdomain portals — a full-page professional
 * dashboard: a fixed, CATEGORIZED tool sidebar on desktop (grouped tools,
 * one-line hints, the active tool marked with a clean accent ring), a
 * slim top bar + slide-in drawer on mobile. Deliberately NO feed
 * navigation: the portals are business tools, not the social app.
 */

interface PortalNavItem {
  id: string;
  label: string;
  hint: string;
  icon: typeof LayoutGrid;
  /** Dashboard tab driven by ?tab= on "/" (all portal homes). */
  tab?: string;
  /** Dedicated route inside the portal. */
  path?: string;
  /** Anchor scrolled to on arrival (combines with path). */
  anchor?: string;
  /** Opens Whisper Meet (meet. subdomain, ?portal=meet fallback). */
  meet?: boolean;
}

interface PortalNavGroup {
  label: string;
  items: PortalNavItem[];
}

const PORTAL_NAV: Record<Portal, PortalNavGroup[]> = {
  business: [
    {
      label: "Home",
      items: [
        {
          id: "overview",
          label: "Overview",
          hint: "Setup, KPIs & quick jumps",
          icon: LayoutGrid,
          tab: "overview",
        },
      ],
    },
    {
      label: "Advertising",
      items: [
        {
          id: "ads",
          label: "Ads Manager",
          hint: "Create, launch & pace ads",
          icon: Megaphone,
          tab: "ads",
        },
        {
          id: "analytics",
          label: "Analytics",
          hint: "Impressions, clicks & CTR",
          icon: BarChart3,
          tab: "analytics",
        },
        {
          id: "library",
          label: "Ad Library",
          hint: "Every live ad — public",
          icon: BookOpen,
          path: "/ad-library",
        },
      ],
    },
    {
      label: "Brand HQ",
      items: [
        { id: "marketplace", label: "Sponsorships", hint: "Applications, agreements & escrow", icon: Handshake, tab: "marketplace" },
        { id: "listing", label: "Marketplace listing", hint: "Showcase, requirements & typical pay", icon: Building2, path: "/brand/signup" },
        {
          id: "profile",
          label: "Business profile",
          hint: "The identity on your ads",
          icon: Building2,
          tab: "profile",
        },
        {
          id: "deals",
          label: "Manual pipeline",
          hint: "Your leads, next steps and notes",
          icon: Handshake,
          tab: "deals",
        },
      ],
    },
    {
      label: "Business+",
      items: [
        {
          id: "plus",
          label: "Business+",
          hint: "Team roles, hiring, HQ & calendar",
          icon: BusinessPlusMark,
          tab: "plus",
        },
      ],
    },
  ],
  coach: [
    {
      label: "Studio",
      items: [
        {
          id: "home",
          label: "Studio home",
          hint: "Overview, requests & stats",
          icon: LayoutGrid,
          tab: "home",
        },
      ],
    },
    {
      label: "Coaching",
      items: [
        {
          id: "clients",
          label: "Clients",
          hint: "Roster & live dashboards",
          icon: Users,
          tab: "clients",
        },
        {
          id: "programs",
          label: "Programs studio",
          hint: "Jasper programs & diet",
          icon: Sparkles,
          tab: "programs",
        },
      ],
    },
    {
      label: "Selling",
      items: [
        {
          id: "selling",
          label: "Drafts & selling",
          hint: "Build & sell in DMs",
          icon: Send,
          tab: "selling",
        },
        {
          id: "plans",
          label: "Plans & pricing",
          hint: "Tiers clients subscribe to",
          icon: ListChecks,
          path: "/coach/earnings",
          anchor: "plans",
        },
      ],
    },
    {
      label: "Money",
      items: [
        {
          id: "earnings",
          label: "Earnings & payouts",
          hint: "Income, bank & cash out",
          icon: BadgeDollarSign,
          path: "/coach/earnings",
        },
      ],
    },
  ],
  // Recruiting OS v4 — the researched talent-CRM shape: a due-today work
  // queue, a drag-and-drop pipeline, the people list, the inbox that feeds
  // it, insights, and growth tools — each its own view.
  recruiter: [
    {
      label: "Work",
      items: [
        {
          id: "today",
          label: "Today",
          hint: "Follow-ups due & overdue",
          icon: CalendarCheck,
          tab: "today",
        },
        {
          id: "pipeline",
          label: "Pipeline",
          hint: "Drag people stage to stage",
          icon: SquareKanban,
          tab: "pipeline",
        },
        {
          id: "people",
          label: "People",
          hint: "Everyone, searchable",
          icon: Users,
          tab: "people",
        },
        {
          id: "inbox",
          label: "Inbox",
          hint: "Applications & meeting asks",
          icon: Inbox,
          tab: "inbox",
        },
      ],
    },
    {
      label: "Grow",
      items: [
        {
          id: "insights",
          label: "Insights",
          hint: "Sources, speed & funnel",
          icon: BarChart3,
          tab: "insights",
        },
        {
          id: "grow",
          label: "Grow your bench",
          hint: "Invite link, QR & territories",
          icon: QrCode,
          tab: "grow",
        },
      ],
    },
  ],
  // Workspace — every tool behind one desk. Studios live on the hub page
  // (role-gated there); the sidebar keeps the universal tools.
  workspace: [
    {
      label: "Your desk",
      items: [
        {
          id: "home",
          label: "Workspace home",
          hint: "All your tools, one place",
          icon: LayoutGrid,
          tab: "home",
        },
        { id: 'work', label: 'Work desk', hint: 'Decisions, deliveries & approvals', icon: LayoutGrid, path: '/work' },
        { id: 'teams', label: 'Teams', hint: 'Set up, add people & manage roles', icon: Users, path: '/teams' },
        {
          id: "notebook",
          label: "Meeting library",
          hint: "Folders, notes, recordings & Jasper",
          icon: NotebookPen,
          path: "/notebook",
        },
        {
          id: "calendar",
          label: "Calendar",
          hint: "Events, RSVPs & planning",
          icon: CalendarDays,
          path: "/calendar",
        },
      ],
    },
    {
      label: "Meetings",
      items: [
        {
          id: "meet",
          label: "Whisper Meet",
          hint: "Start, join or schedule",
          icon: Video,
          path: "/meetings",
        },
      ],
    },
  ],
};

/**
 * Portal mode entered via ?portal= (preview or pre-DNS production) must
 * keep the flag on every link so a hard refresh stays in the portal.
 */
const KEEP_PORTAL_PARAM: boolean =
  typeof window !== "undefined" &&
  !/^(business|coaches|recruiters|workspace)\./.test(
    window.location.hostname.toLowerCase()
  );

function itemTarget(portal: Portal, item: PortalNavItem): string {
  const params = new URLSearchParams();
  if (KEEP_PORTAL_PARAM) params.set("portal", portal);
  if (item.path) {
    const q = params.toString();
    return `${item.path}${q ? `?${q}` : ""}${item.anchor ? `#${item.anchor}` : ""}`;
  }
  if (item.tab) params.set("tab", item.tab);
  const q = params.toString();
  return `/${q ? `?${q}` : ""}${item.anchor ? `#${item.anchor}` : ""}`;
}

function PortalShellBase({
  portal,
  children,
}: {
  portal: Portal;
  children: React.ReactNode;
}) {
  const { profile, signOut } = useAuth();
  const meta = PORTAL_META[portal];
  const groups = PORTAL_NAV[portal];
  const location = useLocation();
  const [menuOpen, setMenuOpen] = useState<boolean>(false);

  const currentTab = useMemo(
    () => new URLSearchParams(location.search).get("tab"),
    [location.search]
  );

  const { defaultTab, tabIds } = useMemo(() => {
    const ids: string[] = [];
    let first: string | undefined;
    for (const group of groups) {
      for (const item of group.items) {
        if (item.tab) {
          ids.push(item.tab);
          if (!first) first = item.tab;
        }
      }
    }
    return { defaultTab: first, tabIds: ids };
  }, [groups]);

  const isActive = (item: PortalNavItem): boolean => {
    if (item.path) {
      if (!location.pathname.startsWith(item.path)) return false;
      return item.anchor
        ? location.hash === `#${item.anchor}`
        : !location.hash;
    }
    if (location.pathname !== "/") return false;
    // Anchor-only items (the recruiter flow steps) light on hash match.
    if (!item.tab && item.anchor) return location.hash === `#${item.anchor}`;
    const current =
      currentTab && tabIds.includes(currentTab) ? currentTab : defaultTab;
    return item.tab === current && !location.hash;
  };

  // Smooth-scroll to dashboard anchors (e.g. Plans & pricing on earnings).
  useEffect(() => {
    if (!location.hash) return;
    const id = location.hash.slice(1);
    const timer = window.setTimeout(() => {
      document
        .getElementById(id)
        ?.scrollIntoView({ behavior: "smooth", block: "start" });
    }, 90);
    return () => window.clearTimeout(timer);
  }, [location.hash, location.key]);

  useEffect(() => {
    setMenuOpen(false);
  }, [location.pathname, location.search, location.hash]);

  const brandBlock = (
    <div className="relative border-b border-border/60 px-5 pb-5 pt-6">
      <div className="flex items-center gap-2.5">
        <WhisperLogo size={26} variant="script" />
        <span
          className="rounded-full px-2.5 py-1 text-[10px] font-black uppercase tracking-[0.14em]"
          style={{ color: meta.accent, backgroundColor: `${meta.accent}1f` }}
        >
          {meta.name}
        </span>
      </div>
      <p className="mt-2.5 text-[11.5px] leading-snug text-muted-foreground">
        {meta.tagline}
      </p>
    </div>
  );

  const navList = (
    <nav className="relative flex-1 overflow-y-auto px-3 pb-4 pt-1">
      {groups.map((group) => (
        <div key={group.label}>
          <p className="px-2.5 pb-1.5 pt-4 text-[10px] font-black uppercase tracking-[0.18em] text-muted-foreground/60">
            {group.label}
          </p>
          <div className="space-y-1">
            {group.items.map((item) => {
              const active = isActive(item);
              // The Workspace is a launcher: every tool opens in its own tab
              // (the desk itself stays in this one).
              const launchesTab = portal === "workspace" && !item.tab;
              if (item.meet) {
                return (
                  <button
                    key={item.id}
                    onClick={() => void openMeet({ newTab: launchesTab })}
                    className="group relative flex w-full items-center gap-3 rounded-2xl px-2.5 py-2 text-left transition-all hover:bg-secondary/60"
                  >
                    <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-secondary/70 text-muted-foreground transition-colors group-hover:text-foreground">
                      <item.icon className="h-[17px] w-[17px]" />
                    </span>
                    <span className="min-w-0">
                      <span className="block truncate text-[13.5px] font-semibold text-foreground/75">
                        {item.label}
                      </span>
                      <span className="block truncate text-[10.5px] text-muted-foreground">
                        {item.hint}
                      </span>
                    </span>
                  </button>
                );
              }
              return (
                <Link
                  key={item.id}
                  to={itemTarget(portal, item)}
                  target={launchesTab && !active ? "_blank" : undefined}
                  rel={launchesTab && !active ? "noopener noreferrer" : undefined}
                  className={`group relative flex items-center gap-3 rounded-2xl px-2.5 py-2 transition-all ${
                    active ? "bg-card shadow-sm" : "hover:bg-secondary/60"
                  }`}
                  style={
                    active
                      ? { boxShadow: `inset 0 0 0 1.5px ${meta.accent}55` }
                      : undefined
                  }
                >
                  <span
                    className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-xl transition-colors ${
                      active
                        ? ""
                        : "bg-secondary/70 text-muted-foreground group-hover:text-foreground"
                    }`}
                    style={
                      active
                        ? {
                            background: `linear-gradient(135deg, ${meta.accent}, ${meta.accent}c9)`,
                            color: "#fff",
                            boxShadow: `0 6px 14px ${meta.accent}55`,
                          }
                        : undefined
                    }
                  >
                    <item.icon className="h-[17px] w-[17px]" />
                  </span>
                  <span className="min-w-0">
                    <span
                      className={`block truncate text-[13.5px] ${
                        active
                          ? "font-extrabold"
                          : "font-semibold text-foreground/75"
                      }`}
                    >
                      {item.label}
                    </span>
                    <span className="block truncate text-[10.5px] text-muted-foreground">
                      {item.hint}
                    </span>
                  </span>
                </Link>
              );
            })}
          </div>
        </div>
      ))}
    </nav>
  );

  const footer = (
    <div className="relative space-y-2 border-t border-border/60 p-3">
      {profile && (
        <div className="flex items-center gap-2.5 rounded-2xl border border-border/60 bg-background/60 p-2.5">
          <Avatar
            url={profile.profile_image_url}
            name={profile.username ?? profile.display_name}
            size={32}
          />
          <span className="min-w-0 flex-1">
            <span className="block truncate text-[12.5px] font-bold">
              @{profile.username}
            </span>
            <span
              className="block text-[9.5px] font-black uppercase tracking-[0.12em]"
              style={{ color: meta.accent }}
            >
              {meta.name} portal
            </span>
          </span>
          <button
            onClick={() => void signOut()}
            aria-label="Sign out"
            title="Sign out"
            className="flex h-8 w-8 items-center justify-center rounded-lg text-muted-foreground transition-colors hover:text-foreground"
          >
            <LogOut className="h-4 w-4" />
          </button>
        </div>
      )}
      <a
        href="https://mydailywhisper.com"
        target="_blank"
        rel="noreferrer"
        className="flex h-10 items-center justify-center gap-1.5 rounded-xl border border-border/60 text-[12px] font-bold text-muted-foreground transition-colors hover:text-foreground"
      >
        Open the app
        <ExternalLink className="h-3 w-3" />
      </a>
    </div>
  );

  /** Soft accent aurora washing the top of the sidebar / drawer. */
  const aurora = (
    <div
      aria-hidden
      className="pointer-events-none absolute inset-x-0 top-0 h-48"
      style={{
        background: `radial-gradient(130% 100% at 50% 0%, ${meta.accent}1e, transparent 72%)`,
      }}
    />
  );

  return (
    <div className="min-h-screen bg-background">
      {/* Desktop — fixed categorized tool sidebar. */}
      <aside className="fixed inset-y-0 left-0 z-40 hidden w-[288px] flex-col overflow-hidden border-r border-border/60 bg-card/60 backdrop-blur-xl lg:flex">
        {aurora}
        {brandBlock}
        {navList}
        {footer}
      </aside>

      {/* Mobile — slim top bar + drawer. */}
      <header className="sticky top-0 z-40 border-b border-border/60 bg-background/85 backdrop-blur-xl lg:hidden">
        <div className="flex h-14 items-center justify-between gap-3 px-4">
          <div className="flex min-w-0 items-center gap-2.5">
            <WhisperLogo size={24} variant="script" />
            <span
              className="rounded-full px-2.5 py-1 text-[10px] font-black uppercase tracking-[0.14em]"
              style={{
                color: meta.accent,
                backgroundColor: `${meta.accent}1f`,
              }}
            >
              {meta.name}
            </span>
          </div>
          <button
            onClick={() => setMenuOpen(true)}
            aria-label="Open menu"
            className="flex h-9 w-9 items-center justify-center rounded-full border border-border/60 text-muted-foreground transition-colors hover:text-foreground"
          >
            <Menu className="h-[18px] w-[18px]" />
          </button>
        </div>
      </header>

      {menuOpen && (
        <div className="fixed inset-0 z-50 lg:hidden">
          <button
            aria-label="Close menu"
            onClick={() => setMenuOpen(false)}
            className="absolute inset-0 bg-black/45 backdrop-blur-[2px]"
          />
          <div className="absolute inset-y-0 left-0 flex w-[300px] max-w-[86vw] flex-col overflow-hidden border-r border-border/60 bg-card shadow-2xl">
            {aurora}
            <div className="relative flex items-center justify-between pr-3">
              <div className="flex-1">{brandBlock}</div>
              <button
                onClick={() => setMenuOpen(false)}
                aria-label="Close menu"
                className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-secondary text-muted-foreground"
              >
                <X className="h-4 w-4" />
              </button>
            </div>
            {navList}
            {footer}
          </div>
        </div>
      )}

      <main className="lg:pl-[288px]">{children}</main>
    </div>
  );
}

export const PortalShell = memo(PortalShellBase);
