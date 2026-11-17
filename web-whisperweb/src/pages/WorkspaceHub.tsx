import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import {
  ArrowRight,
  ArrowUpRight,
  BarChart3,
  BriefcaseBusiness,
  CalendarDays,
  Clapperboard,
  Dumbbell,
  Handshake,
  NotebookPen,
  UserCheck,
  Users,
  Video,
} from "lucide-react";

import { WorkspaceSearchButton } from '@/components/WorkspaceSearchButton';
import { BusinessPlusMark } from "@/components/BusinessPlusMark";

import { useAuth } from "@/hooks/useAuth";
import { useMyBadge } from "@/hooks/useMyBadge";
import { fetchMyBusinessPlus } from "@/lib/businessPlus";
import { openPortal, type Portal } from "@/lib/portal";

const ACCENT = "#0E9F76";

/** Keep ?portal=workspace on internal links when we're not on the subdomain. */
const KEEP_WS_PARAM: boolean =
  typeof window !== "undefined" &&
  !/^workspace\./.test(window.location.hostname.toLowerCase());

function wsHref(path: string): string {
  return KEEP_WS_PARAM ? `${path}?portal=workspace` : path;
}

interface StudioDoor {
  id: string;
  label: string;
  hint: string;
  icon: typeof Video;
  accent: string;
  /** Opens a standalone portal… */
  portal?: Portal;
  /** …or navigates inside the workspace. */
  path?: string;
}

/**
 * Workspace home — workspace.mydailywhisper.com. ONE desk fronting every
 * tool Whisper gives its businesses, coaches, creators, athletes, and
 * recruiters: meetings for everyone, the Notebook, the calendar, and
 * role-gated doors into each studio. Every door opens in a NEW TAB — the
 * desk stays put, like an app launcher.
 */
