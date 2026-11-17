import { memo, useState } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import {
  UtensilsCrossed,
  BookOpen,
  Clock,
  Users,
  Flame,
  Plus,
  Check,
  ShoppingCart,
  X,
} from "lucide-react";
import { toast } from "sonner";

import { cn } from "@/lib/utils";
import {
  type RecipePayload,
  recipeTotalTime,
  logRecipeMeal,
} from "@/lib/recipe";
import { saveRecipe } from "@/lib/jasperConnect";

/**
 * Web parity with the iOS `WhisperRecipeInlineCard` + `WhisperRecipeDetailSheet`.
 * Renders a recipe sent through DM: a compact tappable bubble that opens a full
 * detail modal with ingredients, steps, a "Log to my macros" action (writes to
 * the shared `jasper_nutrition_meals` table) and an "Add to grocery list"
 * action that sends a collaborative grocery embed back into the thread.
 */
function RecipeCardBase({
  payload,
  mine,
  meId,
  onAddToGrocery,
}: {
  payload: RecipePayload;
  mine: boolean;
  meId: string;
  /** Sends the recipe's ingredients into the thread as a grocery list embed. */
  onAddToGrocery?: (title: string, ingredients: string[]) => void;
}) {
  const [open, setOpen] = useState<boolean>(false);
  const [logged, setLogged] = useState<boolean>(false);
  const totalTime = recipeTotalTime(payload);
  const hasCalories = !!payload.calories && payload.calories > 0;

  const saveToJasper = async (): Promise<void> => {
    if (logged) return;
    setLogged(true);
    const ok = await logRecipeMeal(meId, payload);
    if (ok) {
      toast("Saved to Jasper");
    } else {
      setLogged(false);
      toast.error("Couldn't log that — please try again.");
    }
  };

  return (
    <>
      <div
        className={cn(
          "w-[min(260px,82vw)] overflow-hidden rounded-[18px] border p-3.5 text-left",
          mine
            ? "border-transparent bg-primary text-primary-foreground"
            : "border-border bg-card text-foreground"
        )}
      >
        <button
          type="button"
          onClick={() => setOpen(true)}
          className="block w-full text-left"
        >
          <div className="flex items-center gap-2">
            <UtensilsCrossed className="h-3.5 w-3.5 shrink-0" />
            <span className="line-clamp-2 text-sm font-bold">{payload.title}</span>
          </div>
          {payload.summary && (
            <p className="mt-2 line-clamp-3 text-xs opacity-85">{payload.summary}</p>
          )}
          <div className="mt-2.5 flex flex-wrap gap-1.5">
            {totalTime && <Chip mine={mine} icon={<Clock className="h-3 w-3" />} text={totalTime} />}
            {payload.servings != null && (
              <Chip
                mine={mine}
                icon={<Users className="h-3 w-3" />}
                text={`${payload.servings} servings`}
              />
            )}
            {hasCalories && (
              <Chip
                mine={mine}
                icon={<Flame className="h-3 w-3" />}
                text={`${payload.calories} cal`}
              />
            )}
          </div>
          <p className="mt-2.5 text-[11px] font-bold opacity-70">Tap to view recipe</p>
        </button>

        {hasCalories && (
          <button
            type="button"
            onClick={saveToJasper}
            disabled={logged}
            className={cn(
              "mt-2.5 flex w-full items-center justify-center gap-1.5 rounded-full py-1.5 text-xs font-bold transition-colors",
              mine ? "bg-white/15 hover:bg-white/25" : "bg-black/[0.08] hover:bg-black/[0.14]"
            )}
          >
            {logged ? <Check className="h-3.5 w-3.5" /> : <Plus className="h-3.5 w-3.5" />}
            {logged ? "Saved to Jasper" : "Save to Jasper"}
          </button>
        )}
      </div>

      <RecipeDetailModal
        open={open}
        onOpenChange={setOpen}
        payload={payload}
        meId={meId}
        onAddToGrocery={onAddToGrocery}
      />
    </>
  );
}

