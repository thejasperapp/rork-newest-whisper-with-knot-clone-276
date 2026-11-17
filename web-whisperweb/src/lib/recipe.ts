import { supabase } from "@/lib/supabase";

/**
 * Web port of the iOS `WhisperRecipeEmbed` (`::whisper-recipe-v1::`). A recipe
 * card sent via `/recipe <dish>` (or `/ember recipe <dish>`). Ember generates
 * the recipe + a macro estimate and packs the summary, ingredients, steps and
 * macros into a DM embed so the recipient sees a rich, tappable card and can
 * log it straight to their Jasper macros — identical to the iOS card.
 */

const RECIPE_PREFIX = "::whisper-recipe-v1::";

/** Same body-length budget as the other DM embeds (see `dmEmber.ts`). */
const MAX_DM_BODY = 3800;

export interface RecipePayload {
  id: string;
  title: string;
  summary: string;
  prepTime: string | null;
  cookTime: string | null;
  servings: number | null;
  ingredients: string[];
  steps: string[];
  calories: number | null;
  protein: number | null;
  carbs: number | null;
  fat: number | null;
}

/**
 * Serialises a recipe payload, trimming steps/ingredients if the JSON would
 * exceed the `whisper_messages.body` length constraint (so the row always
 * persists rather than silently failing on insert).
 */
export function encodeRecipe(p: RecipePayload): string {
  let payload: RecipePayload = { ...p };
  let out = RECIPE_PREFIX + JSON.stringify(payload);
  while (out.length > MAX_DM_BODY && payload.steps.length > 1) {
    payload = { ...payload, steps: payload.steps.slice(0, -1) };
    out = RECIPE_PREFIX + JSON.stringify(payload);
  }
  while (out.length > MAX_DM_BODY && payload.ingredients.length > 1) {
    payload = { ...payload, ingredients: payload.ingredients.slice(0, -1) };
    out = RECIPE_PREFIX + JSON.stringify(payload);
  }
  return out;
}

export function decodeRecipe(
  body: string | null | undefined
): RecipePayload | null {
  if (!body || !body.startsWith(RECIPE_PREFIX)) return null;
  try {
    const o = JSON.parse(body.slice(RECIPE_PREFIX.length)) as Partial<RecipePayload>;
    if (typeof o.title !== "string") return null;
    return {
      id: o.id ?? crypto.randomUUID(),
      title: o.title,
      summary: o.summary ?? "",
      prepTime: o.prepTime ?? null,
      cookTime: o.cookTime ?? null,
      servings: typeof o.servings === "number" ? o.servings : null,
      ingredients: Array.isArray(o.ingredients)
        ? o.ingredients.filter((i): i is string => typeof i === "string")
        : [],
      steps: Array.isArray(o.steps)
        ? o.steps.filter((s): s is string => typeof s === "string")
        : [],
      calories: typeof o.calories === "number" ? o.calories : null,
      protein: typeof o.protein === "number" ? o.protein : null,
      carbs: typeof o.carbs === "number" ? o.carbs : null,
      fat: typeof o.fat === "number" ? o.fat : null,
    };
  } catch {
    return null;
  }
}

/** "10 min + 20 min" / "30 min" / null — mirrors iOS `totalTimeLabel`. */
export function recipeTotalTime(p: RecipePayload): string | null {
  if (p.prepTime && p.cookTime) return `${p.prepTime} + ${p.cookTime}`;
  return p.prepTime ?? p.cookTime ?? null;
}

/** Default meal slot for the current time, mirroring iOS `defaultMeal()`. */
function defaultMealSlot(): "breakfast" | "lunch" | "dinner" | "snack" {
  const hour = new Date().getHours();
  if (hour >= 4 && hour < 10) return "breakfast";
  if (hour >= 10 && hour < 15) return "lunch";
  if (hour >= 15 && hour < 21) return "dinner";
  return "snack";
}

/**
 * Logs a recipe's macro estimate into the shared `jasper_nutrition_meals`
 * table — the exact same contract the iOS `WhisperRecipeInlineCard` writes via
 * `NutritionStore.addMeal`, so the meal shows up in the sister Jasper app.
 */
export async function logRecipeMeal(
  userId: string,
  recipe: RecipePayload
): Promise<boolean> {
  if (!recipe.calories || recipe.calories <= 0) return false;

  let uid = userId;
  try {
    const { data } = await supabase.auth.getUser();
    if (data.user?.id) uid = data.user.id;
  } catch {
    /* fall back to passed userId */
  }

  const id = crypto.randomUUID();
  const slot = defaultMealSlot();
  const now = new Date();
  const eatenAt = now.toISOString();
  const row = {
    id,
    user_id: uid,
    client_id: id,
    name: recipe.title || "Recipe",
    calories: Math.round(recipe.calories),
    protein_g: recipe.protein ?? 0,
    carbs_g: recipe.carbs ?? 0,
    fat_g: recipe.fat ?? 0,
    eaten_at: eatenAt,
    source: "whisper_recipe",
    meal_type: slot,
    calories_kcal: Math.round(recipe.calories),
    logged_at: eatenAt,
    fiber_g: 0,
    visibility: "private",
  };

  try {
    const { error } = await supabase
      .from("jasper_nutrition_meals")
      .upsert(row, { onConflict: "id" });
    if (!error) return true;
    const msg = String(error.message ?? error).toLowerCase();
    if (
      msg.includes("meal_type") &&
      (msg.includes("could not find") ||
        msg.includes("pgrst204") ||
        msg.includes("schema cache") ||
        msg.includes("does not exist"))
    ) {
      const { meal_type: _omit, ...fallback } = row;
      void _omit;
      const { error: retryErr } = await supabase
        .from("jasper_nutrition_meals")
        .upsert(fallback, { onConflict: "id" });
      return !retryErr;
    }
    return false;
  } catch {
    return false;
  }
}
