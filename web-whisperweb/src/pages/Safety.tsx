import { ArrowRight, BadgeCheck, CreditCard, FileCheck2, Flag, LockKeyhole, MessageCircle, ShieldCheck } from "lucide-react";
import { Link } from "react-router-dom";
import PublicNav from "@/components/PublicNav";
import PublicFooter from "@/components/PublicFooter";
import { PresentationIntro, PresentationLink } from "@/components/Presentation";
import { usePageMeta } from "@/hooks/usePageMeta";
import { useAuth } from "@/hooks/useAuth";

const GUIDES = [
  { id: "contact", icon: MessageCircle, title: "You choose the conversation.", paragraphs: [
    "Direct messages, including attachment messages and service-generated invitations, are checked against shared contact rules. Either-direction blocks and active messaging restrictions take priority over contact permission.",
    "Adult-to-teen first contact requires explicit recipient permission. A previous message alone is not consent, and unknown age is not an automatic exception. Age is self-declared, not independently verified. Revoking permission restores the default contact rules; use blocking to stop contact regardless of age.",
  ] },
  { id: "reports", icon: Flag, title: "A report should reach someone.", paragraphs: [
    "Use the report action on a post, story, profile, or conversation. Add relevant context and wait for confirmation. If confirmation fails, retry rather than assuming the report was received.",
    "Reports and reporter details are private to the reporter and authorized reviewers, not anonymous to the review team. Repeated reports and AI signals are not proof of wrongdoing or automatic account penalties. There is no guaranteed review time.",
  ] },
  { id: "corrections", icon: FileCheck2, title: "Correct the claim. Not the person.", paragraphs: [
    "A Correction notice belongs to a specific reviewed public post. An authorized human reviewer must give an explanation and supporting sources. Opinions, satire, uncertainty, AI findings, and report counts are not proof that a claim is false.",
    "The notice retains the reviewed version after a post is edited. Authors receive private in-app updates and can revisit decisions and appeal in Settings → Decisions & appeals. Notices can be updated or withdrawn. Historical automatic strikes are not presented as new confirmed findings; older appeals may need Support to confirm account ownership.",
  ] },
  { id: "privacy", icon: LockKeyhole, title: "Clear controls. Honest limits.", paragraphs: [
    "Private-account post records require approval. Fitness profile access is limited to you and an accepted coach; an accepted coach can access broad profile information, not only a selected field. Muted words are an app-local display filter, not platform-wide content removal.",
    "Blocking or switching to a private account cannot recall screenshots, downloads, or media already shared through public asset links. Ghost mode and a private account are not guarantees of anonymity or file secrecy. Broader live multi-account, group, media, and notification verification remains outstanding.",
  ] },
  { id: "identity", icon: BadgeCheck, title: "An indicator, not an endorsement.", paragraphs: [
    "Names show at most one identity or staff indicator. Professional roles such as Coach, Creator, and Recruiter appear in profile details. Neither a role nor an identity indicator guarantees safety, competence, results, or the accuracy of every claim.",
    "Application reviews, professional tools, billing, and identity indicators are separate. Membership and age are not public badges.",
  ] },
  { id: "payments", icon: CreditCard, title: "Know what you are paying for.", paragraphs: [
    "Coaching payments are processed through Stripe. Whisper does not see or store your card number. Coaches receive payouts through Stripe's account-verification process.",
    "Review the plan before paying. Monthly coaching subscriptions can be cancelled from Settings, with access through the paid period. Role fees, coaching subscriptions, and program purchases follow their respective billing and refund policies.",
  ] },
];

export default function Safety() {
  const { user } = useAuth();
  usePageMeta("Safety — Whisper", "Practical safety controls, private reports, reviewed corrections, and the limits that matter.");
  return <div className="presentation-page min-h-screen bg-background"><PublicNav />
    <main className="presentation-container">
      <PresentationIntro eyebrow="Safety, in plain words" title="More connection. Clearer boundaries." description="Feeling at home starts with knowing where you stand. Here’s how to manage contact, raise a concern, and understand a decision—and what these protections cannot do.">
        <PresentationLink to={user ? "/settings#privacy" : "/auth"} primary>{user ? "Open safety controls" : "Sign in to manage controls"}</PresentationLink>
        <PresentationLink to="/support">Talk to Support</PresentationLink>
      </PresentationIntro>
      <nav className="safety-shortcuts" aria-label="Safety guide"><a href="#contact"><MessageCircle size={19} />Manage contact<ArrowRight size={15} className="ml-auto" /></a><a href="#reports"><Flag size={19} />Report a concern<ArrowRight size={15} className="ml-auto" /></a><a href="#corrections"><FileCheck2 size={19} />Decisions & appeals<ArrowRight size={15} className="ml-auto" /></a></nav>
      {GUIDES.map(guide => <section id={guide.id} className="safety-protocol" key={guide.id}><div><span className="presentation-icon"><guide.icon size={21} aria-hidden="true" /></span><h2>{guide.title}</h2></div><div className="presentation-body">{guide.paragraphs.map(paragraph => <p key={paragraph}>{paragraph}</p>)}{guide.id === "corrections" && user && <Link className="mt-4 inline-flex items-center gap-2 font-semibold text-foreground underline underline-offset-4" to="/settings#decisions">View your decisions<ArrowRight size={14} /></Link>}{guide.id === "payments" && <Link className="mt-4 inline-flex items-center gap-2 font-semibold text-foreground underline underline-offset-4" to="/policies">Read billing policies<ArrowRight size={14} /></Link>}</div></section>)}
      <aside className="safety-note"><ShieldCheck size={24} className="mb-4" /><h2>Need a person, not another page?</h2><p className="presentation-body">Contact Support for an account concern or help with a historical appeal. If someone is in immediate danger, contact your local emergency services—Whisper is not an emergency response service.</p><div className="presentation-actions"><PresentationLink to="/support" primary>Contact Support</PresentationLink><PresentationLink to="/privacy">Privacy policy</PresentationLink><PresentationLink to="/policies">Roles & payments</PresentationLink></div></aside>
    </main><PublicFooter /></div>;
}
