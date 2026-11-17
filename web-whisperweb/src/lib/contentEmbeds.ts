/**
 * Film + article share embeds — wire-compatible with the iOS
 * `WhisperFilmEmbed` / `WhisperArticleEmbed` (`::whisper-film-v1::` /
 * `::whisper-article-v1::` markers), so a film shared from either app
 * renders as a tappable cinema/journal card on both.
 */

export const FILM_EMBED_PREFIX = "::whisper-film-v1::";
export const ARTICLE_EMBED_PREFIX = "::whisper-article-v1::";

export interface FilmEmbedPayload {
  id: string;
  title: string;
  director: string;
  poster?: string | null;
  duration?: number | null;
}

export interface ArticleEmbedPayload {
  id: string;
  slug: string;
  title: string;
  author: string;
  cover?: string | null;
  category?: string | null;
}

export function encodeFilmEmbed(p: FilmEmbedPayload): string {
  return FILM_EMBED_PREFIX + JSON.stringify(p);
}

export function decodeFilmEmbed(
  body: string | null | undefined
): FilmEmbedPayload | null {
  const t = (body ?? "").trim();
  if (!t.startsWith(FILM_EMBED_PREFIX)) return null;
  try {
    const p = JSON.parse(t.slice(FILM_EMBED_PREFIX.length)) as FilmEmbedPayload;
    if (!p.id || !p.title) return null;
    return p;
  } catch {
    return null;
  }
}

export function encodeArticleEmbed(p: ArticleEmbedPayload): string {
  return ARTICLE_EMBED_PREFIX + JSON.stringify(p);
}

export function decodeArticleEmbed(
  body: string | null | undefined
): ArticleEmbedPayload | null {
  const t = (body ?? "").trim();
  if (!t.startsWith(ARTICLE_EMBED_PREFIX)) return null;
  try {
    const p = JSON.parse(
      t.slice(ARTICLE_EMBED_PREFIX.length)
    ) as ArticleEmbedPayload;
    if (!p.id || !p.title) return null;
    return p;
  } catch {
    return null;
  }
}

// MARK: - Coach plan questionnaire (wire-compatible with iOS)

export const PLAN_QUIZ_PREFIX = "::whisper-plan-quiz-v1::";
export const PLAN_QUIZ_ANSWERS_PREFIX = "::whisper-plan-quiz-answers-v1::";

export interface PlanQuizQuestion {
  id: string;
  q: string;
  opts: string[];
}

export interface PlanQuizPayload {
  id: string;
  coach: string;
  questions: PlanQuizQuestion[];
}

export interface PlanQuizAnswersPayload {
  quizId: string;
  client: string;
  answers: Record<string, string>;
}

export function encodePlanQuiz(p: PlanQuizPayload): string {
  return PLAN_QUIZ_PREFIX + JSON.stringify(p);
}

export function decodePlanQuiz(
  body: string | null | undefined
): PlanQuizPayload | null {
  const t = (body ?? "").trim();
  if (!t.startsWith(PLAN_QUIZ_PREFIX)) return null;
  try {
    const p = JSON.parse(t.slice(PLAN_QUIZ_PREFIX.length)) as PlanQuizPayload;
    if (!p.id || !Array.isArray(p.questions)) return null;
    return p;
  } catch {
    return null;
  }
}

export function encodePlanQuizAnswers(p: PlanQuizAnswersPayload): string {
  return PLAN_QUIZ_ANSWERS_PREFIX + JSON.stringify(p);
}

export function decodePlanQuizAnswers(
  body: string | null | undefined
): PlanQuizAnswersPayload | null {
  const t = (body ?? "").trim();
  if (!t.startsWith(PLAN_QUIZ_ANSWERS_PREFIX)) return null;
  try {
    const p = JSON.parse(
      t.slice(PLAN_QUIZ_ANSWERS_PREFIX.length)
    ) as PlanQuizAnswersPayload;
    if (!p.quizId || typeof p.answers !== "object" || p.answers === null) {
      return null;
    }
    return p;
  } catch {
    return null;
  }
}

