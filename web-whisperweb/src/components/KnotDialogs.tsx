import { useState } from "react";
import { ChevronRight, Smile, Heart, FileText, ImagePlus, Lightbulb, MessageCircle, Mic, PenLine, Search, SlidersHorizontal, TrendingUp, Users, HeartPulse } from "lucide-react";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { KnotMascot, KnotPortrait, KnotWordmark } from "@/components/Knot";
import type { EmberExpression } from "@/lib/emberBrain";

const SKILLS = [
  { title: "Writing & replies", detail: "Posts, bios, messages and announcements", icon: PenLine, prompt: "Help me write a post. Ask me about the topic and tone first." },
  { title: "Research & explanations", detail: "Live web search with returned source links", icon: Search, prompt: "Help me research a topic with sources. Ask me what I want to understand first." },
  { title: "Planning & ideas", detail: "Brainstorm and turn ideas into next steps", icon: Lightbulb, prompt: "Help me turn an idea into a practical plan. Ask me about my goal first." },
  { title: "My Whisper insights", detail: "Explore available posting and engagement data", icon: TrendingUp, prompt: "How is my engagement trending? Use only my available Whisper data and tell me what is missing." },
  { title: "People & communities", detail: "Find your way around Whisper", icon: Users, prompt: "Help me find people and communities that match my interests." },
];
export type KnotTool = "photo" | "file" | "voice" | "tuning";

export function KnotSkillsDialog({ open, onClose, hasConnectedFitness, onPrompt, onTool }: {
  open: boolean; onClose: () => void; hasConnectedFitness: boolean; onPrompt: (prompt: string) => void; onTool: (tool: KnotTool) => void;
}) {
  const skills = hasConnectedFitness ? [...SKILLS, { title: "Connected fitness insights", detail: "Charts from your connected Jasper fitness data", icon: HeartPulse, prompt: "Chart my steps for the last 7 days using my connected data." }] : SKILLS;
  return <Dialog open={open} onOpenChange={value => { if (!value) onClose(); }}><DialogContent className="max-h-[88dvh] overflow-y-auto sm:max-w-lg">
    <DialogHeader><DialogTitle>Skills & tools</DialogTitle><DialogDescription>Choose a skill to start a draft, or open a tool.</DialogDescription></DialogHeader>
    <div className="flex items-center gap-3 rounded-2xl bg-secondary p-4"><KnotMascot size={56} /><p className="text-sm font-semibold">A little help, a lot of possibilities.</p></div>
    <section aria-label="Skills"><h3 className="px-2 pb-2 text-xs font-semibold text-muted-foreground">Skills</h3>{skills.map(skill => <button key={skill.title} type="button" onClick={() => { onClose(); onPrompt(skill.prompt); }} className="flex min-h-16 w-full items-center gap-3 rounded-xl px-3 py-3 text-left hover:bg-secondary"><skill.icon className="h-5 w-5 shrink-0" /><span className="min-w-0 flex-1"><strong className="block text-sm font-semibold">{skill.title}</strong><small className="text-xs text-muted-foreground">{skill.detail}</small></span><ChevronRight className="h-4 w-4 text-muted-foreground" /></button>)}</section>
    <p className="px-2 text-xs leading-relaxed text-muted-foreground">Skills prepare a draft for you to review. Research calls live search when sent; unavailable sources are disclosed. Insights use available Whisper or connected Jasper data, never made-up metrics. Suggested app actions still need your review.</p>
    <section aria-label="Built-in communication skills"><h3 className="px-2 pb-2 text-xs font-semibold text-muted-foreground">Communication · built in</h3>{[
      { title: 'Emoji & tone', detail: 'Natural chat, with sparse emoji when it fits', icon: Smile, prompt: 'Help me write a natural message in my voice. Use emoji only if it fits; ask who it is for and what I want to say.' },
      { title: 'Message reactions', detail: 'An occasional reaction to your message—not answer feedback', icon: Heart, prompt: 'Explain how you use message reactions and how I can ask for no reactions or emoji.' },
    ].map(skill => <button key={skill.title} type="button" onClick={() => { onClose(); onPrompt(skill.prompt); }} className="flex min-h-16 w-full items-center gap-3 rounded-xl px-3 py-3 text-left hover:bg-secondary"><skill.icon className="h-5 w-5 shrink-0" /><span className="flex-1"><strong className="block text-sm">{skill.title}</strong><small className="text-muted-foreground">{skill.detail}</small></span><ChevronRight className="h-4 w-4" /></button>)}<p className="px-2 pt-2 text-xs leading-relaxed text-muted-foreground">Automatic when appropriate; ask for no emoji or reactions at any time. These do not read workspace guides or approve actions. Shortcuts only fill your draft.</p></section>
    <section aria-label="Tools"><h3 className="px-2 pb-2 text-xs font-semibold text-muted-foreground">Tools</h3>{([
      { key: "photo", title: "Look at a photo", icon: ImagePlus }, { key: "file", title: "Read a file", icon: FileText }, { key: "voice", title: "Voice conversation", icon: Mic }, { key: "tuning", title: "Tune Knot", icon: SlidersHorizontal },
    ] as const).map(tool => <button key={tool.key} type="button" className="flex min-h-12 w-full items-center gap-3 rounded-xl px-3 text-left text-sm hover:bg-secondary" onClick={() => { onClose(); onTool(tool.key); }}><tool.icon className="h-5 w-5" />{tool.title}<ChevronRight className="ml-auto h-4 w-4 text-muted-foreground" /></button>)}</section>
  </DialogContent></Dialog>;
}

