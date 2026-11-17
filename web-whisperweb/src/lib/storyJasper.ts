import { emberCompletion, emberConverseWithImage } from "@/lib/ember";

/**
 * Jasper's story brain — the web mirror of the iOS `WhisperStoryJasperBrain`.
 * One vision call reads the actual canvas photo and writes caption ideas +
 * "ask your viewers" prompts for it, plus a once-a-day "Today's spark"
 * cached in localStorage so the whole day shares a single model call.
 * Social energy on purpose — never fitness-coach tone unless the photo is
 * clearly a workout.
 */

export interface StorySparks {
  captions: string[];
  questions: string[];
}

const clean = (s: string): string => s.trim().replace(/^["'`]+|["'`]+$/g, "");

/** Downscaled JPEG data URL for the vision call (mirrors the iOS 1024px cap). */
export async function fileToDataUrl(
  file: File | Blob,
  maxDim = 1024
): Promise<string> {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, maxDim / Math.max(bitmap.width, bitmap.height, 1));
  const canvas = document.createElement("canvas");
  canvas.width = Math.max(1, Math.round(bitmap.width * scale));
  canvas.height = Math.max(1, Math.round(bitmap.height * scale));
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("canvas_unavailable");
  ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  bitmap.close();
  return canvas.toDataURL("image/jpeg", 0.6);
}

/** Reads the photo and returns 3 caption ideas + 3 viewer questions. */
export async function storySparks(
  imageDataUrl: string
): Promise<StorySparks | null> {
  const prompt = `Look at this story photo and return STRICT JSON only (no prose, no code fence):
{"captions":["…","…","…"],"questions":["…","…","…"]}
captions: 3 short punchy story captions for THIS exact photo — ≤70 chars, no hashtags, at most one emoji, three different vibes (one witty, one warm, one bold).
questions: 3 playful "ask your viewers" prompts grounded in what's visible — ≤60 chars, question form, the kind people actually answer.
Social-app energy. Never fitness-coach tone unless the photo is clearly a workout.`;
  const reply = await emberConverseWithImage([], imageDataUrl, prompt);
  const start = reply.indexOf("{");
  const end = reply.lastIndexOf("}");
  if (start < 0 || end <= start) return null;
  try {
    const parsed = JSON.parse(reply.slice(start, end + 1)) as {
      captions?: string[];
      questions?: string[];
    };
    const captions = (parsed.captions ?? []).map(clean).filter(Boolean).slice(0, 3);
    const questions = (parsed.questions ?? []).map(clean).filter(Boolean).slice(0, 3);
    if (captions.length === 0 && questions.length === 0) return null;
    return { captions, questions };
  } catch {
    return null;
  }
}

const FALLBACK_SPARKS: string[] = [
  "Show us your view right now",
  "The last photo you took — no context",
  "Three emojis that sum up today",
  "What's on your desk?",
  "Your current obsession, one photo",
  "Something small that made you smile today",
  "Tonight's plans in one picture",
];

const SPARK_DATE_KEY = "whisper_story_spark_date";
const SPARK_TEXT_KEY = "whisper_story_spark_text";

/** One fun prompt per calendar day, cached so the day shares one call. */
export async function dailyStorySpark(): Promise<string> {
  const today = new Date().toISOString().slice(0, 10);
  try {
    if (localStorage.getItem(SPARK_DATE_KEY) === today) {
      const cached = localStorage.getItem(SPARK_TEXT_KEY);
      if (cached) return cached;
    }
  } catch {
    /* storage unavailable */
  }
  const generated = clean(
    await emberCompletion(
      [
        {
          role: "system",
          content:
            "You write ONE daily story prompt for a social app. Any topic — life, food, views, music, pets, hot takes. Not fitness-specific. ≤60 characters. Imperative or question form. No quotes, no emoji, no preamble — just the prompt.",
        },
        { role: "user", content: `Today's spark (${today}):` },
      ],
      40
    )
  );
  const spark =
    generated && generated.length <= 80
      ? generated
      : FALLBACK_SPARKS[Math.floor(Math.random() * FALLBACK_SPARKS.length)]!;
  try {
    localStorage.setItem(SPARK_DATE_KEY, today);
    localStorage.setItem(SPARK_TEXT_KEY, spark);
  } catch {
    /* storage unavailable */
  }
  return spark;
}
