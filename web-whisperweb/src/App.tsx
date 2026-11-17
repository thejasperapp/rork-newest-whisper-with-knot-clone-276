import { NotebookSyncAgent } from "@/components/NotebookSyncAgent";
import { lazy, Suspense, useState } from "react";
import { onJasperInvalidated } from "@/lib/jasperSession";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route, Navigate, useLocation, useParams } from "react-router-dom";

import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { AuthProvider, useAuth } from "@/hooks/useAuth";
import { Layout } from "@/components/Layout";
import { Splash } from "@/components/Splash";
import { ScrollToTop } from "@/components/ScrollToTop";
import { IncomingCallWatcher } from "@/components/IncomingCallWatcher";
import { MeetingHostProvider } from "@/hooks/useMeetingHost";
import { MeetingHostSurface, MeetRouteBinder } from "@/components/MeetingHostSurface";
import { PortalShell } from "@/components/PortalShell";
import { CreatorStudioGate } from "@/components/CreatorStudioGate";
import { ACTIVE_PORTAL, MEET_PORTAL, type Portal } from "@/lib/portal";

import Auth from "./pages/Auth";
import ResetPassword from "./pages/ResetPassword";
import Feed from "./pages/Feed";
import Messages from "./pages/Messages";
import Profile from "./pages/Profile";
import Compose from "./pages/Compose";
import GridCompose from "./pages/GridCompose";
import Search from "./pages/Search";
import UserProfile from "./pages/UserProfile";
import Community from "./pages/Community";
import Settings from "./pages/Settings";
import Saved from "./pages/Saved";
import Notifications from "./pages/Notifications";
import Welcome from "./pages/Welcome";
import { MarketingLayout } from "./components/MarketingLayout";
import OnboardingPage from "./pages/OnboardingPage";
import NotFound from "./pages/NotFound";

