import { useEffect } from "react";
import { Link, useLocation } from "react-router-dom";
import { BadgeCheck, Dumbbell, ReceiptText } from "lucide-react";

import PublicNav from "@/components/PublicNav";
import PublicFooter from "@/components/PublicFooter";
import { PresentationIntro, PresentationLink } from "@/components/Presentation";

/**
 * Whisper policies — badges & verification, coaching & payments, billing &
 * refunds. Public, linked from every checkout surface on web and iOS so the
 * rules people pay under are always one tap away.
 */

function Section({
  id,
  icon,
  title,
  children,
}: {
  id: string;
  icon: React.ReactNode;
  title: string;
  children: React.ReactNode;
}) {
  return (
    <section
      id={id}
      className="scroll-mt-28 rounded-[28px] border border-border bg-card p-7 sm:p-9"
    >
      <div className="flex items-center gap-3">
        <span className="flex h-10 w-10 items-center justify-center rounded-2xl bg-emerald-500/10 text-emerald-600">
          {icon}
        </span>
        <h2 className="font-display text-[22px] font-extrabold">{title}</h2>
      </div>
      <div className="mt-5 space-y-4 text-[14.5px] leading-relaxed text-muted-foreground">
        {children}
      </div>
    </section>
  );
}

function Rule({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div>
      <p className="font-bold text-foreground">{title}</p>
      <p className="mt-1">{children}</p>
    </div>
  );
}

export default function Policies() {
  const { hash } = useLocation();

  useEffect(() => {
    if (!hash) return;
    const el = document.getElementById(hash.slice(1));
    if (el) el.scrollIntoView({ behavior: "smooth", block: "start" });
  }, [hash]);

  return (
    <div className="presentation-page flex min-h-screen flex-col bg-background">
      <PublicNav />
      <main className="presentation-container flex-1">
        <PresentationIntro eyebrow="The details that matter" title="Know where you stand." description="Roles, coaching, and payments—explained without the maze. The same policies apply on web and iPhone.">
          <a href="#badges" className="presentation-link">Roles & review</a><a href="#coaching" className="presentation-link">Coaching</a><a href="#billing" className="presentation-link">Billing & refunds</a><PresentationLink to="/safety">Safety guide</PresentationLink>
        </PresentationIntro>

        <div className="mt-9 space-y-6">
          <Section id="badges" icon={<BadgeCheck className="h-5 w-5" />} title="Roles & verification">
            <Rule title="Approval is earned — never bought.">
              Coach and Creator roles start with an application reviewed by a human on the Whisper team. Paying is only possible after approval; the annual fee covers the approved role’s tools and ongoing review. If you are not approved, you are not charged. Professional roles appear as plain profile details.
            </Rule>
            <Rule title="Annual renewal.">
              Approved role fees bill once per year through Stripe: Coach $249.99/year and Creator $99.99/year. If a renewal lapses, paid role access follows the existing entitlement rules. Your account and content are not deleted.
            </Rule>
            <Rule title="Team-granted roles can't be purchased.">
              Director, Blogger, Recruiter, and Trusted Member are granted by
              the Whisper team for work inside the community. There is no
              payment path for them, and there never will be.
            </Rule>
            <Rule title="Revocation for conduct.">
              An identity indicator or professional role is not a guarantee of trust, competence, safety, or correctness. Harassment, scams, impersonation, or dangerous advice may lead to action after review. Existing refund terms remain unchanged.
            </Rule>
          </Section>

          <Section id="coaching" icon={<Dumbbell className="h-5 w-5" />} title="Coaching & payments">
            <Rule title="Coaches set their own prices.">
              Every verified coach prices their own coaching — either a single
              monthly rate or up to three plan tiers with their own perks —
              anywhere from $5 to $2,000 per month. What a tier lists is what
              the coach owes you.
            </Rule>
            <Rule title="Where the money goes.">
              Payments run through Stripe. Coaches receive 90% of every charge,
              paid out to their own linked bank account; Whisper keeps a 10%
              platform fee that funds verification, hosting, and support.
            </Rule>
            <Rule title="Cancel anytime.">
              Coaching bills monthly. Cancel from Settings → Billing whenever
              you like — you keep access through the end of the month you
              already paid for, and nothing renews after that.
            </Rule>
            <Rule title="Programs are yours for good.">
              One-time program purchases grant permanent access to that
              program, even if you later stop subscribing to the coach.
            </Rule>
            <Rule title="Unresponsive coaches.">
              If a coach goes silent for 7+ days on an active plan, contact
              support — that qualifies you for a refund even outside the normal
              window, and repeat offenders lose their coach badge.
            </Rule>
          </Section>

          <Section id="billing" icon={<ReceiptText className="h-5 w-5" />} title="Billing & refunds">
            <Rule title="Refund windows.">
              Whisper One — 14 days from any charge. Badge fees — 14 days from
              the charge. Coaching — 7 days from the latest monthly charge.
              Programs — 14 days from purchase. Outside a window, requests are
              still reviewed case by case (see unresponsive coaches above).
            </Rule>
            <Rule title="How to request a refund.">
              Settings → Billing → Request a refund, on either app. Every
              request is reviewed by a human — most decisions land within 2
              business days, and you get an email either way.
            </Rule>
            <Rule title="What an approved refund does.">
              The full charge returns to your original payment method (banks
              typically post it within 5–10 business days). The related
              subscription ends immediately, and for coaching the coach's side
              of the payment is reversed too — you're made 100% whole.
            </Rule>
            <Rule title="Fair use.">
              Refunds exist so trying Whisper is risk-free, not as a free-usage
              loop. Repeat subscribe-refund cycles and chargeback abuse can be
              declined and may limit future purchases. Always reach support
              before opening a bank dispute — humans fix things faster.
            </Rule>
          </Section>
        </div>

        <p className="mt-8 text-center text-[12.5px] text-muted-foreground">
          Effective August 2026 · Whisper ·{" "}
          <Link className="underline" to="/support">
            Contact support
          </Link>
        </p>
      </main>
      <PublicFooter />
    </div>
  );
}
