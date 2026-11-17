import PublicNav from "@/components/PublicNav";
import PublicFooter from "@/components/PublicFooter";
import { Layout } from "@/components/Layout";
import { Splash } from "@/components/Splash";
import { useAuth } from "@/hooks/useAuth";

/**
 * True when the viewer is a signed-in member with a complete profile —
 * the signal that shared-content pages (articles, films) should render
 * INSIDE the app chrome instead of the public marketing shell.
 */
export function useIsMember(): { isMember: boolean; loading: boolean } {
  const { session, profile, loading } = useAuth();
  return { isMember: !!session && !!profile?.username, loading };
}

/**
 * Auth-aware shell for shared/public content pages (articles, films…).
 *
 * Logged-in members get the full in-app experience — left rail, right rail,
 * mobile tab bar — exactly like iOS opens shared content in-app instead of
 * bouncing to a marketing page. Logged-out visitors keep the public
 * marketing chrome (nav + footer) so shared links still sell the product.
 */
export function MemberShell({ children }: { children: React.ReactNode }) {
  const { isMember, loading } = useIsMember();

  // Never flash marketing chrome at a member while the session loads.
  if (loading) {
    return <Splash />;
  }

  if (isMember) {
    return <Layout>{children}</Layout>;
  }

  return (
    <div className="min-h-screen bg-background">
      <PublicNav />
      {children}
      <PublicFooter />
    </div>
  );
}