// ─── Code-split routes ────────────────────────────────────────────
// Heavy/secondary pages load on demand — the core surfaces (feed, messages,
// profile, search) stay in the main bundle so first paint gets dramatically
// lighter. Suspense below shows the splash while a chunk streams in.
const Ember = lazy(() => import("./pages/Ember"));
const Coach = lazy(() => import("./pages/Coach"));
const Reels = lazy(() => import("./pages/Reels"));
const RecruiterDashboard = lazy(() => import("./pages/RecruiterDashboard"));
const Collabs = lazy(() => import("./pages/Collabs"));
const Films = lazy(() => import("./pages/Films"));
const FilmDetail = lazy(() => import("./pages/FilmDetail"));
const DirectorStudio = lazy(() => import("./pages/DirectorStudio"));
const CalendarPage = lazy(() => import("./pages/CalendarPage"));
const Dashboard = lazy(() => import("./pages/Dashboard"));
const Analytics = lazy(() => import("./pages/Analytics"));
const JasperBrain = lazy(() => import("./pages/JasperBrain"));
const BusinessSuite = lazy(() => import("./pages/BusinessSuite"));
const WorkspaceTeams = lazy(() => import("./pages/WorkspaceTeams"));
const Policies = lazy(() => import("./pages/Policies"));
const Faq = lazy(() => import("./pages/Faq"));
const About = lazy(() => import("./pages/About"));
const Coaches = lazy(() => import("./pages/Coaches"));
const Team = lazy(() => import("./pages/Team"));
const ForCreators = lazy(() => import("./pages/ForCreators"));
const TeamMembers = lazy(() => import("./pages/TeamMembers"));
const Articles = lazy(() => import("./pages/Articles"));
const ArticleDetail = lazy(() => import("./pages/ArticleDetail"));
const PublicProfile = lazy(() => import("./pages/PublicProfile"));
const Privacy = lazy(() => import("./pages/Privacy"));
const Safety = lazy(() => import("./pages/Safety"));
const Support = lazy(() => import("./pages/Support"));
const WriteArticles = lazy(() => import("./pages/WriteArticles"));
const RoleDetail = lazy(() => import("./pages/RoleDetail"));
const WhisperOne = lazy(() => import("./pages/WhisperOne"));
const Monetization = lazy(() => import("./pages/Monetization"));
const Investors = lazy(() => import("./pages/Investors"));
const Live = lazy(() => import("./pages/Live"));
const LiveStart = lazy(() => import("./pages/LiveStart"));
const LiveRoom = lazy(() => import("./pages/LiveRoom"));
const Meetings = lazy(() => import("./pages/Meetings"));
const MeetLanding = lazy(() => import("./pages/MeetLanding"));
const Communities = lazy(() => import("./pages/Communities"));
const Terms = lazy(() => import("./pages/Terms"));
const BillingSuccess = lazy(() => import("./pages/BillingSuccess"));
const BadgeActivate = lazy(() => import("./pages/BadgeActivate"));
const Apply = lazy(() => import("./pages/Apply"));
const CoachEarnings = lazy(() => import("./pages/CoachEarnings"));
const Brands = lazy(() => import("./pages/Brands"));
const BrandProfilePage = lazy(() => import("./pages/BrandProfilePage"));
const BusinessApply = lazy(() => import("./pages/BusinessApply"));
const BrandSignup = lazy(() => import("./pages/BrandSignup"));
const BrandDashboard = lazy(() => import("./pages/BrandDashboard"));
const MySponsorships = lazy(() => import("./pages/MySponsorships"));
const HireCoach = lazy(() => import("./pages/HireCoach"));
const AdminEmail = lazy(() => import("./pages/AdminEmail"));
const AdminApplications = lazy(() => import("./pages/AdminApplications"));
const AdminApplicants = lazy(() => import("./pages/AdminApplicants"));
const ApplicantQuestionnaire = lazy(() => import("./pages/ApplicantQuestionnaire"));
const RecruiterQR = lazy(() => import("./pages/RecruiterQR"));
const AdminFeatured = lazy(() => import("./pages/AdminFeatured"));
const AdminBots = lazy(() => import("./pages/AdminBots"));
const AdminArticles = lazy(() => import("./pages/AdminArticles"));
const Pitch = lazy(() => import("./pages/Pitch"));
const PitchDeck = lazy(() => import("./pages/PitchDeck"));
const WorkspaceWork = lazy(() => import('./pages/WorkspaceWork'));
const WorkspaceHub = lazy(() => import("./pages/WorkspaceHub"));
const Notebook = lazy(() => import("./pages/Notebook"));
const AdLibrary = lazy(() => import("./pages/AdLibrary"));

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { staleTime: 30_000, refetchOnWindowFocus: false },
  },
});

const stopJasperCacheListener = onJasperInvalidated(() => {
  const filter = { predicate: (query: { queryKey: readonly unknown[] }) => typeof query.queryKey[0] === "string" && query.queryKey[0].startsWith("jasper-") && query.queryKey[0] !== "jasper-marketplace" };
  void queryClient.cancelQueries(filter);
  // Reset immediately removes private data from active observers as well as the cache.
  void queryClient.resetQueries(filter);
});
if (import.meta.hot) import.meta.hot.dispose(stopJasperCacheListener);

function Loader() {
  return <Splash />;
}

// Subdomain portals (business./coaches./recruiters.) are detected in
// @/lib/portal and rendered as standalone full-page dashboards — see
// PortalRoutes below. The main domain keeps its in-app pages untouched.

/**
 * Session + onboarding gate. A signed-in user with no `whisper_profiles`
 * row (or one missing a username) is redirected to /onboarding before
 * reaching the app — the same gate iOS runs via `evaluateGate()`.
 * The `/onboarding` route itself is exempt from this redirect so the
 * onboarding flow can run without bouncing back to itself.
 */