/** The standard 8-question intake — identical ids/options to iOS so the
 * automation maps onto Jasper's fixed vocabularies on both platforms. */
export function standardPlanQuiz(coach: string): PlanQuizPayload {
  return {
    id: crypto.randomUUID().toLowerCase(),
    coach,
    questions: [
      { id: "goal", q: "Main goal right now?", opts: ["Build muscle", "Lose fat", "Get stronger", "Improve endurance", "General fitness"] },
      { id: "days", q: "Training days per week?", opts: ["2", "3", "4", "5", "6"] },
      { id: "session", q: "Time per session?", opts: ["30 min", "45 min", "60 min", "90 min"] },
      { id: "level", q: "Training experience?", opts: ["New", "1-2 years", "3+ years"] },
      { id: "limits", q: "Anything to train around?", opts: ["Nothing", "Shoulder", "Knee", "Lower back", "Hip"] },
      { id: "diet", q: "Eating style?", opts: ["No Preference", "High Protein", "Vegetarian", "Vegan", "Keto", "Mediterranean"] },
      { id: "allergies", q: "Food allergies?", opts: ["None", "Dairy", "Gluten", "Nuts", "Shellfish"] },
      { id: "meals", q: "Meals per day?", opts: ["2", "3", "4", "5"] },
    ],
  };
}

export const PLAN_QUIZ_DISPLAY_ORDER = [
  "goal", "days", "session", "level", "limits", "diet", "allergies", "meals",
];

export function planQuizLabel(id: string): string {
  switch (id) {
    case "goal": return "Goal";
    case "days": return "Days/wk";
    case "session": return "Session";
    case "level": return "Level";
    case "limits": return "Protect";
    case "diet": return "Diet";
    case "allergies": return "Allergies";
    case "meals": return "Meals";
    default: return id.charAt(0).toUpperCase() + id.slice(1);
  }
}

/** Answer → Jasper diet-generator goal vocabulary. */
export function planQuizDietGoal(answer: string | undefined): string {
  switch (answer) {
    case "Build muscle": return "Muscle Gain";
    case "Lose fat": return "Fat Loss";
    case "Get stronger": return "Lean Bulk";
    default: return "Maintain Weight";
  }
}

/** Answer → plan_shapes program goal vocabulary. */
export function planQuizProgramGoal(answer: string | undefined): string {
  switch (answer) {
    case "Build muscle": return "Build Muscle";
    case "Lose fat": return "Lose Fat";
    case "Get stronger": return "Get Stronger";
    case "Improve endurance": return "Improve Endurance";
    default: return "General Fitness";
  }
}

export interface ContentEmbedSplit {
  cleaned: string;
  film: FilmEmbedPayload | null;
  article: ArticleEmbedPayload | null;
}

/**
 * Splits a post caption into visible text + any film/article embed lines
 * planted by "Post to your wall". Cheap guard so normal captions never pay
 * for line scanning.
 */
export function parseContentEmbeds(
  text: string | null | undefined
): ContentEmbedSplit {
  const raw = text ?? "";
  if (!raw.includes("::whisper-")) {
    return { cleaned: raw, film: null, article: null };
  }
  let film: FilmEmbedPayload | null = null;
  let article: ArticleEmbedPayload | null = null;
  const kept: string[] = [];
  for (const line of raw.split("\n")) {
    const t = line.trim();
    if (!film) {
      const f = decodeFilmEmbed(t);
      if (f) {
        film = f;
        continue;
      }
    }
    if (!article) {
      const a = decodeArticleEmbed(t);
      if (a) {
        article = a;
        continue;
      }
    }
    kept.push(line);
  }
  return { cleaned: kept.join("\n").trim(), film, article };
}
