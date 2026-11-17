import { Link } from "react-router-dom";
import {
  ChevronRight,
  Lock,
  Presentation,
  Sparkles,
} from "lucide-react";

import PublicNav from "@/components/PublicNav";
import PublicFooter from "@/components/PublicFooter";
import { Reveal } from "@/components/Reveal";
import { useAuth } from "@/hooks/useAuth";
import { useMyBadge } from "@/hooks/useMyBadge";
import { PITCH_AUDIENCES, canOpenPitchMode } from "@/lib/pitch";

/**
 * Pitch Mode hub — a public site page (linked from the public nav under
 * "Pitch Mode") that hosts interactive presentation decks for prospect
 * meetings. Moderator+ and recruiters can open it; each card opens an
 * interactive audience-specific deck that uses the real product views
 * with clearly-marked sample data.
 */
export default function Pitch() {
  const badge = useMyBadge();
  const { profile } = useAuth();
  const isRecruiter = !!profile?.is_recruiter;

  if (!canOpenPitchMode(badge, isRecruiter)) {
    return (
      <div className="min-h-screen">
        <PublicNav />
        <div className="mx-auto flex max-w-md flex-col items-center gap-3 px-6 pb-20 pt-32 text-center">
          <span className="flex h-14 w-14 items-center justify-center rounded-2xl bg-secondary">
            <Lock className="h-6 w-6 text-muted-foreground" />
          </span>
          <p className="text-lg font-bold">Team only</p>
          <p className="max-w-xs text-sm text-muted-foreground">
            Pitch Mode is reserved for Whisper moderators, admins, the
            founder, and recruiters. Sign in with a team or recruiter
            account to walk prospects through live decks.
          </p>
          <Link
            to="/auth"
            className="mt-2 rounded-full bg-foreground px-5 py-2.5 text-sm font-bold text-background transition-transform active:scale-95"
          >
            Sign in
          </Link>
        </div>
        <PublicFooter />
      </div>
    );
  }

  return (
    <div className="min-h-screen">
      <PublicNav />
      <div className="mx-auto max-w-2xl px-4 pb-16 pt-24">
        <Reveal variant="up">
          <div className="rounded-[24px] bg-foreground p-6 text-background sm:p-8">
            <p className="flex items-center gap-2 text-[11px] font-bold uppercase tracking-wider opacity-70">
              <Presentation className="h-4 w-4" /> Internal · Mod+
            </p>
            <h1 className="mt-2 text-2xl font-extrabold tracking-tight sm:text-3xl">
              Walk any prospect through Whisper, live.
            </h1>
            <p className="mt-2 text-sm leading-relaxed opacity-80 sm:text-base">
              Each deck uses the product's real views with clearly-marked
              sample data — every card, slider, pipeline stage, and payment
              ledger is clickable so you can demo the exact experience in a
              meeting. No data leaves your screen.
            </p>
            <p className="mt-3 flex items-center gap-1.5 text-[12px] opacity-60">
              <Sparkles className="h-3.5 w-3.5" />
              {PITCH_AUDIENCES.length} audience decks · updated as the product ships
            </p>
          </div>
        </Reveal>

        <div className="mt-6 space-y-2.5">
          {PITCH_AUDIENCES.map((a, i) => (
            <Reveal key={a.id} variant="up" threshold={0.15}>
              <Link
                to={`/pitch/${a.id}`}
                className="group flex items-center gap-3.5 rounded-[20px] border border-border bg-card p-4 shadow-sm transition-all hover:border-foreground/25 hover:shadow-md active:scale-[0.99]"
                style={{ transitionDelay: `${i * 40}ms` }}
              >
                <span className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-secondary transition-colors group-hover:bg-foreground group-hover:text-background">
                  <a.icon className="h-5.5 w-5.5" />
                </span>
                <div className="min-w-0 flex-1">
                  <p className="text-[15px] font-bold">{a.title}</p>
                  <p className="text-xs font-medium text-foreground/70">{a.tagline}</p>
                  <p className="mt-0.5 line-clamp-2 text-xs text-muted-foreground">
                    {a.blurb}
                  </p>
                </div>
                <ChevronRight className="h-5 w-5 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5" />
              </Link>
            </Reveal>
          ))}
        </div>
      </div>
      <PublicFooter />
    </div>
  );
}
