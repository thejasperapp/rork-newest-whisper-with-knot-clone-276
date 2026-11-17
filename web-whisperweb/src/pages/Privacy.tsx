import { Link } from "react-router-dom";

import PublicNav from "@/components/PublicNav";
import PublicFooter from "@/components/PublicFooter";
import { PresentationIntro, PresentationLink } from "@/components/Presentation";
import { Reveal } from "@/components/Reveal";
import { usePageMeta } from "@/hooks/usePageMeta";

interface PrivacySection {
  title: string;
  paragraphs: string[];
  bullets?: string[];
}

const SECTIONS: PrivacySection[] = [
  {
    title: "1. What we collect",
    paragraphs: [
      "We collect only what Whisper needs to work:",
    ],
    bullets: [
      "Account basics — email, username, display name, and profile photo.",
      "Content you create — posts, stories, messages, comments, and workout shares.",
      "Fitness data you choose to share — stats, check-ins, and progress photos you send to a coach or post yourself.",
      "Payment records — handled by Stripe; Whisper never sees or stores your card number.",
      "Device basics — app version and crash logs so we can fix problems.",
    ],
  },
  {
    title: "2. What we never do",
    paragraphs: ["Some lines we don't cross:"],
    bullets: [
      "We never sell your personal data. Ever.",
      "We never share your DMs or coaching conversations with advertisers.",
      "We never post on your behalf.",
      "Private fitness profile access is limited to you and an accepted coach. An accepted coach has broad profile access; public or previously downloaded media cannot be recalled.",
    ],
  },
  {
    title: "3. How your data is used",
    paragraphs: [
      "Your data powers the product you actually asked for: showing your feed, delivering messages, matching you with coaches, processing verified-role payments, and letting Jasper analyze the stats you ask it to. Aggregated, de-identified usage helps us understand what to build next.",
    ],
  },
  {
    title: "4. Who can see what",
    paragraphs: [],
    bullets: [
      "Public posts and your public profile — visible to anyone, including visitors on this site.",
      "Private-account post records require approval. A private setting does not revoke public media links, screenshots, or downloaded files.",
      "DMs and coaching threads are intended for their participants. Submitted reports and relevant evidence can be accessed by authorized reviewers.",
      "Ghost posts and stories — follow the visibility windows shown when you post.",
    ],
  },
  {
    title: "5. Payments",
    paragraphs: [
      "All payments run through Stripe, a PCI-certified payment processor. Whisper receives confirmation of what you purchased — never your card details. Coach payouts run through Stripe's payout system; bank details entered during payout setup go directly to Stripe.",
    ],
  },
  {
    title: "6. Your controls",
    paragraphs: [],
    bullets: [
      "Make your account private at any time in Settings.",
      "Delete any post, story, or message you've created.",
      "Delete your account entirely — this removes your content from the service (brief persistence in backups aside).",
      "Email unsubscribe links are in every marketing email we send.",
    ],
  },
  {
    title: "7. Teens",
    paragraphs: [
      "You must be at least 13 to use Whisper. Accounts for users under 18 get additional protections, including limits on who can message them.",
    ],
  },
  {
    title: "8. Changes & contact",
    paragraphs: [
      "If this policy materially changes, we'll notify you in-app before it takes effect. Questions? Reach us from the Support page or Settings → Help & Support in the app.",
    ],
  },
];

/** Plain-language privacy policy — required for App Store & Stripe live mode. */
export default function Privacy() {
  usePageMeta(
    "Privacy Policy",
    "How Whisper collects, uses, and protects your data — in plain language."
  );

  return (
    <div className="presentation-page min-h-screen bg-background">
      <PublicNav />

      <main>
        <div className="presentation-container !pb-0"><PresentationIntro eyebrow="Your information, explained" title="Privacy should be understandable." description="What Whisper collects, how it is used, and the controls and limits to know before you share. Updated October 29, 2026."><PresentationLink to="/safety">Explore safety controls</PresentationLink><PresentationLink to="/support">Ask a privacy question</PresentationLink></PresentationIntro></div>

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
                See also our{" "}
                <Link
                  to="/terms"
                  className="font-semibold text-foreground underline-offset-4 hover:underline"
                >
                  Terms &amp; refund policy
                </Link>
                , or reach out via{" "}
                <Link
                  to="/support"
                  className="font-semibold text-foreground underline-offset-4 hover:underline"
                >
                  Support
                </Link>
                .
              </p>
            </Reveal>
          </Reveal>
        </section>
      </main>

      <PublicFooter />
    </div>
  );
}
