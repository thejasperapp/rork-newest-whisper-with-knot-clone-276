import { Link, Navigate, useParams } from "react-router-dom";
import { CalendarDays, Camera, ClipboardList, Dumbbell, FileText, Film, LayoutDashboard, MessageCircle, PenLine, Search, TrendingUp, UserPlus, Users, UtensilsCrossed, type LucideIcon } from "lucide-react";
import PublicNav from "@/components/PublicNav";
import PublicFooter from "@/components/PublicFooter";
import { PresentationFAQ, PresentationIntro, PresentationLink } from "@/components/Presentation";
import { useAuth } from "@/hooks/useAuth";

type Feature = { icon: LucideIcon; title: string; desc: string };
type Role = { name: string; headline: string; intro: string; price: string; period: string; note: string; workspace: string; features: Feature[]; faq: { q: string; a: string }[] };
const ROLES: Record<string, Role> = {
  coach: {
    name: "Coach", headline: "More time coaching. Less keeping up.",
    intro: "Your clients, programs, check-ins, and conversations. Bring your coaching practice together in the place you already connect.",
    price: "$249.99", period: "/ year", note: "Application reviewed. Billed only if approved.", workspace: "Coach Studio",
    features: [
      { icon: LayoutDashboard, title: "A home for your clients", desc: "See your roster, incoming requests, and check-in status in Coach Studio. Keep the next step close to the person it belongs to." },
      { icon: Dumbbell, title: "Programs with a plan", desc: "Build structured training programs with exercises, sets, and intensity, then share them with a client in their conversation." },
      { icon: UtensilsCrossed, title: "Nutrition, in context", desc: "Share macro targets, diet plans, and daily goals as readable cards alongside your coaching conversation." },
      { icon: MessageCircle, title: "From first hello to coaching", desc: "Review requests and send coaching proposals in DMs. Contact permissions and safety rules still apply." },
      { icon: Camera, title: "Keep progress in view", desc: "Review submitted check-ins and progress photos in a client timeline, without digging through separate spreadsheets." },
      { icon: TrendingUp, title: "Room for your voice, too", desc: "Approved coaches retain their existing creator distribution tools and long-form posting access. Your content and coaching can live together." },
    ],
    faq: [
      { q: "What does the application review cover?", a: "Submit certifications, client history, or a demonstrable coaching track record. A person reviews your application for coaching-tool eligibility. A role is not a guarantee of safety, competence, or results." },
      { q: "Is this the same as a client's coaching subscription?", a: "No. The annual Coach role fee is separate from the prices you set for your client coaching plans. Existing billing, approvals, and cancellation policies are unchanged." },
      { q: "How is the role shown?", a: "Coach appears in your profile details as plain text. A separate identity or staff indicator may appear beside a name, but roles are not a collection of public seals." },
    ],
  },
  creator: {
    name: "Creator", headline: "Make something worth coming back for.",
    intro: "A place for your perspective, not just your next post. Build an audience around the things you make and the conversations they start.",
    price: "$99.99", period: "/ year", note: "Application reviewed. Billed only if approved.", workspace: "Creator Studio",
    features: [
      { icon: PenLine, title: "Space for the whole thought", desc: "Write up to 1,500 characters per whisper. Share the story, the explanation, or the idea without cutting it short." },
      { icon: TrendingUp, title: "Your existing reach tools", desc: "Keep approved creator distribution benefits, including ranking boost, trending eligibility, and suggested-account placement." },
      { icon: LayoutDashboard, title: "Understand your work", desc: "Use Creator Studio to see how your content performs and plan what to make next." },
      { icon: Users, title: "Build around your niche", desc: "Show what you create in your profile details, and connect through posts, Waves, and communities." },
    ],
    faq: [
      { q: "Who is this for?", a: "Creators across fitness, sport, music, art, education, and more. Submit your content and relevant links. A real person reviews the application; it is not an automatically purchased checkmark." },
      { q: "Does paying guarantee an audience?", a: "No. Approved creator tools support distribution, but views, followers, partnerships, and earnings are not guaranteed." },
      { q: "Is my role an identity guarantee?", a: "No. The Creator role is a profile detail. Any identity indicator has a separate meaning and does not certify every claim or endorsement." },
    ],
  },
  recruiter: {
    name: "Recruiter", headline: "You see the potential. Help it find a home.",
    intro: "For the connectors who know their community. Discover promising people, keep the conversation going, and help grow the Whisper network.",
    price: "Free", period: "to approved recruiters", note: "Application reviewed. No recruiter fee.", workspace: "Recruiter workspace",
    features: [
      { icon: Search, title: "Start with your territory", desc: "Organize scouting around your assigned region and cities. Bring local knowledge to the people you discover." },
      { icon: ClipboardList, title: "A pipeline, not a pile of notes", desc: "Keep prospect notes, status, and next steps together so a promising introduction does not get lost." },
      { icon: UserPlus, title: "Help people take the next step", desc: "Use personal invite links and track your referral and promotion history. Approval remains a separate reviewed decision." },
      { icon: CalendarDays, title: "Coordinate the work", desc: "Use the shared team calendar to organize scouting, meetings, and collaboration with the team." },
    ],
    faq: [
      { q: "Who makes a good recruiter?", a: "People with a relevant network and an eye for potential: community organizers, gym owners, team captains, content managers, and other local connectors. Apply with your background and network." },
      { q: "Does the role let me bypass contact permissions?", a: "No. A recruiter role does not override blocks, messaging restrictions, or protected-contact permission checks." },
      { q: "Is there a subscription?", a: "No. The approved Recruiter role has no fee. Applications are reviewed by the Whisper team." },
    ],
  },
  director: {
    name: "Director", headline: "Give your stories a bigger screen.", intro: "A dedicated place to publish films and share the work behind them. Keep your creative world connected to your Whisper community.",
    price: "Team-granted", period: "role", note: "Access is granted by the Whisper team, not purchased here.", workspace: "Director Studio",
    features: [
      { icon: Film, title: "A studio for your films", desc: "Use Director Studio to upload and manage film content with the tools available to your approved account." },
      { icon: Camera, title: "A place to watch", desc: "Present your work on Whisper's film surfaces, separate from a short-form Wave or a feed post." },
      { icon: MessageCircle, title: "Keep the conversation close", desc: "Share your films with your community and talk about the work through Whisper's existing social features." },
      { icon: Users, title: "Your role, simply stated", desc: "Director is a plain professional detail on your profile, not a promise of quality or a separate public reputation score." },
    ],
    faq: [{ q: "How do I get access?", a: "Director is a team-granted role. Contact Support with your account and work for the team to consider. There is no new paid Director plan on this page." }],
  },
  writer: {
    name: "Writer", headline: "Some ideas deserve more than a caption.", intro: "Make room for the essay, the field notes, and the story you have been meaning to tell. Publish longer work alongside your everyday conversations.",
    price: "Team-granted", period: "role", note: "Access is granted by the Whisper team, not purchased here.", workspace: "Writing studio",
    features: [
      { icon: PenLine, title: "A space for longer work", desc: "Use the article writing tools available to your approved account to prepare and publish your work." },
      { icon: FileText, title: "A home in the journal", desc: "Give readers a dedicated article page, rather than squeezing every idea into a feed caption." },
      { icon: MessageCircle, title: "Let the story travel", desc: "Share articles through Whisper's existing feed and conversation features." },
      { icon: Users, title: "The person behind the words", desc: "Your professional role belongs in your profile details. It does not certify the accuracy of every published claim." },
    ],
    faq: [{ q: "How do I get writing access?", a: "Writing access is team-granted. Contact Support with your account and examples of your work. Existing author permissions and tools are unchanged." }],
  },
};

