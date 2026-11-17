/**
 * Business profile manager — the company identity behind every ad (name,
 * category, contact, logo, about). One profile per account in v1; the ads
 * manager attaches it to every creative it serves.
 */
import { useEffect, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Building2, Check, Globe, ImageUp, Loader2, Mail, Phone } from "lucide-react";

import { supabase } from "@/lib/supabase";
import { useAuth } from "@/hooks/useAuth";
import { BusinessProfile, uploadAdMedia } from "@/lib/business";

const CATEGORIES = [
  "Fitness & training",
  "Supplements & nutrition",
  "Apparel & gear",
  "Health & recovery",
  "Tech & apps",
  "Food & beverage",
  "Local business",
  "Agency",
  "Other",
];

interface ProfileDraft {
  name: string;
  category: string;
  website: string;
  email: string;
  phone: string;
  logoUrl: string;
  about: string;
}

const emptyProfileDraft: ProfileDraft = {
  name: "",
  category: "",
  website: "",
  email: "",
  phone: "",
  logoUrl: "",
  about: "",
};

export function BusinessProfileTab() {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState<ProfileDraft>(emptyProfileDraft);
  const [hydratedFor, setHydratedFor] = useState<string | null>(null);
  const [savedFlash, setSavedFlash] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  const [logoUploading, setLogoUploading] = useState<boolean>(false);
  const logoFileRef = useRef<HTMLInputElement | null>(null);

  /** Upload a logo image to the ad-media bucket and fill the URL field. */
  const handleLogoFile = async (file: File): Promise<void> => {
    if (!user) return;
    if (!file.type.startsWith("image/")) {
      setError("Logos must be an image file.");
      return;
    }
    setLogoUploading(true);
    setError(null);
    try {
      const uploaded = await uploadAdMedia(user.id, file);
      setDraft((prev) => ({ ...prev, logoUrl: uploaded.url }));
    } catch (uploadError) {
      setError((uploadError as Error).message ?? "Upload failed. Try again.");
    }
    setLogoUploading(false);
  };

  const profileQuery = useQuery({
    queryKey: ["business-profile", user?.id ?? "anon"],
    enabled: !!user,
    queryFn: async (): Promise<BusinessProfile | null> => {
      const { data, error: queryError } = await supabase
        .from("business_profiles")
        .select("*")
        .order("created_at", { ascending: true })
        .limit(1);
      if (queryError) throw queryError;
      return ((data ?? [])[0] as BusinessProfile | undefined) ?? null;
    },
  });

  const profile = profileQuery.data ?? null;

  useEffect(() => {
    const key = profile?.id ?? "new";
    if (hydratedFor === key) return;
    setHydratedFor(key);
    if (profile) {
      setDraft({
        name: profile.name,
        category: profile.category ?? "",
        website: profile.website ?? "",
        email: profile.email ?? "",
        phone: profile.phone ?? "",
        logoUrl: profile.logo_url ?? "",
        about: profile.about ?? "",
      });
    }
  }, [profile, hydratedFor]);

  const saveMutation = useMutation({
    mutationFn: async (input: ProfileDraft): Promise<void> => {
      if (!user) throw new Error("Sign in first.");
      const row = {
        name: input.name.trim(),
        category: input.category.trim() || null,
        website: input.website.trim() || null,
        email: input.email.trim() || null,
        phone: input.phone.trim() || null,
        logo_url: input.logoUrl.trim() || null,
        about: input.about.trim() || null,
        updated_at: new Date().toISOString(),
      };
      if (profile) {
        const { error: updateError } = await supabase
          .from("business_profiles")
          .update(row)
          .eq("id", profile.id);
        if (updateError) throw updateError;
      } else {
        const { error: insertError } = await supabase
          .from("business_profiles")
          .insert({ ...row, user_id: user.id });
        if (insertError) throw insertError;
      }
    },
    onSuccess: () => {
      setError(null);
      setSavedFlash(true);
      window.setTimeout(() => setSavedFlash(false), 2200);
      void queryClient.invalidateQueries({ queryKey: ["business-profile", user?.id ?? "anon"] });
    },
    onError: (mutationError: unknown) => {
      const err = mutationError as { message?: string };
      setError(err.message ?? "Couldn't save your business profile.");
    },
  });

  const inputClass =
    "w-full rounded-xl border border-border/60 bg-background px-3 py-2.5 text-[13.5px] outline-none focus:border-[#5A5FE8]/60";

  return (
    <div className="space-y-3.5">
      {/* Identity preview — how the brand shows up on sponsored cards */}
      <div className="glass rounded-[22px] border border-border/60 p-4">
        <p className="text-[10.5px] font-extrabold uppercase tracking-wider text-muted-foreground">
          How Whisper shows your business
        </p>
        <div className="mt-3 flex items-center gap-3">
          {draft.logoUrl.trim() ? (
            <img
              src={draft.logoUrl.trim()}
              alt="Business logo"
              className="h-14 w-14 rounded-2xl border border-border/50 object-cover"
            />
          ) : (
            <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-[#5A5FE8]/15">
              <Building2 className="h-6 w-6 text-[#5A5FE8]" />
            </div>
          )}
          <div className="min-w-0">
            <p className="truncate text-[16px] font-extrabold">
              {draft.name.trim() || "Your business name"}
            </p>
            <p className="truncate text-[12px] text-muted-foreground">
              {draft.category || "Category"} · Sponsored
            </p>
          </div>
        </div>
        {draft.about.trim() && (
          <p className="mt-2.5 line-clamp-2 text-[12.5px] leading-relaxed text-muted-foreground">
            {draft.about.trim()}
          </p>
        )}
        <div className="mt-2.5 flex flex-wrap gap-2">
          {draft.website.trim() && (
            <span className="flex items-center gap-1 rounded-full bg-muted/70 px-2.5 py-1 text-[10.5px] font-semibold text-muted-foreground">
              <Globe className="h-3 w-3" />
              {draft.website.trim()}
            </span>
          )}
          {draft.email.trim() && (
            <span className="flex items-center gap-1 rounded-full bg-muted/70 px-2.5 py-1 text-[10.5px] font-semibold text-muted-foreground">
              <Mail className="h-3 w-3" />
              {draft.email.trim()}
            </span>
          )}
          {draft.phone.trim() && (
            <span className="flex items-center gap-1 rounded-full bg-muted/70 px-2.5 py-1 text-[10.5px] font-semibold text-muted-foreground">
              <Phone className="h-3 w-3" />
              {draft.phone.trim()}
            </span>
          )}
        </div>
      </div>

      {/* Editor */}
      <div className="glass rounded-[22px] border border-border/60 p-4">
        <p className="text-[14px] font-extrabold">
          {profile ? "Business profile" : "Create your business profile"}
        </p>
        <p className="mt-0.5 text-[11.5px] text-muted-foreground">
          This identity fronts every ad you run on Whisper.
        </p>

        <div className="mt-3 space-y-2.5">
          <input
            value={draft.name}
            onChange={(e) => setDraft({ ...draft, name: e.target.value })}
            placeholder="Business name"
            className={inputClass}
          />
          <div className="no-scrollbar flex gap-1.5 overflow-x-auto">
            {CATEGORIES.map((category) => (
              <button
                key={category}
                onClick={() =>
                  setDraft({ ...draft, category: draft.category === category ? "" : category })
                }
                className={`shrink-0 rounded-full px-3 py-1.5 text-[11.5px] font-bold transition-colors ${
                  draft.category === category
                    ? "bg-[#5A5FE8] text-white"
                    : "bg-muted/70 text-muted-foreground"
                }`}
              >
                {category}
              </button>
            ))}
          </div>
          <div className="flex gap-2.5">
            <input
              value={draft.website}
              onChange={(e) => setDraft({ ...draft, website: e.target.value })}
              placeholder="Website"
              className={inputClass}
            />
            <input
              value={draft.email}
              onChange={(e) => setDraft({ ...draft, email: e.target.value })}
              placeholder="Contact email"
              className={inputClass}
            />
          </div>
          <input
            value={draft.phone}
            onChange={(e) => setDraft({ ...draft, phone: e.target.value })}
            placeholder="Phone (optional)"
            className={inputClass}
          />
          <div className="flex items-center gap-2">
            <input
              value={draft.logoUrl}
              onChange={(e) => setDraft({ ...draft, logoUrl: e.target.value })}
              placeholder="Logo — upload a photo or paste a URL"
              className={inputClass}
            />
            <button
              type="button"
              onClick={() => logoFileRef.current?.click()}
              disabled={logoUploading}
              className="flex h-[42px] w-[46px] shrink-0 items-center justify-center rounded-xl border border-border/60 bg-muted/50 text-muted-foreground transition-colors hover:text-foreground disabled:opacity-50"
              aria-label="Upload logo"
            >
              {logoUploading ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <ImageUp className="h-4 w-4" />
              )}
            </button>
            <input
              ref={logoFileRef}
              type="file"
              accept="image/*"
              className="hidden"
              onChange={(e) => {
                const file = e.target.files?.[0];
                if (file) void handleLogoFile(file);
                e.target.value = "";
              }}
            />
          </div>
          <textarea
            value={draft.about}
            onChange={(e) => setDraft({ ...draft, about: e.target.value })}
            placeholder="About your business — what should Whisper users know?"
            rows={3}
            className={`${inputClass} resize-none`}
          />

          {error && <p className="text-[11.5px] font-semibold text-red-500">{error}</p>}

          <button
            onClick={() => {
              if (!draft.name.trim()) {
                setError("Give your business a name.");
                return;
              }
              saveMutation.mutate(draft);
            }}
            disabled={saveMutation.isPending}
            className="flex w-full items-center justify-center gap-1.5 rounded-full bg-[#5A5FE8] py-3 text-[13.5px] font-extrabold text-white transition-transform active:scale-[0.98] disabled:opacity-60"
          >
            {savedFlash ? (
              <>
                <Check className="h-4 w-4" />
                Saved
              </>
            ) : saveMutation.isPending ? (
              "Saving…"
            ) : profile ? (
              "Save changes"
            ) : (
              "Create business profile"
            )}
          </button>
        </div>
      </div>
    </div>
  );
}
