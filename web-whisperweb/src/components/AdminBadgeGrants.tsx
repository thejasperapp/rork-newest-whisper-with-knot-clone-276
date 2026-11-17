import { useState } from "react";
import { useMutation } from "@tanstack/react-query";
import { Award } from "lucide-react";
import { toast } from "sonner";

import { BACKEND_URL } from "@/lib/billing";

const GRANTABLE = [
  { id: "director", label: "Director" },
  { id: "blogger", label: "Blogger" },
  { id: "recruiter", label: "Recruiter" },
  { id: "trusted", label: "Trusted member" },
] as const;

type GrantableBadge = (typeof GRANTABLE)[number]["id"];

/**
 * Admin badge grants — the earned roles (director / blogger / recruiter /
 * trusted) finally have a real granting path instead of manual SQL. Coach,
 * athlete, and verified stay on the application + annual-fee path.
 */
export function AdminBadgeGrants({ token }: { token: string }) {
  const [username, setUsername] = useState<string>("");
  const [badge, setBadge] = useState<GrantableBadge>("director");

  const grant = useMutation({
    mutationFn: async (give: boolean) => {
      const res = await fetch(`${BACKEND_URL}/admin/badges/grant`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ username: username.trim(), badge, grant: give }),
      });
      const data = (await res.json().catch(() => ({}))) as {
        error?: string;
        username?: string | null;
        granted?: boolean;
      };
      if (!res.ok) {
        const map: Record<string, string> = {
          user_not_found: "No user with that username.",
          forbidden: "Admins and the owner only.",
          invalid_badge: "That badge can't be granted here.",
        };
        throw new Error(map[data.error ?? ""] ?? "Grant failed.");
      }
      return data;
    },
    onSuccess: (data) => {
      toast.success(
        `@${data.username ?? username.trim().replace(/^@/, "")} — ${badge} ${
          data.granted ? "granted" : "removed"
        }.`
      );
    },
    onError: (err) =>
      toast.error(err instanceof Error ? err.message : "Grant failed."),
  });

  if (!token) return null;

  return (
    <section className="mt-10">
      <div className="flex items-center gap-2.5">
        <Award className="h-5 w-5" />
        <h2 className="text-[19px] font-extrabold">Earned roles</h2>
      </div>
      <p className="mt-1 text-[13px] text-muted-foreground">
        Director, Blogger, Recruiter, and Trusted are granted here — never
        sold. Coach, athlete, and verified go through the application queues
        above.
      </p>
      <div className="mt-4 flex flex-wrap items-center gap-2 rounded-2xl border border-border bg-card p-4">
        <input
          value={username}
          onChange={(e) => setUsername(e.target.value)}
          placeholder="@username"
          className="h-10 w-44 rounded-full border border-border bg-background px-4 text-[13.5px] outline-none placeholder:text-muted-foreground/60"
        />
        <select
          value={badge}
          onChange={(e) => setBadge(e.target.value as GrantableBadge)}
          className="h-10 rounded-full border border-border bg-background px-3 text-[13.5px] outline-none"
        >
          {GRANTABLE.map((b) => (
            <option key={b.id} value={b.id}>
              {b.label}
            </option>
          ))}
        </select>
        <button
          onClick={() => grant.mutate(true)}
          disabled={grant.isPending || username.trim().length < 2}
          className="h-10 rounded-full bg-foreground px-5 text-[13.5px] font-bold text-background disabled:opacity-40"
        >
          Grant
        </button>
        <button
          onClick={() => grant.mutate(false)}
          disabled={grant.isPending || username.trim().length < 2}
          className="h-10 rounded-full border border-border px-5 text-[13.5px] font-bold disabled:opacity-40"
        >
          Remove
        </button>
      </div>
    </section>
  );
}
