import { useEffect, useMemo, useState } from "react";
import { useJasperGeneration } from "@/hooks/useJasperGeneration";
import { JASPER_NATIVE_REVIEW_MESSAGE, onJasperInvalidated } from "@/lib/jasperSession";
const connectedMealGenerationAvailable: boolean = false;
import * as Dialog from "@radix-ui/react-dialog";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  Check,
  Droplets,
  Leaf,
  Loader2,
  Minus,
  Plus,
  ShoppingCart,
  Sparkles,
  Store,
  Trash2,
  UtensilsCrossed,
  X,
} from "lucide-react";
import { toast } from "sonner";

import { JasperWaterCup } from "@/components/JasperWaterCup";
import {
  JASPER_ACTIVITY_LEVELS,
  JASPER_DIET_GOALS,
  JASPER_DIET_PREFERENCES,
  deleteRecipe,
  fetchGroceryList,
  fetchRecipes,
  fetchWaterToday,
  generateDietPlan,
  jasperDeleteRow,
  jasperPost,
  jasperRead,
  logWaterCup,
  marketplaceBrowse,
  marketplaceImport,
  marketplacePublish,
  recipePerServing,
  saveRecipe,
  setGroceryChecks,
  type JasperDietGenResult,
  type JasperRecipeIngredient,
  type JasperRecipeRow,
} from "@/lib/jasperConnect";
import {
  coachGroceryList,
  coachRead,
  coachSetGroceryChecks,
} from "@/lib/jasperCoachConnect";
import {
  EmberGlowCard,
  EmberGlowIcon,
  EmberKicker,
  EmberPlanKeyframes,
  JasperGeneratingCard,
  JasperMacroTiles,
} from "@/components/JasperPlanCards";
import { JASPER_EMBER_GRADIENT } from "@/lib/jasperIntel";
import { cn } from "@/lib/utils";

