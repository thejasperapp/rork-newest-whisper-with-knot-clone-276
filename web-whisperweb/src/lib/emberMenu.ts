import { supabase } from "@/lib/supabase";
import { fetchClientGoals } from "@/lib/jasperData";
import { emberMenuItems } from "@/lib/ember";

/**
 * Web port of the iOS `EmberMenuService` — resolves a restaurant's menu and
 * ranks each item against the viewer's *remaining* daily macros so the same
 * place shows different picks to different users. Resolution order:
 *   1. Chain table (offline-safe, instant)
 *   2. Ember web-grounded fetch (unknown / independent places)
 *   3. Generic healthy fallback
 */

export interface MenuEntry {
  id: string;
  name: string;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  tag: string | null;
}

export type MenuFilter = "all" | "highProtein" | "lowCal" | "lowCarb";

export const MENU_FILTERS: { id: MenuFilter; label: string }[] = [
  { id: "all", label: "Best fit" },
  { id: "highProtein", label: "High protein" },
  { id: "lowCal", label: "Low cal" },
  { id: "lowCarb", label: "Low carb" },
];

export interface RemainingMacros {
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
}

/** Meal slot, mirroring the iOS `MealType` picker on the Log button. */
export type MealSlot = "breakfast" | "lunch" | "dinner" | "snack" | "drink";

export const MEAL_SLOTS: { id: MealSlot; label: string }[] = [
  { id: "breakfast", label: "Breakfast" },
  { id: "lunch", label: "Lunch" },
  { id: "dinner", label: "Dinner" },
  { id: "snack", label: "Snack" },
  { id: "drink", label: "Drink" },
];

const cache = new Map<string, MenuEntry[]>();
const inflight = new Map<string, Promise<MenuEntry[]>>();

function entry(
  name: string,
  calories: number,
  protein: number,
  carbs: number,
  fat: number,
  tag: string
): MenuEntry {
  return { id: crypto.randomUUID(), name, calories, protein, carbs, fat, tag };
}

function dayKey(): string {
  return new Date().toISOString().slice(0, 10);
}

/** Resolve + cache a restaurant's menu (chain → Ember fetch → fallback). */
export async function resolveMenu(
  name: string,
  category: string | null,
  city: string | null
): Promise<MenuEntry[]> {
  const key = `${name.toLowerCase()}:${dayKey()}`;
  const hit = cache.get(key);
  if (hit) return hit;
  const running = inflight.get(key);
  if (running) return running;

  const task = (async (): Promise<MenuEntry[]> => {
    const chain = chainMenu(name);
    if (chain) return chain;
    const fetched = await emberMenuItems(name, category, city);
    if (fetched.length > 0) {
      return fetched.map((i) =>
        entry(i.name, i.calories, i.protein, i.carbs, i.fat, i.tag ?? "")
      );
    }
    return genericFallback();
  })();

  inflight.set(key, task);
  const result = await task;
  inflight.delete(key);
  cache.set(key, result);
  return result;
}

/** Macro-aware filter + ranking against the viewer's remaining macros. */
export function rankMenu(
  menu: MenuEntry[],
  filter: MenuFilter,
  remaining: RemainingMacros
): MenuEntry[] {
  const filtered = menu.filter((item) => {
    switch (filter) {
      case "all":
        return true;
      case "highProtein":
        return item.protein >= 25;
      case "lowCal":
        return item.calories <= 500;
      case "lowCarb":
        return item.carbs <= 30;
    }
  });
  const proteinGap = remaining.protein;
  const calGap = remaining.calories;
  const score = (i: MenuEntry): number => {
    const calOver = Math.max(0, i.calories - calGap) * 1.4;
    const proteinShort = Math.max(0, proteinGap - i.protein) * 1.6;
    const proteinBonus = -i.protein * 0.4;
    return calOver + proteinShort + proteinBonus;
  };
  return [...filtered].sort((a, b) => score(a) - score(b));
}

interface JasperMealRow {
  calories: number | null;
  calories_kcal: number | null;
  protein_g: number | null;
  carbs_g: number | null;
  fat_g: number | null;
}

/** Start/end ISO bounds for "today" in the local timezone. */
function todayBounds(): { start: string; end: string } {
  const now = new Date();
  const start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const end = new Date(start.getTime() + 24 * 60 * 60 * 1000);
  return { start: start.toISOString(), end: end.toISOString() };
}

/**
 * Sums everything the user has actually eaten today straight from the shared
 * `jasper_nutrition_meals` table — the same live source the iOS app reads via
 * `JasperNutritionRemoteService.fetchToday()`. This is what makes the card
 * reflect the viewer's *active* calories burned-down for the day.
 */
