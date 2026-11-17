import { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Plus, Loader2, MapPin, RefreshCw, Lock, Globe } from "lucide-react";
import { toast } from "sonner";

import { Header } from "@/components/Header";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { useAuth } from "@/hooks/useAuth";
import {
  COMMUNITIES,
  createCommunity,
  fetchCustomCommunities,
  fetchMyPrivateGroups,
  fetchMyGroupRows,
  communityReact,
  type Community,
} from "@/lib/communities";
import {
  fetchNearbyCommunities,
  loadCachedNearby,
} from "@/lib/nearbyCommunities";
import { jasperHasLocalToken } from "@/lib/jasperConnect";
import { cn } from "@/lib/utils";
import { JasperAnalysisDock } from "@/components/JasperAnalysisDock";

/**
 * Communities index — the full catalog plus every user-created community,
 * with a create flow so anyone can start a new topic hub.
 */
export default function Communities() {
  const { user, profile } = useAuth();
  const queryClient = useQueryClient();
  const [creating, setCreating] = useState<boolean>(false);
  const [name, setName] = useState<string>("");
  const [tagline, setTagline] = useState<string>("");
  const [keywords, setKeywords] = useState<string>("");
  const [isPrivateGroup, setIsPrivateGroup] = useState<boolean>(false);

  const customQuery = useQuery({
    queryKey: ["custom-communities"],
    queryFn: fetchCustomCommunities,
  });

  // Private groups I belong to (or am invited to) — they never appear in
  // the public browse grid, so they get their own shelf.
  const myGroupsQuery = useQuery({
    queryKey: ["my-private-groups", user?.id],
    queryFn: () => fetchMyPrivateGroups(user!.id),
    enabled: !!user,
  });
  const myGroupRowsQuery = useQuery({
    queryKey: ["my-group-rows", user?.id],
    queryFn: () => fetchMyGroupRows(user!.id),
    enabled: !!user,
  });
  const invitedSlugs = useMemo(
    () =>
      new Set(
        (myGroupRowsQuery.data ?? [])
          .filter((r) => r.status === "invited")
          .map((r) => r.community_slug)
      ),
    [myGroupRowsQuery.data]
  );

  // Geo suggestions — campus hubs + per-gym crews around the user.
  // Per-account and ADDITIVE: every scan adds hubs, never replaces them.
  const [nearby, setNearby] = useState<Community[] | null>(() => loadCachedNearby(user?.id));
  const [findingNearby, setFindingNearby] = useState<boolean>(false);

  const findNearby = async (): Promise<void> => {
    if (findingNearby) return;
    setFindingNearby(true);
    try {
      const found = await fetchNearbyCommunities(user?.id);
      setNearby(found);
      if (found.length === 0) toast("Nothing recognizable nearby yet — try somewhere busier.");
    } catch {
      toast("Couldn't read your location — check the browser permission.");
    } finally {
      setFindingNearby(false);
    }
  };

  const all = useMemo<Community[]>(
    () => [...(customQuery.data ?? []), ...COMMUNITIES],
    [customQuery.data]
  );

  const create = useMutation({
    mutationFn: () =>
      createCommunity({
        name,
        tagline,
        keywords: keywords.split(",").map((k) => k.trim()).filter(Boolean),
        creatorId: user!.id,
        creatorUsername: profile?.username ?? "you",
        visibility: isPrivateGroup ? "private" : "public",
      }),
    onSuccess: (community) => {
      toast(
        community.visibility === "private"
          ? `${community.name} is live — invite people from the group page`
          : `${community.name} is live — pick it in the composer when you post`
      );
      setCreating(false);
      setName("");
      setTagline("");
      setKeywords("");
      setIsPrivateGroup(false);
      void queryClient.invalidateQueries({ queryKey: ["custom-communities"] });
      void queryClient.invalidateQueries({ queryKey: ["my-private-groups"] });
    },
    onError: (err: Error) => toast(err.message),
  });

  return (
    <div className="min-h-screen">
      <Header title="Communities" />

      {/* Jasper's community matchmaker — the meeting-style dock, pinned
          right above the nav bar (the same pattern as the inbox). */}
      <JasperAnalysisDock
        pillLabel="Jasper's picks"
        boxTitle="Community matchmaker"
        focus="You are Whisper's community matchmaker. From CANDIDATES (and NEARBY when present) pick the 2-3 communities this user would genuinely enjoy — each with a one-line reason grounded in their interests or the nearby places. Mention a NEARBY hub when it fits (that's a real place by them). End with one sentence on what they should post there first. Never invent communities that aren't listed."
        buildContext={() => {
          const lines: string[] = [];
          const interests = profile?.interests ?? [];
          if (interests.length > 0) {
            lines.push(`INTERESTS: ${interests.join(", ")}`);
          }
          if (nearby && nearby.length > 0) {
            lines.push(
              `NEARBY: ${nearby.map((c) => `${c.name} (${c.origin ?? "near you"})`).join(" · ")}`
            );
          }
          lines.push(`CANDIDATES: ${all.slice(0, 24).map((c) => c.name).join(" · ")}`);
          return lines.join("\n");
        }}
        emptyText="Join a community or post something first — then I'll have signal to match you."
      />

      <div className="px-4 pb-16 pt-4">
        <div className="mb-4 flex items-center justify-between">
          <p className="text-[13px] text-muted-foreground">
            Topic hubs built from posts across Whisper
          </p>
          <div className="flex gap-2">
            <Button
              size="sm"
              variant="outline"
              className="rounded-full font-bold"
              onClick={() => {
                setIsPrivateGroup(true);
                setCreating(true);
              }}
              disabled={!user}
            >
              <Lock className="h-4 w-4" />
              New group
            </Button>
            <Button
              size="sm"
              className="rounded-full font-bold"
              onClick={() => {
                setIsPrivateGroup(false);
                setCreating(true);
              }}
              disabled={!user}
            >
              <Plus className="h-4 w-4" />
              New community
            </Button>
          </div>
        </div>

        {/* Near you — geo-detected hubs (a college unlocks the campus pack,
            each gym becomes its own crew). */}
        <div className="mb-5">
          <div className="mb-2 flex items-center justify-between">
            <h3 className="flex items-center gap-1.5 text-[14px] font-bold">
              Near you
              <MapPin className="h-3.5 w-3.5 text-muted-foreground" />
            </h3>
            {nearby && nearby.length > 0 && (
              <button
                onClick={() => void findNearby()}
                disabled={findingNearby}
                className="flex items-center gap-1 text-[12px] font-semibold text-muted-foreground hover:text-foreground"
              >
                <RefreshCw className={findingNearby ? "h-3 w-3 animate-spin" : "h-3 w-3"} />
                Refresh
              </button>
            )}
          </div>
          {nearby === null || nearby.length === 0 ? (
            <div className="flex items-center gap-3 rounded-2xl border border-border bg-card p-4">
              <span
                className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl text-white"
                style={{ backgroundImage: "linear-gradient(135deg, #ED6B38, #FFB366)" }}
              >
                <MapPin className="h-5 w-5" />
              </span>
              <span className="min-w-0 flex-1">
                <span className="block text-[14px] font-bold">Find communities near you</span>
                <span className="block text-[12px] text-muted-foreground">
                  A campus nearby unlocks Whisper Law &amp; friends. Your gym gets its own crew.
                </span>
              </span>
              <Button
                size="sm"
                className="shrink-0 rounded-full font-bold"
                onClick={() => void findNearby()}
                disabled={findingNearby}
              >
                {findingNearby ? <Loader2 className="h-4 w-4 animate-spin" /> : "Enable"}
              </Button>
            </div>
          ) : (
            <div className="-mx-4 flex gap-3 overflow-x-auto px-4 pb-1">
              {nearby.map((c) => {
                const Icon = c.icon;
                const react = communityReact(c);
                return (
                  <Link
                    key={c.id}
                    to={`/c/${c.id}`}
                    className="w-[190px] shrink-0 overflow-hidden rounded-2xl border border-border bg-card transition-transform hover:scale-[1.01]"
                  >
                    <span
                      className="relative flex h-[88px] items-center justify-center"
                      style={{
                        backgroundImage: `linear-gradient(135deg, ${c.gradient[0]}, ${c.gradient[1]})`,
                      }}
                    >
                      <Icon className="h-8 w-8 text-white" />
                      {react && (
                        <span className="absolute right-2 top-2 rounded-full bg-black/35 px-1.5 py-0.5 text-[13px]">
                          {react}
                        </span>
                      )}
                    </span>
                    <span className="block px-3 py-2.5">
                      <span className="block truncate text-[13.5px] font-bold">{c.name}</span>
                      {c.origin && (
                        <span className="mt-0.5 flex items-center gap-1 text-[11px] text-muted-foreground">
                          <MapPin className="h-3 w-3 shrink-0" />
                          <span className="truncate">{c.origin}</span>
                        </span>
                      )}
                    </span>
                  </Link>
                );
              })}
            </div>
          )}
        </div>

        {/* Your private groups — invite-only spaces you're in (or invited to).
            Always visible for signed-in users so creating one is discoverable. */}
        {user && (
          <div className="mb-5">
            <div className="mb-2 flex items-center justify-between">
              <h3 className="flex items-center gap-1.5 text-[14px] font-bold">
                Your groups
                <Lock className="h-3.5 w-3.5 text-muted-foreground" />
              </h3>
              {(myGroupsQuery.data ?? []).length > 0 && (
                <button
                  onClick={() => {
                    setIsPrivateGroup(true);
                    setCreating(true);
                  }}
                  className="flex items-center gap-1 text-[12px] font-semibold text-muted-foreground hover:text-foreground"
                >
                  <Plus className="h-3 w-3" />
                  New group
                </button>
              )}
            </div>
            {(myGroupsQuery.data ?? []).length === 0 && (
              <button
                onClick={() => {
                  setIsPrivateGroup(true);
                  setCreating(true);
                }}
                className="flex w-full items-center gap-3 rounded-2xl border border-dashed border-border bg-card/60 p-4 text-left transition-colors hover:bg-secondary/40"
              >
                <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-foreground text-background">
                  <Lock className="h-5 w-5" />
                </span>
                <span className="min-w-0 flex-1">
                  <span className="block text-[14px] font-bold">Start a private group</span>
                  <span className="block text-[12px] text-muted-foreground">
                    Invite-only — you hand-pick the members and only they see the feed.
                  </span>
                </span>
                <span className="shrink-0 rounded-full bg-secondary px-3 py-1.5 text-[12px] font-bold">
                  Create
                </span>
              </button>
            )}
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              {(myGroupsQuery.data ?? []).map((g) => {
                const Icon = g.icon;
                const invited = invitedSlugs.has(g.id);
                return (
                  <Link
                    key={g.id}
                    to={`/c/${g.id}`}
                    className="flex items-center gap-3 rounded-2xl border border-border bg-card p-4 transition-transform hover:scale-[1.01]"
                  >
                    <span
                      className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl text-white"
                      style={{
                        backgroundImage: `linear-gradient(135deg, ${g.gradient[0]}, ${g.gradient[1]})`,
                      }}
                    >
                      <Icon className="h-5 w-5" />
                    </span>
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-[14.5px] font-bold">{g.name}</span>
                      <span className="block truncate text-[12px] text-muted-foreground">
                        {g.tagline}
                      </span>
                    </span>
                    <span
                      className={cn(
                        "shrink-0 rounded-full px-2 py-1 text-[9px] font-black uppercase tracking-wide",
                        invited
                          ? "border border-amber-400/50 bg-amber-500/10 text-amber-600 dark:text-amber-400"
                          : "border border-border bg-secondary text-muted-foreground"
                      )}
                    >
                      {invited ? "Invited" : "Private"}
                    </span>
                  </Link>
                );
              })}
            </div>
          </div>
        )}

        {customQuery.isLoading ? (
          <div className="flex justify-center py-10">
            <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
          </div>
        ) : (
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            {all.map((community) => {
              const Icon = community.icon;
              // The Jasper Circle wears the ember glow in the list — white
              // card, warm aura — and says whether the account link opens it.
              const jasperOnly = community.requiresJasperLink === true;
              return (
                <Link
                  key={community.id}
                  to={`/c/${community.id}`}
                  className={cn(
                    "flex items-center gap-3 rounded-2xl border bg-card p-4 transition-transform hover:scale-[1.01]",
                    jasperOnly
                      ? "border-orange-400/45 shadow-[0_12px_34px_rgba(249,115,22,0.16),0_3px_12px_rgba(249,115,22,0.10)]"
                      : "border-border"
                  )}
                >
                  <span
                    className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl text-white"
                    style={{
                      backgroundImage: `linear-gradient(135deg, ${community.gradient[0]}, ${community.gradient[1]})`,
                    }}
                  >
                    <Icon className="h-5 w-5" />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-[14.5px] font-bold">
                      {community.name}
                    </span>
                    <span className="block truncate text-[12px] text-muted-foreground">
                      {community.tagline}
                    </span>
                  </span>
                  {jasperOnly && (
                    <span className="shrink-0 rounded-full border border-orange-400/40 bg-orange-500/10 px-2 py-1 text-[9px] font-black uppercase tracking-wide text-orange-600 dark:text-orange-400">
                      {jasperHasLocalToken() ? "👻 Linked" : "Link to view"}
                    </span>
                  )}
                </Link>
              );
            })}
          </div>
        )}
      </div>

      <Dialog open={creating} onOpenChange={setCreating}>
        <DialogContent className="max-w-sm rounded-3xl">
          <DialogHeader>
            <DialogTitle>{isPrivateGroup ? "New private group" : "New community"}</DialogTitle>
          </DialogHeader>
          <div className="space-y-3">
            <div>
              <p className="mb-1.5 text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
                Name
              </p>
              <Input
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="Trail Runners"
                maxLength={40}
              />
            </div>
            <div>
              <p className="mb-1.5 text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
                Tagline
              </p>
              <Input
                value={tagline}
                onChange={(e) => setTagline(e.target.value)}
                placeholder="Dirt, hills, and long Sundays."
                maxLength={80}
              />
            </div>
            {!isPrivateGroup && (
              <div>
                <p className="mb-1.5 text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
                  Keywords (comma separated)
                </p>
                <Input
                  value={keywords}
                  onChange={(e) => setKeywords(e.target.value)}
                  placeholder="trail, ultra, vert"
                />
                <p className="mt-1 text-[11px] text-muted-foreground">
                  People pick the community when they post — keywords just help
                  older posts that mention these words find their way in.
                </p>
              </div>
            )}
            <button
              type="button"
              onClick={() => setIsPrivateGroup((v) => !v)}
              className={cn(
                "flex w-full items-center gap-3 rounded-2xl border p-3 text-left transition-colors",
                isPrivateGroup ? "border-foreground/50 bg-secondary/60" : "border-border bg-card"
              )}
            >
              <span
                className={cn(
                  "flex h-9 w-9 shrink-0 items-center justify-center rounded-xl",
                  isPrivateGroup ? "bg-foreground text-background" : "bg-secondary text-muted-foreground"
                )}
              >
                {isPrivateGroup ? <Lock className="h-4 w-4" /> : <Globe className="h-4 w-4" />}
              </span>
              <span className="min-w-0 flex-1">
                <span className="block text-[13.5px] font-bold">
                  {isPrivateGroup ? "Private group" : "Public community"}
                </span>
                <span className="block text-[11.5px] leading-snug text-muted-foreground">
                  {isPrivateGroup
                    ? "Invite only — members are hand-picked and only they see the feed."
                    : "Anyone can find it, join it, and post to it."}
                </span>
              </span>
              <span
                className={cn(
                  "relative h-6 w-10 shrink-0 rounded-full transition-colors",
                  isPrivateGroup ? "bg-foreground" : "bg-secondary"
                )}
              >
                <span
                  className={cn(
                    "absolute top-0.5 h-5 w-5 rounded-full bg-background shadow transition-all",
                    isPrivateGroup ? "left-[18px]" : "left-0.5"
                  )}
                />
              </span>
            </button>
            <Button
              className="h-11 w-full rounded-full font-bold"
              disabled={create.isPending || name.trim().length < 2}
              onClick={() => create.mutate()}
            >
              {create.isPending ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : isPrivateGroup ? (
                <Lock className="h-4 w-4" />
              ) : (
                <Plus className="h-4 w-4" />
              )}
              {isPrivateGroup ? "Create private group" : "Create community"}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}
