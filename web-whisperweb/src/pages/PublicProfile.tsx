import { Link, Navigate, useParams } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { ArrowRight, Check, Dumbbell, Loader2, Trophy } from "lucide-react";

import PublicNav from "@/components/PublicNav";
import PublicFooter from "@/components/PublicFooter";
import { Avatar } from "@/components/Avatar";
import { Reveal } from "@/components/Reveal";
import { SealBadge } from "@/components/SealBadge";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/hooks/useAuth";
import { usePageMeta } from "@/hooks/usePageMeta";
import { BACKEND_URL } from "@/lib/billing";

interface PublicProfileData {
  username: string;
  display_name: string | null;
  bio: string | null;
  profile_image_url: string | null;
  interests: string[];
  is_coach: boolean;
  is_athlete: boolean;
  is_verified: boolean;
}

async function fetchPublicProfile(
  username: string
): Promise<PublicProfileData | null> {
  const res = await fetch(
    `${BACKEND_URL}/public/profile?username=${encodeURIComponent(username)}`
  );
  if (res.status === 404) return null;
  if (!res.ok) throw new Error("load_failed");
  const data = (await res.json()) as { profile?: PublicProfileData };
  return data.profile ?? null;
}

/** Public, read-only member profile — visible before signing up. */
export default function PublicProfile() {
  const { username } = useParams<{ username: string }>();
  const { session } = useAuth();

  const profile = useQuery({
    queryKey: ["public-profile", username],
    queryFn: () => fetchPublicProfile(username ?? ""),
    enabled: !!username,
    staleTime: 60_000,
    retry: 1,
  });

  const p = profile.data;

  // Members never see the marketing profile — a shared /p/ link opens the
  // real in-app profile, exactly like iOS.
  if (session && username) {
    return <Navigate to={`/u/${username}`} replace />;
  }
  usePageMeta(
    p ? `@${p.username}` : "Profile",
    p?.bio || `@${username ?? ""} on Whisper — the social network built on real connection.`
  );

  return (
    <div className="flex min-h-screen flex-col bg-background">
      <PublicNav />

      <main className="mx-auto w-full max-w-2xl flex-1 px-4 pb-20 pt-32 sm:px-6 lg:pt-36">
        {profile.isLoading ? (
          <div className="flex justify-center pt-24">
            <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
          </div>
        ) : !p ? (
          <div className="rounded-[28px] border border-border bg-card p-10 text-center">
            <p className="text-[16px] font-semibold">
              This profile isn't available.
            </p>
            <p className="mt-1.5 text-[14.5px] text-muted-foreground">
              It may be private, or the link is wrong.
            </p>
            <Button className="mt-6 rounded-full" asChild>
              <Link to="/team">Meet our team</Link>
            </Button>
          </div>
        ) : (
          <>
            <Reveal variant="scale" className="rounded-[32px] border border-border bg-card p-8 text-center sm:p-10">
              <div className="mx-auto w-fit rounded-full p-1 ring-2 ring-border">
                <Avatar
                  url={p.profile_image_url}
                  name={p.display_name ?? p.username}
                  size={104}
                />
              </div>
              <div className="mt-5 flex items-center justify-center gap-2.5">
                <h1 className="font-display text-[28px] font-extrabold tracking-tight">
                  {p.display_name || p.username}
                </h1>
                {p.is_coach && (
                  <SealBadge size={24} solid="#fa7321" shadowColor="#fa7321" title="Verified Coach">
                    <Dumbbell style={{ width: 11, height: 11 }} strokeWidth={3} />
                  </SealBadge>
                )}
                {p.is_athlete && (
                  <SealBadge
                    size={24}
                    colors={["#fb7185", "#e11d48"]}
                    shadowColor="#e11d48"
                    title="Verified Athlete"
                  >
                    <Trophy style={{ width: 11, height: 11 }} strokeWidth={3} />
                  </SealBadge>
                )}
                {p.is_verified && !p.is_coach && !p.is_athlete && (
                  <SealBadge
                    size={24}
                    colors={["#4aa8ff", "#2f86f0"]}
                    shadowColor="#3399ff"
                    title="Verified"
                  >
                    <Check style={{ width: 11, height: 11 }} strokeWidth={3.5} />
                  </SealBadge>
                )}
              </div>
              <p className="mt-1 text-[15px] font-semibold text-muted-foreground">
                @{p.username}
              </p>

              {p.bio && (
                <p className="mx-auto mt-4 max-w-md text-[15px] leading-relaxed text-foreground/85">
                  {p.bio}
                </p>
              )}

              {p.interests.length > 0 && (
                <div className="mt-5 flex flex-wrap justify-center gap-2">
                  {p.interests.map((interest) => (
                    <span
                      key={interest}
                      className="rounded-full border border-border bg-background px-3.5 py-1.5 text-[13px] font-semibold text-muted-foreground"
                    >
                      {interest}
                    </span>
                  ))}
                </div>
              )}

              <Button
                className="mt-8 h-12 rounded-full px-8 text-[15px] font-semibold"
                asChild
              >
                <Link
                  to={
                    session ? `/u/${p.username}` : "/auth?mode=signup"
                  }
                >
                  {session
                    ? "View full profile in the app"
                    : `Follow @${p.username} on Whisper`}
                  <ArrowRight className="ml-1 h-4 w-4" />
                </Link>
              </Button>
            </Reveal>

            {!session && (
              <p className="mt-6 text-center text-[13.5px] text-muted-foreground">
                Posts, check-ins, and coaching live inside the app —{" "}
                <Link
                  to="/auth?mode=signup"
                  className="font-semibold text-foreground underline-offset-4 hover:underline"
                >
                  join free
                </Link>{" "}
                to see the rest.
              </p>
            )}
          </>
        )}
      </main>

      <PublicFooter />
    </div>
  );
}