/** Shared modal shell for the Jasper web panels (ember-glow language). */
function PanelShell({
  open,
  onClose,
  kicker,
  title,
  children,
}: {
  open: boolean;
  onClose: () => void;
  kicker: string;
  title: string;
  children: React.ReactNode;
}) {
  useEffect(() => onJasperInvalidated(() => { if (open) onClose(); }), [open, onClose]);
  return (
    <Dialog.Root open={open} onOpenChange={(o) => { if (!o) onClose(); }}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm" />
        <Dialog.Content className="fixed left-1/2 top-1/2 z-50 flex max-h-[86vh] w-[min(31rem,calc(100vw-1.5rem))] -translate-x-1/2 -translate-y-1/2 flex-col overflow-hidden rounded-[24px] border border-border bg-card shadow-2xl focus:outline-none">
          <div className="flex items-center justify-between border-b border-border px-5 py-3.5">
            <div className="min-w-0">
              <p className="text-[9px] font-black uppercase tracking-[0.16em] text-[#f39057]">
                {kicker}
              </p>
              <Dialog.Title className="truncate text-[15px] font-black text-foreground">
                {title}
              </Dialog.Title>
            </div>
            <Dialog.Close
              aria-label="Close"
              className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-secondary text-muted-foreground transition-colors hover:text-foreground"
            >
              <X className="h-3.5 w-3.5" strokeWidth={3} />
            </Dialog.Close>
          </div>
          <div className="overflow-y-auto px-5 py-4">{children}</div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

function errorLine(e: unknown): string {
  return e instanceof Error ? e.message : "Something went sideways — try again.";
}

// MARK: - Marketplace (browse + import; publishing happens on plan rows)

export function JasperMarketplacePanel({
  open,
  onClose,
  initialQuery,
}: {
  open: boolean;
  onClose: () => void;
  /** Pre-seeded search text (Jasper's marketplace chat action). */
  initialQuery?: string;
}) {
  const [kind, setKind] = useState<string | null>(null);
  const [query, setQuery] = useState<string>("");
  useEffect(() => {
    if (open && initialQuery) setQuery(initialQuery);
  }, [open, initialQuery]);
  const browseQuery = useQuery({
    queryKey: ["jasper-marketplace", kind, query],
    queryFn: () => marketplaceBrowse(kind ?? undefined, query || undefined),
    enabled: open,
  });
  const importMutation = useMutation({
    mutationFn: (id: string) => marketplaceImport(id),
    onSuccess: () => toast("Imported into your Jasper — re-imports update in place."),
    onError: (e) => toast.error(errorLine(e)),
  });

  const templates = browseQuery.data ?? [];
  return (
    <PanelShell open={open} onClose={onClose} kicker="Jasper marketplace" title="Coach-published plans">
      <div className="mb-3 flex items-center gap-2">
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search plans…"
          className="h-9 min-w-0 flex-1 rounded-full border border-border bg-secondary px-4 text-[13px] outline-none"
        />
        {[
          { label: "All", value: null },
          { label: "Programs", value: "program" },
          { label: "Diet", value: "diet_plan" },
        ].map((chip) => (
          <button
            key={chip.label}
            type="button"
            onClick={() => setKind(chip.value)}
            className={cn(
              "rounded-full px-3 py-1.5 text-[11px] font-bold transition-colors",
              kind === chip.value
                ? "bg-foreground text-background"
                : "bg-secondary text-muted-foreground"
            )}
          >
            {chip.label}
          </button>
        ))}
      </div>
      {browseQuery.isLoading ? (
        <div className="flex items-center gap-2 py-8 text-[13px] text-muted-foreground">
          <Loader2 className="h-4 w-4 animate-spin" /> Browsing the marketplace…
        </div>
      ) : templates.length === 0 ? (
        <p className="py-8 text-center text-[13px] text-muted-foreground">
          Nothing published for this search yet.
        </p>
      ) : (
        <div className="space-y-2.5">
          {templates.map((t) => (
            <div key={t.id} className="rounded-2xl border border-border p-3.5">
              <div className="flex items-center gap-2">
                <span className="text-[9px] font-black uppercase tracking-[0.14em] text-muted-foreground">
                  {t.kind === "program" ? "Program" : "Diet plan"}
                  {t.goal ? ` · ${t.goal}` : ""}
                </span>
                {t.coachName && (
                  <span className="ml-auto truncate text-[10px] text-muted-foreground">
                    by {t.coachName}
                  </span>
                )}
              </div>
              <p className="mt-1 text-[15px] font-black text-foreground">{t.title}</p>
              {t.summary && (
                <p className="mt-0.5 line-clamp-2 text-[12px] text-muted-foreground">{t.summary}</p>
              )}
              <button
                type="button"
                disabled={importMutation.isPending}
                onClick={() => importMutation.mutate(t.id)}
                className="mt-2.5 flex items-center gap-1.5 rounded-full bg-foreground px-3.5 py-1.5 text-[11px] font-bold text-background disabled:opacity-50"
              >
                {importMutation.isPending ? (
                  <Loader2 className="h-3 w-3 animate-spin" />
                ) : (
                  <Store className="h-3 w-3" />
                )}
                Import into my Jasper
              </button>
            </div>
          ))}
        </div>
      )}
    </PanelShell>
  );
}

// MARK: - Recipes (ONE shared library with Jasper)

function blankIngredient(): JasperRecipeIngredient {
  return { name: "", calories: 0, protein: 0, carbs: 0, fat: 0, servingUnit: "serving", numberOfServings: 1 };
}

/** A save-ready draft Jasper Intelligence hands the recipe editor. */
export interface JasperRecipePanelDraft {
  title: string;
  servings?: number;
  emoji?: string;
  prepTime?: string;
  cookTime?: string;
  steps?: string[];
  ingredients: JasperRecipeIngredient[];
}

export function JasperRecipesPanel({
  open,
  onClose,
  initialDraft,
}: {
  open: boolean;
  onClose: () => void;
  /** When present, the editor opens pre-filled (recipe chat action). */
  initialDraft?: JasperRecipePanelDraft | null;
}) {
  const generation = useJasperGeneration();
  const queryClient = useQueryClient();
  const [composing, setComposing] = useState<boolean>(false);
  const [name, setName] = useState<string>("");
  const [servings, setServings] = useState<number>(2);
  const [note, setNote] = useState<string>("");
  const [stepsText, setStepsText] = useState<string>("");
  const [emoji, setEmoji] = useState<string>("");
  const [prepTime, setPrepTime] = useState<string>("");
  const [cookTime, setCookTime] = useState<string>("");
  const [ingredients, setIngredients] = useState<JasperRecipeIngredient[]>([blankIngredient()]);

  useEffect(() => {
    if (!open || !initialDraft) return;
    setComposing(true);
    setName(initialDraft.title);
    setServings(Math.max(1, initialDraft.servings ?? 1));
    setEmoji(initialDraft.emoji ?? "");
    setPrepTime(initialDraft.prepTime ?? "");
    setCookTime(initialDraft.cookTime ?? "");
    setStepsText((initialDraft.steps ?? []).join("\n"));
    setIngredients(
      initialDraft.ingredients.length > 0 ? initialDraft.ingredients : [blankIngredient()]
    );
  }, [open, initialDraft]);

  const recipesQuery = useQuery({
    queryKey: ["jasper-recipes", generation],
    queryFn: fetchRecipes,
    enabled: open,
  });
  const saveMutation = useMutation({
    mutationFn: () =>
      saveRecipe({
        name,
        servings,
        note,
        emoji: emoji || undefined,
        prepTime: prepTime || undefined,
        cookTime: cookTime || undefined,
        steps: stepsText.split("\n"),
        ingredients: ingredients.filter((i) => i.name.trim().length > 0),
      }),
    onSuccess: () => {
      toast("Saved — it's in Jasper under Nutrition → Recipes now.");
      setComposing(false);
      setName("");
      setNote("");
      setStepsText("");
      setIngredients([blankIngredient()]);
      void queryClient.invalidateQueries({ queryKey: ["jasper-recipes"] });
    },
    onError: (e) => toast.error(errorLine(e)),
  });
  const deleteMutation = useMutation({
    mutationFn: (id: string) => deleteRecipe(id),
    onSuccess: () => {
      toast("Deleted from both apps.");
      void queryClient.invalidateQueries({ queryKey: ["jasper-recipes"] });
    },
    onError: (e) => toast.error(errorLine(e)),
  });

  const updateIngredient = (index: number, patch: Partial<JasperRecipeIngredient>): void => {
    setIngredients((prev) => prev.map((ing, i) => (i === index ? { ...ing, ...patch } : ing)));
  };

  const recipes = recipesQuery.data ?? [];
  return (
    <PanelShell open={open} onClose={onClose} kicker="Shared with Jasper" title="Recipes">
      {composing ? (
        <div className="space-y-2.5">
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Recipe name"
            className="h-10 w-full rounded-xl border border-border bg-secondary px-3.5 text-[14px] font-bold outline-none"
          />
          <div className="flex items-center gap-3">
            <span className="text-[12px] font-bold text-muted-foreground">Servings</span>
            <button type="button" onClick={() => setServings((s) => Math.max(1, s - 1))} className="flex h-7 w-7 items-center justify-center rounded-full bg-secondary"><Minus className="h-3 w-3" /></button>
            <span className="w-6 text-center text-[14px] font-black">{servings}</span>
            <button type="button" onClick={() => setServings((s) => Math.min(20, s + 1))} className="flex h-7 w-7 items-center justify-center rounded-full bg-secondary"><Plus className="h-3 w-3" /></button>
          </div>
          <p className="text-[10.5px] text-muted-foreground">
            Ingredient macros are for ONE serving of that ingredient; count is how much the whole recipe uses. Per-serving macros derive live.
          </p>
          {ingredients.map((ing, i) => (
            <div key={i} className="rounded-xl border border-border p-2.5">
              <div className="flex items-center gap-2">
                <input
                  value={ing.name}
                  onChange={(e) => updateIngredient(i, { name: e.target.value })}
                  placeholder="Ingredient"
                  className="h-8 min-w-0 flex-1 rounded-lg bg-secondary px-2.5 text-[12.5px] font-semibold outline-none"
                />
                <button type="button" onClick={() => setIngredients((prev) => prev.filter((_, j) => j !== i))} className="text-muted-foreground"><X className="h-3.5 w-3.5" /></button>
              </div>
              <div className="mt-2 grid grid-cols-5 gap-1.5">
                {([
                  ["kcal", ing.calories, (v: number) => updateIngredient(i, { calories: v })],
                  ["P", ing.protein, (v: number) => updateIngredient(i, { protein: v })],
                  ["C", ing.carbs, (v: number) => updateIngredient(i, { carbs: v })],
                  ["F", ing.fat, (v: number) => updateIngredient(i, { fat: v })],
                  ["Count", ing.numberOfServings, (v: number) => updateIngredient(i, { numberOfServings: v })],
                ] as [string, number, (v: number) => void][]).map(([label, value, set]) => (
                  <label key={label} className="block">
                    <span className="text-[8.5px] font-black uppercase text-muted-foreground">{label}</span>
                    <input
                      type="number"
                      value={value === 0 ? "" : String(value)}
                      onChange={(e) => set(Number(e.target.value) || 0)}
                      className="h-8 w-full rounded-lg bg-secondary px-1.5 text-[12px] outline-none"
                    />
                  </label>
                ))}
              </div>
            </div>
          ))}
          <button type="button" onClick={() => setIngredients((prev) => [...prev, blankIngredient()])} className="flex items-center gap-1.5 text-[12px] font-bold text-[#f39057]">
            <Plus className="h-3.5 w-3.5" /> Add ingredient
          </button>
          <textarea
            value={stepsText}
            onChange={(e) => setStepsText(e.target.value)}
            placeholder={"Steps — one per line"}
            rows={3}
            className="w-full rounded-xl border border-border bg-secondary px-3.5 py-2.5 text-[13px] outline-none"
          />
          <input
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="Note (optional)"
            className="h-9 w-full rounded-xl border border-border bg-secondary px-3.5 text-[13px] outline-none"
          />
          <div className="flex gap-2">
            <button type="button" onClick={() => setComposing(false)} className="flex-1 rounded-full bg-secondary py-2.5 text-[13px] font-bold">Cancel</button>
            <button
              type="button"
              disabled={saveMutation.isPending || name.trim().length === 0}
              onClick={() => saveMutation.mutate()}
              className="flex flex-1 items-center justify-center gap-1.5 rounded-full bg-foreground py-2.5 text-[13px] font-black text-background disabled:opacity-50"
            >
              {saveMutation.isPending && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
              Save to Jasper
            </button>
          </div>
        </div>
      ) : (
        <>
          <button
            type="button"
            onClick={() => setComposing(true)}
            className="mb-3 flex w-full items-center gap-2 rounded-2xl border border-dashed border-border px-3.5 py-3 text-[13px] font-bold text-muted-foreground transition-colors hover:text-foreground"
          >
            <Plus className="h-4 w-4" /> New recipe — saves into Jasper instantly
          </button>
          {recipesQuery.isLoading ? (
            <div className="flex items-center gap-2 py-6 text-[13px] text-muted-foreground">
              <Loader2 className="h-4 w-4 animate-spin" /> Reading your Jasper…
            </div>
          ) : recipesQuery.isError ? (
            <p className="py-6 text-center text-[12.5px] text-muted-foreground">{errorLine(recipesQuery.error)}</p>
          ) : recipes.length === 0 ? (
            <p className="py-6 text-center text-[13px] text-muted-foreground">
              No recipes yet — save one here or in Jasper and it shows up in both.
            </p>
          ) : (
            <div className="space-y-2.5">
              {recipes.map((r: JasperRecipeRow) => {
                const per = recipePerServing(r);
                return (
                  <div key={r.id} className="rounded-2xl border border-border p-3.5">
                    <div className="flex items-start gap-2">
                      <span className="text-lg leading-none">{r.emoji || "🍽️"}</span>
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-[14.5px] font-black text-foreground">{r.name}</p>
                        <p className="text-[11px] text-muted-foreground">
                          {r.servings} serving{r.servings === 1 ? "" : "s"} · per serving {per.calories} kcal · P{per.protein} C{per.carbs} F{per.fat}
                        </p>
                      </div>
                      <button
                        type="button"
                        aria-label={`Delete ${r.name}`}
                        disabled={deleteMutation.isPending}
                        onClick={() => deleteMutation.mutate(r.id)}
                        className="text-muted-foreground transition-colors hover:text-destructive"
                      >
                        <Trash2 className="h-3.5 w-3.5" />
                      </button>
                    </div>
                    {r.ingredients.length > 0 && (
                      <p className="mt-1.5 line-clamp-2 text-[11.5px] text-muted-foreground">
                        {r.ingredients.map((i) => i.name).join(" · ")}
                      </p>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </>
      )}
    </PanelShell>
  );
}

// MARK: - Shared grocery checklist

export function JasperGroceryPanel({
  open,
  onClose,
  clientUid,
  clientUsername,
}: {
  open: boolean;
  onClose: () => void;
  /** Coach view: read/write the CLIENT's shared list through the coach token. */
  clientUid?: string;
  clientUsername?: string;
}) {
  const generation = useJasperGeneration();
  const queryClient = useQueryClient();
  const queryKey = ["jasper-grocery", clientUid ?? "own", generation];
  const groceryQuery = useQuery({
    queryKey,
    queryFn: () => (clientUid ? coachGroceryList(clientUid) : fetchGroceryList()),
    enabled: open,
  });
  const checkMutation = useMutation({
    mutationFn: (input: { id: string; checked: boolean }) =>
      clientUid
        ? coachSetGroceryChecks(clientUid, groceryQuery.data?.planId ?? null, [input])
        : setGroceryChecks(groceryQuery.data?.planId ?? null, [input]),
    onError: (e) => {
      toast.error(errorLine(e));
      void queryClient.invalidateQueries({ queryKey });
    },
  });

  const toggle = (id: string, checked: boolean): void => {
    queryClient.setQueryData(queryKey, (prev: typeof groceryQuery.data) =>
      prev
        ? {
            ...prev,
            categories: prev.categories.map((c) => ({
              ...c,
              items: c.items.map((it) => (it.id === id ? { ...it, checked } : it)),
            })),
          }
        : prev
    );
    checkMutation.mutate({ id, checked });
  };

  const data = groceryQuery.data;
  return (
    <PanelShell
      open={open}
      onClose={onClose}
      kicker={
        clientUsername
          ? `@${clientUsername} · shared state — checks sync with their Jasper live`
          : "Shared state — checks sync with Jasper live"
      }
      title={data?.planName ? `Groceries · ${data.planName}` : "Grocery list"}
    >
      {groceryQuery.isLoading ? (
        <div className="flex items-center gap-2 py-6 text-[13px] text-muted-foreground">
          <Loader2 className="h-4 w-4 animate-spin" /> Reading the shared checklist…
        </div>
      ) : groceryQuery.isError ? (
        <p className="py-6 text-center text-[12.5px] text-muted-foreground">{errorLine(groceryQuery.error)}</p>
      ) : !data || data.categories.length === 0 ? (
        <p className="py-6 text-center text-[13px] text-muted-foreground">
          No active diet plan carries a grocery list yet.
        </p>
      ) : (
        <div className="space-y-4">
          {data.categories.map((cat) => (
            <div key={cat.name}>
              <p className="mb-1.5 flex items-center gap-1.5 text-[10px] font-black uppercase tracking-[0.14em] text-muted-foreground">
                <ShoppingCart className="h-3 w-3" /> {cat.name}
              </p>
              <div className="space-y-1">
                {cat.items.map((item) => (
                  <button
                    key={item.id}
                    type="button"
                    onClick={() => toggle(item.id, !item.checked)}
                    className="flex w-full items-center gap-2.5 rounded-xl px-2 py-1.5 text-left transition-colors hover:bg-secondary"
                  >
                    {/* WHISPER_PLANS.md §4.6 — 22px check circle: teal fill + white check. */}
                    <span
                      className="flex h-[22px] w-[22px] shrink-0 items-center justify-center rounded-full"
                      style={
                        item.checked
                          ? { background: "#5CDBB8", color: "#FFFFFF" }
                          : { border: "1px solid rgba(128,128,128,0.35)" }
                      }
                    >
                      {item.checked && <Check className="h-3 w-3" strokeWidth={3} />}
                    </span>
                    <span
                      className={cn(
                        "min-w-0 flex-1 truncate text-[13.5px] font-semibold",
                        item.checked ? "text-muted-foreground line-through" : "text-foreground"
                      )}
                    >
                      {item.name}
                    </span>
                    {item.quantity && (
                      <span className="shrink-0 text-[11px] text-muted-foreground">{item.quantity}</span>
                    )}
                  </button>
                ))}
              </div>
            </div>
          ))}
          <p className="text-[10.5px] text-muted-foreground">
            These are the SAME rows Jasper's in-app checklist reads and writes — a check here shows up there.
          </p>
        </div>
      )}
    </PanelShell>
  );
}

// MARK: - Diet builder (Jasper's OWN generator, writes into YOUR Jasper)

export function JasperDietBuilderPanel({
  open,
  onClose,
  onSaved,
}: {
  open: boolean;
  onClose: () => void;
  onSaved?: () => void;
}) {
  const [goal, setGoal] = useState<string>("Fat Loss");
  const [preference, setPreference] = useState<string>("No Preference");
  const [allergies, setAllergies] = useState<string>("");
  const [mealsPerDay, setMealsPerDay] = useState<number>(4);
  const [useProfile, setUseProfile] = useState<boolean>(false);
  const [kcal, setKcal] = useState<string>("");
  const [protein, setProtein] = useState<string>("");
  const [carbs, setCarbs] = useState<string>("");
  const [fat, setFat] = useState<string>("");
  const [age, setAge] = useState<string>("");
  const [gender, setGender] = useState<string>("male");
  const [weightLbs, setWeightLbs] = useState<string>("");
  const [heightIn, setHeightIn] = useState<string>("");
  const [activity, setActivity] = useState<string>("Moderately Active");
  const [saveDirect, setSaveDirect] = useState<boolean>(true);
  const [result, setResult] = useState<JasperDietGenResult | null>(null);
  const [saved, setSaved] = useState<boolean>(false);
  const [published, setPublished] = useState<boolean>(false);

  const generateMutation = useMutation({
    mutationFn: () =>
      generateDietPlan({
        goal,
        preference,
        allergies: allergies.split(",").map((a) => a.trim()).filter((a) => a.length > 0),
        mealsPerDay,
        targets: useProfile
          ? undefined
          : {
              calories: Number(kcal) || undefined,
              protein: Number(protein) || undefined,
              carbs: Number(carbs) || undefined,
              fat: Number(fat) || undefined,
            },
        profile: useProfile
          ? {
              age: Number(age) || 30,
              gender,
              weightLbs: Number(weightLbs) || 170,
              heightInches: Number(heightIn) || 69,
              activityLevel: activity,
            }
          : undefined,
        save: saveDirect,
      }),
    onSuccess: (r) => {
      setResult(r);
      setSaved(r.saved);
      if (r.saved) onSaved?.();
    },
    onError: (e) => toast.error(errorLine(e)),
  });
  const saveMutation = useMutation({
    mutationFn: () => jasperPost("diet_plans", result?.postBody ?? {}),
    onSuccess: () => {
      setSaved(true);
      onSaved?.();
      toast("Saved into your Jasper.");
    },
    onError: (e) => toast.error(errorLine(e)),
  });
  const publishMutation = useMutation({
    mutationFn: () => {
      if (!result) throw new Error("Generate first.");
      const topLevel = { ...result.postBody };
      delete topLevel.payload;
      delete topLevel.client_id;
      const payload = result.postBody.payload;
      return marketplacePublish({
        kind: "diet_plan",
        title: result.planName,
        summary: [result.goal, `${result.days.length} days`].filter(Boolean).join(" · "),
        goal: result.goal ?? goal,
        topLevel,
        payload: typeof payload === "object" && payload !== null ? (payload as Record<string, unknown>) : {},
      });
    },
    onSuccess: () => {
      setPublished(true);
      toast("Published — re-publishing the same title updates in place.");
    },
    onError: (e) => toast.error(errorLine(e)),
  });

  const chipRow = (options: readonly string[], value: string, set: (v: string) => void): React.ReactNode => (
    <div className="flex flex-wrap gap-1.5">
      {options.map((o) => (
        <button
          key={o}
          type="button"
          onClick={() => set(o)}
          className={cn(
            "rounded-full px-3 py-1.5 text-[11px] font-bold transition-colors",
            value === o ? "bg-[#f39057] text-black" : "bg-secondary text-muted-foreground"
          )}
        >
          {o}
        </button>
      ))}
    </div>
  );

  if (!connectedMealGenerationAvailable) {
    return <PanelShell open={open} onClose={onClose} kicker="Native review required" title="Nutrition planning">
      <div className="space-y-4 py-4">
        <p className="text-base leading-relaxed">{JASPER_NATIVE_REVIEW_MESSAGE}</p>
        <p className="text-sm text-muted-foreground">Saved plans remain readable with your permission. Planned macros are estimates, not logged intake. Cloud storage does not confirm native validation or active selection.</p>
        <a className="inline-flex min-h-11 items-center rounded-full bg-foreground px-5 text-sm font-semibold text-background" href="https://www.thejasperapp.com/connect" target="_blank" rel="noopener noreferrer">Jasper connection details</a>
      </div>
    </PanelShell>;
  }

  const generatingStatus = !useProfile && Number(kcal) > 0
    ? `Jasper is composing 7 days around ${Number(kcal).toLocaleString()} kcal…`
    : `Jasper is composing 7 days of ${mealsPerDay} meals — 15-60s…`;

  return (
    <PanelShell open={open} onClose={onClose} kicker="Jasper's own engine · 15-60s" title="Diet builder">
      <EmberPlanKeyframes />
      {generateMutation.isPending ? (
        /* WHISPER_PLANS.md §4 — mandatory generate state: the glow box breathes
           ember while Jasper cooks, never a bare spinner. */
        <JasperGeneratingCard status={generatingStatus} />
      ) : result ? (
        <EmberGlowCard glow={0.5} className="space-y-3 p-4">
          <div className="flex items-start gap-3">
            <EmberGlowIcon>
              <Leaf className="h-4 w-4" strokeWidth={2.4} />
            </EmberGlowIcon>
            <div className="min-w-0 flex-1">
              <EmberKicker text="Diet plan" />
              <p className="text-[16px] font-black">{result.planName}</p>
              {result.targetCalories !== null && (
                <p className="text-[12px] font-bold" style={{ color: "#F39057" }}>
                  {result.targetCalories} kcal / day
                </p>
              )}
            </div>
          </div>
          <div className="flex gap-1.5 overflow-x-auto pb-1" style={{ overscrollBehaviorX: "contain" }}>
            {result.days.map((d) => (
              <div key={d.dayName} className="w-24 shrink-0 rounded-xl p-2.5" style={{ background: "rgba(128,128,128,0.12)" }}>
                <p className="truncate text-[11px] font-black">{d.dayName}</p>
                <p className="text-[10px] opacity-55">{d.mealCount} meals</p>
                <p className="text-[10px] font-bold" style={{ color: "#F39057" }}>{d.kcal} kcal</p>
              </div>
            ))}
          </div>
          {result.groceryCount > 0 && (
            <p className="text-[11px] opacity-55">
              Grocery list derived — {result.groceryCount} items, live in the shared checklist once saved.
            </p>
          )}
          {saved ? (
            <p className="flex items-center gap-1.5 text-[12.5px] font-bold" style={{ color: "#5CDBB8" }}>
              <Check className="h-3.5 w-3.5" /> Saved into your Jasper — live under Nutrition now.
            </p>
          ) : (
            <button
              type="button"
              disabled={saveMutation.isPending}
              onClick={() => saveMutation.mutate()}
              className="flex w-full items-center justify-center gap-1.5 rounded-full bg-foreground py-2.5 text-[13px] font-black text-background disabled:opacity-50"
            >
              {saveMutation.isPending && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
              Save to my Jasper
            </button>
          )}
          {published ? (
            <p className="flex items-center gap-1.5 text-[12.5px] font-bold" style={{ color: "#5CDBB8" }}>
              <Store className="h-3.5 w-3.5" /> On the marketplace.
            </p>
          ) : (
            <button
              type="button"
              disabled={publishMutation.isPending}
              onClick={() => publishMutation.mutate()}
              className="flex w-full items-center justify-center gap-1.5 rounded-full border border-border py-2.5 text-[13px] font-bold text-foreground disabled:opacity-50"
            >
              {publishMutation.isPending && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
              Publish to marketplace
            </button>
          )}
          <button
            type="button"
            onClick={() => {
              setResult(null);
              setSaved(false);
              setPublished(false);
            }}
            className="w-full rounded-full py-2 text-[12px] font-bold opacity-70"
            style={{ background: "rgba(128,128,128,0.14)" }}
          >
            Generate again
          </button>
        </EmberGlowCard>
      ) : (
        <div className="space-y-3.5">
          <div>
            <p className="mb-1.5 text-[10px] font-black uppercase tracking-[0.14em] text-muted-foreground">Goal</p>
            {chipRow(JASPER_DIET_GOALS, goal, setGoal)}
          </div>
          <div>
            <p className="mb-1.5 text-[10px] font-black uppercase tracking-[0.14em] text-muted-foreground">Preference</p>
            {chipRow(JASPER_DIET_PREFERENCES, preference, setPreference)}
          </div>
          <input
            value={allergies}
            onChange={(e) => setAllergies(e.target.value)}
            placeholder="Allergies (comma separated, optional)"
            className="h-9 w-full rounded-xl border border-border bg-secondary px-3.5 text-[13px] outline-none"
          />
          <div className="flex items-center gap-3">
            <span className="text-[12px] font-bold text-muted-foreground">Meals / day</span>
            <button type="button" onClick={() => setMealsPerDay((m) => Math.max(2, m - 1))} className="flex h-7 w-7 items-center justify-center rounded-full bg-secondary"><Minus className="h-3 w-3" /></button>
            <span className="w-5 text-center text-[14px] font-black">{mealsPerDay}</span>
            <button type="button" onClick={() => setMealsPerDay((m) => Math.min(6, m + 1))} className="flex h-7 w-7 items-center justify-center rounded-full bg-secondary"><Plus className="h-3 w-3" /></button>
          </div>
          <div className="flex gap-1.5">
            <button type="button" onClick={() => setUseProfile(false)} className={cn("rounded-full px-3.5 py-1.5 text-[11px] font-bold", !useProfile ? "bg-[#f39057] text-black" : "bg-secondary text-muted-foreground")}>Macro targets</button>
            <button type="button" onClick={() => setUseProfile(true)} className={cn("rounded-full px-3.5 py-1.5 text-[11px] font-bold", useProfile ? "bg-[#f39057] text-black" : "bg-secondary text-muted-foreground")}>Real profile</button>
          </div>
          {useProfile ? (
            <div className="space-y-2">
              <div className="grid grid-cols-2 gap-2">
                <input value={age} onChange={(e) => setAge(e.target.value)} placeholder="Age" inputMode="numeric" className="h-9 rounded-xl border border-border bg-secondary px-3 text-[13px] outline-none" />
                <div className="flex gap-1.5">
                  <button type="button" onClick={() => setGender("male")} className={cn("flex-1 rounded-full text-[11px] font-bold", gender === "male" ? "bg-[#f39057] text-black" : "bg-secondary text-muted-foreground")}>Male</button>
                  <button type="button" onClick={() => setGender("female")} className={cn("flex-1 rounded-full text-[11px] font-bold", gender === "female" ? "bg-[#f39057] text-black" : "bg-secondary text-muted-foreground")}>Female</button>
                </div>
                <input value={weightLbs} onChange={(e) => setWeightLbs(e.target.value)} placeholder="Weight (lbs)" inputMode="numeric" className="h-9 rounded-xl border border-border bg-secondary px-3 text-[13px] outline-none" />
                <input value={heightIn} onChange={(e) => setHeightIn(e.target.value)} placeholder="Height (in)" inputMode="numeric" className="h-9 rounded-xl border border-border bg-secondary px-3 text-[13px] outline-none" />
              </div>
              {chipRow(JASPER_ACTIVITY_LEVELS, activity, setActivity)}
              <p className="text-[10.5px] text-muted-foreground">Mifflin-St Jeor computes the targets exactly like the Jasper app.</p>
            </div>
          ) : (
            <div className="grid grid-cols-4 gap-2">
              <input value={kcal} onChange={(e) => setKcal(e.target.value)} placeholder="kcal" inputMode="numeric" className="h-9 rounded-xl border border-border bg-secondary px-2.5 text-[12.5px] outline-none" />
              <input value={protein} onChange={(e) => setProtein(e.target.value)} placeholder="P g" inputMode="numeric" className="h-9 rounded-xl border border-border bg-secondary px-2.5 text-[12.5px] outline-none" />
              <input value={carbs} onChange={(e) => setCarbs(e.target.value)} placeholder="C g" inputMode="numeric" className="h-9 rounded-xl border border-border bg-secondary px-2.5 text-[12.5px] outline-none" />
              <input value={fat} onChange={(e) => setFat(e.target.value)} placeholder="F g" inputMode="numeric" className="h-9 rounded-xl border border-border bg-secondary px-2.5 text-[12.5px] outline-none" />
            </div>
          )}
          <label className="flex items-center gap-2 text-[12.5px] font-bold text-foreground">
            <input type="checkbox" checked={saveDirect} onChange={(e) => setSaveDirect(e.target.checked)} className="h-4 w-4 accent-[#f39057]" />
            Save into my Jasper in the same call
          </label>
          <button
            type="button"
            disabled={generateMutation.isPending}
            onClick={() => generateMutation.mutate()}
            className="flex w-full items-center justify-center gap-1.5 rounded-full bg-[#f39057] py-3 text-[14px] font-black text-black disabled:opacity-70"
          >
            {generateMutation.isPending ? (
              <>
                <Loader2 className="h-4 w-4 animate-spin" /> Jasper is cooking your week — 15-60s
              </>
            ) : (
              <>
                <Sparkles className="h-4 w-4" /> Generate with Jasper
              </>
            )}
          </button>
        </div>
      )}
    </PanelShell>
  );
}

// MARK: - Water (Jasper's own animated cup, tap-to-log)

export function JasperWaterPanel({ open, onClose }: { open: boolean; onClose: () => void }) {
  const generation = useJasperGeneration();
  const queryClient = useQueryClient();
  const waterQuery = useQuery({
    queryKey: ["jasper-water-today", generation],
    queryFn: fetchWaterToday,
    enabled: open,
  });
  const rows = useMemo(() => waterQuery.data ?? [], [waterQuery.data]);
  const totalML = rows.reduce((acc, r) => acc + r.ml, 0);
  const cups = Math.round(totalML / 250);
  const goal = 8;

  const addMutation = useMutation({
    mutationFn: () => logWaterCup(250),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: ["jasper-water-today"] }),
    onError: (e) => toast.error(errorLine(e)),
  });
  const removeMutation = useMutation({
    mutationFn: () => {
      const last = rows[rows.length - 1];
      if (!last) throw new Error("Nothing to remove.");
      return jasperDeleteRow("water", last.id);
    },
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: ["jasper-water-today"] }),
    onError: (e) => toast.error(errorLine(e)),
  });

  return (
    <PanelShell open={open} onClose={onClose} kicker="Jasper's own water cup" title="Water · today">
      {waterQuery.isError ? (
        <p className="py-6 text-center text-[12.5px] text-muted-foreground">{errorLine(waterQuery.error)}</p>
      ) : (
        <div className="flex items-center gap-5 rounded-2xl bg-[#FBF4E4] p-4 dark:bg-[#24201D]">
          <div className="min-w-0 flex-1">
            <p className="flex items-center gap-1 text-[10px] font-black uppercase tracking-[0.16em] text-[#338FDB] dark:text-[#5CB3F2]">
              <Droplets className="h-3 w-3" /> Water
            </p>
            <p className="mt-1 text-[34px] font-black leading-none text-[#211C1A] dark:text-[#FBF4E4]">
              {cups}
              <span className="ml-1.5 text-[14px] font-bold opacity-45">of {goal}</span>
            </p>
            <p className="mt-1 text-[11px] text-[#211C1A]/50 dark:text-[#FBF4E4]/50">{totalML} ml today</p>
            <div className="mt-2.5 flex gap-2">
              <button
                type="button"
                disabled={removeMutation.isPending || rows.length === 0}
                onClick={() => removeMutation.mutate()}
                className="flex h-8 w-8 items-center justify-center rounded-full bg-black/10 text-[#211C1A] disabled:opacity-40 dark:bg-white/10 dark:text-white"
              >
                <Minus className="h-3.5 w-3.5" />
              </button>
              <button
                type="button"
                disabled={addMutation.isPending}
                onClick={() => addMutation.mutate()}
                className="flex h-8 w-8 items-center justify-center rounded-full bg-black/10 text-[#211C1A] disabled:opacity-40 dark:bg-white/10 dark:text-white"
              >
                <Plus className="h-3.5 w-3.5" />
              </button>
            </div>
          </div>
          <button
            type="button"
            aria-label="Log one cup"
            onClick={() => addMutation.mutate()}
            className="transition-transform active:scale-95"
          >
            <JasperWaterCup level={Math.min(1, cups / goal)} />
          </button>
        </div>
      )}
      <p className="mt-3 text-[10.5px] text-muted-foreground">
        Rendered from Jasper's own water_cup spec — every tap writes a real 250 ml cup into your Jasper.
      </p>
    </PanelShell>
  );
}

// MARK: - Diet plan (the full plan exactly as Jasper stores it)

interface DietPlanView {
  name: string;
  goal: string | null;
  preference: string | null;
  mealsPerDay: number | null;
  targets: { kcal: number | null; protein: number | null; carbs: number | null; fat: number | null };
  days: {
    name: string;
    meals: {
      name: string;
      mealType: string | null;
      kcal: number | null;
      protein: number | null;
      carbs: number | null;
      fat: number | null;
    }[];
  }[];
  groceryCount: number;
}

function parseDietPlanRow(row: Record<string, unknown>): DietPlanView | null {
  const payload = (typeof row.payload === "object" && row.payload !== null ? row.payload : {}) as Record<string, unknown>;
  const name = (typeof row.name === "string" && row.name) || (typeof payload.name === "string" && payload.name) || null;
  if (!name) return null;
  const numOrNull = (v: unknown): number | null => (typeof v === "number" && Number.isFinite(v) ? v : null);
  const strOrNull = (v: unknown): string | null => (typeof v === "string" && v.length > 0 ? v : null);
  const days = (Array.isArray(payload.days) ? payload.days : []).map((rawDay) => {
    const day = (typeof rawDay === "object" && rawDay !== null ? rawDay : {}) as Record<string, unknown>;
    const meals = (Array.isArray(day.meals) ? day.meals : []).map((rawMeal) => {
      const meal = (typeof rawMeal === "object" && rawMeal !== null ? rawMeal : {}) as Record<string, unknown>;
      return {
        name: strOrNull(meal.name) ?? "Meal",
        mealType: strOrNull(meal.meal_type) ?? strOrNull(meal.type),
        kcal: numOrNull(meal.calories) ?? numOrNull(meal.calories_kcal) ?? numOrNull(meal.kcal),
        protein: numOrNull(meal.protein_g) ?? numOrNull(meal.protein),
        carbs: numOrNull(meal.carbs_g) ?? numOrNull(meal.carbs),
        fat: numOrNull(meal.fat_g) ?? numOrNull(meal.fat),
      };
    });
    return { name: strOrNull(day.dayName) ?? strOrNull(day.name) ?? "Day", meals };
  });
  const grocery = (typeof payload.groceryList === "object" && payload.groceryList !== null ? payload.groceryList : {}) as Record<string, unknown>;
  const groceryCount = (Array.isArray(grocery.categories) ? grocery.categories : []).reduce<number>((acc, cat) => {
    const c = (typeof cat === "object" && cat !== null ? cat : {}) as Record<string, unknown>;
    return acc + (Array.isArray(c.items) ? c.items.length : 0);
  }, 0);
  return {
    name,
    goal: strOrNull(row.goal) ?? strOrNull(payload.goal),
    preference: strOrNull(row.dietary_preference) ?? strOrNull(payload.dietaryPreference),
    mealsPerDay: numOrNull(row.meals_per_day) ?? numOrNull(payload.mealsPerDay),
    targets: {
      kcal: numOrNull(row.target_calories) ?? numOrNull(payload.targetCalories),
      protein: numOrNull(row.target_protein_g) ?? numOrNull(payload.targetProtein),
      carbs: numOrNull(row.target_carbs_g) ?? numOrNull(payload.targetCarbs),
      fat: numOrNull(row.target_fat_g) ?? numOrNull(payload.targetFat),
    },
    days,
    groceryCount,
  };
}

/** The live diet plan read off the API — own account or a coached client. */
export function JasperDietPlanPanel({
  open,
  onClose,
  clientUid,
  clientUsername,
  onOpenGrocery,
}: {
  open: boolean;
  onClose: () => void;
  clientUid?: string;
  clientUsername?: string;
  onOpenGrocery?: () => void;
}) {
  const generation = useJasperGeneration();
  const planQuery = useQuery({
    queryKey: ["jasper-diet-plan", clientUid ?? "own", generation],
    queryFn: async () => {
      const rows = clientUid
        ? await coachRead(clientUid, "diet_plans", 10)
        : await jasperRead("diet_plans", 10);
      for (const row of rows) {
        const parsed = parseDietPlanRow(row);
        if (parsed) return parsed;
      }
      return null;
    },
    enabled: open,
  });
  const plan = planQuery.data;
  const [dayIndex, setDayIndex] = useState<number>(0);
  return (
    <PanelShell
      open={open}
      onClose={onClose}
      kicker={clientUsername ? `@${clientUsername} · live from their Jasper` : "Live from your Jasper"}
      title={plan?.name ?? "Diet plan"}
    >
      {planQuery.isLoading ? (
        <div className="flex items-center gap-2 py-6 text-[13px] text-muted-foreground">
          <Loader2 className="h-4 w-4 animate-spin" /> Reading the live plan…
        </div>
      ) : planQuery.isError ? (
        <p className="py-6 text-center text-[12.5px] text-muted-foreground">{errorLine(planQuery.error)}</p>
      ) : !plan ? (
        <p className="py-6 text-center text-[13px] text-muted-foreground">
          No diet plan on the account yet — generate one with Jasper from the studio's Diet tab.
        </p>
      ) : (
        <div className="space-y-3.5">
          <EmberPlanKeyframes />
          <p className="text-[11px] font-bold text-muted-foreground">
            {[plan.goal, plan.preference, plan.mealsPerDay ? `${plan.mealsPerDay} meals/day` : null]
              .filter(Boolean)
              .join(" · ") || "Active plan"}
          </p>
          {/* WHISPER_PLANS.md §4.2 — macro tiles in the canonical colors. */}
          <JasperMacroTiles
            kcal={plan.targets.kcal}
            protein={plan.targets.protein}
            carbs={plan.targets.carbs}
            fat={plan.targets.fat}
          />
          {/* §4.3 — the 7-day chip strip: selected = ember-gradient capsule. */}
          {plan.days.length > 0 && (
            <div className="flex gap-2 overflow-x-auto pb-1" style={{ overscrollBehaviorX: "contain" }}>
              {plan.days.map((day, i) => {
                const selected = i === Math.min(dayIndex, plan.days.length - 1);
                return (
                  <button
                    key={`${day.name}-${i}`}
                    type="button"
                    onClick={() => setDayIndex(i)}
                    className="shrink-0 rounded-full px-3.5 py-2 text-[11px] font-bold transition-transform active:scale-95"
                    style={
                      selected
                        ? { background: JASPER_EMBER_GRADIENT, color: "#FFFFFF" }
                        : { background: "rgba(128,128,128,0.12)", color: "inherit", opacity: 0.75 }
                    }
                  >
                    {day.name}
                  </button>
                );
              })}
            </div>
          )}
          {/* §4.4–5 — the selected day's meal cards + the day totals row. */}
          {plan.days.length > 0 && (() => {
            const day = plan.days[Math.min(dayIndex, plan.days.length - 1)];
            const total = (pick: (m: (typeof day.meals)[number]) => number | null): number =>
              day.meals.reduce((acc, m) => acc + (pick(m) ?? 0), 0);
            return (
              <div className="space-y-2.5">
                {day.meals.map((meal, i) => (
                  <div
                    key={`${meal.name}-${i}`}
                    className="rounded-[15px] p-3"
                    style={{ background: "rgba(128,128,128,0.10)" }}
                  >
                    {meal.mealType && (
                      <p className="text-[10px] font-bold uppercase tracking-[0.06em] text-[#E76F3A] dark:text-[#F39057]">
                        {meal.mealType}
                      </p>
                    )}
                    <p className="text-[13.5px] font-bold text-foreground">{meal.name}</p>
                    <p className="mt-0.5 text-[11.5px] text-muted-foreground" style={{ fontVariantNumeric: "tabular-nums" }}>
                      {[
                        meal.kcal !== null ? `${Math.round(meal.kcal)} kcal` : null,
                        meal.protein !== null ? `${Math.round(meal.protein)}P` : null,
                        meal.carbs !== null ? `${Math.round(meal.carbs)}C` : null,
                        meal.fat !== null ? `${Math.round(meal.fat)}F` : null,
                      ]
                        .filter(Boolean)
                        .join(" · ")}
                    </p>
                  </div>
                ))}
                {day.meals.length === 0 && (
                  <p className="text-[11px] text-muted-foreground">No meals on this day.</p>
                )}
                {day.meals.length > 0 && (
                  <p className="border-t border-border/70 pt-2 text-[11.5px] font-semibold text-muted-foreground">
                    Day total · {Math.round(total((m) => m.kcal)).toLocaleString()} kcal · {Math.round(total((m) => m.protein))}P · {Math.round(total((m) => m.carbs))}C · {Math.round(total((m) => m.fat))}F
                  </p>
                )}
              </div>
            );
          })()}
          {plan.groceryCount > 0 && (
            <button type="button" onClick={() => onOpenGrocery?.()} className="block w-full text-left">
              {/* §4.6 — the grocery box rides as a second glow box (glow 0.5). */}
              <EmberGlowCard glow={0.5} className="flex items-center gap-3 p-3">
                <EmberGlowIcon size={32}>
                  <ShoppingCart className="h-3.5 w-3.5" strokeWidth={2.4} />
                </EmberGlowIcon>
                <span className="min-w-0 flex-1">
                  <EmberKicker text="Grocery list" secondary />
                  <span className="block text-[11.5px] opacity-60">
                    Shared with Jasper — checks sync both ways
                  </span>
                </span>
                <span className="shrink-0 text-[14px] font-bold" style={{ color: "#E76F3A" }}>
                  {plan.groceryCount}
                </span>
              </EmberGlowCard>
            </button>
          )}
        </div>
      )}
    </PanelShell>
  );
}

// Icon kept for panel triggers elsewhere.
export const JasperPanelIcons = { UtensilsCrossed };
