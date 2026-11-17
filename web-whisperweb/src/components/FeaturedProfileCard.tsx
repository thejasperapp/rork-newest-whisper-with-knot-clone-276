import { useState } from "react";
import { Link } from "react-router-dom";
import {
  ArrowRight,
  ArrowUpRight,
  CalendarCheck,
  ChevronDown,
  Dumbbell,
  Mail,
  MessageCircle,
  Quote,
  Sparkles,
  Users,
} from "lucide-react";

import { Button } from "@/components/ui/button";
import { MeetingRequestModal } from "@/components/MeetingRequestModal";
import { useAuth } from "@/hooks/useAuth";
import type {
  FeaturedActionButton,
  FeaturedProfile,
} from "@/lib/featured";

const TIER_COLORS: Record<number, string> = {
  1: "#ef4444",
  2: "#eab308",
  3: "#22c55e",
};

function TierDot({ tier, size = 10 }: { tier: number; size?: number }) {
  const color = TIER_COLORS[tier] ?? TIER_COLORS[1];
  return (
    <span
      className="inline-block shrink-0 rounded-full"
      style={{
        width: size,
        height: size,
        backgroundColor: color,
        boxShadow: `0 0 0 3px ${color}22`,
      }}
      aria-label={`Tier ${tier}`}
    />
  );
}

function ProfessionalRole({ kind }: { kind: FeaturedProfile["kind"] }) {
  return <p className="mt-1 text-sm text-muted-foreground">{kind === "coach" ? "Coach" : kind === "recruiter" ? "Recruiter" : "Creator"}</p>;
}

const HIGHLIGHT_ICONS = [
  <Dumbbell key="d" className="h-4 w-4" />,
  <CalendarCheck key="c" className="h-4 w-4" />,
  <MessageCircle key="m" className="h-4 w-4" />,
  <Users key="u" className="h-4 w-4" />,
];

interface FeaturedProfileCardProps {
  profile: FeaturedProfile;
  /** Hide the testimonial block (e.g. compact admin preview). */
  hideTestimonials?: boolean;
}

/**
 * Renders a single CTA button from the typed action_buttons list. The first
 * button in the list is treated as the primary (filled) action; subsequent
 * ones are outline. Calendar/email resolve client-side so visitors go to
 * signup instead of a dead in-app link.
 */
function ActionButton({
  button,
  profile,
  primary,
  signedIn,
  onCalendarClick,
}: {
  button: FeaturedActionButton;
  profile: FeaturedProfile;
  primary: boolean;
  signedIn: boolean;
  onCalendarClick: (profile: FeaturedProfile) => void;
}) {
  const baseClass = primary
    ? "h-12 rounded-full px-6 text-[15px] font-semibold"
    : "h-12 rounded-full px-6 text-[15px] font-semibold border border-border bg-background text-foreground hover:bg-secondary";

  const iconFor = (type: FeaturedActionButton["type"]) => {
    switch (type) {
      case "email":
        return <Mail className="ml-1 h-4 w-4" />;
      case "calendar":
        return <CalendarCheck className="ml-1 h-4 w-4" />;
      case "link":
        return <ArrowUpRight className="ml-1 h-4 w-4" />;
      default:
        return <ArrowRight className="ml-1 h-4 w-4" />;
    }
  };

  if (button.type === "link") {
    const href = button.href.trim();
    if (!href) return null;
    return (
      <Button className={baseClass} asChild>
        <a href={href} target="_blank" rel="noopener noreferrer">
          {button.label}
          {iconFor("link")}
        </a>
      </Button>
    );
  }

  if (button.type === "email") {
    const email = button.href.trim();
    if (!email) return null;
    return (
      <Button className={baseClass} asChild>
        <a href={`mailto:${email}`}>
          {button.label}
          {iconFor("email")}
        </a>
      </Button>
    );
  }

  if (button.type === "calendar") {
    // The calendar is never exposed to the requester. The button opens a
    // meeting-request modal — the recruiter reviews and emails a Google Meet
    // invite on approval. Falls back to signup if the recruiter's account
    // isn't linked yet (we need a recruiter_id to route the request).
    if (!profile.user_id) {
      return (
        <Button className={baseClass} asChild>
          <Link to="/auth?mode=signup">
            {button.label}
            {iconFor("calendar")}
          </Link>
        </Button>
      );
    }
    return (
      <Button
        className={baseClass}
        onClick={() => onCalendarClick(profile)}
      >
        {button.label}
        {iconFor("calendar")}
      </Button>
    );
  }

  // `profile` — link to the in-app profile when signed in and a username is
  // linked; otherwise send visitors to signup (unlinked goes to search).
  const to = signedIn
    ? profile.username
      ? `/u/${profile.username}`
      : "/search"
    : "/auth?mode=signup";
  return (
    <Button className={baseClass} asChild>
      <Link to={to}>
        {button.label}
        {iconFor("profile")}
      </Link>
    </Button>
  );
}

