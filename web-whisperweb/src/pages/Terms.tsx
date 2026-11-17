import { Link } from "react-router-dom";
import { FileText } from "lucide-react";

import PublicNav from "@/components/PublicNav";
import PublicFooter from "@/components/PublicFooter";
import { Reveal } from "@/components/Reveal";

interface TermsSection {
  title: string;
  paragraphs: string[];
  bullets?: string[];
}

const SECTIONS: TermsSection[] = [
  {
    title: "1. Your account",
    paragraphs: [
      "Whisper is free to join. You're responsible for the accuracy of your profile and for keeping your login secure. You must be at least 13 years old to use Whisper; teen accounts carry additional protections.",
    ],
  },
  {
    title: "2. Verified roles & billing",
    paragraphs: [
      "Creator and Coach are application-based verified badges. Applications are reviewed by a real person and approval is never guaranteed. Verified creators choose a niche (for example Athlete, Fitness, or Music) that is displayed on their profile.",
    ],
    bullets: [
      "Creator — $99.99/year. Coach — $249.99/year.",
      "You are only billed after your application is approved and you activate the role subscription. Submitting an application costs nothing.",
      "Verified roles renew annually. You can cancel renewal at any time and keep your role until the end of the paid period.",
      "Badges can be revoked for violations of these terms (misrepresenting credentials, harming clients, spam). Revocation for cause does not entitle you to a refund.",
    ],
  },
  {
    title: "3. Whisper One billing",
    paragraphs: [
      "Whisper One is an instant, non-application membership billed at $14.99/month or $119.99/year.",
    ],
    bullets: [
      "It renews automatically until cancelled. Cancel anytime; perks remain active until the end of the current billing period.",
      "Whisper One does not include verification, paywalled coaching, or more than 3 concurrent client slots.",
      "Membership unlocks tools without a public membership badge. Identity indicators are separate and do not guarantee safety or professional competence.",
    ],
  },
  {
    title: "4. Refund policy",
    paragraphs: [
      "We want billing to feel as honest as the badges.",
    ],
    bullets: [
      "First purchase: full refund within 14 days of your first charge for any paid plan — no questions asked.",
      "Renewals: refundable in full within 14 days of the renewal charge, provided the renewed period hasn't been materially used to charge clients.",
      "Approval-based roles: because you're only billed after approval, a declined application never results in a charge.",
      "To request a refund, contact support from Settings → Help & Support in the app, or reply to your purchase receipt email.",
    ],
  },
  {
    title: "5. Coaching & paid services",
    paragraphs: [
      "Only verified Coaches may charge for coaching through Whisper. Coaching rates, scope, and deliverables are set by the coach in their DM proposals; Whisper displays them transparently to the client before acceptance.",
      "Training and nutrition content on Whisper — including coach programs and Jasper's analysis — is fitness guidance, not medical advice. Consult a physician before starting a new training or nutrition program.",
    ],
  },
  {
    title: "6. Acceptable use",
    paragraphs: [
      "Keep Whisper honest. The following can lead to content removal, badge revocation, or account termination:",
    ],
    bullets: [
      "Misrepresenting credentials, results, or client testimonials.",
      "Selling coaching services without the verified Coach role.",
      "Harassment, hate, spam, or artificially inflating engagement.",
      "Attempting to move payments off-platform specifically to avoid client protections.",
    ],
  },
  {
    title: "7. Your content",
    paragraphs: [
      "You own what you post. By posting, you grant Whisper a licence to display your content within the service (feed, discovery, embeds). You can delete your content or your account at any time; deletion removes it from the service, though it may persist briefly in backups.",
    ],
  },
  {
    title: "8. Changes to these terms",
    paragraphs: [
      "We may update these terms as Whisper evolves. If a change materially affects billing or your rights, we'll notify you in-app before it takes effect. Continued use after the effective date means you accept the updated terms.",
    ],
  },
];

export default function Terms() {
  return (
    <div className="min-h-screen bg-background">
      <PublicNav />

      <main>
        <section className="px-4 pb-10 pt-32 sm:px-6 lg:px-8 lg:pt-40">
          <div className="mx-auto max-w-3xl text-center">
            <div className="inline-flex items-center gap-2 rounded-full border border-border bg-card px-4 py-1.5 text-[13px] font-medium text-muted-foreground">
              <FileText className="h-4 w-4" />
              Legal
            </div>
            <h1 className="mt-6 font-display text-[36px] font-extrabold leading-[1.1] tracking-tight sm:text-[48px]">
              Terms & refund policy
            </h1>
            <p className="mx-auto mt-5 max-w-xl text-[16.5px] leading-relaxed text-muted-foreground">
              Written in plain language, because you shouldn't need a lawyer to
              understand what you're paying for. Last updated July 2026.
            </p>
          </div>
        </section>

        <section className="px-4 pb-20 sm:px-6 lg:px-8">
          <Reveal stagger className="mx-auto max-w-3xl space-y-4">
            {SECTIONS.map((section) => (
              <div
                key={section.title}
                className="rounded-3xl border border-border bg-card p-6 sm:p-7"
              >
                <h2 className="text-[19px] font-extrabold">{section.title}</h2>
                {section.paragraphs.map((paragraph) => (
                  <p
                    key={paragraph}
                    className="mt-2.5 text-[15px] leading-relaxed text-muted-foreground"
                  >
                    {paragraph}
                  </p>
                ))}
                {section.bullets && (
                  <ul className="mt-3 space-y-2">
                    {section.bullets.map((bullet) => (
                      <li
                        key={bullet}
                        className="flex items-start gap-2.5 text-[14.5px] leading-snug text-muted-foreground"
                      >
                        <span className="mt-[7px] h-1.5 w-1.5 shrink-0 rounded-full bg-foreground/60" />
                        {bullet}
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            ))}

            <Reveal className="rounded-3xl border border-border bg-card p-6 text-center">
              <p className="text-[15px] text-muted-foreground">
                Questions about a charge? See{" "}
                <Link
                  to="/monetization"
                  className="font-semibold text-foreground underline-offset-4 hover:underline"
                >
                  Monetization
                </Link>{" "}
                for what each plan includes, or contact support from{" "}
                <span className="font-semibold text-foreground">
                  Settings → Help & Support
                </span>{" "}
                in the app.
              </p>
            </Reveal>
          </Reveal>
        </section>
      </main>

      <PublicFooter />
    </div>
  );
}