async function fetchConsumedToday(
  userId: string
): Promise<RemainingMacros | null> {
  try {
    const { start, end } = todayBounds();
    const { data, error } = await supabase
      .from("jasper_nutrition_meals")
      .select("calories, calories_kcal, protein_g, carbs_g, fat_g")
      .eq("user_id", userId)
      .gte("eaten_at", start)
      .lt("eaten_at", end)
      .limit(200);
    if (error || !data) return null;
    const rows = data as JasperMealRow[];
    return rows.reduce<RemainingMacros>(
      (acc, r) => {
        const cal = (r.calories ?? 0) > 0 ? (r.calories ?? 0) : r.calories_kcal ?? 0;
        acc.calories += cal;
        acc.protein += r.protein_g ?? 0;
        acc.carbs += r.carbs_g ?? 0;
        acc.fat += r.fat_g ?? 0;
        return acc;
      },
      { calories: 0, protein: 0, carbs: 0, fat: 0 }
    );
  } catch {
    return null;
  }
}

/**
 * Resolves the signed-in user's remaining macros for today, mirroring iOS:
 * the canonical daily goal MINUS everything already eaten today in Jasper
 * (`jasper_nutrition_meals`). This is the "check the user's active calories
 * from Jasper" behaviour — the same numbers the Jasper app shows.
 */
export async function fetchRemainingMacros(
  userId: string
): Promise<RemainingMacros> {
  // Daily budget (goal). Default mirrors iOS NutritionGoals.default.
  let goal: RemainingMacros = { calories: 2000, protein: 150, carbs: 250, fat: 65 };
  try {
    const goals = await fetchClientGoals(userId);
    if ((goals.calories ?? 0) > 0) {
      goal = {
        calories: goals.calories ?? goal.calories,
        protein: goals.protein_g ?? goal.protein,
        carbs: goals.carbs_g ?? goal.carbs,
        fat: goals.fat_g ?? goal.fat,
      };
    }
  } catch {
    /* keep default budget */
  }

  // Subtract what Jasper already has logged today.
  const consumed = await fetchConsumedToday(userId);
  if (!consumed) return goal;
  return {
    calories: Math.max(0, Math.round(goal.calories - consumed.calories)),
    protein: Math.max(0, goal.protein - consumed.protein),
    carbs: Math.max(0, goal.carbs - consumed.carbs),
    fat: Math.max(0, goal.fat - consumed.fat),
  };
}

/**
 * Encodes a meal slot as a canonical hour-of-day today, mirroring iOS so
 * Jasper's hour-bucketed grouping lands the row in the right slot even on
 * older clients that pre-date the `meal_type` column. Drinks fall through to
 * "now".
 */
function timestampForSlot(slot: MealSlot): string {
  const now = new Date();
  const hour =
    slot === "breakfast" ? 8
    : slot === "lunch" ? 12
    : slot === "dinner" ? 19
    : slot === "snack" ? 15
    : -1;
  if (hour < 0) return now.toISOString();
  const d = new Date(now.getFullYear(), now.getMonth(), now.getDate(), hour, 30);
  return d.toISOString();
}

/**
 * Logs a chosen item into the shared `jasper_nutrition_meals` table — the
 * exact same contract the iOS Whisper app writes to via
 * `JasperNutritionRemoteService.pushMeal`, so the meal really shows up in the
 * sister Jasper app. We resolve the live auth UID (RLS is owner-write) and
 * mirror legacy columns to satisfy NOT NULL constraints.
 */
