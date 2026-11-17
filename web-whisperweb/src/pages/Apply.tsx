import { useMemo, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ArrowLeft,
  BadgeCheck,
  CheckCircle2,
  ChevronRight,
  CircleAlert,
  Clock,
  Dumbbell,
  Hourglass,
  Loader2,
  ShieldCheck,
} from "lucide-react";
import { toast } from "sonner";

import { Header } from "@/components/Header";
import { useAuth } from "@/hooks/useAuth";
import { submitCoachApplication } from "@/lib/coach";
import {
  VERIFICATION_CATEGORIES,
  fetchRoleState,
  submitVerificationRequest,
  type SpecialRole,
} from "@/lib/applications";

const ROLE_META: Record<
  SpecialRole,
  {
    kicker: string;
    title: string;
    blurb: string;
    accent: string;
    accentBg: string;
    perks: string[];
  }
> = {
  coach: {
    kicker: "Coach program",
    title: "Apply to become a coach",
    blurb:
      "Approved coaches can build workout programs, manage clients, and share programs with clients' Jasper app. Coach appears as a plain professional detail on your profile.",
    accent: "text-orange-500",
    accentBg: "bg-orange-500",
    perks: [
      "Coach role in your profile details",
      "Share Jasper programs to your feed",
      "Client roster + booking link",
      "Workout cards open into Jasper",
    ],
  },
  verified: {
    kicker: "Creator program",
    title: "Apply for Creator access",
    blurb:
      "For creators, athletes, artists, and public figures with a real public presence. Share your work and choose a niche for your profile. Creator access is reviewed separately from identity verification.",
    accent: "text-sky-500",
    accentBg: "bg-sky-500",
    perks: [
      "Creator role in your profile details.",
      "Your niche (Athlete, Fitness, Music…) shown under your name on your profile.",
      "Featured in the brand marketplace — brands browsing sponsorships see you.",
      "Algorithm boost, trending priority, and long-form posts.",
      "Creator Studio analytics and the WPP ad-revenue share.",
    ],
  },
};

function Field({
  label,
  value,
  onChange,
  placeholder,
  type = "text",
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  placeholder: string;
  type?: string;
}) {
  return (
    <label className="block">
      <span className="text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
        {label}
      </span>
      <input
        type={type}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        className="mt-1.5 w-full rounded-xl border border-border bg-background px-3.5 py-2.5 text-[15px] outline-none placeholder:text-muted-foreground/60 focus:border-foreground/40"
      />
    </label>
  );
}

function TextArea({
  label,
  value,
  onChange,
  placeholder,
  rows = 4,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  placeholder: string;
  rows?: number;
}) {
  return (
    <label className="block">
      <span className="text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
        {label}
      </span>
      <textarea
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        rows={rows}
        className="mt-1.5 w-full resize-y rounded-xl border border-border bg-background px-3.5 py-2.5 text-[15px] leading-snug outline-none placeholder:text-muted-foreground/60 focus:border-foreground/40"
      />
    </label>
  );
}

function Chips({
  label,
  options,
  value,
  onChange,
}: {
  label: string;
  options: { id: string; label: string }[];
  value: string;
  onChange: (v: string) => void;
}) {
  return (
    <div>
      <span className="text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
        {label}
      </span>
      <div className="mt-2 flex flex-wrap gap-2">
        {options.map((o) => {
          const active = value === o.id;
          return (
            <button
              key={o.id}
              type="button"
              onClick={() => onChange(o.id)}
              className={`rounded-full border px-3.5 py-1.5 text-[13px] font-bold transition-colors ${
                active
                  ? "border-foreground bg-foreground text-background"
                  : "border-border bg-background text-foreground hover:bg-secondary/60"
              }`}
            >
              {o.label}
            </button>
          );
        })}
      </div>
    </div>
  );
}

function Card({ children }: { children: React.ReactNode }) {
  return (
    <div className="rounded-[20px] border border-border bg-card p-5 shadow-sm">
      {children}
    </div>
  );
}