export default function RoleDetail() {
  const { role } = useParams<{ role: string }>();
  const { user } = useAuth();
  if (role === "athlete") return <Navigate to="/roles/creator" replace />;
  if (role === "blogger") return <Navigate to="/roles/writer" replace />;
  const data = role ? ROLES[role] : undefined;
  if (!data) return <Navigate to="/team" replace />;
  const granted = role === "director" || role === "writer";
  const applyTo = granted ? "/support" : !user ? "/auth?mode=signup" : role === "recruiter" ? "/recruiter" : `/apply/${role === "creator" ? "verified" : "coach"}`;
  return <div className="presentation-page min-h-screen bg-background">
    <PublicNav />
    <main className="presentation-container">
      <nav aria-label="Professional roles" className="role-tabs">{Object.entries(ROLES).map(([key, value]) => <Link key={key} to={`/roles/${key}`} aria-current={role === key ? "page" : undefined}>{value.name}</Link>)}</nav>
      <div className="role-hero">
        <PresentationIntro eyebrow={`Whisper for ${data.name === "Coach" ? "coaches" : `${data.name.toLowerCase()}s`}`} title={data.headline} description={data.intro}>
          <PresentationLink to={applyTo} primary>{granted ? "Talk to the team" : user ? "View your application" : "Start with a free account"}</PresentationLink>
          <a href="#tools" className="presentation-link">Explore the tools</a>
          <div className="w-full"><div className="role-price"><strong>{data.price}</strong><span>{data.period}</span></div><p className="mt-2 text-xs text-muted-foreground">{data.note}</p></div>
        </PresentationIntro>
        <aside className="role-preview" aria-label={`${data.workspace} capability overview`}>
          <div className="role-preview-header">{data.workspace}<span>At a glance</span></div>
          {data.features.slice(0, 3).map((feature, i) => <div className="role-preview-row" key={feature.title}><feature.icon aria-hidden="true" /><div><strong>{feature.title}</strong><small>{["Organize your work", "Make it your own", "Keep it connected"][i]}</small></div></div>)}
          <p className="role-preview-note">Built into your Whisper experience. The same account, with tools for the work you do.</p>
        </aside>
      </div>
      <div className="presentation-section" id="tools" style={{ scrollMarginTop: 90 }}>
        <p className="presentation-eyebrow">Made for your day-to-day</p><h2>Less scattered. More connected.</h2>
        <div className="presentation-grid">{data.features.map(feature => <article className="presentation-card" key={feature.title}><span className="presentation-icon"><feature.icon size={21} aria-hidden="true" /></span><h3>{feature.title}</h3><p>{feature.desc}</p></article>)}</div>
      </div>
      <div className="presentation-section"><p className="presentation-eyebrow">A clear path in</p><h2>{granted ? "Work with the Whisper team." : "Start free. Apply when you’re ready."}</h2>
        <div className="presentation-steps">{[
          ["01", "Join Whisper", "Create a free account and make your profile your own."],
          ["02", granted ? "Share your work" : "Submit an application", granted ? "Contact Support with examples and your account details." : "Open applications from your account and provide your relevant background."],
          ["03", "Human review", "The team reviews your application. A role does not guarantee safety or results."],
          ["04", "Put your tools to work", granted || role === "recruiter" ? "Approved access follows the existing role process. No new fee is introduced." : "Billing starts only after approval, under the existing terms."],
        ].map(([number, title, body]) => <div key={number}><span>{number}</span><h3>{title}</h3><p className="presentation-body">{body}</p></div>)}</div>
      </div>
      <div className="presentation-section"><p className="presentation-eyebrow">Good to know</p><h2>A few things, made clear.</h2><PresentationFAQ items={data.faq} />
        <div className="presentation-actions"><PresentationLink to="/policies">Read the policies</PresentationLink><PresentationLink to="/safety">Safety on Whisper</PresentationLink>{role === "coach" && <PresentationLink to="/coaches">Meet the coaches</PresentationLink>}</div>
      </div>
    </main><PublicFooter />
  </div>;
}