/**
 * The "Hudson" spotlight template: photo panel + details, optional client
 * testimonials below. Renders identically for coaches, athletes, creators,
 * and recruiters — only the seal, tier pill, and CTA wording change.
 *
 * On mobile, the card starts collapsed showing just the photo, name, and
 * first paragraph. Tapping "View full profile" expands everything.
 */
export function FeaturedProfileCard({
  profile,
  hideTestimonials = false,
}: FeaturedProfileCardProps) {
  const { session } = useAuth();
  const [expanded, setExpanded] = useState(false);
  const [meetingOpen, setMeetingOpen] = useState(false);
  const signedIn = !!session;

  // Build the final button list: typed action_buttons first, then a legacy
  // fallback synthesized from cta_label/cta_url so existing rows keep working.
  const buttons: FeaturedActionButton[] =
    profile.action_buttons.length > 0
      ? profile.action_buttons
      : (() => {
          const label = profile.cta_label?.trim();
          if (!label) return [];
          return [
            {
              label,
              type: profile.cta_url?.trim() ? "link" : "profile",
              href: profile.cta_url?.trim() ?? "",
            },
          ];
        })();

  const testimonialHeading =
    profile.kind === "coach"
      ? `What ${profile.name}'s clients say`
      : `What people say about ${profile.name}`;

  return (
    <div>
      <div className="overflow-hidden rounded-[24px] border border-border bg-card sm:rounded-[32px]">
        <div className="grid lg:grid-cols-[420px_1fr]">
          {/* Photo — portrait on mobile (4:5) so full uploads aren't cropped */}
          <div className="relative aspect-[4/5] w-full bg-secondary sm:aspect-auto sm:h-[380px] lg:h-auto">
            {profile.photo_url ? (
              <img
                src={profile.photo_url}
                alt={`${profile.name} — featured ${profile.kind}`}
                className="absolute inset-0 h-full w-full object-cover object-top"
              />
            ) : (
              <div className="absolute inset-0 flex items-center justify-center text-muted-foreground">
                <Sparkles className="h-10 w-10" />
              </div>
            )}
          </div>

          {/* Details */}
          <div className="flex flex-col justify-center p-5 sm:p-10">
            <div className="flex items-center gap-2.5">
              <h2 className="font-display text-[24px] font-extrabold tracking-tight sm:text-[32px] lg:text-[40px]">
                {profile.name}
              </h2>
            </div>
            <ProfessionalRole kind={profile.kind} />

            <div className="mt-3 flex flex-wrap items-center gap-1.5 sm:gap-2">
              {profile.tier !== null && (
                <span className="inline-flex items-center gap-2 rounded-full border border-border bg-background px-3.5 py-1.5 text-[13.5px] font-semibold">
                  <TierDot tier={profile.tier} />
                  Tier {profile.tier}
                  {profile.discipline ? ` · ${profile.discipline}` : ""}
                </span>
              )}
              {profile.tier === null && profile.discipline && (
                <span className="rounded-full border border-border bg-background px-3.5 py-1.5 text-[13.5px] font-semibold">
                  {profile.discipline}
                </span>
              )}
              {profile.chips.map((chip) => (
                <span
                  key={chip}
                  className="rounded-full border border-border bg-background px-3.5 py-1.5 text-[13.5px] font-semibold text-muted-foreground"
                >
                  {chip}
                </span>
              ))}
              {profile.username && (
                <span className="rounded-full border border-border bg-background px-3.5 py-1.5 text-[13.5px] font-semibold text-muted-foreground">
                  @{profile.username}
                </span>
              )}
            </div>

            {/* First paragraph always visible */}
            {profile.paragraphs[0] && (
              <p className="mt-5 text-[16px] leading-relaxed text-muted-foreground">
                {profile.paragraphs[0]}
              </p>
            )}

            {/* Remaining content — always visible on desktop, collapsible on mobile */}
            <div
              className={
                expanded
                  ? "mt-0"
                  : "hidden lg:mt-0 lg:block"
              }
            >
              {profile.paragraphs.slice(1).map((paragraph, index) => (
                <p
                  key={`${profile.id}-p-rest-${index}`}
                  className="mt-3 text-[16px] leading-relaxed text-muted-foreground"
                >
                  {paragraph}
                </p>
              ))}

              {profile.highlights.length > 0 && (
                <div className="mt-5 grid gap-2 sm:grid-cols-2 lg:mt-6 lg:gap-2.5">
                  {profile.highlights.map((text, index) => (
                    <div
                      key={`${profile.id}-h-${index}`}
                      className="flex items-center gap-2.5 rounded-xl bg-secondary px-3.5 py-2.5 text-[13.5px] font-medium"
                    >
                      <span className="text-foreground/70">
                        {HIGHLIGHT_ICONS[index % HIGHLIGHT_ICONS.length]}
                      </span>
                      {text}
                    </div>
                  ))}
                </div>
              )}

              {buttons.length > 0 && (
                <div className="mt-6 flex flex-wrap gap-3 lg:mt-7">
                  {buttons.map((button, index) => (
                    <ActionButton
                      key={`${profile.id}-btn-${index}-${button.type}`}
                      button={button}
                      profile={profile}
                      primary={index === 0}
                      signedIn={signedIn}
                      onCalendarClick={() => setMeetingOpen(true)}
                    />
                  ))}
                </div>
              )}
            </div>

            {/* Mobile expand/collapse toggle */}
            <button
              onClick={() => setExpanded((v) => !v)}
              className="mt-4 flex items-center justify-center gap-1.5 rounded-full bg-secondary py-2.5 text-[14px] font-semibold text-foreground/80 transition-colors hover:bg-secondary/80 lg:hidden"
              aria-expanded={expanded}
            >
              {expanded ? "Show less" : "View full profile"}
              <ChevronDown
                className={`h-4 w-4 transition-transform duration-200 ${
                  expanded ? "rotate-180" : ""
                }`}
              />
            </button>
          </div>
        </div>
      </div>

      <MeetingRequestModal
        open={meetingOpen}
        profile={profile}
        onClose={() => setMeetingOpen(false)}
      />

      {/* Testimonials — hidden on mobile when collapsed */}
      {!hideTestimonials && profile.testimonials.length > 0 && (
        <div
          className={
            expanded
              ? "mt-8 sm:mt-10"
              : "hidden mt-8 sm:mt-10 lg:block"
          }
        >
          <h2 className="text-center font-display text-[22px] font-extrabold sm:text-[30px]">
            {testimonialHeading}
          </h2>
          <p className="mx-auto mt-2 max-w-xl text-center text-[13.5px] text-muted-foreground sm:text-[14.5px]">
            Early check-in feedback — results verified through in-app progress
            tracking.
          </p>
          <div className="mt-6 grid gap-3 sm:mt-7 md:grid-cols-3">
            {profile.testimonials.map((t) => (
              <div
                key={`${profile.id}-${t.name}-${t.quote.slice(0, 16)}`}
                className="flex flex-col rounded-[20px] border border-border bg-card p-5 sm:rounded-[24px] sm:p-6"
              >
                <Quote className="h-5 w-5 text-muted-foreground" />
                <p className="mt-3 flex-1 text-[14.5px] leading-relaxed text-foreground/90">
                  {t.quote}
                </p>
                <div className="mt-5 flex items-center justify-between gap-2">
                  <span className="text-[13.5px] font-bold">{t.name}</span>
                  {t.result && (
                    <span className="rounded-full bg-secondary px-2.5 py-1 text-[11px] font-bold text-foreground/75">
                      {t.result}
                    </span>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