function ProfileRecovery() {
  const { profileError, refreshProfile, signOut } = useAuth();
  const [retrying, setRetrying] = useState(false);
  return <main className="flex min-h-dvh flex-col items-center justify-center gap-4 px-6 text-center">
    <h1 className="text-xl font-semibold">Let’s reconnect</h1>
    <p role="status" className="max-w-sm text-sm text-muted-foreground">{profileError}</p>
    <button disabled={retrying} className="min-h-11 rounded-full bg-secondary px-6 font-semibold disabled:opacity-50" onClick={() => { setRetrying(true); void refreshProfile().finally(() => setRetrying(false)); }}>{retrying ? "Reconnecting…" : "Try again"}</button>
    <button className="min-h-11 px-4 text-sm text-muted-foreground" onClick={() => void signOut()}>Sign out</button>
  </main>;
}

function Protected({ children }: { children: React.ReactNode }) {
  const { session, profile, loading, profileError } = useAuth();
  const location = useLocation();
  if (loading) return <Loader />;
  if (!session) return <Navigate to="/welcome" replace />;
  if (profileError) return <ProfileRecovery />;
  // Force onboarding only when the profile is missing or incomplete.
  // `/onboarding` is intentionally exempt so the flow can complete.
  const needsOnboarding = !profile || !profile.username;
  if (needsOnboarding && !location.pathname.startsWith("/onboarding")) {
    const next = encodeURIComponent(location.pathname + location.search);
    return <Navigate to={`/onboarding?next=${next}`} replace />;
  }
  return <Layout>{children}</Layout>;
}

/**
 * Portal twin of `Protected` — same session + onboarding gate, but wraps
 * the page in the standalone PortalShell (no feed chrome) instead of the
 * social app Layout.
 */
function PortalProtected({
  portal,
  children,
}: {
  portal: Portal;
  children: React.ReactNode;
}) {
  const { session, profile, loading, profileError } = useAuth();
  const location = useLocation();
  if (loading) return <Loader />;
  if (!session) return <Navigate to="/welcome" replace />;
  if (profileError) return <ProfileRecovery />;
  const needsOnboarding = !profile || !profile.username;
  if (needsOnboarding && !location.pathname.startsWith("/onboarding")) {
    const next = encodeURIComponent(location.pathname + location.search);
    return <Navigate to={`/onboarding?next=${next}`} replace />;
  }
  return <PortalShell portal={portal}>{children}</PortalShell>;
}

/**
 * Standalone portal mode — on business./coaches./recruiters. subdomains
 * the dashboard IS the site: it renders full-page at "/" with portal
 * chrome, only auth/legal/billing routes ride along, and every other
 * path (feed, messages, reels…) lands back on the dashboard.
 */
