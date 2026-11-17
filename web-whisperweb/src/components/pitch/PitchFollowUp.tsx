import { Calendar, Mail } from "lucide-react";

import { usePitch } from "@/components/pitch/PitchContext";
import type { PitchFaqItem } from "@/components/pitch/PitchSpeakerNotes";

export function PitchFollowUp({
  audienceTitle,
  faqs,
}: {
  audienceTitle: string;
  faqs?: PitchFaqItem[];
}) {
  const { notes } = usePitch();

  // Pull the live client notes the mod typed during the call, then any
  // per-section bullets they edited. The follow-up email is pre-filled with
  // a real summary of what was discussed — not a generic template.
  const clientNotes = (notes["__client"] ?? "").trim();
  const sectionSummaries = Object.entries(notes)
    .filter(([key]) => key !== "__client")
    .map(([section, value]) => {
      const trimmed = value.trim();
      if (!trimmed) return null;
      // Strip the default bullet prefix so the email reads as prose.
      const prose = trimmed
        .split("\n")
        .map((line) => line.replace(/^\s*•\s*/, "- ").trim())
        .filter(Boolean)
        .join("\n");
      return `${section}:\n${prose}`;
    })
    .filter(Boolean)
    .join("\n\n");

  const discussedBlock = [clientNotes, sectionSummaries]
    .filter(Boolean)
    .map((block) => block)
    .join("\n\n---\n\n");

  // Surface the top objection as a single line so the follow-up addresses it
  // head-on — a direct response to the most-asked question in the room.
  const topObjection = faqs?.[0];

  const bodyParts: string[] = [
    `Hi — thanks for walking through the Whisper ${audienceTitle.toLowerCase()} pitch. I wanted to follow up with next steps and a recap of what we covered.`,
    "",
    "Quick recap of what we discussed:",
    discussedBlock
      ? discussedBlock
      : "- The live product demo (real views, sample data)\n- How Whisper handles the money flow end-to-end\n- Next steps for getting you set up",
    "",
  ];

  if (topObjection) {
    bodyParts.push(
      `On your question — "${topObjection.question}":`,
      topObjection.answer,
      ""
    );
  }

  bodyParts.push(
    "Next steps:",
    "1. Reply with any follow-up questions and I'll answer them directly.",
    "2. If you'd like a live account or a product demo, I can set that up this week.",
    "3. If you're ready to move forward, I'll send over the short onboarding form.",
    "",
    "Thanks again for your time — looking forward to getting you on Whisper.",
    "",
    "— Whisper Team"
  );

  const subject = encodeURIComponent(`Follow-up: Whisper for ${audienceTitle}`);
  const body = encodeURIComponent(bodyParts.join("\n"));

  return (
    <div className="rounded-[20px] bg-foreground p-5 text-background">
      <p className="text-[11px] font-bold uppercase tracking-wider opacity-70">
        Next step
      </p>
      <h3 className="mt-1 text-[18px] font-extrabold">Book a follow-up</h3>
      <p className="mt-1 text-[13px] leading-snug opacity-80">
        The follow-up email is pre-filled with your live client notes and the
        top objection from the deck. Send it straight from here — the recipient
        never sees Pitch Mode, just your normal invite.
      </p>
      <div className="mt-4 flex flex-col gap-2 sm:flex-row">
        <a
          href={`mailto:?subject=${subject}&body=${body}`}
          className="flex flex-1 items-center justify-center gap-2 rounded-full bg-background py-2.5 text-[13px] font-bold text-foreground transition-transform active:scale-95"
        >
          <Mail className="h-4 w-4" /> Send follow-up email
        </a>
        <a
          href="https://cal.com/whisper"
          target="_blank"
          rel="noreferrer"
          className="flex flex-1 items-center justify-center gap-2 rounded-full border border-background/30 py-2.5 text-[13px] font-bold transition-colors hover:bg-background/10"
        >
          <Calendar className="h-4 w-4" /> Schedule a call
        </a>
      </div>
      {discussedBlock && (
        <p className="mt-3 text-[10px] leading-snug opacity-60">
          Includes your live client notes from this pitch. Reset notes before
          the next meeting to start fresh.
        </p>
      )}
    </div>
  );
}
