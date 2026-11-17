import { supabase } from "@/lib/supabase";

/**
 * Web port of the iOS `WhisperJasperDataService` macro resolution. The
 * canonical source of truth for a client's current calories + macros is
 * `jasper_preferences.payload_json.nutrition_goals` — it's upserted on every
 * macro-survey save, goal edit, diet-plan save and app foreground. We read
 * that first, then fall back to the active `jasper_diet_plans` row and finally
 * the legacy `user_data` blob, so the coach card lights up regardless of which
 * client build wrote the data.
 *
 * Jasper builds in the wild write the macros with wildly inconsistent shapes
 * (object vs JSON-encoded string in jsonb, `protein_g` vs `protein` vs
 * `target_protein_g` vs `targetProtein`, nested under unexpected keys), so the
 * resolver tolerates all of them via a recursive scan.
 */

export interface JasperGoals {
  calories: number | null;
  protein_g: number | null;
  carbs_g: number | null;
  fat_g: number | null;
  /** Where the values came from — surfaced in the UI for transparency. */
  source: "preferences" | "diet_plan" | "user_data" | null;
  updatedAt: string | null;
}

const CAL_KEYS = ["calories", "calorie", "target_calories", "targetCalories", "kcal"];
const PROTEIN_KEYS = [
  "protein_g", "protein", "target_protein_g", "target_protein", "targetProtein", "proteinGrams",
];
const CARB_KEYS = [
  "carbs_g", "carbs", "target_carbs_g", "target_carbs", "targetCarbs", "carbsGrams",
  "carbohydrates", "carbohydrates_g",
];
const FAT_KEYS = ["fat_g", "fat", "target_fat_g", "target_fat", "targetFat", "fatGrams"];

type Json = unknown;

function num(dict: Record<string, Json>, keys: string[]): number | null {
  for (const k of keys) {
    const v = dict[k];
    if (typeof v === "number" && v > 0) return v;
    if (typeof v === "string") {
      const n = Number(v);
      if (Number.isFinite(n) && n > 0) return n;
    }
  }
  return null;
}

/** Coerces a jsonb cell that may be an object or a JSON-encoded string. */
function normalize(raw: Json): Record<string, Json> | null {
  if (raw && typeof raw === "object" && !Array.isArray(raw)) {
    return raw as Record<string, Json>;
  }
  if (typeof raw === "string") {
    try {
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        return parsed as Record<string, Json>;
      }
    } catch {
      /* not JSON */
    }
  }
  return null;
}

interface Goals {
  calories: number | null;
  protein_g: number | null;
  carbs_g: number | null;
  fat_g: number | null;
}

function extractGoals(raw: Json): Goals | null {
  const dict = normalize(raw);
  if (!dict) return null;
  const calories = num(dict, CAL_KEYS);
  const protein_g = num(dict, PROTEIN_KEYS);
  const carbs_g = num(dict, CARB_KEYS);
  const fat_g = num(dict, FAT_KEYS);
  if (calories == null && protein_g == null && carbs_g == null && fat_g == null) {
    return null;
  }
  return { calories, protein_g, carbs_g, fat_g };
}

/** Recursively scans a JSON tree for the first goals-shaped object. */
function deepFindGoals(raw: Json): Goals | null {
  let best: Goals | null = null;
  const visit = (node: Json): void => {
    if (best && (best.calories ?? 0) > 0) return;
    if (typeof node === "string") {
      try {
        visit(JSON.parse(node));
      } catch {
        /* leaf string */
      }
      return;
    }
    if (Array.isArray(node)) {
      for (const item of node) visit(item);
      return;
    }
    if (!node || typeof node !== "object") return;
    const g = extractGoals(node);
    if (g && (g.calories ?? 0) > 0) {
      best = g;
      return;
    }
    if (!best && g) best = g;
    for (const v of Object.values(node as Record<string, Json>)) visit(v);
  };
  visit(raw);
  return best;
}

interface PrefsRow {
  payload_json: Json;
  updated_at: string | null;
}

interface DietPlanRow {
  target_calories: number | null;
  target_protein_g: number | null;
  target_carbs_g: number | null;
  target_fat_g: number | null;
  recorded_on: string | null;
}

interface UserDataRow {
  data_blob: string | null;
}

/**
 * Writes calorie/macro targets into the signed-in user's canonical
 * `jasper_preferences.payload_json.nutrition_goals`, the exact same place
 * the iOS Jasper app reads on launch. Only the fields supplied are changed;
 * everything else in the preferences blob is preserved. Mirrors the iOS
 * `WhisperCoachMacrosImport.apply` behaviour (merge, never clobber). Returns
 * true on a successful write.
 */
