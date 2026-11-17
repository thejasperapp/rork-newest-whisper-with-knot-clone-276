import { useState } from "react";
import { Link } from "react-router-dom";
import { ArrowDown, ArrowRight, ArrowUpRight, AudioLines, BadgeCheck, Check, ChevronLeft, ChevronRight, Clapperboard, Heart, MessageCircle, Mic, PenLine, Phone, Play, Plus, Repeat2, Send, ShieldCheck, Sparkles, Users, Video } from "lucide-react";
import { MarketingLayout } from "@/components/MarketingLayout";

const ART = "/marketing-20261029/";
const MOMENTS = [
  { name: "Share", title: "The thought you almost kept to yourself.", text: "A photo dump. A passing thought. A story from your day. Share it in a post, a thread, or a story—without making your whole life a performance.", label: "YOUR EVERYDAY, SHARED", icon: PenLine },
  { name: "Create", title: "Your next ‘I made this.’", text: "Make a Wave, write something longer, or go live with your people. From a quick clip to a bigger idea, there’s more than one way to put yourself out there.", label: "MAKE A LITTLE SOMETHING", icon: Clapperboard },
  { name: "Belong", title: "The people who just get it.", text: "Find a community around the things you love. Trade ideas, ask the honest questions, and turn a shared interest into a familiar face.", label: "FIND YOUR CORNER", icon: Users },
];
const FEATURES = [
  { icon: Clapperboard, title: "Creator Studio", text: "A home for your creative work. Explore publishing, audience insights, and the tools available to verified creators.", to: "/for-creators", cta: "Explore the studio", tint: "peach" },
  { icon: BadgeCheck, title: "Recruiters", text: "Discover people, explore profiles, and learn about the recruiting tools and roles inside Whisper.", to: "/recruiters", cta: "Meet the recruiters", tint: "blue" },
  { icon: Heart, title: "Coaches", text: "Find a coach who fits. Explore verified profiles and learn how coaching conversations and programs work.", to: "/coaches", cta: "Find your coach", tint: "sage" },
  { icon: Sparkles, title: "Room to grow", text: "Learn about verified roles, earning on Whisper, and optional Whisper One membership. Choose what fits you.", to: "/monetization", cta: "See your possibilities", tint: "sand" },
];
const QUESTIONS = [
  { q: "What is Whisper?", a: "Whisper is a social home for your everyday: posts, stories, Waves, messages, live conversations, and communities. Knot and professional tools for creators, coaches, and recruiters give you a little more room to explore." },
  { q: "Is it free to join?", a: "Yes. You can create a Whisper account for free. Optional memberships and verified-role tools have their own details, which you can review before deciding whether they are right for you." },
  { q: "What can I share?", a: "Post a thought, start a thread, share photos or a story, make a short-form Wave, or explore long-form articles and live video. Pick the format that fits the moment." },
  { q: "What can Knot help with?", a: "Knot is Whisper’s assistant for writing, explanations, exploring ideas, and planning. Get help finding the words or untangling a thought. AI can make mistakes, so always review important information." },
  { q: "How do verified roles work?", a: "Everyone starts with a regular account. Verified roles are application-based, not badges selected at signup. Explore the role pages for the current requirements and available tools." },
];

function ConversationPreview({ hero = false }: { hero?: boolean }) {
  return <div className={`wm-conversation ${hero ? "wm-hero-conversation" : ""}`} aria-label="Illustrative Whisper conversation">
    <div className="wm-preview-heading"><span className="wm-avatar">J</span><div><strong>Jamie</strong><small>Your kind of company</small></div><span className="wm-online" /><Phone size={15} /><Video size={17} /></div>
    <span className="wm-chat-time">TODAY, 10:24</span>
    <p className="wm-chat-bubble">Found our new favourite little place.</p>
    <p className="wm-chat-bubble wm-chat-own">Coffee, a long walk, absolutely no plans?</p>
    <p className="wm-chat-bubble">You get me.</p>
    <div className="wm-voice-bubble"><Play size={13} fill="currentColor" /><AudioLines size={38} /><AudioLines size={38} /><span>0:12</span></div>
    <span className="wm-chat-read">A little closer already.</span>
    <div className="wm-chat-input"><Plus size={16} /><span>Send a little hello…</span><Mic size={15} /><Send size={15} /></div>
    <span className="wm-demo-label">Illustrative conversation</span>
  </div>;
}

function FeedPreview({ selected }: { selected: number }) {
  return <div className="wm-feed-preview" aria-label="Illustrative Whisper post">
    <div className="wm-preview-heading"><span className="wm-avatar">W</span><div><strong>The little things</strong><small>A moment on Whisper</small></div><span className="wm-preview-more">···</span></div>
    <div className={`wm-post-scene wm-scene-${selected}`}><div className="wm-scene-sun" /><div className="wm-scene-hill wm-hill-back" /><div className="wm-scene-hill" /><span>{selected === 0 ? "a little more present." : selected === 1 ? "made to be shared." : "right where you belong."}</span></div>
    <p>{selected === 0 ? "Less overthinking. More moments like this." : selected === 1 ? "That idea you almost kept to yourself? Share it." : "Good company changes everything."}</p>
    <div className="wm-post-actions"><Heart size={18} /><MessageCircle size={18} /><Repeat2 size={18} /><Send size={17} /></div><span className="wm-demo-label">An illustration of the experience</span>
  </div>;
}