function PortalRoutes({ portal }: { portal: Portal }) {
  const { session, loading } = useAuth();

  const dashboard =
    portal === "business" ? (
      <BusinessSuite />
    ) : portal === "coach" ? (
      <Coach />
    ) : portal === "workspace" ? (
      <WorkspaceHub />
    ) : (
      <RecruiterDashboard />
    );

  return (
    <Suspense fallback={<Loader />}>
      <Routes>
        <Route
          path="/auth"
          element={
            loading ? (
              <Loader />
            ) : session ? (
              <Navigate to="/" replace />
            ) : (
              <Auth />
            )
          }
        />
        <Route path="/reset-password" element={<ResetPassword />} />
        <Route
          path="/onboarding"
          element={
            loading ? (
              <Loader />
            ) : session ? (
              <OnboardingPage />
            ) : (
              <Navigate to="/welcome" replace />
            )
          }
        />
        <Route path="/welcome" element={<Welcome />} />
        <Route path="/policies" element={<MarketingLayout><Policies /></MarketingLayout>} />
        <Route path="/investors" element={<MarketingLayout><Investors /></MarketingLayout>} />
        <Route path="/faq" element={<MarketingLayout><Faq /></MarketingLayout>} />
        <Route path="/terms" element={<MarketingLayout><Terms /></MarketingLayout>} />
        <Route path="/privacy" element={<MarketingLayout><Privacy /></MarketingLayout>} />
        <Route path="/support" element={<MarketingLayout><Support /></MarketingLayout>} />
        <Route path="/billing/success" element={<BillingSuccess />} />
        <Route path="/badge/activate" element={<BadgeActivate />} />
        <Route path="/p/:username" element={<MarketingLayout preserveMember><PublicProfile /></MarketingLayout>} />
        <Route path="/hire/:coachId" element={<MarketingLayout preserveMember><HireCoach /></MarketingLayout>} />
        <Route
          path="/apply"
          element={
            <PortalProtected portal={portal}>
              <Apply />
            </PortalProtected>
          }
        />
        <Route
          path="/apply/:type"
          element={
            <PortalProtected portal={portal}>
              <Apply />
            </PortalProtected>
          }
        />
        <Route
          path="/"
          element={
            <PortalProtected portal={portal}>{dashboard}</PortalProtected>
          }
        />
        {portal === "coach" && (
          <Route
            path="/coach/earnings"
            element={
              <PortalProtected portal={portal}>
                <CoachEarnings />
              </PortalProtected>
            }
          />
        )}
        {portal === "recruiter" && (
          <Route
            path="/recruiter/qr"
            element={
              <PortalProtected portal={portal}>
                <RecruiterQR />
              </PortalProtected>
            }
          />
        )}
        {portal === "business" && (
          <Route
            path="/ad-library"
            element={
              <PortalProtected portal={portal}>
                <AdLibrary />
              </PortalProtected>
            }
          />
        )}
        {portal === "business" && <>
          <Route path="/brand/signup" element={<PortalProtected portal={portal}><BrandSignup /></PortalProtected>} />
          <Route path="/brand/dashboard" element={<PortalProtected portal={portal}><BrandDashboard /></PortalProtected>} />
          <Route path="/brands/:brandId" element={<PortalProtected portal={portal}><BrandProfilePage /></PortalProtected>} />
        </>}
        <Route path="/teams" element={<PortalProtected portal={portal}><WorkspaceTeams /></PortalProtected>} />
        <Route path="/work" element={<WorkspaceWork />} />
        {/* Workspace — the one desk that fronts every tool. */}
        {portal === "workspace" && (
          <>
            <Route
              path="/notebook"
              element={
                <PortalProtected portal={portal}>
                  <Notebook />
                </PortalProtected>
              }
            />
            <Route
              path="/calendar"
              element={
                <PortalProtected portal={portal}>
                  <CalendarPage />
                </PortalProtected>
              }
            />
            <Route
              path="/meetings"
              element={
                <PortalProtected portal={portal}>
                  <Meetings />
                </PortalProtected>
              }
            />
            <Route
              path="/dashboard"
              element={
                <PortalProtected portal={portal}>
                  <CreatorStudioGate>
                    <Dashboard />
                  </CreatorStudioGate>
                </PortalProtected>
              }
            />
            <Route
              path="/analytics"
              element={
                <PortalProtected portal={portal}>
                  <Analytics />
                </PortalProtected>
              }
            />
            <Route
              path="/director"
              element={
                <PortalProtected portal={portal}>
                  <DirectorStudio />
                </PortalProtected>
              }
            />
            <Route
              path="/collabs"
              element={
                <PortalProtected portal={portal}>
                  <Collabs />
                </PortalProtected>
              }
            />
            <Route path="/meet/:id" element={<MeetRouteBinder />} />
          </>
        )}
        {/* In-app paths from shared links land on the portal home. */}
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </Suspense>
  );
}

