import { useEffect, useRef, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ArrowLeft,
  Briefcase,
  Building2,
  Check,
  Flame,
  ImagePlus,
  Loader2,
  ShieldCheck,
  ShieldX,
  Video,
  X,
} from "lucide-react";
import { toast } from "sonner";

import { useAuth } from "@/hooks/useAuth";
import { uploadMedia } from "@/lib/api";
import { emberInspectBrand } from "@/lib/emberBrandCheck";
import {
  BASIS_LABELS,
  fetchBrand,
  saveBrandProfile,
  saveBrandVerification,
  type SponsorBasis,
} from "@/lib/brands";

const AMENITY_OPTIONS: string[] = [
  "Creator analytics",
  "Campaign tracking",
  "Creator discovery",
  "Content approvals",
  "Product seeding",
  "Affiliate links",
  "Contract templates",
  "Dedicated support",
];

const BASES: SponsorBasis[] = ["per_post", "per_month", "per_year"];

function Field({
  label,
  hint,
  children,
}: {
  label: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <div>
      <p className="text-[12px] font-bold uppercase tracking-wide text-muted-foreground">
        {label}
      </p>
      {hint && (
        <p className="mt-0.5 text-[12px] text-muted-foreground/80">{hint}</p>
      )}
      <div className="mt-1.5">{children}</div>
    </div>
  );
}

const inputClass =
  "w-full rounded-xl border border-border bg-background px-3.5 py-2.5 text-[14.5px] outline-none placeholder:text-muted-foreground/60";

/**
 * Brand signup / profile editor — company details, the amenities they need,
 * sponsorship requirements that gate applicants (min followers / age /
 * posts), and transparent typical pay.
 */