export default function Welcome() {
  const [selected, setSelected] = useState(0);
  const moment = MOMENTS[selected];
  const MomentIcon = moment.icon;
  return <MarketingLayout homepage><main id="wm-main" tabIndex={-1}>
    <section className="wm-hero" aria-labelledby="wm-title"><div className="wm-container wm-hero-grid">
      <div className="wm-hero-copy"><p className="wm-eyebrow wm-arrive">SMALL HELLOS. REAL CONNECTIONS.</p><h1 id="wm-title" className="wm-arrive">Less noise.<br /><span className="wm-warm-text">More your people.</span></h1><p className="wm-lead wm-arrive">The group chat that gets you. The idea you finally share. The people who feel like your people. A little space for every part of you—that’s Whisper.</p><div className="wm-hero-links wm-arrive"><Link to="/auth?mode=signup" className="wm-button">Find your people <ArrowRight size={16} /></Link><a href="#experience" className="wm-text-link">Take a little look <span className="wm-arrow-circle"><ArrowDown size={13} /></span></a></div><p className="wm-fine">Free to join. Come as you are.</p></div>
      <div className="wm-social-stage"><div className="wm-floating-thought">anyone else taking the scenic route?</div><ConversationPreview hero /><div className="wm-stage-knot"><img src={`${ART}knot-20261026/knot-mascot-assembled-v2.webp`} alt="Knot, Whisper’s assistant" width={120} height={120} /><span>A little help from Knot.</span></div><span className="wm-stage-scribble">this feels more like us.</span></div>
    </div></section>

    <div className="wm-container"><nav className="wm-directory" aria-label="Explore Whisper"><a href="#experience"><PenLine /><span>Your everyday, shared.<small>Posts, threads & stories</small></span></a><a href="#connections"><MessageCircle /><span>A little more talking.<small>Messages & communities</small></span></a><a href="#creativity"><Clapperboard /><span>Make a little noise.<small>Waves, articles & live</small></span></a><a href="#possibilities"><Sparkles /><span>See where it takes you.<small>Studios, roles & more</small></span></a></nav></div>

    <section id="experience" className="wm-section wm-container"><div className="wm-section-heading"><p className="wm-eyebrow">LIFE DOESN’T FIT IN ONE FORMAT.</p><h2>A thought. A story.<br /><span className="wm-muted">A whole little world.</span></h2><p>For the big days, the ordinary Tuesdays, and everything you haven’t found the words for yet.</p></div>
      <div className="wm-experience-panel"><div className="wm-experience-copy"><div className="wm-moment-tabs" role="tablist" aria-label="Explore the experience">{MOMENTS.map((item, index) => <button key={item.name} id={`wm-tab-${index}`} role="tab" aria-selected={selected === index} aria-controls="wm-moment-panel" tabIndex={selected === index ? 0 : -1} onClick={() => setSelected(index)} onKeyDown={event => { const next = event.key === "ArrowRight" ? (index + 1) % 3 : event.key === "ArrowLeft" ? (index + 2) % 3 : event.key === "Home" ? 0 : event.key === "End" ? 2 : null; if (next !== null) { event.preventDefault(); setSelected(next); document.getElementById(`wm-tab-${next}`)?.focus(); } }}>{item.name}</button>)}</div><div id="wm-moment-panel" role="tabpanel" aria-labelledby={`wm-tab-${selected}`} key={selected} className="wm-moment-copy"><span className="wm-feature-icon"><MomentIcon size={25} /></span><p className="wm-eyebrow">{moment.label}</p><h3>{moment.title}</h3><p>{moment.text}</p><Link className="wm-text-link" to="/auth?mode=signup">Make yourself at home <ArrowRight size={16} /></Link></div><div className="wm-panel-controls"><span>0{selected + 1} <span className="wm-muted">/ 03</span></span><div><button className="wm-icon-button" aria-label="Previous experience" onClick={() => setSelected((selected + 2) % 3)}><ChevronLeft size={18} /></button><button className="wm-icon-button" aria-label="Next experience" onClick={() => setSelected((selected + 1) % 3)}><ChevronRight size={18} /></button></div></div></div><div className="wm-experience-visual"><FeedPreview selected={selected} /></div></div>
    </section>

    <section id="connections" className="wm-container wm-connection-grid wm-section"><div className="wm-connection-art"><ConversationPreview /><span className="wm-handwritten">less ‘we should catch up.’<br />more actually catching up.</span></div><div className="wm-story-copy"><p className="wm-eyebrow">NOT JUST A FOLLOW. A FAMILIAR FACE.</p><h2>Some conversations<br /><span className="wm-warm-text">just feel like home.</span></h2><p>Keep your people close in direct messages and group chats. Send a voice note, share a photo, react to the little things, or turn a catch-up into a call.</p><p>And when you’re looking for your corner of the world? Find a community that gets it.</p><div className="wm-inline-features"><span><Mic size={15} /> Voice notes</span><span><Users size={15} /> Group chats</span><span><Phone size={15} /> Calls</span></div><Link to="/auth?mode=signup" className="wm-text-link">Start with a hello <ArrowRight size={16} /></Link><Link to="/safety" className="wm-safety-note"><ShieldCheck size={17} /> Your space. Your boundaries. Explore safety <ArrowUpRight size={13} /></Link></div></section>

    <section id="creativity" className="wm-container wm-section"><div className="wm-creative-banner"><div className="wm-story-copy"><p className="wm-eyebrow">FOR THE THINGS YOU CAN’T KEEP TO YOURSELF.</p><h2>Make a Wave.<br />Tell your story.</h2><p>A quick clip. An article you’ve been meaning to write. A live moment with your community. Create in the way that feels like you, then see who it reaches.</p><Link to="/for-creators" className="wm-text-link">Step into Creator Studio <ArrowRight size={16} /></Link></div><div className="wm-wave-art" aria-label="Illustrative Waves preview"><div className="wm-wave-orbit" /><Play size={36} fill="currentColor" /><span>little moments.<br /><i>big feeling.</i></span><small>WAVES ON WHISPER · ILLUSTRATION</small></div></div><div className="wm-role-row"><p><Check size={17} /> Your ideas. More ways to share them.</p><div><Link to="/articles">Read articles <ArrowUpRight size={14} /></Link><Link to="/roles/creator">Verified Creators <ArrowUpRight size={14} /></Link><Link to="/one">Whisper One <ArrowUpRight size={14} /></Link></div></div></section>

    <section id="knot" className="wm-section wm-container"><div className="wm-knot-panel"><div className="wm-knot-art"><img src={`${ART}knot-20261026/knot-mascot-assembled-v2.webp`} alt="Knot, Whisper’s familiar assistant" width={512} height={512} loading="lazy" /><span className="wm-knot-wordmark"><img className="wm-light-art" src={`${ART}knot-20261026/knot-wordmark-black.webp`} alt="Knot" width={1600} height={588} loading="lazy" /><img className="wm-dark-art" src={`${ART}knot-20261026/knot-wordmark-white.webp`} alt="Knot" width={1600} height={588} loading="lazy" /></span></div><div className="wm-story-copy"><p className="wm-eyebrow">BIG THOUGHTS. A LITTLE HELP.</p><h2>A thought in a knot?<br /><span className="wm-muted">He gets it.</span></h2><p>Meet Knot, your familiar little presence inside Whisper. Find the words for a reply, explore a rabbit hole, untangle an idea, or make a plan for what’s next.</p><div className="wm-knot-skills"><span>Writing & replies</span><span>Ideas & explanations</span><span>Planning & perspective</span></div><Link to="/auth" className="wm-text-link">Say hello to Knot <ArrowRight size={16} /></Link><p className="wm-fine">AI can make mistakes. Review important answers.</p></div></div></section>

    <section id="possibilities" className="wm-section wm-container"><div className="wm-family-heading"><div><p className="wm-eyebrow">STILL WHISPER. A LITTLE MORE POSSIBILITY.</p><h2>Do your thing.<br /><span className="wm-warm-text">Find your next thing.</span></h2></div><div><p>For the creator finding their voice, the coach making a difference, and the recruiter seeing someone’s potential. There’s room to grow here, too.</p></div></div><div className="wm-capability-grid">{FEATURES.map(feature => <Link key={feature.title} to={feature.to} className={`wm-capability wm-tint-${feature.tint}`}><span className="wm-feature-icon"><feature.icon size={25} /></span><h3>{feature.title}</h3><p>{feature.text}</p><span className="wm-text-link">{feature.cta} <ArrowUpRight size={15} /></span></Link>)}</div></section>

    <section id="questions" className="wm-section wm-container wm-faq"><div><p className="wm-eyebrow">A FEW THINGS YOU MIGHT BE WONDERING.</p><h2>Good questions.<br /><span className="wm-muted">Straight answers.</span></h2><Link to="/faq" className="wm-text-link">More about Whisper <ArrowUpRight size={16} /></Link></div><div className="wm-faq-list">{QUESTIONS.map(item => <details key={item.q}><summary>{item.q}<Plus size={18} /></summary><p>{item.a}</p></details>)}</div></section>
    <section className="wm-final"><div className="wm-container"><p className="wm-eyebrow">IT DOESN’T HAVE TO START WITH SOMETHING BIG.</p><h2>Just a little hello.<br /><span className="wm-warm-text">See where it goes.</span></h2><p>Your people. Your possibilities. Your Whisper.</p><Link to="/auth?mode=signup" className="wm-button">Make yourself at home <ArrowRight size={16} /></Link><span className="wm-fine">Already here? <Link to="/auth">Sign in</Link></span></div></section>
  </main></MarketingLayout>;
}
