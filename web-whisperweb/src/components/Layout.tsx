import { memo, useState, type SVGProps } from "react";
import "@/social.css";
import { NavLink, useNavigate, useLocation } from "react-router-dom";
import {
  User as UserIcon,
  Flame,
  LogOut,
  Pencil,
  Settings,
  Dumbbell,
  ChevronUp,
  Bell,
  BarChart3,
  PenSquare,
  Users,
  BriefcaseBusiness,
  LifeBuoy,
} from "lucide-react";

import { cn } from "@/lib/utils";
import { WhisperHome as Home, WhisperPlane as MessageCircle, WhisperSearch as Search } from "@/components/WhisperGlyph";
import { useAuth } from "@/hooks/useAuth";
import { useUnreadActivity } from "@/hooks/useUnreadActivity";
import { useMyBadge } from "@/hooks/useMyBadge";
import { Avatar } from "@/components/Avatar";
import { KnotMascot } from "@/components/Knot";
import { WhisperLogo } from "@/components/WhisperLogo";
import { CreateSelector } from "@/components/CreateSelector";
import { NewMessageDialog } from "@/components/NewMessageDialog";
import { RightRail } from "@/components/RightRail";
import { DecisionInboxNotice } from "@/components/DecisionInboxNotice";
import { ViewMoreList } from "@/components/ui/ViewMoreList";
import { communitiesForInterests } from "@/lib/communities";
import { openPortal, type Portal } from "@/lib/portal";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

/**
 * The custom WAVES mark — Whisper's short-video surface wears its own tab
 * button: a thick rounded squircle with a rounded play wedge, matching the
 * iOS tab glyph. Inherits currentColor so active states tint it like any
 * lucide icon.
 */
const WavesIcon = ((props: SVGProps<SVGSVGElement>) => (
  <svg
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth={2.4}
    strokeLinecap="round"
    strokeLinejoin="round"
    aria-hidden="true"
    {...props}
  >
    <rect x="3" y="3" width="18" height="18" rx="5.5" />
    <path d="M10 8.8 15.7 12 10 15.2Z" fill="currentColor" strokeWidth={1.7} />
  </svg>
)) as typeof Home;

interface NavItem {
  to: string;
  label: string;
  icon: typeof Home;
  /** When set, the entry opens the standalone full-page portal instead. */
  portal?: Portal;
}

const BASE_NAV: NavItem[] = [
  { to: "/", label: "Home", icon: Home },
  { to: "/reels", label: "Waves", icon: WavesIcon },
  { to: "/ember", label: "Knot", icon: Flame },
  { to: "/messages", label: "Messages", icon: MessageCircle },
  { to: "/notifications", label: "Activity", icon: Bell },
  { to: "/profile", label: "Profile", icon: UserIcon },
];

