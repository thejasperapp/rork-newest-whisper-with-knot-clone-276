import { useEffect, useState } from "react";
import { Heart, Loader2, MapPin, MapPinOff } from "lucide-react";
import { toast } from "sonner";

import { EmberMascot } from "@/components/EmberMascot";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import {
  GENDER_OPTIONS,
  INTENT_OPTIONS,
  LIFESTYLE_TOPICS,
  RADIUS_STOPS,
  SEEKING_OPTIONS,
  loadDatingPrefs,
  prefsHasLocation,
  prefsIsConfigured,
  resolveCoarseLocation,
  saveDatingPrefs,
  syncDatingPrefsFromCloud,
  type DatingPrefs,
} from "@/lib/datingPrefs";
import { cn } from "@/lib/utils";

const CUPID = { accent: "#F5B8CC", softAccent: "#FFEDF2", deepAccent: "#E68FAD" };

/**
 * Dating preferences — who you want to meet, age range, distance radius,
 * what you're looking for, and a coarse location. Mirrors iOS
 * `WhisperDatingPrefsSheet`.
 */
export function DatingPrefsDialog({
  open,
  onOpenChange,
  userId,
  username,
  onSaved,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  userId: string;
  username: string | null;
  onSaved?: (prefs: DatingPrefs) => void;
}) {
  const [prefs, setPrefs] = useState<DatingPrefs>(() => loadDatingPrefs(userId));
  const [locating, setLocating] = useState<boolean>(false);
  const [locationError, setLocationError] = useState<string | null>(null);
  const [saving, setSaving] = useState<boolean>(false);

  useEffect(() => {
    if (!open) return;
    const local = loadDatingPrefs(userId);
    setPrefs(local);
    void syncDatingPrefsFromCloud(userId).then((cloud) => {
      if (prefsIsConfigured(cloud) && !prefsIsConfigured(local)) setPrefs(cloud);
    });
  }, [open, userId]);

  const radiusIndex = Math.max(0, RADIUS_STOPS.indexOf(prefs.radiusKm));
  const hasLocation = prefsHasLocation(prefs);

  const useMyLocation = async (): Promise<void> => {
    setLocating(true);
    setLocationError(null);
    try {
      const loc = await resolveCoarseLocation();
      setPrefs((p) => ({ ...p, lat: loc.lat, lng: loc.lng, cityLabel: loc.label }));
    } catch {
      setLocationError("Couldn't get your location — allow it in the browser, or leave distance on Anywhere.");
    } finally {
      setLocating(false);
    }
  };

  const save = async (): Promise<void> => {
    setSaving(true);
    await saveDatingPrefs(userId, username, prefs);
    setSaving(false);
    onSaved?.(loadDatingPrefs(userId));
    onOpenChange(false);
    toast.success("Preferences saved 💘");
  };

  const chip = (label: string, on: boolean, onClick: () => void): React.ReactNode => (
    <button
      key={label}
      type="button"
      onClick={onClick}
      className={cn(
        "rounded-full border px-3 py-2 text-[12.5px] font-bold transition-transform active:scale-95",
        on
          ? "border-transparent bg-rose-500 text-white"
          : "border-rose-300/60 bg-rose-500/10 text-rose-600 dark:text-rose-300"
      )}
    >
      {label}
    </button>
  );

  const section = (title: string, children: React.ReactNode): React.ReactNode => (
    <div className="rounded-[16px] border border-rose-300/30 bg-card p-3">
      <p className="text-[10px] font-black uppercase tracking-[0.16em] text-rose-500">{title}</p>
      <div className="mt-2">{children}</div>
    </div>
  );

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[92vh] max-w-md overflow-y-auto rounded-[24px]">
        <DialogHeader>
          <DialogTitle className="text-[15px] font-extrabold">Dating preferences</DialogTitle>
        </DialogHeader>
        <div className="flex items-start gap-2.5">
          <EmberMascot size={40} palette={CUPID} smitten expression="curious" />
          <p className="text-[12px] leading-snug text-muted-foreground">
            Who you want to meet, and how far you'll look. Your exact spot never leaves your device —
            only a ~1 km area, and other people only ever see a rounded distance.
          </p>
        </div>

        {section(
          "I am",
          <div className="flex flex-wrap gap-2">
            {GENDER_OPTIONS.map((o) =>
              chip(o.label, prefs.gender === o.id, () =>
                setPrefs((p) => ({ ...p, gender: p.gender === o.id ? null : o.id }))
              )
            )}
          </div>
        )}

        {section(
          "Show me",
          <div className="flex flex-wrap gap-2">
            {chip("Everyone", prefs.seeking.length === 0, () => setPrefs((p) => ({ ...p, seeking: [] })))}
            {SEEKING_OPTIONS.map((o) =>
              chip(o.label, prefs.seeking.includes(o.id), () =>
                setPrefs((p) => ({
                  ...p,
                  seeking: p.seeking.includes(o.id)
                    ? p.seeking.filter((x) => x !== o.id)
                    : [...p.seeking, o.id],
                }))
              )
            )}
          </div>
        )}

        {section(
          "My age",
          <div className="flex items-center gap-3">
            <span className="min-w-[52px] text-[28px] font-black tabular-nums">{prefs.age ?? "—"}</span>
            <input
              type="range"
              min={18}
              max={99}
              value={prefs.age ?? 25}
              onChange={(e) => setPrefs((p) => ({ ...p, age: Number(e.target.value) }))}
              className="flex-1 accent-rose-500"
            />
            {prefs.age == null && (
              <span className="text-[11px] text-muted-foreground">Slide to set</span>
            )}
          </div>
        )}

        {section(
          `Age range · ${prefs.ageMin}–${prefs.ageMax}`,
          <div className="space-y-2">
            <label className="flex items-center gap-2 text-[11.5px] font-semibold text-muted-foreground">
              <span className="w-16">Youngest</span>
              <input
                type="range"
                min={18}
                max={99}
                value={prefs.ageMin}
                onChange={(e) => {
                  const v = Number(e.target.value);
                  setPrefs((p) => ({ ...p, ageMin: v, ageMax: Math.max(v, p.ageMax) }));
                }}
                className="flex-1 accent-rose-500"
              />
              <span className="w-6 text-right text-[12.5px] font-bold text-foreground">{prefs.ageMin}</span>
            </label>
            <label className="flex items-center gap-2 text-[11.5px] font-semibold text-muted-foreground">
              <span className="w-16">Oldest</span>
              <input
                type="range"
                min={18}
                max={99}
                value={prefs.ageMax}
                onChange={(e) => {
                  const v = Number(e.target.value);
                  setPrefs((p) => ({ ...p, ageMax: v, ageMin: Math.min(v, p.ageMin) }));
                }}
                className="flex-1 accent-rose-500"
              />
              <span className="w-6 text-right text-[12.5px] font-bold text-foreground">{prefs.ageMax}</span>
            </label>
          </div>
        )}

        {section(
          `Distance · ${prefs.radiusKm <= 0 ? "Anywhere" : `Within ${prefs.radiusKm} km`}`,
          <div>
            <input
              type="range"
              min={0}
              max={RADIUS_STOPS.length - 1}
              step={1}
              value={radiusIndex}
              onChange={(e) => setPrefs((p) => ({ ...p, radiusKm: RADIUS_STOPS[Number(e.target.value)] }))}
              className="w-full accent-rose-500"
            />
            <div className="mt-1 flex justify-between text-[10.5px] font-semibold text-muted-foreground">
              <span>5 km</span>
              <span>Anywhere</span>
            </div>
            {!hasLocation && prefs.radiusKm > 0 && (
              <p className="mt-1.5 text-[11px] font-semibold text-rose-500">
                Set your location below so the radius can actually filter.
              </p>
            )}
          </div>
        )}

        {section(
          "Looking for",
          <div className="flex flex-wrap gap-2">
            {INTENT_OPTIONS.map((o) =>
              chip(`${o.emoji} ${o.label}`, prefs.intent === o.id, () =>
                setPrefs((p) => ({ ...p, intent: p.intent === o.id ? null : o.id }))
              )
            )}
          </div>
        )}

        {section(
          "My lifestyle",
          <div className="space-y-3">
            <p className="text-[11px] text-muted-foreground">Shown to your matches as a short line — “Doesn’t smoke · Drinks socially”.</p>
            {LIFESTYLE_TOPICS.map((t) => (
              <div key={t.id}>
                <p className="mb-1.5 text-[12px] font-bold">{t.label}</p>
                <div className="flex flex-wrap gap-2">
                  {t.options.map((o) =>
                    chip(o.label, (prefs.lifestyle ?? {})[t.id] === o.id, () =>
                      setPrefs((p) => {
                        const next = { ...(p.lifestyle ?? {}) };
                        if (next[t.id] === o.id) delete next[t.id];
                        else next[t.id] = o.id;
                        return { ...p, lifestyle: next };
                      })
                    )
                  )}
                </div>
              </div>
            ))}
          </div>
        )}

        {section(
          "Dealbreakers",
          <div className="space-y-3">
            <p className="text-[11px] text-muted-foreground">
              Pick what you’ll accept per topic. Anyone who answered otherwise is never paired with you — in the blind-date queue or nearby. People who left a topic blank still pass.
            </p>
            {LIFESTYLE_TOPICS.map((t) => {
              const accepted = (prefs.dealbreakers ?? {})[t.id] ?? [];
              return (
                <div key={t.id}>
                  <p className="mb-1.5 flex items-center gap-2 text-[12px] font-bold">
                    {t.label}
                    {accepted.length > 0 ? (
                      <span className="rounded-full bg-rose-500 px-1.5 py-0.5 text-[9px] font-extrabold uppercase tracking-wide text-white">Dealbreaker</span>
                    ) : (
                      <span className="text-[10.5px] font-normal text-muted-foreground">Any answer OK</span>
                    )}
                  </p>
                  <div className="flex flex-wrap gap-2">
                    {t.options.map((o) =>
                      chip(`OK: ${o.label}`, accepted.includes(o.id), () =>
                        setPrefs((p) => {
                          const next = { ...(p.dealbreakers ?? {}) };
                          const set = [...(next[t.id] ?? [])];
                          const i = set.indexOf(o.id);
                          if (i >= 0) set.splice(i, 1);
                          else set.push(o.id);
                          if (set.length === 0) delete next[t.id];
                          else next[t.id] = set;
                          return { ...p, dealbreakers: next };
                        })
                      )
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        )}

        {section(
          "Location",
          <div>
            <div className="flex items-center gap-2.5">
              {hasLocation ? (
                <MapPin className="h-4 w-4 shrink-0 text-rose-500" />
              ) : (
                <MapPinOff className="h-4 w-4 shrink-0 text-muted-foreground" />
              )}
              <div className="min-w-0 flex-1">
                <p className="truncate text-[13.5px] font-bold">
                  {prefs.cityLabel ?? (hasLocation ? "Location saved" : "Not set")}
                </p>
                <p className="text-[11px] text-muted-foreground">
                  {hasLocation
                    ? "Saved as a ~1 km area, never your exact spot."
                    : "Used only to measure distance to other daters."}
                </p>
              </div>
              <button
                type="button"
                onClick={() => void useMyLocation()}
                disabled={locating}
                className="flex shrink-0 items-center gap-1.5 rounded-full bg-rose-500 px-3 py-2 text-[12px] font-bold text-white transition-transform active:scale-95 disabled:opacity-60"
              >
                {locating ? <Loader2 className="h-3 w-3 animate-spin" /> : <MapPin className="h-3 w-3" />}
                {hasLocation ? "Update" : "Use my location"}
              </button>
            </div>
            {locationError && (
              <p className="mt-1.5 text-[11.5px] font-semibold text-rose-500">{locationError}</p>
            )}
            {hasLocation && (
              <button
                type="button"
                onClick={() => setPrefs((p) => ({ ...p, lat: null, lng: null, cityLabel: null }))}
                className="mt-1.5 text-[12px] font-semibold text-muted-foreground underline-offset-2 hover:underline"
              >
                Remove location
              </button>
            )}
          </div>
        )}

        <button
          type="button"
          onClick={() => void save()}
          disabled={saving}
          className="flex w-full items-center justify-center gap-1.5 rounded-full bg-rose-500 py-2.5 text-[13px] font-bold text-white transition-transform active:scale-95 disabled:opacity-60"
        >
          {saving ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Heart className="h-3.5 w-3.5" />}
          Save preferences
        </button>
      </DialogContent>
    </Dialog>
  );
}
