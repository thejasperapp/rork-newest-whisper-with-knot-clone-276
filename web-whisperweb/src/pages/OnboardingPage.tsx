import { useEffect } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { Loader2 } from "lucide-react";

import { OnboardingFlow } from "@/components/OnboardingFlow";
import { useAuth } from "@/hooks/useAuth";

/**
 * Session-gated onboarding route. A signed-in user with no `whisper_profiles`
 * row (or one that hasn't completed onboarding) is forced through the same
 * multi-step setup iOS runs: profile → interests → follows → safety.
 *
 * This closes the web gap where signup only collected email + password and
 * dropped the user into the feed with a null profile, causing downstream
 * issues (null username, empty feed, broken compose, etc).
 */
export default function OnboardingPage() {
  const { session, profile, loading } = useAuth();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const nextPath =
    (searchParams.get("next") ?? "/").startsWith("/") &&
    !(searchParams.get("next") ?? "/").startsWith("//")
      ? (searchParams.get("next") as string)
      : "/";

  useEffect(() => {
    const handler = (e: Event) => {
      const detail = (e as CustomEvent).detail as { nextPath?: string } | undefined;
      navigate(detail?.nextPath ?? "/", { replace: true });
    };
    window.addEventListener("whisper-onboarding-complete", handler);
    return () => window.removeEventListener("whisper-onboarding-complete", handler);
  }, [navigate, nextPath]);

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
      </div>
    );
  }

  // Not signed in — send back to signup.
  if (!session) {
    navigate(`/auth?mode=signup&next=${encodeURIComponent(nextPath)}`, { replace: true });
    return null;
  }

  // Already onboarded (profile exists with a username) — skip to the app.
  if (profile && profile.username) {
    navigate(nextPath, { replace: true });
    return null;
  }

  return <OnboardingFlow nextPath={nextPath} />;
}
