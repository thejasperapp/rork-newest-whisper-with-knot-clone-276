import { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import {
  ArrowRight,
  BadgeCheck,
  BriefcaseBusiness,
  CheckCircle2,
  Compass,
  Handshake,
  HeartHandshake,
  Search,
  ShieldCheck,
  Sparkles,
  UserRoundPlus,
  UsersRound,
} from "lucide-react";

import { UserRow } from "@/components/FollowListDialog";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { useAuth } from "@/hooks/useAuth";
import { fetchSuggestions } from "@/lib/api";
import { COMMUNITIES } from "@/lib/communities";
import {
  submitVerificationRequest,
  VERIFICATION_CATEGORIES,
} from "@/lib/applications";
import { toast } from "sonner";
import type { EmberFeature, EmberFeatureKind } from "@/lib/emberBrain";
import { cn } from "@/lib/utils";

/**
 * Deterministic, in-chat feature cards for Ember. These are real app entry
 * points — not a list of fake answers — so phrases such as "find people for
 * me", "how do I get verified", or "find a sponsor" always turn into the
 * appropriate Whisper flow. The intent router in emberBrain recognizes 50+
 * natural phrasings across these nine cards.
 */

const FEATURE_ICON: Record<EmberFeatureKind, React.ReactNode> = {
  people: <UsersRound className="h-4 w-4" />,
  verification: <BadgeCheck className="h-4 w-4" />,
  profile: <UserRoundPlus className="h-4 w-4" />,
  communities: <Compass className="h-4 w-4" />,
  brands: <BriefcaseBusiness className="h-4 w-4" />,
  coaching: <HeartHandshake className="h-4 w-4" />,
  recruiting: <Search className="h-4 w-4" />,
  moderation: <ShieldCheck className="h-4 w-4" />,
  collaboration: <Handshake className="h-4 w-4" />,
};

function CardShell({
  feature,
  children,
}: {
  feature: EmberFeature;
  children: React.ReactNode;
}) {
  return (
    <div className="overflow-hidden rounded-2xl border border-border bg-card">
      <div className="flex items-center gap-2 border-b border-border px-3.5 py-2.5">
        <span className="flex h-7 w-7 items-center justify-center rounded-full bg-foreground text-background">
          {FEATURE_ICON[feature.kind]}
        </span>
        <div className="min-w-0">
          <p className="text-[12px] font-extrabold leading-tight">{feature.title}</p>
          <p className="text-[10.5px] leading-snug text-muted-foreground">{feature.subtitle}</p>
        </div>
      </div>
      {children}
    </div>
  );
}

function FullButton({
  to,
  children,
  dark = true,
}: {
  to: string;
  children: React.ReactNode;
  dark?: boolean;
}) {
  return (
    <Link
      to={to}
      className={cn(
        "flex w-full items-center justify-center gap-1.5 rounded-full py-2.5 text-sm font-bold transition-transform active:scale-[0.98]",
        dark
          ? "bg-foreground text-background"
          : "border border-border bg-card text-foreground hover:bg-secondary"
      )}
    >
      {children}
      <ArrowRight className="h-3.5 w-3.5" />
    </Link>
  );
}

function PeopleCard({ feature }: { feature: EmberFeature }) {
  const { user } = useAuth();
  const people = useQuery({
    queryKey: ["ember-suggestions", user?.id],
    queryFn: () => fetchSuggestions(user!.id),
    enabled: !!user,
  });

  return (
    <CardShell feature={feature}>
      <div className="divide-y divide-border px-3.5 py-1">
        {people.isLoading && (
          <p className="py-5 text-center text-xs text-muted-foreground">
            Finding your people…
          </p>
        )}
        {(people.data ?? []).slice(0, 3).map((person) => (
          <UserRow key={person.userId} person={person} />
        ))}
        {!people.isLoading && (people.data ?? []).length === 0 && (
          <p className="py-5 text-center text-xs text-muted-foreground">
            Your next suggestions will appear as people join your interests.
          </p>
        )}
      </div>
      <div className="border-t border-border p-2.5">
        <FullButton to="/search">
          <UsersRound className="h-3.5 w-3.5" />
          Explore more people
        </FullButton>
      </div>
    </CardShell>
  );
}

function VerificationCard({ feature }: { feature: EmberFeature }) {
  const { user, profile } = useAuth();
  const [chosen, setChosen] = useState<"verified" | "coach" | null>(null);
  const [open, setOpen] = useState<boolean>(false);
  const [fullName, setFullName] = useState<string>(profile?.display_name ?? "");
  const [category, setCategory] = useState<string>(VERIFICATION_CATEGORIES[0]?.id ?? "Digital creator");
  const [reason, setReason] = useState<string>("");
  const [links, setLinks] = useState<string>("");
  const [followers, setFollowers] = useState<string>("");
  const [submitting, setSubmitting] = useState<boolean>(false);
  const options: { id: "verified" | "coach"; label: string; detail: string }[] = [
    { id: "verified", label: "Creator", detail: "Verified check + your niche" },
    { id: "coach", label: "Coach", detail: "Clients + programs" },
  ];

  return (
    <CardShell feature={feature}>
      <div className="grid grid-cols-2 gap-1.5 px-3.5 pt-3">
        {options.map((option) => (
          <button
            key={option.id}
            onClick={() => setChosen(option.id)}
            className={cn(
              "rounded-xl border px-2 py-2 text-left transition-colors",
              chosen === option.id
                ? "border-foreground bg-foreground text-background"
                : "border-border bg-background hover:bg-secondary"
            )}
          >
            <span className="block text-[12px] font-bold">{option.label}</span>
            <span
              className={cn(
                "mt-0.5 block text-[10px] leading-snug",
                chosen === option.id ? "text-background/70" : "text-muted-foreground"
              )}
            >
              {option.detail}
            </span>
          </button>
        ))}
      </div>
      <div className="p-3.5">
        {chosen === "coach" ? (
          <FullButton to={`/apply/${chosen}`}>
            <BadgeCheck className="h-3.5 w-3.5" />
            Start {chosen} application
          </FullButton>
        ) : (
          <button
            type="button"
            onClick={() => setOpen(true)}
            className="flex w-full items-center justify-center gap-1.5 rounded-full bg-foreground py-2.5 text-sm font-bold text-background transition-transform active:scale-[0.98]"
          >
            <BadgeCheck className="h-3.5 w-3.5" />
            Apply for verification here
            <ArrowRight className="h-3.5 w-3.5" />
          </button>
        )}
        <p className="mt-2 text-center text-[10.5px] text-muted-foreground">
          Every application is reviewed by a real person.
        </p>
      </div>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="no-scrollbar max-h-[88dvh] max-w-md overflow-y-auto rounded-[28px] p-0">
          <DialogHeader className="border-b border-border px-5 pb-4 pt-5 text-left">
            <DialogTitle className="flex items-center gap-2 text-[18px] font-extrabold">
              <span className="flex h-8 w-8 items-center justify-center rounded-full bg-foreground text-background"><BadgeCheck className="h-4 w-4" /></span>
              Verification application
            </DialogTitle>
            <DialogDescription>
              Start it here. Whisper's team will review the public presence you share.
            </DialogDescription>
          </DialogHeader>
          <form
            className="space-y-3 px-5 pb-5"
            onSubmit={(event) => {
              event.preventDefault();
              if (!user || !reason.trim()) {
                toast.error("Tell us why verification fits your public presence.");
                return;
              }
              setSubmitting(true);
              void submitVerificationRequest({
                userId: user.id,
                username: profile?.username ?? "you",
                email: user.email ?? "",
                fullName: fullName.trim() || profile?.username || "Whisper member",
                category,
                reason: reason.trim(),
                links: links.trim(),
                followers: Number(followers) || 0,
              })
                .then(() => {
                  toast.success("Application sent to the Whisper team.");
                  setOpen(false);
                })
                .catch(() => toast.error("Couldn't send that application. Try again in a moment."))
                .finally(() => setSubmitting(false));
            }}
          >
            <label className="block text-[12px] font-bold">Public name
              <input value={fullName} onChange={(event) => setFullName(event.target.value)} placeholder="Your name or creator name" className="mt-1.5 h-10 w-full rounded-xl border border-border bg-background px-3 text-sm outline-none focus:border-foreground" />
            </label>
            <label className="block text-[12px] font-bold">Your niche — shown under your name
              <select value={category} onChange={(event) => setCategory(event.target.value)} className="mt-1.5 h-10 w-full rounded-xl border border-border bg-background px-3 text-sm outline-none focus:border-foreground">
                {VERIFICATION_CATEGORIES.map((option) => <option key={option.id} value={option.id}>{option.label}</option>)}
              </select>
            </label>
            <label className="block text-[12px] font-bold">Why should Whisper verify you?
              <textarea required value={reason} onChange={(event) => setReason(event.target.value)} placeholder="Tell us about your work, audience, and public presence." rows={4} className="mt-1.5 w-full rounded-xl border border-border bg-background px-3 py-2.5 text-sm outline-none focus:border-foreground" />
            </label>
            <label className="block text-[12px] font-bold">Links that help us review <span className="font-normal text-muted-foreground">(optional)</span>
              <input value={links} onChange={(event) => setLinks(event.target.value)} placeholder="Website or public social links" className="mt-1.5 h-10 w-full rounded-xl border border-border bg-background px-3 text-sm outline-none focus:border-foreground" />
            </label>
            <label className="block text-[12px] font-bold">Approx. audience size <span className="font-normal text-muted-foreground">(optional)</span>
              <input inputMode="numeric" value={followers} onChange={(event) => setFollowers(event.target.value.replace(/[^0-9]/g, ""))} placeholder="0" className="mt-1.5 h-10 w-full rounded-xl border border-border bg-background px-3 text-sm outline-none focus:border-foreground" />
            </label>
            <button disabled={submitting} type="submit" className="flex h-11 w-full items-center justify-center gap-2 rounded-full bg-foreground text-sm font-bold text-background disabled:opacity-60">
              <BadgeCheck className="h-4 w-4" /> {submitting ? "Sending…" : "Send application"}
            </button>
          </form>
        </DialogContent>
      </Dialog>
    </CardShell>
  );
}

function ProfileCard({ feature }: { feature: EmberFeature }) {
  return (
    <CardShell feature={feature}>
      <div className="space-y-2 px-3.5 py-3">
        <div className="flex items-center gap-2 rounded-xl bg-secondary/55 px-3 py-2.5">
          <UserRoundPlus className="h-4 w-4 shrink-0" />
          <p className="text-[12.5px] leading-snug">
            Update your name, bio, cover photo, and interests in the exact same profile editor the app uses.
          </p>
        </div>
        <FullButton to="/profile?edit=1">
          <Sparkles className="h-3.5 w-3.5" />
          Open Edit profile
        </FullButton>
      </div>
    </CardShell>
  );
}

function CommunitiesCard({ feature }: { feature: EmberFeature }) {
  const communities = useMemo(() => COMMUNITIES.slice(0, 4), []);
  return (
    <CardShell feature={feature}>
      <div className="grid grid-cols-2 gap-1.5 px-3.5 py-3">
        {communities.map((community) => {
          const Icon = community.icon;
          return (
            <Link
              key={community.id}
              to={`/c/${community.id}`}
              className="overflow-hidden rounded-xl p-2.5 text-white transition-transform active:scale-[0.98]"
              style={{
                backgroundImage: `linear-gradient(135deg, ${community.gradient[0]}, ${community.gradient[1]})`,
              }}
            >
              <Icon className="h-4 w-4" />
              <p className="mt-2 text-[12px] font-bold">{community.name}</p>
              <p className="mt-0.5 line-clamp-2 text-[10px] leading-snug text-white/80">
                {community.tagline}
              </p>
            </Link>
          );
        })}
      </div>
      <div className="border-t border-border p-2.5">
        <FullButton to="/search" dark={false}>
          <Compass className="h-3.5 w-3.5" />
          Search all communities
        </FullButton>
      </div>
    </CardShell>
  );
}

function RoutedFeatureCard({ feature }: { feature: EmberFeature }) {
  const data: Record<Exclude<EmberFeatureKind, "people" | "verification" | "profile" | "communities">, { to: string; label: string; icon: React.ReactNode; helper: string }> = {
    brands: {
      to: "/brands",
      label: "Browse sponsor brands",
      icon: <BriefcaseBusiness className="h-3.5 w-3.5" />,
      helper: "Live opportunities show real budgets, requirements, and payment terms before you apply.",
    },
    coaching: {
      to: "/coach",
      label: "Open Coach Studio",
      icon: <HeartHandshake className="h-3.5 w-3.5" />,
      helper: "Manage clients, programs, and coaching income through the real studio.",
    },
    recruiting: {
      to: "/recruiter",
      label: "Open recruiter pipeline",
      icon: <Search className="h-3.5 w-3.5" />,
      helper: "Scout consistently, make thoughtful outreach, and keep every prospect in one place.",
    },
    moderation: {
      to: "/safety",
      label: "Open safety tools",
      icon: <ShieldCheck className="h-3.5 w-3.5" />,
      helper: "Reports, trust, and community health work best when the whole team follows one process.",
    },
    collaboration: {
      to: "/collabs",
      label: "Open Collab Projects",
      icon: <Handshake className="h-3.5 w-3.5" />,
      helper: "Invite creators, coaches, athletes, and recruiters into a shared campaign or challenge.",
    },
  };
  const item = data[feature.kind as keyof typeof data];
  if (!item) return null;
  return (
    <CardShell feature={feature}>
      <div className="space-y-3 px-3.5 py-3">
        <div className="flex items-start gap-2 rounded-xl bg-secondary/55 px-3 py-2.5">
          <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0" />
          <p className="text-[12.5px] leading-snug">{item.helper}</p>
        </div>
        <FullButton to={item.to}>{item.icon}{item.label}</FullButton>
      </div>
    </CardShell>
  );
}

export function EmberFeatureCard({ feature }: { feature: EmberFeature }) {
  if (feature.kind === "people") return <PeopleCard feature={feature} />;
  if (feature.kind === "verification") return <VerificationCard feature={feature} />;
  if (feature.kind === "profile") return <ProfileCard feature={feature} />;
  if (feature.kind === "communities") return <CommunitiesCard feature={feature} />;
  return <RoutedFeatureCard feature={feature} />;
}
