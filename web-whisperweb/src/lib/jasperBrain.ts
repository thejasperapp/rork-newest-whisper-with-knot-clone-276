/**
 * Jasper Brain — ONE shared intelligence config for iOS + web.
 *
 * Admins write voice/grammar, formatting, knowledge, and guardrail rules at
 * /jasper-brain; this module composes them into a single block appended to
 * every Jasper system prompt. iOS reads the same table and composes the
 * IDENTICAL block, so Jasper's behavior matches across platforms.
 *
 * Zero-cost discipline: a plain DB read cached for 5 minutes, fetched only
 * when a Jasper call actually happens. Failures (or an un-migrated table)
 * resolve to "" so Jasper keeps working exactly as before.
 */
import { supabase } from "@/lib/supabase";

export interface JasperBrainRow {
  section: string;
  title: string;
  content: string;
  updated_by: string | null;
  updated_at: string | null;
}

/** Section metadata — order here IS the order inside the composed block
 *  (mirrored byte-for-byte by the iOS service). */
export const JASPER_BRAIN_SECTIONS: {
  id: string;
  title: string;
  hint: string;
  placeholder: string;
}[] = [
  {
    id: "voice",
    title: "Voice & grammar",
    hint: "How Jasper talks everywhere — tone, phrasing, contractions, words to avoid.",
    placeholder:
      'e.g. "Always sound like a sharp gym friend, never corporate. Contractions always. Never say \'as an AI\', \'utilize\', or \'furthermore\'."',
  },
  {
    id: "formatting",
    title: "Formatting & cards",
    hint: "Reply structure rules — bold leads, bullets, when to attach interactive cards.",
    placeholder:
      'e.g. "Lead with one bold takeaway. Numbers get bullets. Attach a plan card whenever the user asks for a routine."',
  },
  {
    id: "knowledge",
    title: "Whisper knowledge",
    hint: "Facts Jasper always knows — features, pricing, people, positioning.",
    placeholder:
      'e.g. "Whisper One is $x/mo and includes… Recruiters verify athletes, creators, and coaches. Films live under the Films tab."',
  },
  {
    id: "guardrails",
    title: "Guardrails",
    hint: "Hard lines — what Jasper must never say or do.",
    placeholder:
      'e.g. "Never give medical dosage advice. Never promise earnings. Never mention competitor apps by name."',
  },
];

const HEADER =
  "=== JASPER TEAM BRAIN (live shared rules — identical on iOS and web; follow them exactly) ===";

/** Pure composer — used by the runtime block AND the editor's live preview. */
export function composeJasperBrainBlock(contents: Record<string, string>): string {
  const parts: string[] = [];
  for (const meta of JASPER_BRAIN_SECTIONS) {
    const content = (contents[meta.id] ?? "").trim();
    if (content) parts.push(`[${meta.title}]\n${content.slice(0, 1200)}`);
  }
  return parts.length > 0 ? `${HEADER}\n${parts.join("\n\n")}` : "";
}

/** All rows, for the editor page. Throws on error so the page can show an
 *  honest "run the migration" state. */
export async function fetchJasperBrain(): Promise<JasperBrainRow[]> {
  const { data, error } = await supabase
    .from("jasper_brain")
    .select("section,title,content,updated_by,updated_at");
  if (error) throw error;
  return (data ?? []) as JasperBrainRow[];
}

/** Saves one section and busts the runtime cache. */
export async function saveJasperBrainSection(
  section: string,
  title: string,
  content: string,
  updatedBy: string
): Promise<void> {
  const { error } = await supabase.from("jasper_brain").upsert(
    {
      section,
      title,
      content,
      updated_by: updatedBy,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "section" }
  );
  if (error) throw error;
  invalidateJasperBrain();
}

let blockCache: { text: string; at: number } | null = null;

export function invalidateJasperBrain(): void {
  blockCache = null;
}

/** The composed team-rules block appended to Jasper system prompts.
 *  Cached 5 minutes; "" when empty or unreachable. */
export async function jasperBrainBlock(): Promise<string> {
  if (blockCache && Date.now() - blockCache.at < 300_000) return blockCache.text;
  try {
    const rows = await fetchJasperBrain();
    const contents: Record<string, string> = {};
    for (const r of rows) contents[r.section] = r.content;
    const text = composeJasperBrainBlock(contents);
    blockCache = { text, at: Date.now() };
    return text;
  } catch {
    blockCache = { text: "", at: Date.now() };
    return "";
  }
}