export async function logMenuItem(
  userId: string,
  item: MenuEntry,
  restaurantName: string,
  placeId: string | null = null,
  slot: MealSlot = "snack"
): Promise<boolean> {
  // RLS checks auth.uid(); prefer the live session UID over the passed value.
  let uid = userId;
  try {
    const { data } = await supabase.auth.getUser();
    if (data.user?.id) uid = data.user.id;
  } catch {
    /* fall back to passed userId */
  }

  const id = crypto.randomUUID();
  const eatenAt = timestampForSlot(slot);
  const row = {
    id,
    user_id: uid,
    client_id: id,
    name: item.name || "Meal",
    calories: Math.round(item.calories),
    protein_g: item.protein,
    carbs_g: item.carbs,
    fat_g: item.fat,
    eaten_at: eatenAt,
    source: "whisper_restaurant",
    meal_type: slot,
    restaurant_name: restaurantName,
    restaurant_place_id: placeId,
    calories_kcal: Math.round(item.calories),
    logged_at: eatenAt,
    fiber_g: 0,
    visibility: "private",
  };

  try {
    const { error } = await supabase
      .from("jasper_nutrition_meals")
      .upsert(row, { onConflict: "id" });
    if (!error) return true;
    // Older shared table may not have `meal_type` yet — retry without it.
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

// MARK: - Chain table (mirrors the iOS catalogue)

function genericFallback(): MenuEntry[] {
  return [
    entry("Grilled Chicken Plate", 540, 42, 48, 18, "High protein"),
    entry("Salmon Bowl", 620, 36, 52, 24, "Balanced"),
    entry("House Salad + Protein", 420, 30, 22, 20, "Low carb"),
    entry("Veggie Wrap", 460, 16, 62, 14, "Plant-based"),
    entry("Pasta of the Day", 720, 24, 92, 22, "Indulgent"),
  ];
}

function chainMenu(name: string): MenuEntry[] | null {
  const l = name.toLowerCase();
  if (l.includes("chipotle"))
    return [
      entry("Chicken Burrito Bowl", 625, 45, 70, 18, "High protein"),
      entry("Steak Salad Bowl", 560, 40, 35, 22, "Low carb"),
      entry("Sofritas Bowl (no rice)", 410, 18, 38, 16, "Light"),
      entry("Chicken Quesadilla", 1100, 55, 95, 55, "Indulgent"),
      entry("Veggie Tacos (3)", 480, 18, 65, 14, "Plant-based"),
    ];
  if (l.includes("sweetgreen"))
    return [
      entry("Harvest Bowl", 705, 35, 85, 25, "Balanced"),
      entry("Chicken Pesto Parm", 690, 41, 47, 36, "High protein"),
      entry("Shroomami", 615, 21, 78, 22, "Plant-based"),
      entry("Guacamole Greens", 540, 16, 38, 32, "Veggie"),
      entry("Hummus Crunch (no pita)", 460, 19, 42, 18, "Light"),
    ];
  if (l.includes("cava"))
    return [
      entry("Greens + Grains Bowl", 540, 30, 58, 18, "Balanced"),
      entry("Lentil Avocado Bowl", 620, 22, 70, 24, "Plant-based"),
      entry("Spicy Lamb Pita", 780, 38, 72, 32, "Indulgent"),
      entry("Falafel Salad", 480, 18, 38, 22, "Veggie"),
      entry("Chicken Power Bowl", 560, 44, 35, 18, "High protein"),
    ];
  if (l.includes("shake shack") || l.includes("shakeshack"))
    return [
      entry("Single ShackBurger", 560, 30, 36, 32, "Indulgent"),
      entry("Chicken Shack", 540, 32, 45, 25, "Classic"),
      entry("Hamburger", 440, 26, 33, 23, "Lighter"),
      entry("Crispy Chicken Bites (6)", 410, 28, 25, 22, "High protein"),
      entry("Side of Fries", 470, 6, 56, 24, "Treat"),
    ];
  if (l.includes("chick-fil-a") || l.includes("chick fil a") || l.includes("chickfila"))
    return [
      entry("Grilled Chicken Sandwich", 390, 28, 44, 11, "Lean"),
      entry("Spicy Deluxe Sandwich", 550, 30, 45, 27, "Indulgent"),
      entry("Grilled Nuggets (8ct)", 140, 25, 1, 3, "High protein"),
      entry("Cobb Salad (grilled)", 520, 41, 27, 27, "Balanced"),
      entry("Market Salad (grilled)", 330, 26, 22, 14, "Light"),
    ];
  if (l.includes("starbucks"))
    return [
      entry("Egg White & Pepper Bites", 170, 13, 11, 8, "Light"),
      entry("Spinach Feta Wrap", 290, 14, 33, 10, "Balanced"),
      entry("Turkey Bacon Sandwich", 230, 17, 28, 5, "Lean"),
      entry("Bacon Gouda Sandwich", 360, 17, 31, 18, "Indulgent"),
      entry("Protein Box (eggs)", 460, 23, 40, 25, "High protein"),
    ];
  if (l.includes("panera"))
    return [
      entry("Green Goddess Cobb", 530, 41, 24, 31, "High protein"),
      entry("Modern Greek Salad", 380, 28, 18, 22, "Low carb"),
      entry("Mediterranean Bowl", 560, 18, 71, 22, "Plant-based"),
      entry("Chicken Avocado Sandwich", 720, 41, 56, 34, "Hearty"),
      entry("Broccoli Cheddar Soup", 360, 12, 30, 22, "Comfort"),
    ];
  if (l.includes("mcdonald"))
    return [
      entry("Egg McMuffin", 310, 17, 30, 13, "Lighter"),
      entry("Big Mac", 590, 25, 46, 33, "Indulgent"),
      entry("McDouble", 400, 22, 33, 20, "Classic"),
      entry("Grilled Chicken McWrap", 360, 30, 38, 11, "High protein"),
      entry("Side Salad", 15, 1, 3, 0, "Light"),
    ];
  if (l.includes("subway"))
    return [
      entry('Turkey 6" on Wheat', 280, 19, 41, 4, "Lean"),
      entry('Rotisserie Chicken 6"', 350, 29, 45, 6, "High protein"),
      entry('Steak & Cheese 6"', 380, 24, 41, 12, "Hearty"),
      entry('Veggie Delite 6"', 230, 9, 44, 3, "Light"),
      entry('Tuna Salad 6"', 470, 19, 40, 25, "Filling"),
    ];
  if (l.includes("taco bell"))
    return [
      entry("Power Menu Bowl (chicken)", 470, 27, 50, 18, "Balanced"),
      entry("Crunchwrap Supreme", 530, 16, 71, 21, "Indulgent"),
      entry("Soft Taco (beef)", 180, 9, 17, 8, "Light"),
      entry("Black Bean Quesarito", 620, 18, 78, 26, "Plant-based"),
      entry("Chalupa Supreme (chicken)", 360, 16, 30, 19, "Classic"),
    ];
  return null;
}
