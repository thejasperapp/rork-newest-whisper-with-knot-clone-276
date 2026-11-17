/**
 * Portal mode — standalone, full-page dashboards served from dedicated
 * subdomains, completely detached from the social feed:
 *
 *   business.mydailywhisper.com   → Business Suite
 *   coaches.mydailywhisper.com    → Coach Studio
 *   recruiters.mydailywhisper.com → Recruiter hub
 *   workspace.mydailywhisper.com  → Workspace (every tool, one desk)
 *
 * Same accounts, same data — a different front door with its own chrome
 * (no feed tabs, no social routes). The main domain keeps its in-app
 * /business, /coach and /recruiter pages untouched.
 *
 * For local/preview testing, append ?portal=business|coach|recruiter|
 * workspace to any URL — the flag holds until the next full page load.
 */

export type Portal = "business" | "coach" | "recruiter" | "workspace";

export interface PortalMeta {
  /** Chip label next to the wordmark. */
  name: string;
  /** One-liner shown in the top bar on wider screens. */
  tagline: string;
  /** Accent for the portal chip. */
  accent: string;
}

export const PORTAL_META: Record<Portal, PortalMeta> = {
  business: {
    name: "Business",
    tagline: "Ads, deals & analytics",
    accent: "#5A5FE8",
  },
  coach: {
    name: "Coaches",
    tagline: "Clients, plans & earnings",
    accent: "#E8853D",
  },
  recruiter: {
    name: "Recruiting",
    tagline: "Scouting & talent pipeline",
    accent: "#7059E8",
  },
  workspace: {
    name: "Workspace",
    tagline: "Meetings, notebook & studios",
    accent: "#0E9F76",
  },
};

/** Subdomain that fronts each portal on the production domain. */
export const PORTAL_SUBDOMAIN: Record<Portal, string> = {
  business: "business",
  coach: "coaches",
  recruiter: "recruiters",
  workspace: "workspace",
};

function portalParamUrl(portal: Portal): string {
  return `${window.location.origin}/?portal=${portal}`;
}

export interface OpenDoorOptions {
  /** Open in a NEW browser tab (Workspace doors always do). */
  newTab?: boolean;
}

/**
 * A navigator that can target a new tab WITHOUT tripping popup blockers:
 * the tab is opened synchronously inside the click, and the real URL is
 * assigned once the (async) subdomain probe settles. When the browser
 * refuses the tab, it falls back to navigating this one.
 */
function beginNavigation(newTab: boolean): (url: string) => void {
  if (!newTab) return (url) => window.location.assign(url);
  const tab = window.open("", "_blank");
  if (!tab) return (url) => window.location.assign(url);
  try {
    tab.opener = null;
  } catch {
    /* cross-origin opener already severed */
  }
  return (url) => {
    try {
      tab.location.href = url;
    } catch {
      window.location.assign(url);
    }
  };
}

/**
 * Send the user to a portal's full-page dashboard. On the production
 * domain the dedicated subdomain is preferred (business./coaches./
 * recruiters.mydailywhisper.com); if its DNS isn't configured yet the
 * same full-page portal opens on the current origin via ?portal=.
 * Preview hosts always use the origin flag.
 */
export async function openPortal(portal: Portal, options: OpenDoorOptions = {}): Promise<void> {
  if (typeof window === "undefined") return;
  const go = beginNavigation(options.newTab === true);
  const host = window.location.hostname.toLowerCase();
  const onProdDomain =
    host === "mydailywhisper.com" || host.endsWith(".mydailywhisper.com");
  if (!onProdDomain) {
    go(portalParamUrl(portal));
    return;
  }
  const subdomainUrl = `https://${PORTAL_SUBDOMAIN[portal]}.mydailywhisper.com/`;
  try {
    const controller = new AbortController();
    const timer = window.setTimeout(() => controller.abort(), 1_500);
    // no-cors probe — resolves (opaque) when the subdomain serves, throws
    // when its DNS isn't set up yet, so the button never dead-ends.
    await fetch(`${subdomainUrl}favicon.ico`, {
      mode: "no-cors",
      signal: controller.signal,
    });
    window.clearTimeout(timer);
    go(subdomainUrl);
  } catch {
    go(portalParamUrl(portal));
  }
}

function detectPortal(): Portal | null {
  if (typeof window === "undefined") return null;
  const param = new URLSearchParams(window.location.search).get("portal");
  if (
    param === "business" ||
    param === "coach" ||
    param === "recruiter" ||
    param === "workspace"
  ) {
    return param;
  }
  const host = window.location.hostname.toLowerCase();
  if (host.startsWith("business.")) return "business";
  // Vanity doors for the suite's two wings — ads.… lands on the Ads
  // Manager, brands.… lands on Brand HQ (BusinessSuite reads the host).
  if (host.startsWith("ads.") || host.startsWith("brands.")) return "business";
  if (host.startsWith("coaches.")) return "coach";
  if (host.startsWith("recruiters.")) return "recruiter";
  if (host.startsWith("workspace.")) return "workspace";
  return null;
}

/** Resolved once at load — the portal can't change mid-session. */
export const ACTIVE_PORTAL: Portal | null = detectPortal();

/**
 * Whisper Meet — meet.mydailywhisper.com (or ?portal=meet for preview):
 * a Google-Meet-style front door — start a meeting or join by link/code.
 * Deliberately separate from the Portal type; it has its own chrome.
 */
export const MEET_PORTAL: boolean = (() => {
  if (typeof window === "undefined") return false;
  if (new URLSearchParams(window.location.search).get("portal") === "meet") {
    return true;
  }
  return window.location.hostname.toLowerCase().startsWith("meet.");
})();

/**
 * Open Whisper Meet — the real front door for meetings. On production the
 * dedicated meet. subdomain is preferred; when its DNS isn't live yet (or
 * on preview hosts) the same experience opens via ?portal=meet.
 */
export async function openMeet(options: OpenDoorOptions = {}): Promise<void> {
  if (typeof window === "undefined") return;
  const go = beginNavigation(options.newTab === true);
  const fallback = `${window.location.origin}/?portal=meet`;
  const host = window.location.hostname.toLowerCase();
  const onProdDomain =
    host === "mydailywhisper.com" || host.endsWith(".mydailywhisper.com");
  if (!onProdDomain) {
    go(fallback);
    return;
  }
  const meetUrl = "https://meet.mydailywhisper.com/";
  try {
    const controller = new AbortController();
    const timer = window.setTimeout(() => controller.abort(), 1_500);
    await fetch(`${meetUrl}favicon.ico`, {
      mode: "no-cors",
      signal: controller.signal,
    });
    window.clearTimeout(timer);
    go(meetUrl);
  } catch {
    go(fallback);
  }
}