function Chip({
  mine,
  icon,
  text,
}: {
  mine: boolean;
  icon: React.ReactNode;
  text: string;
}) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-bold",
        mine ? "bg-white/15" : "bg-black/[0.06]"
      )}
    >
      {icon}
      {text}
    </span>
  );
}

function RecipeDetailModal({
  open,
  onOpenChange,
  payload,
  meId,
  onAddToGrocery,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  payload: RecipePayload;
  meId: string;
  onAddToGrocery?: (title: string, ingredients: string[]) => void;
}) {
  const [logged, setLogged] = useState<boolean>(false);
  const [groceryAdded, setGroceryAdded] = useState<boolean>(false);
  const [libSaved, setLibSaved] = useState<boolean>(false);
  const hasCalories = !!payload.calories && payload.calories > 0;

  const logMacros = async (): Promise<void> => {
    if (logged) return;
    setLogged(true);
    const ok = await logRecipeMeal(meId, payload);
    if (ok) {
      toast("Logged to Jasper");
    } else {
      setLogged(false);
      toast.error("Couldn't log that — please try again.");
    }
  };

  const addGrocery = (): void => {
    if (groceryAdded || !onAddToGrocery) return;
    onAddToGrocery(payload.title, payload.ingredients);
    setGroceryAdded(true);
    onOpenChange(false);
  };

  /** Saves into the SHARED recipe library (Jasper → Nutrition → Recipes).
   * The DM card only carries per-serving totals, so macros are split evenly
   * across ingredients — honest estimates, editable in Jasper; the derived
   * per-serving math (totals ÷ servings) lands exactly on the card's numbers. */
  const saveToRecipeLibrary = async (): Promise<void> => {
    if (libSaved) return;
    const servings = Math.max(1, payload.servings ?? 1);
    const count = Math.max(1, payload.ingredients.length);
    try {
      await saveRecipe({
        name: payload.title,
        servings,
        note: payload.summary,
        steps: payload.steps,
        prepTime: payload.prepTime ?? undefined,
        cookTime: payload.cookTime ?? undefined,
        ingredients: payload.ingredients.map((name) => ({
          name,
          calories: Math.round(((payload.calories ?? 0) * servings) / count),
          protein: Math.round(((payload.protein ?? 0) * servings) / count),
          carbs: Math.round(((payload.carbs ?? 0) * servings) / count),
          fat: Math.round(((payload.fat ?? 0) * servings) / count),
          servingUnit: "serving",
          numberOfServings: 1,
        })),
      });
      setLibSaved(true);
      toast("Saved to your Jasper recipes — it's in both apps now.");
    } catch {
      toast.error("Couldn't save — is this account connected to Jasper?");
    }
  };

  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-[60] bg-black/60 backdrop-blur-[2px] data-[state=open]:animate-in data-[state=open]:fade-in-0" />
        <Dialog.Content
          className="fixed inset-x-0 bottom-0 z-[60] mx-auto flex max-h-[90vh] w-full max-w-[480px] flex-col rounded-t-[26px] bg-background shadow-2xl outline-none data-[state=open]:animate-in data-[state=open]:slide-in-from-bottom sm:bottom-auto sm:top-1/2 sm:-translate-y-1/2 sm:rounded-[26px]"
        >
          <div className="flex items-center justify-between border-b border-border px-4 py-3.5">
            <Dialog.Title className="font-display text-[17px] font-bold">
              Recipe
            </Dialog.Title>
            <button
              onClick={() => onOpenChange(false)}
              className="flex h-8 w-8 items-center justify-center rounded-full transition-colors hover:bg-secondary"
              aria-label="Close"
            >
              <X className="h-5 w-5" />
            </button>
          </div>

          <div className="min-h-0 flex-1 space-y-5 overflow-y-auto px-5 py-5">
            <div>
              <h2 className="text-xl font-bold">{payload.title}</h2>
              {payload.summary && (
                <p className="mt-1.5 text-sm text-muted-foreground">{payload.summary}</p>
              )}
            </div>

            {(hasCalories || payload.protein != null) && (
              <div className="flex flex-wrap gap-2">
                {hasCalories && (
                  <MacroTag text={`${payload.calories} cal`} color="#f97316" icon={<Flame className="h-3 w-3" />} />
                )}
                {payload.protein != null && (
                  <MacroTag text={`${Math.round(payload.protein)}p`} color="#ef4444" />
                )}
                {payload.carbs != null && (
                  <MacroTag text={`${Math.round(payload.carbs)}c`} color="#eab308" />
                )}
                {payload.fat != null && (
                  <MacroTag text={`${Math.round(payload.fat)}f`} color="#3b82f6" />
                )}
              </div>
            )}

            {payload.ingredients.length > 0 && (
              <section>
                <h3 className="mb-2 text-base font-bold">Ingredients</h3>
                <ul className="space-y-1.5">
                  {payload.ingredients.map((line, i) => (
                    <li key={i} className="flex gap-2 text-sm">
                      <span className="text-muted-foreground">•</span>
                      <span>{line}</span>
                    </li>
                  ))}
                </ul>
              </section>
            )}

            {payload.steps.length > 0 && (
              <section>
                <h3 className="mb-2 text-base font-bold">Steps</h3>
                <ol className="space-y-2.5">
                  {payload.steps.map((step, i) => (
                    <li key={i} className="flex gap-2.5 text-sm">
                      <span className="shrink-0 font-bold text-muted-foreground">{i + 1}.</span>
                      <span>{step}</span>
                    </li>
                  ))}
                </ol>
              </section>
            )}
          </div>

          {(hasCalories || payload.ingredients.length > 0) && (
            <div className="space-y-2.5 border-t border-border px-5 py-4">
              {hasCalories && (
                <button
                  onClick={logMacros}
                  disabled={logged}
                  className={cn(
                    "flex w-full items-center justify-center gap-2 rounded-full py-3 text-[15px] font-bold text-background transition-colors",
                    logged ? "bg-green-500" : "bg-foreground"
                  )}
                >
                  {logged ? <Check className="h-4 w-4" /> : <Plus className="h-4 w-4" />}
                  {logged ? "Logged to Jasper" : "Log to my macros"}
                </button>
              )}
              {payload.ingredients.length > 0 && onAddToGrocery && (
                <button
                  onClick={addGrocery}
                  disabled={groceryAdded}
                  className="flex w-full items-center justify-center gap-2 rounded-full border border-border bg-card py-3 text-[15px] font-bold transition-colors hover:bg-secondary disabled:opacity-60"
                >
                  {groceryAdded ? <Check className="h-4 w-4" /> : <ShoppingCart className="h-4 w-4" />}
                  {groceryAdded ? "Sent to chat" : "Add to grocery list"}
                </button>
              )}
              {payload.ingredients.length > 0 && (
                <button
                  onClick={() => void saveToRecipeLibrary()}
                  disabled={libSaved}
                  className="flex w-full items-center justify-center gap-2 rounded-full border border-border bg-card py-3 text-[15px] font-bold transition-colors hover:bg-secondary disabled:opacity-60"
                >
                  {libSaved ? <Check className="h-4 w-4" /> : <BookOpen className="h-4 w-4" />}
                  {libSaved ? "In your Jasper recipes" : "Save to Jasper — Recipes"}
                </button>
              )}
            </div>
          )}
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

function MacroTag({
  text,
  color,
  icon,
}: {
  text: string;
  color: string;
  icon?: React.ReactNode;
}) {
  return (
    <span
      className="inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-bold"
      style={{ color, background: `${color}1f` }}
    >
      {icon}
      {text}
    </span>
  );
}

export const RecipeCard = memo(RecipeCardBase);
