/**
 * Ember's brand background check — when a company signs up, Ember researches
 * their public Instagram (tagged posts, creator collabs, real product
 * mentions) through a web-search-grounded model so brands can't lie about
 * using social platforms to recruit creators/athletes.
 *
 * Uses the same Rork toolkit Vercel AI Gateway passthrough as every other
 * Ember feature, but with Perplexity Sonar (search-grounded) instead of a
 * plain chat model so the answer reflects the live web.
 */

const TOOLKIT_SECRET: string =
  (import.meta.env.EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY as string | undefined) ??
  "";
const TOOLKIT_BASE: string = (() => {
  const raw =
    (import.meta.env.EXPO_PUBLIC_TOOLKIT_URL as string | undefined) ??
    "https://toolkit.rork.com";
  const trimmed = raw.replace(/\/+$/, "");
  return /^https?:\/\//.test(trimmed) ? trimmed : `https://${trimmed}`;
})();

const ENDPOINT = `${TOOLKIT_BASE}/v2/vercel/v1/chat/completions`;

/** Search-grounded model — required so Ember can actually look at the web. */
const SEARCH_MODEL = "perplexity/sonar";

export interface EmberBrandVerdict {
  verified: boolean;
  score: number;
  summary: string;
}

const SYSTEM_PROMPT = `You are Ember, Whisper's safety companion. Your job is to protect creators and athletes from fake sponsor brands.
You will be given a company name and their claimed Instagram handle. Research the live web:
1. Does instagram.com/{handle} appear to be a real, active account belonging to this company?
2. Do real people tag or mention this company's products in posts (tagged posts, creator collaborations, sponsored content, reviews)?
3. Is there evidence the company genuinely works with creators/athletes on social platforms?
Be skeptical — a missing or inactive account, no third-party mentions, or a handle that belongs to someone else should fail verification.
Respond ONLY with a JSON object, no markdown fences, in exactly this shape:
{"authentic": true or false, "score": 0-100, "summary": "2-3 plain sentences a creator can read"}
"authentic" is true only when the Instagram presence is real AND there is evidence of genuine product tags/mentions or creator collaborations. "score" is your 0-100 confidence that this brand is safe for creators.`;

/** Pull the first JSON object out of a model reply (tolerates fences). */
function parseVerdict(raw: string): EmberBrandVerdict | null {
  const match = raw.match(/\{[\s\S]*\}/);
  if (!match) return null;
  try {
    const parsed = JSON.parse(match[0]) as {
      authentic?: unknown;
      score?: unknown;
      summary?: unknown;
    };
    const score = Math.round(Number(parsed.score));
    return {
      verified: parsed.authentic === true,
      score: Number.isFinite(score) ? Math.min(100, Math.max(0, score)) : 0,
      summary:
        typeof parsed.summary === "string" && parsed.summary.trim()
          ? parsed.summary.trim().slice(0, 1200)
          : "Jasper couldn't summarize this brand's Instagram presence.",
    };
  } catch {
    return null;
  }
}

/**
 * Runs Ember's live Instagram review for a brand. Throws with a friendly
 * message when the check can't run (offline, model error).
 */
export async function emberInspectBrand(opts: {
  companyName: string;
  instagram: string;
  website?: string;
}): Promise<EmberBrandVerdict> {
  if (!TOOLKIT_SECRET) {
    throw new Error("Jasper isn't available right now — try again later.");
  }
  const handle = opts.instagram.replace(/^@+/, "").trim();
  if (!handle) throw new Error("Enter the brand's Instagram handle first.");

  const userPrompt = [
    `Company name: ${opts.companyName.trim()}`,
    `Claimed Instagram: instagram.com/${handle}`,
    opts.website?.trim() ? `Website: ${opts.website.trim()}` : null,
    "Research this brand's Instagram presence and tagged posts now, then return the JSON verdict.",
  ]
    .filter(Boolean)
    .join("\n");

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 60000);
  try {
    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${TOOLKIT_SECRET}`,
      },
      body: JSON.stringify({
        model: SEARCH_MODEL,
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: userPrompt },
        ],
        max_tokens: 600,
        temperature: 0.2,
      }),
      signal: controller.signal,
    });
    if (!res.ok) {
      throw new Error("Jasper couldn't reach the web right now — try again.");
    }
    const data = (await res.json()) as {
      choices?: { message?: { content?: string } }[];
    };
    const content = data.choices?.[0]?.message?.content ?? "";
    const verdict = parseVerdict(content);
    if (!verdict) {
      throw new Error("Jasper couldn't finish the review — try again.");
    }
    return verdict;
  } finally {
    clearTimeout(timer);
  }
}
