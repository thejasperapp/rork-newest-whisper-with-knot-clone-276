import { useParams, useNavigate, useSearchParams, Navigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { ArrowLeft } from "lucide-react";

import { ProfileView } from "@/components/ProfileView";
import { fetchProfileByUsername, fetchProfilesByIds } from "@/lib/api";
import { useAuth } from "@/hooks/useAuth";

export default function UserProfile() {
  const { username = "" } = useParams();
  const navigate = useNavigate();
  const { user } = useAuth();
  const [params] = useSearchParams();
  const candidateID = params.get("id");
  const userID = candidateID && /^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(candidateID) ? candidateID.toLowerCase() : null;

  const profileQuery = useQuery({
    queryKey: ["profile-by-username", user?.id, userID ?? username.toLowerCase()],
    queryFn: async () => userID ? (await fetchProfilesByIds([userID]))[userID] ?? null : fetchProfileByUsername(username),
    enabled: username.length > 0,
  });

  if (profileQuery.isLoading) {
    return (
      <div className="flex h-screen items-center justify-center text-sm text-muted-foreground">
        Loading…
      </div>
    );
  }

  const profile = profileQuery.data;
  if (!profile) {
    return (
      <div className="flex h-screen flex-col items-center justify-center gap-3 px-6 text-center">
        <p className="font-display text-lg font-bold">{profileQuery.isError ? "Couldn't load this profile" : "Profile unavailable"}</p>
        {profileQuery.isError && <button type="button" onClick={() => void profileQuery.refetch()} className="min-h-11 rounded-full border px-5 text-sm">Try again</button>}
        <button
          onClick={() => navigate(-1)}
          className="rounded-full bg-secondary px-5 py-2 text-sm font-semibold"
        >
          Go back
        </button>
      </div>
    );
  }

  // Viewing your own handle → canonical profile page.
  if (profile.user_id === user?.id) {
    return <Navigate to="/profile" replace />;
  }

  return (
    <div>
      <button
        onClick={() => navigate(-1)}
        className="glass fixed left-3 top-3 z-40 rounded-full bg-black/30 p-2 text-white md:hidden"
      >
        <ArrowLeft className="h-5 w-5" />
      </button>
      <ProfileView profile={profile} isMe={false} />
    </div>
  );
}