function PerksCard({ role }: { role: SpecialRole }) {
  const meta = ROLE_META[role];
  return (
    <Card>
      <p className="text-[15px] font-bold">
        {role === "verified" ? "What you get" : "What you unlock"}
      </p>
      <div className="mt-3 space-y-2.5">
        {meta.perks.map((perk) => (
          <div key={perk} className="flex items-start gap-2.5">
            <CheckCircle2 className={`mt-0.5 h-4 w-4 shrink-0 ${meta.accent}`} />
            <p className="text-[14px] leading-snug">{perk}</p>
          </div>
        ))}
      </div>
    </Card>
  );
}

function StatusCard({
  icon,
  title,
  body,
  children,
}: {
  icon: React.ReactNode;
  title: string;
  body: string;
  children?: React.ReactNode;
}) {
  return (
    <Card>
      <div className="flex flex-col items-center py-4 text-center">
        {icon}
        <p className="mt-4 text-[19px] font-extrabold">{title}</p>
        <p className="mt-2 max-w-sm text-[14px] leading-relaxed text-muted-foreground">
          {body}
        </p>
        {children}
      </div>
    </Card>
  );
}

function CoachForm({ onDone }: { onDone: () => void }) {
  const { user, profile } = useAuth();
  const [fullName, setFullName] = useState<string>("");
  const [email, setEmail] = useState<string>(user?.email ?? "");
  const [experienceYears, setExperienceYears] = useState<number>(1);
  const [specialties, setSpecialties] = useState<string>("");
  const [credentials, setCredentials] = useState<string>("");
  const [bio, setBio] = useState<string>("");
  const [website, setWebsite] = useState<string>("");
  const [social, setSocial] = useState<string>("");

  const canSubmit =
    fullName.trim().length > 0 &&
    credentials.trim().length > 0 &&
    bio.trim().length > 0;

  const mutation = useMutation({
    mutationFn: () =>
      submitCoachApplication({
        userId: user!.id,
        username: profile?.username ?? "you",
        email,
        fullName: fullName.trim(),
        credentials: credentials.trim(),
        specialties: specialties
          .split(",")
          .map((s) => s.trim())
          .filter(Boolean),
        experienceYears,
        bio: bio.trim(),
        website: website.trim(),
        social: social.trim(),
      }),
    onSuccess: onDone,
    onError: (err) =>
      toast.error(
        err instanceof Error
          ? `Couldn't save your application: ${err.message}`
          : "Couldn't submit application. Please try again."
      ),
  });

  return (
    <Card>
      <div className="space-y-4">
        <Field label="Full name" value={fullName} onChange={setFullName} placeholder="Jane Doe" />
        <Field label="Email" value={email} onChange={setEmail} placeholder="you@example.com" type="email" />
        <div>
          <span className="text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
            Experience
          </span>
          <div className="mt-1.5 flex items-center gap-3">
            <button
              type="button"
              onClick={() => setExperienceYears((v) => Math.max(0, v - 1))}
              className="flex h-9 w-9 items-center justify-center rounded-full border border-border text-lg font-bold transition-transform active:scale-90"
              aria-label="Fewer years"
            >
              −
            </button>
            <p className="min-w-[72px] text-center text-[15px] font-semibold">
              {experienceYears} year{experienceYears === 1 ? "" : "s"}
            </p>
            <button
              type="button"
              onClick={() => setExperienceYears((v) => Math.min(50, v + 1))}
              className="flex h-9 w-9 items-center justify-center rounded-full border border-border text-lg font-bold transition-transform active:scale-90"
              aria-label="More years"
            >
              +
            </button>
          </div>
        </div>
        <Field
          label="Specialties"
          value={specialties}
          onChange={setSpecialties}
          placeholder="Strength, Hypertrophy, Mobility"
        />
        <TextArea
          label="Credentials / certifications"
          value={credentials}
          onChange={setCredentials}
          placeholder="NASM-CPT, 5 years training collegiate athletes, …"
        />
        <TextArea
          label="Why do you want to coach on Jasper?"
          value={bio}
          onChange={setBio}
          placeholder="Tell us about your training philosophy…"
          rows={5}
        />
        <Field label="Website (optional)" value={website} onChange={setWebsite} placeholder="https://your-site.com" />
        <Field label="Instagram / social (optional)" value={social} onChange={setSocial} placeholder="@username" />
        <button
          onClick={() => mutation.mutate()}
          disabled={!canSubmit || mutation.isPending}
          className="flex h-12 w-full items-center justify-center gap-2 rounded-full bg-orange-500 text-[15px] font-bold text-white transition-transform active:scale-[0.98] disabled:opacity-40"
        >
          {mutation.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
          {mutation.isPending ? "Submitting…" : "Submit application"}
        </button>
      </div>
    </Card>
  );
}

function VerifiedForm({ onDone }: { onDone: () => void }) {
  const { user, profile } = useAuth();
  const [fullName, setFullName] = useState<string>("");
  const [email, setEmail] = useState<string>(user?.email ?? "");
  const [category, setCategory] = useState<string>(VERIFICATION_CATEGORIES[0]?.id ?? "Digital creator");
  const [followers, setFollowers] = useState<string>("");
  const [reason, setReason] = useState<string>("");
  const [links, setLinks] = useState<string>("");

  const canSubmit = fullName.trim().length > 0 && reason.trim().length > 0;

  const mutation = useMutation({
    mutationFn: () =>
      submitVerificationRequest({
        userId: user!.id,
        username: profile?.username ?? "you",
        email,
        fullName: fullName.trim(),
        category,
        reason: reason.trim(),
        links: links.trim(),
        followers: Number(followers.replace(/[^0-9]/g, "")) || 0,
      }),
    onSuccess: onDone,
    onError: (err) =>
      toast.error(
        err instanceof Error
          ? `Couldn't submit: ${err.message}`
          : "Couldn't submit application. Please try again."
      ),
  });

  return (
    <Card>
      <div className="space-y-4">
        <Field label="Legal name" value={fullName} onChange={setFullName} placeholder="Full name" />
        <Field label="Email" value={email} onChange={setEmail} placeholder="you@example.com" type="email" />
        <Chips
          label="Your niche — shown under your name"
          options={VERIFICATION_CATEGORIES}
          value={category}
          onChange={setCategory}
        />
        <Field
          label="Total followers across platforms"
          value={followers}
          onChange={setFollowers}
          placeholder="e.g. 25000"
        />
        <TextArea
          label="Why should you be verified?"
          value={reason}
          onChange={setReason}
          placeholder="Tell us about your work, audience, and what people search for you on."
        />
        <TextArea
          label="Links (one per line)"
          value={links}
          onChange={setLinks}
          placeholder={"https://instagram.com/you\nhttps://yoursite.com"}
        />
        <button
          onClick={() => mutation.mutate()}
          disabled={!canSubmit || mutation.isPending}
          className="flex h-12 w-full items-center justify-center gap-2 rounded-full bg-foreground text-[15px] font-bold text-background transition-transform active:scale-[0.98] disabled:opacity-40"
        >
          {mutation.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
          {mutation.isPending ? "Submitting…" : "Submit application"}
        </button>
      </div>
    </Card>
  );
}

function RoleApplication({ role }: { role: SpecialRole }) {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const [didSubmit, setDidSubmit] = useState<boolean>(false);
  const meta = ROLE_META[role];

  const state = useQuery({
    queryKey: ["role-state", user?.id ?? "", role],
    queryFn: () => fetchRoleState(user!.id, role),
    enabled: !!user?.id,
  });

  const handleDone = (): void => {
    setDidSubmit(true);
    queryClient.invalidateQueries({ queryKey: ["role-state", user?.id ?? "", role] });
    queryClient.invalidateQueries({ queryKey: ["special-account-states"] });
  };

  const label = role === "coach" ? "Coach" : "Creator";

  let body: React.ReactNode;
  if (state.isPending) {
    body = (
      <div className="flex justify-center py-16">
        <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
      </div>
    );
  } else if (state.data?.active) {
    body = (
      <StatusCard
        icon={<BadgeCheck className={`h-12 w-12 ${meta.accent}`} />}
        title={`Your ${label} account is live`}
        body="Your role is active. Your existing tools are ready to use, and your role appears in your profile details."
      />
    );
  } else if (didSubmit) {
    body = (
      <StatusCard
        icon={<CheckCircle2 className={`h-12 w-12 ${meta.accent}`} />}
        title="Application submitted"
        body={
          role === "verified"
            ? "We'll review and get back to you here."
            : "Saved to our database. Approval typically takes 1–3 business days — you'll get an email the moment there's an update."
        }
      />
    );
  } else if (state.data?.application === "pending") {
    body = (
      <StatusCard
        icon={<Hourglass className={`h-12 w-12 ${meta.accent}`} />}
        title="Under review"
        body={
          role === "verified"
            ? "Your application has been received. Reviews typically take 3–7 days."
            : "Your application has been received. A real person reviews every application — approval typically takes 1–3 business days."
        }
      />
    );
  } else if (state.data?.application === "approved") {
    body = (
      <StatusCard
        icon={<BadgeCheck className={`h-12 w-12 ${meta.accent}`} />}
        title="You're approved!"
        body="A real person reviewed and approved your application. Continue to activate your role under the existing subscription terms."
      >
        <Link
          to={`/badge/activate?role=${role}`}
          className={`mt-6 flex h-12 w-full max-w-xs items-center justify-center rounded-full ${meta.accentBg} text-[15px] font-bold text-white transition-transform active:scale-[0.98]`}
        >
          Activate your role
        </Link>
      </StatusCard>
    );
  } else {
    body = (
      <>
        {state.data?.application === "denied" && (
          <Card>
            <div className="flex items-start gap-3">
              <CircleAlert className="mt-0.5 h-5 w-5 shrink-0 text-muted-foreground" />
              <p className="text-[14px] leading-snug text-muted-foreground">
                Your previous application wasn&rsquo;t approved. You can
                strengthen your credentials and apply again below.
              </p>
            </div>
          </Card>
        )}
        <PerksCard role={role} />
        {role === "coach" ? (
          <CoachForm onDone={handleDone} />
        ) : (
          <VerifiedForm onDone={handleDone} />
        )}
        <p className="px-2 text-[12.5px] leading-snug text-muted-foreground">
          {role === "verified"
            ? "Applications are reviewed by Whisper moderators. Applying is free. Approved Creator access is $99.99/year; your professional role is a profile detail, not a purchased identity check."
            : "Applications are reviewed by a real person. Applying is free. Approved Coach access is $249.99/year, activated after approval."}
        </p>
      </>
    );
  }

  return (
    <div className="space-y-4 pb-12">
      <div className="px-1 pt-2">
        <p
          className={`text-[11px] font-black uppercase tracking-[0.2em] ${meta.accent}`}
        >
          {meta.kicker}
        </p>
        <h1 className="mt-1.5 font-display text-[26px] font-extrabold leading-tight">
          {meta.title}
        </h1>
        <p className="mt-2 text-[14px] leading-relaxed text-muted-foreground">
          {meta.blurb}
        </p>
      </div>
      {body}
    </div>
  );
}

function statusLine(
  state: { application: string; active: boolean } | undefined
): string | null {
  if (!state) return null;
  if (state.active) return "Active";
  if (state.application === "pending") return "In review";
  if (state.application === "approved") return "Approved — activate";
  return null;
}

function Picker() {
  const { user } = useAuth();

  const states = useQuery({
    queryKey: ["special-account-states", user?.id ?? ""],
    queryFn: async () => {
      const { fetchAllRoleStates } = await import("@/lib/applications");
      return fetchAllRoleStates(user!.id);
    },
    enabled: !!user?.id,
  });

  const tiers: {
    role: SpecialRole;
    title: string;
    blurb: string;
    icon: React.ReactNode;
  }[] = useMemo(
    () => [
      {
        role: "coach",
        title: "Coach",
        blurb: "For trainers who run programs and clients.",
        icon: <Dumbbell className="h-5 w-5" />,
      },
      {
        role: "verified",
        title: "Creator",
        blurb: "For creators, athletes, artists, and public figures — with your niche in your profile details.",
        icon: <ShieldCheck className="h-5 w-5" />,
      },
    ],
    []
  );

  return (
    <div className="space-y-4 pb-12">
      <div className="flex flex-col items-center px-4 pt-4 text-center">
        <BadgeCheck className="h-10 w-10" />
        <h1 className="mt-3 font-display text-[24px] font-extrabold">
          Professional roles
        </h1>
        <p className="mt-1.5 max-w-sm text-[14px] leading-relaxed text-muted-foreground">
          Apply for Coach or Creator tools. Every application is reviewed by a real
          person before activation. Professional roles are shown in profile details.
        </p>
      </div>

      {tiers.map((tier) => {
        const meta = ROLE_META[tier.role];
        const line = statusLine(states.data?.[tier.role]);
        return (
          <Link
            key={tier.role}
            to={`/apply/${tier.role}`}
            className="block rounded-[20px] border border-border bg-card p-4 shadow-sm transition-colors hover:bg-secondary/40"
          >
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-foreground text-background">
                {tier.icon}
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <p className="text-[15px] font-bold">{tier.title}</p>
                  {line && (
                    <span
                      className={`rounded-full px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide text-white ${
                        line === "Active" ? meta.accentBg : "bg-muted-foreground"
                      }`}
                    >
                      {line}
                    </span>
                  )}
                </div>
                <p className="mt-0.5 text-[13px] text-muted-foreground">
                  {tier.blurb}
                </p>
              </div>
              <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
            </div>
            <div className="mt-3 space-y-1.5 pl-[52px]">
              {meta.perks.slice(0, 4).map((perk) => (
                <div key={perk} className="flex items-start gap-2">
                  <CheckCircle2
                    className={`mt-0.5 h-3.5 w-3.5 shrink-0 ${meta.accent}`}
                  />
                  <p className="text-[13px] leading-snug text-foreground/85">
                    {perk}
                  </p>
                </div>
              ))}
            </div>
          </Link>
        );
      })}

      <div className="flex items-center gap-2 px-2 text-muted-foreground">
        <Clock className="h-4 w-4 shrink-0" />
        <p className="text-[12.5px] leading-snug">
          Applying is free. Coach and Creator access is activated
          with an annual subscription after a real person approves your
          application. A role does not guarantee safety or results.
        </p>
      </div>
    </div>
  );
}

/**
 * Verified badge applications — the web port of the iOS
 * `WhisperSpecialAccountSheet` + the Coach / Creator application forms.
 * Writes to the exact same Supabase tables, so applications land in the
 * same mod review dashboard as mobile. Old /apply/athlete links land on the
 * Creator application (the Athlete badge is a Creator niche now).
 */
export default function Apply() {
  const navigate = useNavigate();
  const { type } = useParams<{ type: string }>();
  const role: SpecialRole | null =
    type === "coach" ? "coach" : type === "verified" || type === "athlete" || type === "creator" ? "verified" : null;

  return (
    <div>
      <Header
        title={role ? "Application" : "Professional roles"}
        left={
          <button
            onClick={() => (role ? navigate("/apply") : navigate(-1))}
            aria-label="Back"
            className="glass flex h-10 w-10 items-center justify-center rounded-full border border-border/60 shadow-sm transition-transform active:scale-90"
          >
            <ArrowLeft className="h-5 w-5" />
          </button>
        }
        right={<span className="h-10 w-10" />}
      />
      <div className="px-4 sm:px-0">
        {role ? <RoleApplication role={role} /> : <Picker />}
      </div>
    </div>
  );
}
