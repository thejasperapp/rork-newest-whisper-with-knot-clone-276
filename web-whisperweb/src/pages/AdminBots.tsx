import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Bot, Loader2, Pause, Play, Zap } from "lucide-react";
import { toast } from "sonner";

import { Header } from "@/components/Header";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/hooks/useAuth";
import { supabase } from "@/lib/supabase";
import { BACKEND_URL } from "@/lib/billing";
import { cn } from "@/lib/utils";

interface BotConfig {
  paused: boolean;
  intensity: "calm" | "normal" | "lively";
  last_run_at: string | null;
}

interface BotsStatus {
  config: BotConfig | null;
  bots: { username: string; persona: string }[];
}

async function adminToken(): Promise<string> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) throw new Error("Sign in required");
  return token;
}

async function fetchBotsStatus(): Promise<BotsStatus> {
  const token = await adminToken();
  const res = await fetch(`${BACKEND_URL}/bots/status`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (res.status === 403) throw new Error("forbidden");
  if (!res.ok) throw new Error("Couldn't load bot status.");
  return (await res.json()) as BotsStatus;
}

/**
 * Admin control panel for the bot crew — pause/resume, set activity
 * intensity, and trigger an activity wave on demand. Waves also run on a
 * schedule via an external cron hitting POST /bots/run.
 */
export default function AdminBots() {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const [running, setRunning] = useState<boolean>(false);

  const statusQuery = useQuery({
    queryKey: ["admin-bots-status", user?.id],
    queryFn: fetchBotsStatus,
    enabled: !!user,
    retry: false,
  });

  const config = statusQuery.data?.config ?? null;
  const bots = statusQuery.data?.bots ?? [];

  const updateConfig = useMutation({
    mutationFn: async (patch: { paused?: boolean; intensity?: string }) => {
      const token = await adminToken();
      const res = await fetch(`${BACKEND_URL}/bots/config`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify(patch),
      });
      if (!res.ok) throw new Error("Update failed");
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["admin-bots-status"] });
    },
    onError: () => toast.error("Couldn't update bot settings."),
  });

  const runWave = async (): Promise<void> => {
    setRunning(true);
    try {
      const token = await adminToken();
      const res = await fetch(`${BACKEND_URL}/bots/run`, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}` },
      });
      const data = (await res.json()) as {
        ok?: boolean;
        skipped?: string;
        postsCreated?: number;
        likesGiven?: number;
        commentsGiven?: number;
        error?: string;
      };
      if (data.skipped === "paused") {
        toast("Bots are paused — resume them first.");
      } else if (data.ok) {
        toast.success(
          `Wave complete: ${data.postsCreated ?? 0} posts, ${data.likesGiven ?? 0} likes, ${data.commentsGiven ?? 0} comments`
        );
      } else {
        toast.error(data.error === "no_bots_seeded"
          ? "No bots found — run supabase/bots.sql first."
          : "Wave failed.");
      }
      void queryClient.invalidateQueries({ queryKey: ["admin-bots-status"] });
    } catch {
      toast.error("Couldn't run the wave.");
    } finally {
      setRunning(false);
    }
  };

  if (statusQuery.isError) {
    return (
      <div className="min-h-screen">
        <Header title="Bots" />
        <div className="px-4 py-16 text-center text-[14px] text-muted-foreground">
          {(statusQuery.error as Error).message === "forbidden"
            ? "Your account doesn't have admin permissions."
            : "Couldn't load bot status. Is the backend deployed?"}
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen">
      <Header title="Bot crew" />

      <div className="space-y-5 px-4 pb-16 pt-4">
        {/* Status card */}
        <div className="rounded-3xl border border-border bg-card p-5">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <span
                className={cn(
                  "flex h-10 w-10 items-center justify-center rounded-2xl",
                  config?.paused
                    ? "bg-secondary text-muted-foreground"
                    : "bg-emerald-500/15 text-emerald-500"
                )}
              >
                <Bot className="h-5 w-5" />
              </span>
              <div>
                <p className="text-[15px] font-bold">
                  {config?.paused ? "Paused" : "Active"} · {bots.length} bots
                </p>
                <p className="text-[12px] text-muted-foreground">
                  {config?.last_run_at
                    ? `Last wave ${new Date(config.last_run_at).toLocaleString()}`
                    : "No waves run yet"}
                </p>
              </div>
            </div>
            <Button
              variant={config?.paused ? "default" : "outline"}
              className="rounded-full"
              disabled={updateConfig.isPending || !config}
              onClick={() => updateConfig.mutate({ paused: !config?.paused })}
            >
              {config?.paused ? (
                <>
                  <Play className="h-4 w-4" /> Resume
                </>
              ) : (
                <>
                  <Pause className="h-4 w-4" /> Pause
                </>
              )}
            </Button>
          </div>

          {/* Intensity */}
          <div className="mt-4">
            <p className="mb-2 text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
              Activity level
            </p>
            <div className="flex gap-2">
              {(["calm", "normal", "lively"] as const).map((level) => (
                <button
                  key={level}
                  onClick={() => updateConfig.mutate({ intensity: level })}
                  className={cn(
                    "flex-1 rounded-full border px-3 py-2 text-[13px] font-semibold capitalize transition-colors",
                    config?.intensity === level
                      ? "border-foreground bg-foreground text-background"
                      : "border-border text-muted-foreground hover:border-foreground/30"
                  )}
                >
                  {level}
                </button>
              ))}
            </div>
          </div>

          <Button
            className="mt-4 h-12 w-full rounded-full font-bold"
            disabled={running}
            onClick={runWave}
          >
            {running ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              <Zap className="h-4 w-4" />
            )}
            Run a wave now
          </Button>
          <p className="mt-2.5 text-[11.5px] leading-relaxed text-muted-foreground">
            A wave makes a few bots post (real sports headlines with sources,
            training tips, motivation) and several more engage with recent
            posts. For automatic activity, point an external scheduler (e.g.
            cron-job.org) at POST {BACKEND_URL}/bots/run every 2–3 hours with
            the broadcast secret.
          </p>
        </div>

        {/* Roster */}
        <div>
          <p className="mb-2 px-1 text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
            Roster
          </p>
          <div className="overflow-hidden rounded-3xl border border-border bg-card">
            {statusQuery.isLoading ? (
              <div className="flex justify-center py-10">
                <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
              </div>
            ) : bots.length === 0 ? (
              <p className="px-5 py-8 text-center text-[13.5px] text-muted-foreground">
                No bots seeded yet — run supabase/bots.sql in the SQL editor.
              </p>
            ) : (
              bots.map((b, i) => (
                <div
                  key={b.username}
                  className={cn(
                    "flex items-center justify-between px-5 py-3",
                    i > 0 && "border-t border-border/60"
                  )}
                >
                  <span className="text-[14px] font-semibold">@{b.username}</span>
                  <span className="rounded-full bg-secondary px-2.5 py-1 text-[11px] font-semibold capitalize text-muted-foreground">
                    {b.persona}
                  </span>
                </div>
              ))
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