export async function applyMyGoals(
  userId: string,
  patch: { calories?: number | null; protein_g?: number | null; carbs_g?: number | null; fat_g?: number | null }
): Promise<boolean> {
  try {
    const { data } = await supabase
      .from("jasper_preferences")
      .select("payload_json")
      .eq("user_id", userId)
      .limit(1)
      .maybeSingle();
    const existing = normalize((data as PrefsRow | null)?.payload_json) ?? {};
    const existingGoals = normalize(existing["nutrition_goals"]) ?? {};
    const mergedGoals: Record<string, Json> = { ...existingGoals };
    // Write both `_g` and bare keys so every Jasper build picks it up.
    if (patch.calories != null) mergedGoals["calories"] = patch.calories;
    if (patch.protein_g != null) {
      mergedGoals["protein_g"] = patch.protein_g;
      mergedGoals["protein"] = patch.protein_g;
    }
    if (patch.carbs_g != null) {
      mergedGoals["carbs_g"] = patch.carbs_g;
      mergedGoals["carbs"] = patch.carbs_g;
    }
    if (patch.fat_g != null) {
      mergedGoals["fat_g"] = patch.fat_g;
      mergedGoals["fat"] = patch.fat_g;
    }
    const payload = { ...existing, nutrition_goals: mergedGoals };
    const { error } = await supabase.from("jasper_preferences").upsert(
      { user_id: userId, payload_json: payload, updated_at: new Date().toISOString() },
      { onConflict: "user_id" }
    );
    return !error;
  } catch {
    return false;
  }
}

/**
 * Resolves a coached client's canonical nutrition goals. Tries each source in
 * priority order and returns the first that yields positive calories. Never
 * throws — RLS / missing-table failures resolve to empty so the coach UI can
 * fall back to manual entry.
 */
export async function fetchClientGoals(clientUserId: string): Promise<JasperGoals> {
  const empty: JasperGoals = {
    calories: null,
    protein_g: null,
    carbs_g: null,
    fat_g: null,
    source: null,
    updatedAt: null,
  };

  // 1) jasper_preferences.payload_json.nutrition_goals (canonical).
  try {
    const { data } = await supabase
      .from("jasper_preferences")
      .select("payload_json, updated_at")
      .eq("user_id", clientUserId)
      .limit(1)
      .maybeSingle();
    const row = data as PrefsRow | null;
    if (row) {
      const payload = normalize(row.payload_json);
      const goals =
        (payload && extractGoals(payload["nutrition_goals"])) ||
        (payload && extractGoals(payload)) ||
        deepFindGoals(row.payload_json);
      if (goals && (goals.calories ?? 0) > 0) {
        return { ...goals, source: "preferences", updatedAt: row.updated_at };
      }
    }
  } catch {
    /* RLS or missing table */
  }

  // 2) Active jasper_diet_plans row.
  try {
    const { data } = await supabase
      .from("jasper_diet_plans")
      .select("target_calories, target_protein_g, target_carbs_g, target_fat_g, recorded_on")
      .eq("user_id", clientUserId)
      .eq("is_active", true)
      .order("recorded_on", { ascending: false })
      .limit(1)
      .maybeSingle();
    const row = data as DietPlanRow | null;
    if (row && (row.target_calories ?? 0) > 0) {
      return {
        calories: row.target_calories,
        protein_g: row.target_protein_g,
        carbs_g: row.target_carbs_g,
        fat_g: row.target_fat_g,
        source: "diet_plan",
        updatedAt: row.recorded_on,
      };
    }
  } catch {
    /* RLS or missing table */
  }

  // 3) Legacy user_data blob (base64-encoded NutritionGoals struct).
  try {
    const { data } = await supabase
      .from("user_data")
      .select("data_blob")
      .eq("user_id", clientUserId)
      .eq("data_key", "jasper_nutrition_goals")
      .limit(1)
      .maybeSingle();
    const row = data as UserDataRow | null;
    if (row?.data_blob) {
      let json = row.data_blob;
      try {
        json = atob(row.data_blob);
      } catch {
        /* already plain JSON */
      }
      const goals = deepFindGoals(json);
      if (goals && (goals.calories ?? 0) > 0) {
        return { ...goals, source: "user_data", updatedAt: null };
      }
    }
  } catch {
    /* RLS or missing table */
  }

  return empty;
}