function AppRoutes() {
  const { session, loading } = useAuth();

  // meet.mydailywhisper.com — the Google-Meet-style front door: start a
  // meeting or join by code/link. meet./<code> drops straight into a room.
  if (MEET_PORTAL) {
    return (
      <Suspense fallback={<Loader />}>
        <Routes>
          <Route
            path="/auth"
            element={
              loading ? (
                <Loader />
              ) : session ? (
                <Navigate to="/" replace />
              ) : (
                <Auth />
              )
            }
          />
          <Route path="/reset-password" element={<ResetPassword />} />
          <Route path="/welcome" element={<Welcome />} />
          <Route path="/meet/:id" element={<MeetRouteBinder />} />
          <Route path="/notebook" element={loading ? <Loader /> : session ? <Notebook /> : <Navigate to="/auth" replace />} />
          <Route path="/" element={<MeetLanding />} />
          <Route path="/:code" element={<MeetLanding />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </Suspense>
    );
  }

  // Standalone portal hosts render their own route table — the dashboard
  // IS the site there, detached from the feed and every social surface.
  if (ACTIVE_PORTAL) {
    return <PortalRoutes portal={ACTIVE_PORTAL} />;
  }

  return (
    <Suspense fallback={<Loader />}>
    <Routes>
      <Route
        path="/auth"
        element={
          loading ? (
            <Loader />
          ) : session ? (
            <Navigate to="/" replace />
          ) : (
            <Auth />
          )
        }
      />
      <Route path="/reset-password" element={<ResetPassword />} />
      <Route
        path="/onboarding"
        element={
          loading ? (
            <Loader />
          ) : session ? (
            <OnboardingPage />
          ) : (
            <Navigate to="/welcome" replace />
          )
        }
      />
      <Route path="/welcome" element={<Welcome />} />
      <Route path="/about" element={<MarketingLayout><About /></MarketingLayout>} />
      <Route path="/pricing" element={<Navigate to="/monetization" replace />} />
      <Route path="/coaches" element={<MarketingLayout><Coaches /></MarketingLayout>} />
      <Route path="/team" element={<MarketingLayout><Team /></MarketingLayout>} />
      <Route path="/for-creators" element={<MarketingLayout><ForCreators /></MarketingLayout>} />
      {/* The Athlete badge retired into a Creator niche — old links land on Creators. */}
      <Route path="/athletes" element={<Navigate to="/creators" replace />} />
      <Route path="/creators" element={<MarketingLayout><TeamMembers kind="creators" /></MarketingLayout>} />
      <Route path="/recruiters" element={<MarketingLayout><TeamMembers kind="recruiters" /></MarketingLayout>} />
      <Route path="/articles" element={<MarketingLayout preserveMember><Articles /></MarketingLayout>} />
      <Route path="/articles/:slug" element={<MarketingLayout preserveMember><ArticleDetail /></MarketingLayout>} />
      <Route path="/p/:username" element={<MarketingLayout preserveMember><PublicProfile /></MarketingLayout>} />
      <Route path="/privacy" element={<MarketingLayout><Privacy /></MarketingLayout>} />
      <Route path="/safety" element={<MarketingLayout><Safety /></MarketingLayout>} />
      <Route path="/support" element={<MarketingLayout><Support /></MarketingLayout>} />
      <Route path="/studio/articles" element={<WriteArticles />} />
      <Route path="/roles/:role" element={<MarketingLayout><RoleDetail /></MarketingLayout>} />
      <Route path="/one" element={<MarketingLayout><WhisperOne /></MarketingLayout>} />
      <Route path="/monetization" element={<MarketingLayout><Monetization /></MarketingLayout>} />
      {/* The investor page — the monetization funnel + growth plan, public and shareable. */}
      <Route path="/investors" element={<MarketingLayout><Investors /></MarketingLayout>} />
      <Route path="/live" element={<Protected><Live /></Protected>} />
      <Route path="/live/start" element={<Protected><LiveStart /></Protected>} />
      <Route path="/live/:id" element={<Protected><LiveRoom /></Protected>} />
      <Route path="/meetings" element={<Protected><Meetings /></Protected>} />
      <Route path="/notebook" element={<Protected><Notebook /></Protected>} />
      <Route path="/work" element={<WorkspaceWork />} />
      {/* Ad Library — public transparency page, like Meta's. */}
      <Route path="/ad-library" element={<MarketingLayout preserveMember><AdLibrary /></MarketingLayout>} />
      <Route path="/communities" element={<Protected><Communities /></Protected>} />
      <Route path="/meet/:id" element={<MeetRouteBinder />} />
      <Route path="/terms" element={<MarketingLayout><Terms /></MarketingLayout>} />
      {/* Badge / coaching / refund policies — public, linked from checkouts. */}
      <Route path="/policies" element={<MarketingLayout><Policies /></MarketingLayout>} />
      {/* The in-depth FAQ — public and shareable. */}
      <Route path="/faq" element={<MarketingLayout><Faq /></MarketingLayout>} />
      <Route path="/billing/success" element={<BillingSuccess />} />
      <Route path="/badge/activate" element={<BadgeActivate />} />
      <Route path="/hire/:coachId" element={<MarketingLayout preserveMember><HireCoach /></MarketingLayout>} />
      <Route path="/admin/email" element={<AdminEmail />} />
      <Route path="/admin/applications" element={<AdminApplications />} />
      <Route path="/admin/applicants" element={<AdminApplicants />} />
      <Route path="/apply/questionnaire" element={<ApplicantQuestionnaire />} />
      <Route path="/recruiter/qr" element={<Protected><RecruiterQR /></Protected>} />
      <Route path="/admin/featured" element={<AdminFeatured />} />
      <Route path="/admin/bots" element={<Protected><AdminBots /></Protected>} />
      <Route path="/admin/articles" element={<AdminArticles />} />
      <Route
        path="/"
        element={
          <Protected>
            <Feed />
          </Protected>
        }
      />
      <Route
        path="/search"
        element={
          <Protected>
            <Search />
          </Protected>
        }
      />
      <Route
        path="/reels"
        element={
          <Protected>
            <Reels />
          </Protected>
        }
      />
      <Route
        path="/compose"
        element={
          <Protected>
            <Compose />
          </Protected>
        }
      />
      <Route
        path="/compose/grid"
        element={
          <Protected>
            <GridCompose />
          </Protected>
        }
      />
      <Route
        path="/messages"
        element={
          <Protected>
            <Messages />
          </Protected>
        }
      />
      <Route
        path="/profile"
        element={
          <Protected>
            <Profile />
          </Protected>
        }
      />
      <Route
        path="/u/:username"
        element={
          <Protected>
            <UserProfile />
          </Protected>
        }
      />
      <Route
        path="/ember"
        element={
          <Protected>
            <Ember />
          </Protected>
        }
      />
      <Route
        path="/coach"
        element={
          <Protected>
            <Coach />
          </Protected>
        }
      />
      <Route
        path="/settings"
        element={
          <Protected>
            <Settings />
          </Protected>
        }
      />
      <Route
        path="/saved"
        element={
          <Protected>
            <Saved />
          </Protected>
        }
      />
      <Route
        path="/apply"
        element={
          <Protected>
            <Apply />
          </Protected>
        }
      />
      <Route
        path="/coach/earnings"
        element={
          <Protected>
            <CoachEarnings />
          </Protected>
        }
      />
      <Route
        path="/brands"
        element={
          <Protected>
            <Brands />
          </Protected>
        }
      />
      <Route
        path="/brands/:brandId"
        element={
          <Protected>
            <BrandProfilePage />
          </Protected>
        }
      />
      <Route
        path="/work-with/:businessId"
        element={
          <Protected>
            <BusinessApply />
          </Protected>
        }
      />
      <Route
        path="/brand/signup"
        element={
          <Protected>
            <BrandSignup />
          </Protected>
        }
      />
      <Route
        path="/brand/dashboard"
        element={
          <Protected>
            <BrandDashboard />
          </Protected>
        }
      />
      <Route
        path="/sponsorships"
        element={
          <Protected>
            <MySponsorships />
          </Protected>
        }
      />
      <Route
        path="/apply/:type"
        element={
          <Protected>
            <Apply />
          </Protected>
        }
      />
      <Route
        path="/notifications"
        element={
          <Protected>
            <Notifications />
          </Protected>
        }
      />
      <Route
        path="/dashboard"
        element={
          <Protected>
            <CreatorStudioGate>
              <Dashboard />
            </CreatorStudioGate>
          </Protected>
        }
      />
      <Route
        path="/analytics"
        element={
          <Protected>
            <Analytics />
          </Protected>
        }
      />
      <Route
        path="/jasper-brain"
        element={
          <Protected>
            <JasperBrain />
          </Protected>
        }
      />
      <Route
        path="/teams"
        element={<Protected><WorkspaceTeams /></Protected>}
      />
      <Route
        path="/business"
        element={
          <Protected>
            <BusinessSuite />
          </Protected>
        }
      />
      <Route
        path="/recruiter"
        element={
          <Protected>
            <RecruiterDashboard />
          </Protected>
        }
      />
      <Route
        path="/pitch"
        element={<Pitch />}
      />
      <Route
        path="/pitch/:audience"
        element={<PitchDeck />}
      />
      <Route
        path="/collabs"
        element={
          <Protected>
            <Collabs />
          </Protected>
        }
      />
      <Route path="/films" element={<MarketingLayout preserveMember><Films /></MarketingLayout>} />
      <Route path="/films/:id" element={<MarketingLayout preserveMember><FilmDetail /></MarketingLayout>} />
      <Route
        path="/director"
        element={
          <Protected>
            <DirectorStudio />
          </Protected>
        }
      />
      <Route
        path="/calendar"
        element={
          <Protected>
            <CalendarPage />
          </Protected>
        }
      />
      <Route
        path="/c/:id"
        element={
          <Protected>
            <Community />
          </Protected>
        }
      />
      {/* Old hub links (and the speed-date "Back to Dating" exit) said
          /communities/<id> — the hub lives at /c/<id>. */}
      <Route path="/communities/:id" element={<CommunityAliasRedirect />} />
      {/* A bare meeting code pasted on the main domain (mydailywhisper.com/wsp-…)
          opens the room instead of a dead end — same as meet.mydailywhisper.com. */}
      <Route path="/:code" element={<CodeOrNotFound />} />
      <Route path="*" element={<NotFound />} />
    </Routes>
    </Suspense>
  );
}

/** /communities/<id> → /c/<id>, query + hash preserved. */
function CommunityAliasRedirect() {
  const { id } = useParams<{ id: string }>();
  const location = useLocation();
  return <Navigate to={`/c/${id ?? ""}${location.search}${location.hash}`} replace />;
}

const MEETING_CODE_RE = /^wsp-[a-z0-9]{4}-[a-z0-9]{4}$/i;

/** Single-segment unknown paths: meeting codes open the room, everything
 *  else is the real Not Found page. */
function CodeOrNotFound() {
  const { code } = useParams<{ code: string }>();
  const location = useLocation();
  if (code && MEETING_CODE_RE.test(code.trim())) {
    return <Navigate to={`/meet/${code.trim()}${location.search}`} replace />;
  }
  return <NotFound />;
}

const WorkspaceSearch = lazy(() => import('@/components/WorkspaceSearch').then((module) => ({ default: module.WorkspaceSearch })));
const KnotWelcomeCall = lazy(() => import('@/components/KnotWelcomeCall').then(module => ({ default: module.KnotWelcomeCall })));
function KnotWelcomeAgent() {
  const { user, loading } = useAuth();
  return user && !loading ? <Suspense fallback={null}><KnotWelcomeCall /></Suspense> : null;
}

const App = () => (
  <QueryClientProvider client={queryClient}>
    <TooltipProvider>
      <Sonner />
      <AuthProvider>
        <BrowserRouter>
          <MeetingHostProvider>
            <ScrollToTop />
            {/* Global 1:1 call ring — answers DM video calls from anywhere. */}
            <IncomingCallWatcher />
            <KnotWelcomeAgent />
            <NotebookSyncAgent />
            <AppRoutes />
            <Suspense fallback={null}><WorkspaceSearch /></Suspense>
            {/* Floating meeting window — survives navigation, minimizes to a corner tile. */}
            <MeetingHostSurface />
          </MeetingHostProvider>
        </BrowserRouter>
      </AuthProvider>
    </TooltipProvider>
  </QueryClientProvider>
);

export default App;