function LayoutBase({ children }: { children: React.ReactNode }) {
  const { profile, signOut } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [createOpen, setCreateOpen] = useState<boolean>(false);
  const [newMessage, setNewMessage] = useState<boolean>(false);
  const unreadActivity = useUnreadActivity();
  useMyBadge();

  const onMessages = location.pathname.startsWith("/messages");

  // Full-screen pages (Waves, the live studio, the live setup) position their
  // root `fixed inset-0`. The page-entrance wrapper below animates `transform`
  // with fill-mode both — and ANY non-none transform makes an element the
  // containing block for its fixed descendants. Inside it, a fixed root
  // resolves `inset-0` against a zero-height wrapper: the stage collapsed to
  // nothing and only the absolutely-positioned header spilled out (the blank
  // Waves page). These routes render their root without the wrapper.
  const immersive =
    location.pathname === "/reels" ||
    location.pathname.startsWith("/live/");

  const communities = communitiesForInterests(profile?.interests);

  const extraNav: NavItem[] = [];
  extraNav.push({ to: "/communities", label: "Communities", icon: Users });

  const NAV: NavItem[] =
    extraNav.length > 0
      ? [...BASE_NAV.slice(0, 3), ...extraNav, ...BASE_NAV.slice(3)]
      : BASE_NAV;

  // Mobile bottom bar — Search stays here since the right rail is hidden on
  // mobile. Workspace rides along too: phones have no left rail, and without
  // this door the entire work layer (meetings, notebook, calendar, studios)
  // was unreachable on mobile.
  const MOBILE_NAV: NavItem[] = [
    { to: "/", label: "Home", icon: Home },
    { to: "/search", label: "Search", icon: Search },
    { to: "/reels", label: "Waves", icon: WavesIcon },
    { to: "/workspace", label: "Workspace", icon: BriefcaseBusiness, portal: "workspace" },
    { to: "/messages", label: "Messages", icon: MessageCircle },
    { to: "/profile", label: "Profile", icon: UserIcon },
  ];

  const handleSignOut = async (): Promise<void> => {
    await signOut();
    navigate("/auth");
  };

  return (
    <div className="whisper-social min-h-screen bg-background">
      {/* Three-column desktop layout: left rail · feed · right rail.
          Both rails are rectangular boxed sidebars (not edge-attached) so
          everything is centered properly with the feed in the middle. */}
      <div className="mx-auto flex w-full max-w-[1280px] justify-center px-0 sm:px-4">
        {/* Left rail — boxed sidebar mirroring the right rail, sticky with
            internal overflow so it stays in view while the center feed scrolls. */}
        <aside className="sticky top-0 hidden h-[100dvh] max-h-[100dvh] w-[260px] shrink-0 flex-col gap-4 py-6 pr-6 lg:flex xl:flex">
          <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto pr-1">
            <div className="flex flex-col gap-4 social-rail-panel rounded-2xl border border-border/50 bg-background/60 p-4 backdrop-blur-sm">
              {/* Logo — classic looped-script W mark */}
              <NavLink
                to="/"
                aria-label="Home feed"
                className="flex h-10 items-center justify-center transition-transform active:scale-95"
              >
                <WhisperLogo size={28} />
              </NavLink>

              {/* Nav items — collapsed with "View more" if the list is long. */}
              <ViewMoreList
                items={NAV}
                maxVisible={7}
                itemClassName="flex flex-col gap-0.5"
                renderItem={(item) => {
                  const portalTarget = item.portal;
                  if (portalTarget) {
                    // Portal tools open their standalone full-page dashboard
                    // (coaches./recruiters. subdomain, ?portal= fallback).
                    return (
                      <button
                        key={item.to}
                        onClick={() => void openPortal(portalTarget)}
                        className="flex h-11 w-full items-center gap-3 rounded-xl px-3 text-left text-foreground/60 transition-colors hover:bg-secondary/50 hover:text-foreground"
                      >
                        <item.icon className="h-[22px] w-[22px] shrink-0" />
                        <span className="whitespace-nowrap text-[14.5px] font-medium">
                          {item.label}
                        </span>
                      </button>
                    );
                  }
                  return (
                  <NavLink
                    key={item.to}
                    to={item.to}
                    end={item.to === "/"}
                    className={({ isActive }) =>
                      cn(
                        "flex h-11 items-center gap-3 rounded-xl px-3 transition-colors",
                        isActive
                          ? "bg-secondary/80 text-foreground"
                          : "text-foreground/60 hover:bg-secondary/50 hover:text-foreground"
                      )
                    }
                  >
                    {({ isActive }) => (
                      <>
                        <span className="relative shrink-0">
                          {item.to === "/ember" ? (
                            <KnotMascot
                              size={22}
                              className={cn(
                                "transition-transform",
                                isActive ? "scale-110" : "opacity-90"
                              )}
                            />
                          ) : (
                            <item.icon
                              className={cn("h-[22px] w-[22px]", isActive && "stroke-[2.4]")}
                              fill={isActive && (item.to === "/messages" || item.to === "/") ? "currentColor" : "none"}
                            />
                          )}
                          {item.to === "/notifications" && unreadActivity > 0 && (
                            <span className="absolute -right-1.5 -top-1.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-primary px-1 text-[10px] font-bold text-primary-foreground">
                              {unreadActivity > 9 ? "9+" : unreadActivity}
                            </span>
                          )}
                        </span>
                        <span
                          className={cn(
                            "whitespace-nowrap text-[14.5px]",
                            isActive ? "font-bold" : "font-medium"
                          )}
                        >
                          {item.label}
                        </span>
                      </>
                    )}
                  </NavLink>
                  );
                }}
              />
            </div>

            {/* Workspace — ONE door to every work tool: meetings, the
                notebook, calendar, and all the studios live behind it on
                workspace.mydailywhisper.com (?portal=workspace fallback). */}
            <button
              onClick={() => void openPortal("workspace")}
              className="group flex w-full items-center gap-3 social-rail-panel rounded-2xl border border-border/50 bg-background/60 p-3.5 text-left backdrop-blur-sm transition-colors hover:bg-secondary/40"
            >
              <span
                className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl text-white shadow-sm transition-transform group-active:scale-95"
                style={{
                  background: "linear-gradient(135deg, #0E9F76, #0B8163)",
                }}
              >
                <BriefcaseBusiness className="h-5 w-5" />
              </span>
              <span className="min-w-0 flex-1">
                <span className="block text-[14px] font-bold">Workspace</span>
                <span className="block truncate text-[11.5px] text-muted-foreground">
                  Meetings, notebook & studios
                </span>
              </span>
            </button>

            {/* Communities box */}
            {communities.length > 0 && (
              <div className="social-rail-panel rounded-2xl border border-border/50 bg-background/60 p-4 backdrop-blur-sm">
                <p className="mb-2 text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
                  Your communities
                </p>
                <ViewMoreList
                  items={communities}
                  maxVisible={6}
                  itemClassName="flex flex-col gap-0.5"
                  renderItem={(c) => (
                    <button
                      key={c.id}
                      onClick={() => navigate(`/c/${c.id}`)}
                      title={c.name}
                      className="flex h-10 items-center gap-3 rounded-xl px-2 text-left transition-colors hover:bg-secondary/60"
                    >
                      <span
                        className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-white"
                        style={{
                          backgroundImage: `linear-gradient(135deg, ${c.gradient[0]}, ${c.gradient[1]})`,
                        }}
                      >
                        <c.icon className="h-3.5 w-3.5" />
                      </span>
                      <span className="truncate whitespace-nowrap text-[13.5px] font-medium text-foreground/85">
                        {c.name}
                      </span>
                    </button>
                  )}
                />
              </div>
            )}
          </div>

          {/* Profile button */}
          <DropdownMenu>
            <DropdownMenuTrigger className="flex items-center gap-3 social-rail-panel rounded-2xl border border-border/50 bg-background/60 p-3 outline-none backdrop-blur-sm transition-colors hover:bg-secondary/50">
              <Avatar
                url={profile?.profile_image_url}
                name={profile?.username ?? profile?.display_name}
                size={34}
              />
              <div className="min-w-0 flex-1 text-left">
                <p className="truncate text-sm font-semibold">
                  {profile?.display_name || profile?.username || "You"}
                </p>
                <p className="truncate text-xs text-muted-foreground">
                  @{profile?.username ?? "you"}
                </p>
              </div>
              <ChevronUp className="h-4 w-4 shrink-0 text-muted-foreground" />
            </DropdownMenuTrigger>
            <DropdownMenuContent side="top" align="start" className="w-52">
              <DropdownMenuLabel className="truncate">
                @{profile?.username ?? "you"}
              </DropdownMenuLabel>
              <DropdownMenuSeparator />
              <DropdownMenuItem onClick={() => navigate("/profile")}>
                <UserIcon className="mr-2 h-4 w-4" />
                View profile
              </DropdownMenuItem>
              <DropdownMenuItem onClick={() => void openPortal("workspace")}>
                <BriefcaseBusiness className="mr-2 h-4 w-4" />
                Workspace
              </DropdownMenuItem>
              {profile?.is_coach && (
                <DropdownMenuItem onClick={() => void openPortal("coach")}>
                  <Dumbbell className="mr-2 h-4 w-4" />
                  Coach Studio
                </DropdownMenuItem>
              )}
              <DropdownMenuItem onClick={() => navigate("/dashboard")}>
                <BarChart3 className="mr-2 h-4 w-4" />
                Dashboard
              </DropdownMenuItem>
              <DropdownMenuItem onClick={() => navigate("/settings")}>
                <Settings className="mr-2 h-4 w-4" />
                Settings
              </DropdownMenuItem>
              <DropdownMenuItem onClick={() => navigate("/faq")}>
                <LifeBuoy className="mr-2 h-4 w-4" />
                Help & FAQ
              </DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem
                onClick={handleSignOut}
                className="text-destructive focus:text-destructive"
              >
                <LogOut className="mr-2 h-4 w-4" />
                Log out
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </aside>

        {/* Centered main feed column — Jasper Intelligence goes immersive:
            full-bleed center stage on desktop, no right rail, its own
            composer pinned to the true viewport bottom. Films are cinema
            pages — they go wide inside the app chrome too. */}
        <main
          className={cn(
            "social-main min-w-0 w-full flex-1 px-0 sm:px-0",
            onMessages ? "pb-[76px] lg:pb-0 [&:has([aria-label='Conversation'])]:pb-0 [&:has([aria-label='Group_conversation'])]:pb-0" : "pb-20 lg:pb-0",
            location.pathname === "/ember"
              ? "max-w-none lg:pb-0"
              : location.pathname.startsWith("/films")
                ? "max-w-none lg:pb-10"
                : "max-w-[640px]"
          )}
        >
          {!immersive && !onMessages && <DecisionInboxNotice />}
          {immersive ? (
            <div key={location.pathname}>{children}</div>
          ) : (
            <div key={location.pathname} className="animate-page-in">
              {children}
            </div>
          )}
        </main>

        {/* Right rail — hidden on immersive stages (Jasper, cinema) */}
        {location.pathname !== "/ember" &&
          !location.pathname.startsWith("/films") && <RightRail />}
      </div>

      <CreateSelector open={createOpen} onOpenChange={setCreateOpen} />

      {/* Floating composer button */}
      <button
        onClick={() => (onMessages ? setNewMessage(true) : setCreateOpen(true))}
        aria-label={onMessages ? "New message" : "Create"}
        className={cn(
          "whisper-global-compose fixed bottom-[86px] right-4 z-40 h-14 w-14 items-center justify-center rounded-full bg-primary text-primary-foreground shadow-lg shadow-black/25 transition-transform active:scale-90 lg:bottom-7 lg:right-7 lg:flex lg:h-[60px] lg:w-[60px]",
          onMessages ? "flex" : "hidden"
        )}
      >
        {onMessages ? (
          <PenSquare className="h-6 w-6" />
        ) : (
          <Pencil className="h-6 w-6" />
        )}
      </button>

      <NewMessageDialog
        open={newMessage}
        onOpenChange={setNewMessage}
        onPick={(p) =>
          navigate(`/messages?to=${p.user_id}&u=${encodeURIComponent(p.username)}`)
        }
      />

      {/* Private decisions remain available in Settings, never as account labels. */}

      {/* Mobile bottom nav */}
      <nav
        className="fixed inset-x-0 bottom-0 z-40 flex items-center justify-around border-t border-border bg-background px-1 pt-2 lg:hidden"
        style={{ paddingBottom: "max(0.375rem, env(safe-area-inset-bottom))" }}
      >
        {MOBILE_NAV.map((item) => {
          if (item.portal) {
            return (
              <button
                key={item.to}
                onClick={() => void openPortal(item.portal as Portal)}
                aria-label={item.label}
                className="flex h-10 w-11 items-center justify-center rounded-xl text-muted-foreground transition-colors hover:text-foreground"
              >
                <item.icon className="h-[26px] w-[26px]" strokeWidth={2} />
              </button>
            );
          }
          return (
          <NavLink
            key={item.to}
            to={item.to}
            end={item.to === "/"}
            className={({ isActive }) =>
              cn(
                "flex h-10 w-11 items-center justify-center rounded-xl transition-colors",
                isActive
                  ? "text-foreground"
                  : "text-muted-foreground hover:text-foreground"
              )
            }
          >
            {({ isActive }) =>
              item.to === "/profile" ? (
                <span
                  className={cn(
                    "rounded-full transition-shadow",
                    isActive && "ring-2 ring-foreground"
                  )}
                >
                  <Avatar
                    url={profile?.profile_image_url}
                    name={profile?.username ?? profile?.display_name}
                    size={26}
                  />
                </span>
              ) : item.to === "/ember" ? (
                <span
                  className={cn(
                    "relative rounded-[8px] transition-all",
                    isActive ? "scale-110 ring-2 ring-foreground/80" : "opacity-90"
                  )}
                >
                  <KnotMascot size={26} />
                </span>
              ) : (
                <span className="relative">
                  <item.icon
                    className={cn("h-[26px] w-[26px]", isActive && "stroke-[2.4]")}
                    fill={isActive && (item.to === "/messages" || item.to === "/") ? "currentColor" : "none"}
                    strokeWidth={2.2}
                  />
                </span>
              )
            }
          </NavLink>
          );
        })}
      </nav>
    </div>
  );
}

export const Layout = memo(LayoutBase);