export default function BrandSignup() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const queryClient = useQueryClient();

  const existing = useQuery({
    queryKey: ["brand", user?.id ?? ""],
    queryFn: () => fetchBrand(user!.id),
    enabled: !!user?.id,
  });

  const [companyName, setCompanyName] = useState<string>("");
  const [website, setWebsite] = useState<string>("");
  const [industry, setIndustry] = useState<string>("");
  const [about, setAbout] = useState<string>("");
  const [logoUrl, setLogoUrl] = useState<string>("");
  const [coverUrl, setCoverUrl] = useState<string>("");
  const [mediaUrls, setMediaUrls] = useState<string[]>([]);
  const [videoUrl, setVideoUrl] = useState<string>("");
  const [instagram, setInstagram] = useState<string>("");
  const [logoUploading, setLogoUploading] = useState<boolean>(false);
  const [coverUploading, setCoverUploading] = useState<boolean>(false);
  const [galleryUploading, setGalleryUploading] = useState<boolean>(false);
  const [videoUploading, setVideoUploading] = useState<boolean>(false);
  const logoInputRef = useRef<HTMLInputElement | null>(null);
  const coverInputRef = useRef<HTMLInputElement | null>(null);
  const galleryInputRef = useRef<HTMLInputElement | null>(null);
  const videoInputRef = useRef<HTMLInputElement | null>(null);
  const [amenities, setAmenities] = useState<string[]>([]);
  const [minFollowers, setMinFollowers] = useState<string>("1000");
  const [minAge, setMinAge] = useState<string>("18");
  const [minPosts, setMinPosts] = useState<string>("10");
  const [payBasis, setPayBasis] = useState<SponsorBasis>("per_post");
  const [payMin, setPayMin] = useState<string>("");
  const [payMax, setPayMax] = useState<string>("");
  const [paymentTerms, setPaymentTerms] = useState<string>("");
  const [published, setPublished] = useState<boolean>(true);
  const [hydrated, setHydrated] = useState<boolean>(false);

  useEffect(() => {
    const brand = existing.data;
    if (!brand || hydrated) return;
    setHydrated(true);
    setCompanyName(brand.company_name);
    setWebsite(brand.website ?? "");
    setIndustry(brand.industry ?? "");
    setAbout(brand.about ?? "");
    setLogoUrl(brand.logo_url ?? "");
    setCoverUrl(brand.cover_url ?? "");
    setMediaUrls(brand.media_urls ?? []);
    setVideoUrl(brand.video_url ?? "");
    setInstagram(brand.instagram ?? "");
    setAmenities(brand.amenities);
    setMinFollowers(String(brand.min_followers));
    setMinAge(String(brand.min_age));
    setMinPosts(String(brand.min_posts));
    setPayBasis(brand.pay_basis);
    if (brand.typical_pay_min_cents)
      setPayMin(String(brand.typical_pay_min_cents / 100));
    if (brand.typical_pay_max_cents)
      setPayMax(String(brand.typical_pay_max_cents / 100));
    setPaymentTerms(brand.payment_terms ?? "");
    setPublished(brand.published);
  }, [existing.data, hydrated]);

  const save = useMutation({
    mutationFn: async () => {
      const dollarsToCents = (raw: string): number | null => {
        const n = Number(raw.replace(/[^0-9.]/g, ""));
        return Number.isFinite(n) && n > 0 ? Math.round(n * 100) : null;
      };
      if (!companyName.trim()) throw new Error("Enter your company name.");
      await saveBrandProfile({
        companyName: companyName.trim(),
        website: website.trim(),
        industry: industry.trim(),
        about: about.trim(),
        logoUrl: logoUrl.trim(),
        coverUrl: coverUrl.trim(),
        mediaUrls,
        videoUrl: videoUrl.trim(),
        instagram: instagram.trim(),
        amenities,
        minFollowers: Math.max(0, Math.round(Number(minFollowers) || 0)),
        minAge: Math.max(13, Math.round(Number(minAge) || 18)),
        minPosts: Math.max(0, Math.round(Number(minPosts) || 0)),
        payBasis,
        typicalPayMinCents: dollarsToCents(payMin),
        typicalPayMaxCents: dollarsToCents(payMax),
        paymentTerms: paymentTerms.trim(),
        published,
      });
    },
    onSuccess: () => {
      toast.success("Brand profile saved.");
      queryClient.invalidateQueries({ queryKey: ["brand"] });
      queryClient.invalidateQueries({ queryKey: ["brands"] });
      navigate("/brand/dashboard");
    },
    onError: (err) =>
      toast.error(err instanceof Error ? err.message : "Couldn't save."),
  });

  const toggleAmenity = (a: string): void => {
    setAmenities((prev) =>
      prev.includes(a) ? prev.filter((x) => x !== a) : [...prev, a]
    );
  };

  const onLogoFile = async (
    e: React.ChangeEvent<HTMLInputElement>
  ): Promise<void> => {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file || !user) return;
    if (!file.type.startsWith("image/")) {
      toast.error("Choose an image file.");
      return;
    }
    setLogoUploading(true);
    try {
      const url = await uploadMedia(file, user.id);
      setLogoUrl(url);
      toast.success("Logo uploaded — don't forget to save.");
    } catch {
      toast.error("Couldn't upload the logo. Try again.");
    } finally {
      setLogoUploading(false);
    }
  };

  const onCoverFile = async (
    e: React.ChangeEvent<HTMLInputElement>
  ): Promise<void> => {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file || !user) return;
    if (!file.type.startsWith("image/")) {
      toast.error("Choose an image file.");
      return;
    }
    setCoverUploading(true);
    try {
      const url = await uploadMedia(file, user.id);
      setCoverUrl(url);
      toast.success("Cover uploaded — don't forget to save.");
    } catch {
      toast.error("Couldn't upload the cover. Try again.");
    } finally {
      setCoverUploading(false);
    }
  };

  const onGalleryFiles = async (
    e: React.ChangeEvent<HTMLInputElement>
  ): Promise<void> => {
    const files = Array.from(e.target.files ?? []);
    e.target.value = "";
    if (files.length === 0 || !user) return;
    const valid = files.filter((f) => f.type.startsWith("image/"));
    if (valid.length === 0) {
      toast.error("Choose image files.");
      return;
    }
    if (mediaUrls.length + valid.length > 12) {
      toast.error("You can add up to 12 gallery images.");
      return;
    }
    setGalleryUploading(true);
    try {
      const urls = await Promise.all(valid.map((f) => uploadMedia(f, user.id)));
      setMediaUrls((prev) => [...prev, ...urls]);
      toast.success(`${urls.length} image${urls.length === 1 ? "" : "s"} added — don't forget to save.`);
    } catch {
      toast.error("Couldn't upload one or more images. Try again.");
    } finally {
      setGalleryUploading(false);
    }
  };

  const onVideoFile = async (
    e: React.ChangeEvent<HTMLInputElement>
  ): Promise<void> => {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file || !user) return;
    if (!file.type.startsWith("video/")) {
      toast.error("Choose a video file.");
      return;
    }
    if (file.size > 60 * 1024 * 1024) {
      toast.error("Video must be under 60MB.");
      return;
    }
    setVideoUploading(true);
    try {
      const url = await uploadMedia(file, user.id);
      setVideoUrl(url);
      toast.success("Video uploaded — don't forget to save.");
    } catch {
      toast.error("Couldn't upload the video. Try again.");
    } finally {
      setVideoUploading(false);
    }
  };

  const verify = useMutation({
    mutationFn: async () => {
      if (!companyName.trim()) throw new Error("Enter your company name first.");
      if (!instagram.trim())
        throw new Error("Enter your Instagram handle first.");
      const verdict = await emberInspectBrand({
        companyName: companyName.trim(),
        instagram: instagram.trim(),
        website: website.trim(),
      });
      await saveBrandVerification({
        instagram: instagram.trim(),
        verified: verdict.verified,
        score: verdict.score,
        summary: verdict.summary,
      });
      return verdict;
    },
    onSuccess: (verdict) => {
      toast[verdict.verified ? "success" : "warning"](
        verdict.verified
          ? "Jasper verified your Instagram presence."
          : "Jasper couldn't verify this Instagram yet — see the notes below."
      );
      queryClient.invalidateQueries({ queryKey: ["brand"] });
      queryClient.invalidateQueries({ queryKey: ["brands"] });
    },
    onError: (err) =>
      toast.error(
        err instanceof Error ? err.message : "Jasper couldn't run the check."
      ),
  });

  const emberResult = verify.data ?? null;
  const savedVerified = existing.data?.ember_verified === true;
  const savedSummary = existing.data?.ember_summary ?? null;
  const savedScore = existing.data?.ember_score ?? null;
  const showVerified = emberResult ? emberResult.verified : savedVerified;
  const showSummary = emberResult ? emberResult.summary : savedSummary;
  const showScore = emberResult ? emberResult.score : savedScore;
  const hasEmberResult =
    emberResult !== null || savedSummary !== null || savedVerified;

  return (
    <div className="mx-auto w-full max-w-xl px-4 pb-24 pt-3">
      <button
        onClick={() => navigate(-1)}
        className="mb-3 inline-flex items-center gap-1.5 text-[13.5px] font-bold text-muted-foreground"
      >
        <ArrowLeft className="h-4 w-4" /> Back
      </button>

      <div className="flex items-center gap-3">
        <span className="flex h-11 w-11 items-center justify-center rounded-2xl bg-indigo-500/10">
          <Briefcase className="h-5 w-5 text-indigo-500" />
        </span>
        <div>
          <h1 className="text-[20px] font-black">
            {existing.data ? "Edit brand profile" : "Create a brand profile"}
          </h1>
          <p className="text-[13px] text-muted-foreground">
            Everything creators see before they apply.
          </p>
        </div>
      </div>

      <div className="mt-5 space-y-4 rounded-[20px] border border-border bg-card p-4">
        <p className="text-[14px] font-extrabold">Company</p>
        <Field label="Company name">
          <input
            value={companyName}
            onChange={(e) => setCompanyName(e.target.value)}
            placeholder="Acme Nutrition"
            className={inputClass}
          />
        </Field>
        <Field label="Website">
          <input
            value={website}
            onChange={(e) => setWebsite(e.target.value)}
            placeholder="acme.com"
            className={inputClass}
          />
        </Field>
        <Field label="Industry">
          <input
            value={industry}
            onChange={(e) => setIndustry(e.target.value)}
            placeholder="Supplements"
            className={inputClass}
          />
        </Field>
        <Field label="Logo" hint="Upload a square image — creators see it everywhere.">
          <div className="flex items-center gap-3">
            <div
              className="flex shrink-0 items-center justify-center overflow-hidden rounded-2xl bg-secondary"
              style={{ width: 64, height: 64 }}
            >
              {logoUrl ? (
                <img
                  src={logoUrl}
                  alt="Brand logo"
                  className="h-full w-full object-cover"
                />
              ) : (
                <Building2 className="h-6 w-6 text-indigo-500/60" />
              )}
            </div>
            <div className="flex flex-col gap-1.5">
              <button
                type="button"
                onClick={() => logoInputRef.current?.click()}
                disabled={logoUploading}
                className="inline-flex items-center gap-1.5 rounded-full bg-indigo-500/10 px-4 py-2 text-[12.5px] font-bold text-indigo-500 transition-transform active:scale-[0.97] disabled:opacity-50"
              >
                {logoUploading ? (
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                ) : (
                  <ImagePlus className="h-3.5 w-3.5" />
                )}
                {logoUrl ? "Replace logo" : "Upload logo"}
              </button>
              {logoUrl && (
                <button
                  type="button"
                  onClick={() => setLogoUrl("")}
                  className="text-left text-[12px] font-bold text-red-500"
                >
                  Remove
                </button>
              )}
            </div>
            <input
              ref={logoInputRef}
              type="file"
              accept="image/*"
              onChange={(e) => void onLogoFile(e)}
              className="hidden"
            />
          </div>
        </Field>
        <Field label="Instagram" hint="Jasper reviews your tagged posts to verify you really work with creators.">
          <div className="flex items-center rounded-xl border border-border bg-background px-3.5">
            <span className="text-[14.5px] font-semibold text-muted-foreground">@</span>
            <input
              value={instagram}
              onChange={(e) => setInstagram(e.target.value.replace(/^@+/, ""))}
              placeholder="acmenutrition"
              className="w-full bg-transparent px-1.5 py-2.5 text-[14.5px] outline-none placeholder:text-muted-foreground/60"
            />
          </div>
        </Field>
        <Field label="About">
          <textarea
            value={about}
            onChange={(e) => setAbout(e.target.value)}
            placeholder="What your brand does and what you look for in creators…"
            rows={3}
            className={`${inputClass} resize-none`}
          />
        </Field>
      </div>

      <div className="mt-3 space-y-4 rounded-[20px] border border-border bg-card p-4">
        <div>
          <p className="text-[14px] font-extrabold">Showcase media</p>
          <p className="mt-0.5 text-[12.5px] text-muted-foreground">
            A cover image, optional video, and up to 12 gallery photos appear in
            your marketplace card — this is your hero moment, make it count.
          </p>
        </div>

        <Field label="Cover image" hint="Wide backdrop shown behind your logo on the marketplace card.">
          <div className="flex items-center gap-3">
            <div
              className="flex shrink-0 items-center justify-center overflow-hidden rounded-2xl bg-secondary"
              style={{ width: 96, height: 56 }}
            >
              {coverUrl ? (
                <img src={coverUrl} alt="Cover" className="h-full w-full object-cover" />
              ) : (
                <ImagePlus className="h-5 w-5 text-indigo-500/50" />
              )}
            </div>
            <div className="flex flex-col gap-1.5">
              <button
                type="button"
                onClick={() => coverInputRef.current?.click()}
                disabled={coverUploading}
                className="inline-flex items-center gap-1.5 rounded-full bg-indigo-500/10 px-4 py-2 text-[12.5px] font-bold text-indigo-500 transition-transform active:scale-[0.97] disabled:opacity-50"
              >
                {coverUploading ? (
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                ) : (
                  <ImagePlus className="h-3.5 w-3.5" />
                )}
                {coverUrl ? "Replace cover" : "Upload cover"}
              </button>
              {coverUrl && (
                <button
                  type="button"
                  onClick={() => setCoverUrl("")}
                  className="text-left text-[12px] font-bold text-red-500"
                >
                  Remove
                </button>
              )}
            </div>
            <input
              ref={coverInputRef}
              type="file"
              accept="image/*"
              onChange={(e) => void onCoverFile(e)}
              className="hidden"
            />
          </div>
        </Field>

        <Field label="Showreel video" hint="Optional MP4 (under 60MB). Plays as the first slide in the carousel.">
          <div className="flex items-center gap-3">
            <div
              className="flex shrink-0 items-center justify-center overflow-hidden rounded-2xl bg-secondary"
              style={{ width: 96, height: 56 }}
            >
              {videoUrl ? (
                <video src={videoUrl} className="h-full w-full object-cover" muted />
              ) : (
                <Video className="h-5 w-5 text-indigo-500/50" />
              )}
            </div>
            <div className="flex flex-col gap-1.5">
              <button
                type="button"
                onClick={() => videoInputRef.current?.click()}
                disabled={videoUploading}
                className="inline-flex items-center gap-1.5 rounded-full bg-indigo-500/10 px-4 py-2 text-[12.5px] font-bold text-indigo-500 transition-transform active:scale-[0.97] disabled:opacity-50"
              >
                {videoUploading ? (
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                ) : (
                  <Video className="h-3.5 w-3.5" />
                )}
                {videoUrl ? "Replace video" : "Upload video"}
              </button>
              {videoUrl && (
                <button
                  type="button"
                  onClick={() => setVideoUrl("")}
                  className="text-left text-[12px] font-bold text-red-500"
                >
                  Remove
                </button>
              )}
            </div>
            <input
              ref={videoInputRef}
              type="file"
              accept="video/*"
              onChange={(e) => void onVideoFile(e)}
              className="hidden"
            />
          </div>
        </Field>

        <Field label="Gallery" hint="Up to 12 photos shown in the carousel after the cover/video.">
          <div className="space-y-2">
            {mediaUrls.length > 0 && (
              <div className="grid grid-cols-4 gap-2">
                {mediaUrls.map((url, idx) => (
                  <div
                    key={`${url}-${idx}`}
                    className="group relative aspect-square overflow-hidden rounded-xl bg-secondary"
                  >
                    <img src={url} alt="" className="h-full w-full object-cover" />
                    <button
                      type="button"
                      onClick={() =>
                        setMediaUrls((prev) => prev.filter((_, i) => i !== idx))
                      }
                      className="absolute right-1 top-1 flex h-5 w-5 items-center justify-center rounded-full bg-black/60 text-white transition-opacity"
                      aria-label="Remove"
                    >
                      <X className="h-3 w-3" />
                    </button>
                  </div>
                ))}
              </div>
            )}
            <button
              type="button"
              onClick={() => galleryInputRef.current?.click()}
              disabled={galleryUploading || mediaUrls.length >= 12}
              className="flex w-full items-center justify-center gap-2 rounded-xl border border-dashed border-border py-3 text-[12.5px] font-bold text-muted-foreground transition-transform active:scale-[0.99] disabled:opacity-50"
            >
              {galleryUploading ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <ImagePlus className="h-4 w-4" />
              )}
              {mediaUrls.length === 0 ? "Add gallery photos" : "Add more"}
              <span className="text-muted-foreground/70">({mediaUrls.length}/12)</span>
            </button>
            <input
              ref={galleryInputRef}
              type="file"
              accept="image/*"
              multiple
              onChange={(e) => void onGalleryFiles(e)}
              className="hidden"
            />
          </div>
        </Field>
      </div>

      <div className="mt-3 rounded-[20px] border border-orange-500/25 bg-orange-500/5 p-4">
        <div className="flex items-center gap-2">
          <span className="flex h-8 w-8 items-center justify-center rounded-full bg-orange-500/15">
            <Flame className="h-4 w-4 text-orange-500" />
          </span>
          <div>
            <p className="text-[14px] font-extrabold">Jasper verification</p>
            <p className="text-[12px] text-muted-foreground">
              Jasper checks your Instagram's tagged posts and creator collabs —
              so creators know you're the real deal.
            </p>
          </div>
        </div>

        {hasEmberResult && (
          <div
            className={`mt-3 rounded-[14px] border p-3 ${
              showVerified
                ? "border-emerald-500/30 bg-emerald-500/5"
                : "border-amber-500/30 bg-amber-500/5"
            }`}
          >
            <div className="flex items-center gap-1.5">
              {showVerified ? (
                <ShieldCheck className="h-4 w-4 text-emerald-600" />
              ) : (
                <ShieldX className="h-4 w-4 text-amber-600" />
              )}
              <p
                className={`text-[13px] font-bold ${
                  showVerified ? "text-emerald-600" : "text-amber-600"
                }`}
              >
                {showVerified
                  ? "Jasper verified this brand"
                  : "Not verified yet"}
                {typeof showScore === "number" && ` · ${showScore}/100`}
              </p>
            </div>
            {showSummary && (
              <p className="mt-1.5 text-[12.5px] leading-snug text-muted-foreground">
                {showSummary}
              </p>
            )}
          </div>
        )}

        <button
          type="button"
          onClick={() => verify.mutate()}
          disabled={verify.isPending || !instagram.trim() || !companyName.trim() || !existing.data}
          className="mt-3 flex w-full items-center justify-center gap-2 rounded-full bg-orange-500 py-2.5 text-[13px] font-bold text-white transition-transform active:scale-[0.98] disabled:opacity-40"
        >
          {verify.isPending ? (
            <>
              <Loader2 className="h-4 w-4 animate-spin" /> Jasper is reviewing
              your Instagram…
            </>
          ) : (
            <>
              <Flame className="h-4 w-4" />
              {hasEmberResult ? "Run Jasper's check again" : "Have Jasper verify my Instagram"}
            </>
          )}
        </button>
        {!existing.data && (
          <p className="mt-2 text-[11.5px] text-muted-foreground">
            Save your brand profile first, then run Jasper's check.
          </p>
        )}
      </div>

      <div className="mt-3 space-y-3 rounded-[20px] border border-border bg-card p-4">
        <p className="text-[14px] font-extrabold">Tools you need</p>
        <div className="grid grid-cols-2 gap-1.5">
          {AMENITY_OPTIONS.map((a) => {
            const on = amenities.includes(a);
            return (
              <button
                key={a}
                onClick={() => toggleAmenity(a)}
                className={`flex items-center gap-1.5 rounded-xl border px-3 py-2 text-left text-[12.5px] font-semibold transition-colors ${
                  on
                    ? "border-indigo-500/50 text-indigo-500"
                    : "border-border text-muted-foreground"
                }`}
              >
                <Check
                  className={`h-3.5 w-3.5 shrink-0 ${on ? "" : "opacity-25"}`}
                />
                {a}
              </button>
            );
          })}
        </div>
      </div>

      <div className="mt-3 space-y-4 rounded-[20px] border border-border bg-card p-4">
        <div>
          <p className="text-[14px] font-extrabold">Sponsorship requirements</p>
          <p className="mt-0.5 text-[12.5px] text-muted-foreground">
            Only creators who meet these can apply — it keeps your inbox
            high-signal.
          </p>
        </div>
        <div className="grid grid-cols-3 gap-2.5">
          <Field label="Min followers">
            <input
              inputMode="numeric"
              value={minFollowers}
              onChange={(e) => setMinFollowers(e.target.value)}
              className={inputClass}
            />
          </Field>
          <Field label="Min age">
            <input
              inputMode="numeric"
              value={minAge}
              onChange={(e) => setMinAge(e.target.value)}
              className={inputClass}
            />
          </Field>
          <Field label="Min posts">
            <input
              inputMode="numeric"
              value={minPosts}
              onChange={(e) => setMinPosts(e.target.value)}
              className={inputClass}
            />
          </Field>
        </div>
      </div>

      <div className="mt-3 space-y-4 rounded-[20px] border border-border bg-card p-4">
        <div>
          <p className="text-[14px] font-extrabold">Payment transparency</p>
          <p className="mt-0.5 text-[12.5px] text-muted-foreground">
            Creators see this before applying. Transparent brands get better
            applicants.
          </p>
        </div>
        <div className="grid grid-cols-3 gap-1.5">
          {BASES.map((b) => (
            <button
              key={b}
              onClick={() => setPayBasis(b)}
              className={`rounded-full px-3 py-2 text-[12.5px] font-bold transition-colors ${
                payBasis === b
                  ? "bg-indigo-500 text-white"
                  : "bg-secondary text-muted-foreground"
              }`}
            >
              {BASIS_LABELS[b]}
            </button>
          ))}
        </div>
        <div className="grid grid-cols-2 gap-2.5">
          <Field label="Typical min ($)">
            <input
              inputMode="decimal"
              value={payMin}
              onChange={(e) => setPayMin(e.target.value)}
              placeholder="100"
              className={inputClass}
            />
          </Field>
          <Field label="Typical max ($)">
            <input
              inputMode="decimal"
              value={payMax}
              onChange={(e) => setPayMax(e.target.value)}
              placeholder="500"
              className={inputClass}
            />
          </Field>
        </div>
        <Field label="Payment terms">
          <textarea
            value={paymentTerms}
            onChange={(e) => setPaymentTerms(e.target.value)}
            placeholder="e.g. Paid per approved post, released weekly once posts are verified…"
            rows={2}
            className={`${inputClass} resize-none`}
          />
        </Field>
      </div>

      <div className="mt-3 flex items-center justify-between rounded-[20px] border border-border bg-card p-4">
        <div>
          <p className="text-[14px] font-bold">Listed in the brand directory</p>
          <p className="text-[12.5px] text-muted-foreground">
            Creators can find you and apply.
          </p>
        </div>
        <button
          role="switch"
          aria-checked={published}
          onClick={() => setPublished((v) => !v)}
          className={`relative h-7 w-12 rounded-full transition-colors ${
            published ? "bg-indigo-500" : "bg-secondary"
          }`}
        >
          <span
            className={`absolute top-0.5 h-6 w-6 rounded-full bg-white shadow transition-all ${
              published ? "left-[22px]" : "left-0.5"
            }`}
          />
        </button>
      </div>

      <button
        onClick={() => save.mutate()}
        disabled={save.isPending || !companyName.trim()}
        className="mt-5 flex w-full items-center justify-center gap-2 rounded-full bg-indigo-500 py-3.5 text-[15px] font-bold text-white transition-transform active:scale-[0.98] disabled:opacity-40"
      >
        {save.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
        {existing.data ? "Save brand profile" : "Create brand profile"}
      </button>

      <p className="mt-3 text-center text-[12px] text-muted-foreground">
        Already live?{" "}
        <Link to="/brand/dashboard" className="font-bold text-indigo-500">
          Open your dashboard
        </Link>
      </p>
    </div>
  );
}
