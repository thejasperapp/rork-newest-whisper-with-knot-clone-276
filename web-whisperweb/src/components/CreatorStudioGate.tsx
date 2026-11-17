import { Navigate } from "react-router-dom";

import { useAuth } from "@/hooks/useAuth";
import { canOpenCreatorStudio } from "@/lib/accountAccess";

/**
 * Route gate for Creator Studio — VERIFIED ONLY. Professional accounts are
 * sent to Analytics (their tier's insights); personal accounts land there
 * too, where Analytics explains how to unlock it. Keeps the separation
 * enforceable at the URL, not just in menus. Renders children while the
 * profile is still loading so the page never flashes a redirect.
 */
export function CreatorStudioGate({ children }: { children: React.ReactNode }) {
  const { profile, loading } = useAuth();
  if (loading || !profile) return <>{children}</>;
  if (!canOpenCreatorStudio(profile)) return <Navigate to="/analytics" replace />;
  return <>{children}</>;
}