export default function WorkspaceHub() {
  const { user, profile } = useAuth();
  const badge = useMyBadge();
  const isVerified = badge !== "none";

  // Business+ door — shows for plan owners AND their team members.
  const bizPlusQuery = useQuery({
    queryKey: ["my-business-plus", user?.id],
    queryFn: () => fetchMyBusinessPlus(user!.id),
    enabled: !!user?.id,
    staleTime: 0,
    gcTime: 0,
    refetchOnWindowFocus: true,
  });

  const studios: StudioDoor[] = [];
  if (profile?.is_coach) {
    studios.push({
      id: "coach",
      label: "Coach Studio",
      hint: "Clients, plans & earnings",
      icon: Dumbbell,
      accent: "#E8853D",
      portal: "coach",
    });
  }
  if (profile?.is_recruiter) {
    studios.push({
      id: "recruiter",
      label: "Recruiter HQ",
      hint: "Pipeline, inbox & insights",
      icon: UserCheck,
      accent: "#7059E8",
      portal: "recruiter",
    });
  }
  studios.push({
    id: "business",
    label: "Business Suite",
    hint: "Ads, wallet & analytics",
    icon: BriefcaseBusiness,
    accent: "#5A5FE8",
    portal: "business",
  });
  if (bizPlusQuery.data) {
    studios.push({
      id: "business-plus",
      label: `${bizPlusQuery.data.business.company_name?.trim() || "Business"}+`,
      hint: "Team, hiring, HQ & calendar",
      icon: BusinessPlusMark,
      accent: "#7A7FF0",
      path: "/teams",
    });
  }
  if (isVerified) {
    studios.push({
      id: "creator",
      label: "Creator Studio",
      hint: "Analytics, WPP & articles",
      icon: BarChart3,
      accent: "#0E9F76",
      path: "/dashboard",
    });
  }
  if (profile?.is_director) {
    studios.push({
      id: "director",
      label: "Whisper Studio",
      hint: "Films & premieres",
      icon: Clapperboard,
      accent: "#B04ADB",
      path: "/director",
    });
  }
  if (badge === "moderator" || badge === "admin" || badge === "owner") {
    studios.push({
      id: "collabs",
      label: "Collab projects",
      hint: "Cross-team productions",
      icon: Handshake,
      accent: "#D5484F",
      path: "/collabs",
    });
  }

  const firstName =
    (profile?.display_name || profile?.username || "there").split(" ")[0];

  return (
    <div className="mx-auto w-full max-w-5xl px-4 py-8 lg:py-10">
      <div className="mb-5"><WorkspaceSearchButton /></div>
      {/* Greeting */}
      <p
        className="text-[11px] font-black uppercase tracking-[0.2em]"
        style={{ color: ACCENT }}
      >
        Workspace
      </p>
      <h1 className="mt-1 font-display text-[26px] font-extrabold leading-tight sm:text-[32px]">
        Welcome back, {firstName}.
      </h1>
      <p className="mt-1.5 max-w-lg text-[13.5px] leading-relaxed text-muted-foreground">
        Every tool Whisper gives you — one desk. Meetings and Jasper
        come with every role: businesses, coaches, creators, athletes, and
        recruiters.
      </p>

      <Link to={wsHref('/work')} className="mt-6 flex items-center justify-between gap-5 rounded-3xl border bg-foreground p-6 text-background transition-opacity hover:opacity-90"><div><p className="text-xs font-medium uppercase tracking-widest opacity-60">Move work forward</p><h2 className="mt-2 text-xl font-semibold">Decisions. Deliveries. Approvals.</h2><p className="mt-2 text-sm opacity-75">One desk for work that needs a next step.</p></div><ArrowRight className="h-6 w-6 shrink-0" /></Link>
      {/* Meetings — the headline tool, for everyone. */}
      <div
        className="mt-6 overflow-hidden rounded-[24px] border p-5 sm:p-6"
        style={{
          borderColor: `${ACCENT}40`,
          background: `linear-gradient(135deg, ${ACCENT}14, transparent 60%)`,
        }}
      >
        <div className="flex items-center gap-2">
          <span
            className="flex h-9 w-9 items-center justify-center rounded-xl text-white"
            style={{ background: `linear-gradient(135deg, ${ACCENT}, #0B8163)` }}
          >
            <Video className="h-4.5 w-4.5" />
          </span>
          <div>
            <p className="text-[15.5px] font-extrabold leading-tight">
              Meetings, the Whisper way
            </p>
            <p className="text-[11.5px] text-muted-foreground">
              Start, join and schedule in one place. Find notes and recordings in your Meetings library.
            </p>
          </div>
        </div>
        <Link to={wsHref("/meetings")} className="mt-4 inline-flex min-h-11 items-center gap-3 rounded-full bg-foreground px-5 text-sm font-semibold text-background">Open Whisper Meet<ArrowRight className="h-4 w-4" /></Link>
      </div>

      <Link to={wsHref('/teams')} className="mt-4 flex items-center gap-3 rounded-[20px] border border-border bg-card p-4 transition-colors hover:bg-secondary/40"><Users className="h-6 w-6 shrink-0" /><span className="flex-1"><span className="block text-sm font-semibold">Teams</span><span className="mt-1 block text-xs text-muted-foreground">Set up a team, add people or update roles</span></span><ArrowUpRight className="h-4 w-4" /></Link>
      {/* Universal tools */}
      <div className="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-2">
        {[
          {
            id: "notebook",
            label: "Meeting library",
            hint: "Notes, recordings & reviewed follow-ups",
            icon: NotebookPen,
            path: "/notebook",
          },
          {
            id: "calendar",
            label: "Calendar",
            hint: "Events, RSVPs & planning",
            icon: CalendarDays,
            path: "/calendar",
          },
        ].map((t) => (
          <Link
            key={t.id}
            to={wsHref(t.path)}
            className="group flex items-center gap-3 rounded-[20px] border border-border/60 bg-card p-4 transition-colors hover:bg-secondary/40"
          >
            <span
              className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl"
              style={{ backgroundColor: `${ACCENT}16`, color: ACCENT }}
            >
              <t.icon className="h-5 w-5" />
            </span>
            <span className="min-w-0 flex-1">
              <span className="block text-[14px] font-extrabold">{t.label}</span>
              <span className="block truncate text-[11px] text-muted-foreground">
                {t.hint}
              </span>
            </span>
            <ArrowUpRight className="h-4 w-4 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5 group-hover:-translate-y-0.5" />
          </Link>
        ))}
      </div>

      {/* Studios — role-gated doors. */}
      <p className="mt-8 text-[11px] font-black uppercase tracking-[0.18em] text-muted-foreground">
        Your studios
      </p>
      <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {studios.map((s) => {
          const inner = (
            <>
              <span
                className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl text-white"
                style={{
                  background: `linear-gradient(135deg, ${s.accent}, ${s.accent}c9)`,
                }}
              >
                <s.icon className="h-5 w-5" />
              </span>
              <span className="min-w-0 flex-1">
                <span className="block text-[14.5px] font-extrabold">
                  {s.label}
                </span>
                <span className="block truncate text-[11px] text-muted-foreground">
                  {s.hint}
                </span>
              </span>
              <ArrowUpRight className="h-4 w-4 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5 group-hover:-translate-y-0.5" />
            </>
          );
          if (s.portal) {
            return (
              <button
                key={s.id}
                onClick={() => void openPortal(s.portal as Portal, { newTab: true })}
                className="group flex items-center gap-3 rounded-[20px] border border-border/60 bg-card p-4 text-left transition-colors hover:bg-secondary/40"
              >
                {inner}
              </button>
            );
          }
          return (
            <a
              key={s.id}
              href={wsHref(s.path ?? "/")}
              target="_blank"
              rel="noopener noreferrer"
              className="group flex items-center gap-3 rounded-[20px] border border-border/60 bg-card p-4 transition-colors hover:bg-secondary/40"
            >
              {inner}
            </a>
          );
        })}
      </div>

      <p className="mt-8 text-[11px] leading-relaxed text-muted-foreground">
        This desk lives at workspace.mydailywhisper.com — same account, same
        data, its own front door. Every tool opens in its own tab so the desk
        stays put; studios open their dedicated dashboards, meetings run on
        Whisper Meet.
      </p>
    </div>
  );
}