export function KnotProfileDialog({ open, onClose, onTune, onSkills }: { open: boolean; onClose: () => void; onTune: () => void; onSkills: () => void }) {
  const [expression, setExpression] = useState<EmberExpression>("calm");
  return <Dialog open={open} onOpenChange={value => { if (!value) onClose(); }}><DialogContent className="max-h-[88dvh] overflow-y-auto sm:max-w-md">
    <DialogHeader><DialogTitle>Knot’s profile</DialogTitle><DialogDescription>Whisper’s built-in assistant</DialogDescription></DialogHeader>
    <div className="flex flex-col items-center rounded-3xl bg-secondary/60 p-6"><KnotPortrait size={144} expression={expression} /><KnotWordmark width={100} /><span className="mt-2 text-xs text-muted-foreground">AI assistant · not a member account</span></div>
    <label className="flex min-h-11 items-center justify-between gap-3 text-sm">Expression<select className="min-h-11 rounded-xl border border-border bg-background px-3" value={expression} onChange={e => setExpression(e.target.value as EmberExpression)}><option value="calm">Calm</option><option value="happy">Happy</option><option value="curious">Curious</option><option value="thinking">Thinking</option></select></label>
    <p className="text-sm leading-relaxed text-muted-foreground">Here to help you find the words, explore ideas, and untangle what’s next. Knot can make mistakes; review important answers.</p>
    <div className="flex flex-wrap gap-2"><button type="button" onClick={onClose} className="flex min-h-11 items-center gap-2 rounded-full bg-foreground px-4 text-sm font-semibold text-background"><MessageCircle className="h-4 w-4" />Message</button><button type="button" onClick={() => { onClose(); onTune(); }} className="min-h-11 rounded-full border border-border px-4 text-sm">Tune Knot</button><button type="button" onClick={() => { onClose(); onSkills(); }} className="min-h-11 rounded-full border border-border px-4 text-sm">Skills & tools</button></div>
    <p className="text-xs leading-relaxed text-muted-foreground">Knot is app-owned and doesn’t follow people. Your private chats never appear on this profile. Answers you choose to share in a conversation are visible to that audience.</p>
  </DialogContent></Dialog>;
}
