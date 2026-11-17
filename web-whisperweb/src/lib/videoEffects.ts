/**
 * WhisperVideoFx — browser-side virtual backgrounds for meetings and calls.
 *
 * Mirrors the iOS `WhisperVideoEffects` engine: person segmentation
 * (MediaPipe selfie segmenter) + canvas compositing turn the raw camera
 * track into a processed track with either a Google Meet-style background
 * blur or a chosen/AI-generated backdrop image behind the person.
 *
 *   camera track → hidden <video> → segment + composite on <canvas>
 *                → canvas.captureStream() track → published to peers
 *
 * The engine is deliberately defensive: while the segmentation model is
 * still loading (or fails to load), frames pass through untouched so video
 * never freezes because of an effect.
 */

import { FilesetResolver, ImageSegmenter } from "@mediapipe/tasks-vision";

export type VideoFxMode = "none" | "blur" | "backdrop";

const MODE_KEY = "whisper_videofx_mode";
const IMAGE_KEY = "whisper_videofx_image";
const SAVED_KEY = "whisper_videofx_saved";

const WASM_BASE = "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@1.0.1/wasm";
/** Square selfie model (256×256) — portrait / square sources. */
const MODEL_URL =
  "https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_segmenter/float16/latest/selfie_segmenter.tflite";
/** Landscape selfie model (256×144) — the right one for 16:9 webcams: the
 *  mask resolution matches the frame so edges stop staircasing. */
const MODEL_URL_LANDSCAPE =
  "https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_segmenter_landscape/float16/latest/selfie_segmenter_landscape.tflite";

/** Background blur radius — CSS blur(px) is a Gaussian sigma, so this mirrors
 *  the iOS engine's `applyingGaussianBlur(sigma: 16)`. */
const BLUR_SIGMA = 16;
/** Mask feather (px at output resolution) applied when the upscaled mask is
 *  composited — softens the model's staircase without haloing. */
const MASK_FEATHER_PX = 2.5;
/** Temporal smoothing — share of the NEW mask per frame (the rest is the
 *  previous frame). Kills the edge flicker the raw model produces. */
const MASK_EMA = 0.62;

/** Safari < 15.4 and older Chromium lack frame callbacks — feature-detect. */
function hasFrameCallbacks(video: HTMLVideoElement): boolean {
  return typeof video.requestVideoFrameCallback === "function";
}

// ─── Backdrop presets (match the iOS picker) ─────────────────────────────────

export interface BackdropPreset {
  id: string;
  name: string;
  colors: [string, string];
}

export const BACKDROP_PRESETS: BackdropPreset[] = [
  { id: "office", name: "Office", colors: ["#565660", "#1d1d24"] },
  { id: "nature", name: "Nature", colors: ["#41805a", "#0f2b1c"] },
  { id: "cozy", name: "Cozy", colors: ["#8a5a3b", "#2b1a10"] },
  { id: "studio", name: "Studio", colors: ["#2a2a2a", "#0d0d0d"] },
  { id: "sunset", name: "Sunset", colors: ["#fa8747", "#8c296b"] },
  { id: "ocean", name: "Ocean", colors: ["#1f6bb8", "#081c42"] },
  { id: "forest", name: "Forest", colors: ["#297349", "#08291a"] },
  { id: "neon", name: "Neon", colors: ["#7338f2", "#0da6d9"] },
  { id: "loft", name: "Loft", colors: ["#9e8770", "#3d3026"] },
];

const presetCache = new Map<string, string>();

/** Renders a preset gradient into a reusable 640×360 JPEG data URL. */
export function presetDataUrl(preset: BackdropPreset): string {
  const cached = presetCache.get(preset.id);
  if (cached) return cached;
  const canvas = document.createElement("canvas");
  canvas.width = 640;
  canvas.height = 360;
  const ctx = canvas.getContext("2d");
  if (!ctx) return "";
  const linear = ctx.createLinearGradient(0, 0, 640, 360);
  linear.addColorStop(0, preset.colors[0]);
  linear.addColorStop(1, preset.colors[1]);
  ctx.fillStyle = linear;
  ctx.fillRect(0, 0, 640, 360);
  const radial = ctx.createRadialGradient(480, 72, 10, 480, 72, 320);
  radial.addColorStop(0, "rgba(255,255,255,0.16)");
  radial.addColorStop(1, "rgba(255,255,255,0)");
  ctx.fillStyle = radial;
  ctx.fillRect(0, 0, 640, 360);
  const url = canvas.toDataURL("image/jpeg", 0.9);
  presetCache.set(preset.id, url);
  return url;
}

// ─── Saved (generated) backdrops ─────────────────────────────────────────────

/** Saved custom backdrop data URLs, newest first. */
export function savedBackdrops(): string[] {
  try {
    const raw = localStorage.getItem(SAVED_KEY);
    const list = raw ? (JSON.parse(raw) as unknown) : [];
    return Array.isArray(list)
      ? list.filter((item): item is string => typeof item === "string")
      : [];
  } catch {
    return [];
  }
}

/** Stores a generated backdrop (deduped, capped so localStorage stays sane). */
export function saveBackdrop(url: string): string[] {
  let list = [url, ...savedBackdrops().filter((item) => item !== url)].slice(0, 4);
  while (list.length > 0) {
    try {
      localStorage.setItem(SAVED_KEY, JSON.stringify(list));
      break;
    } catch {
      // Quota — drop the oldest and retry.
      list = list.slice(0, list.length - 1);
    }
  }
  return list;
}

export function deleteBackdrop(url: string): string[] {
  const list = savedBackdrops().filter((item) => item !== url);
  try {
    localStorage.setItem(SAVED_KEY, JSON.stringify(list));
  } catch {
    /* ignore */
  }
  return list;
}

// ─── Engine ──────────────────────────────────────────────────────────────────

/**
 * Draws `src` into `ctx` at (pad, pad, dw, dh) and REPLICATES its edge pixels
 * outward into the pad band — a blur that samples past the frame edge then
 * sees the border colour instead of transparent black (no dark vignette) and
 * nothing has to be zoomed to hide the seam, so the blurred background stays
 * pixel-aligned with the sharp person on top.
 */
function drawEdgePadded(
  ctx: CanvasRenderingContext2D,
  src: CanvasImageSource,
  sw: number,
  sh: number,
  dw: number,
  dh: number,
  pad: number
): void {
  ctx.drawImage(src, 0, 0, sw, sh, pad, pad, dw, dh);
  if (pad <= 0) return;
  ctx.drawImage(src, 0, 0, 1, sh, 0, pad, pad, dh);
  ctx.drawImage(src, sw - 1, 0, 1, sh, pad + dw, pad, pad, dh);
  ctx.drawImage(src, 0, 0, sw, 1, pad, 0, dw, pad);
  ctx.drawImage(src, 0, sh - 1, sw, 1, pad, pad + dh, dw, pad);
  ctx.drawImage(src, 0, 0, 1, 1, 0, 0, pad, pad);
  ctx.drawImage(src, sw - 1, 0, 1, 1, pad + dw, 0, pad, pad);
  ctx.drawImage(src, 0, sh - 1, 1, 1, 0, pad + dh, pad, pad);
  ctx.drawImage(src, sw - 1, sh - 1, 1, 1, pad + dw, pad + dh, pad, pad);
}

/** Smoothstep lookup table between `lo` and `hi` (raw confidence → alpha). */
function smoothstepLut(lo: number, hi: number): Uint8Array {
  const lut = new Uint8Array(256);
  for (let i = 0; i < 256; i++) {
    const v = i / 255;
    const t = Math.min(1, Math.max(0, (v - lo) / (hi - lo)));
    lut[i] = Math.round(t * t * (3 - 2 * t) * 255);
  }
  return lut;
}

class WhisperVideoFxEngine {
  mode: VideoFxMode = "none";
  imageUrl: string | null = null;

  private segmenter: ImageSegmenter | null = null;
  private segmenterLoading: Promise<void> | null = null;
  private segmenterFailed = false;
  private segmenterLandscape = false;

  private video: HTMLVideoElement | null = null;
  private canvas: HTMLCanvasElement | null = null;
  private ctx: CanvasRenderingContext2D | null = null;
  /** The sharp person cut-out at output resolution. */
  private personCanvas: HTMLCanvasElement | null = null;
  private personCtx: CanvasRenderingContext2D | null = null;
  /** Person mask at model resolution (alpha = composited opacity). */
  private maskCanvas: HTMLCanvasElement | null = null;
  private maskCtx: CanvasRenderingContext2D | null = null;
  private maskImage: ImageData | null = null;
  /** A WIDER, harder mask used to punch the person out of the background
   *  before it's blurred (see paintBlurredBackground). */
  private holeMaskCanvas: HTMLCanvasElement | null = null;
  private holeMaskCtx: CanvasRenderingContext2D | null = null;
  private holeImage: ImageData | null = null;
  /** Half-resolution background stage — every blur runs here (4× cheaper
   *  and invisible at these radii), then it's upscaled under the person. */
  private bgCanvas: HTMLCanvasElement | null = null;
  private bgCtx: CanvasRenderingContext2D | null = null;
  private padCanvas: HTMLCanvasElement | null = null;
  private padCtx: CanvasRenderingContext2D | null = null;
  private holeCanvas: HTMLCanvasElement | null = null;
  private holeCtx: CanvasRenderingContext2D | null = null;
  private fillCanvas: HTMLCanvasElement | null = null;
  private fillCtx: CanvasRenderingContext2D | null = null;
  /** Previous frame's smoothed mask — the temporal filter's memory. */
  private maskPrev: Float32Array | null = null;
  /** Person composite curve: fringe below drops out, the core is opaque. */
  private static readonly MASK_CURVE: Uint8Array = smoothstepLut(0.34, 0.7);
  /** Hole curve: generous — anything that MIGHT be person leaves the
   *  background layer, so no skin/hair colour survives into the blur. */
  private static readonly HOLE_CURVE: Uint8Array = smoothstepLut(0.08, 0.3);

  private rafHandle: number | null = null;
  private timer: number | null = null;
  private running = false;
  private visibilityBound = false;
  /** Frame-change detection so each camera frame is composited exactly once. */
  private lastFrameCount = -1;
  private lastFrameTime = -1;

  private backdrop: HTMLImageElement | null = null;
  private backdropLoadedUrl: string | null = null;

  /** Temporary backdrop override (shared room scenes) — outranks the
   *  user's own effect WITHOUT touching their persisted choice. */
  private overrideUrl: string | null = null;
  private overrideImg: HTMLImageElement | null = null;

  private source: MediaStreamTrack | null = null;
  private output: MediaStreamTrack | null = null;

  constructor() {
    try {
      const mode = localStorage.getItem(MODE_KEY) as VideoFxMode | null;
      const image = localStorage.getItem(IMAGE_KEY);
      if (mode === "blur") {
        this.mode = "blur";
      } else if (mode === "backdrop" && image) {
        this.mode = "backdrop";
        this.imageUrl = image;
        this.loadBackdrop(image);
      }
    } catch {
      /* storage unavailable */
    }
  }

  /** True when frames should be processed (an effect is selected). */
  get active(): boolean {
    if (this.overrideUrl) return true;
    return this.mode !== "none" && !(this.mode === "backdrop" && !this.imageUrl);
  }

  /** The raw camera track currently feeding the pipeline. */
  get sourceTrack(): MediaStreamTrack | null {
    return this.source;
  }

  /** The processed track peers receive (null when the pipeline is idle). */
  get outputTrack(): MediaStreamTrack | null {
    return this.output;
  }

  /** Selects an effect. Persisted so meetings, calls and lives all reuse it. */
  setMode(mode: VideoFxMode, imageUrl?: string | null): void {
    this.mode = mode;
    if (mode === "backdrop") {
      if (imageUrl) {
        this.imageUrl = imageUrl;
        this.loadBackdrop(imageUrl);
      } else if (!this.imageUrl) {
        this.mode = "none";
      }
    }
    try {
      localStorage.setItem(MODE_KEY, this.mode);
      if (this.mode === "backdrop" && this.imageUrl) {
        localStorage.setItem(IMAGE_KEY, this.imageUrl);
      }
    } catch {
      /* storage full — the session still works */
    }
    if (this.mode !== "none") void this.ensureSegmenter();
  }

  /** Applies (or clears with null) a temporary backdrop that wins over the
   *  user's own effect while set. Never persisted — clearing it returns
   *  their saved choice untouched. Data URLs keep the canvas untainted. */
  setOverride(url: string | null): void {
    this.overrideUrl = url;
    if (!url) {
      this.overrideImg = null;
      return;
    }
    const img = new Image();
    img.src = url;
    this.overrideImg = img;
    void this.ensureSegmenter();
  }

  /**
   * Routes a camera track through the effects pipeline and returns the
   * processed track. Idempotent: passing the pipeline's own output back
   * returns it unchanged; passing a new camera track rebinds the source
   * while the output track (already on the wire) keeps flowing.
   */
  wrap(track: MediaStreamTrack): MediaStreamTrack {
    if (!track || track.kind !== "video") return track;
    if (this.output && track === this.output) return this.output;
    this.source = track;
    void this.ensureSegmenter();

    const settings = track.getSettings();
    const srcW = settings.width ?? 1280;
    const srcH = settings.height ?? 720;
    const scale = Math.min(1, 960 / Math.max(srcW, srcH));
    const w = Math.max(2, Math.round(srcW * scale));
    const h = Math.max(2, Math.round(srcH * scale));

    if (!this.canvas) {
      this.canvas = document.createElement("canvas");
      this.ctx = this.canvas.getContext("2d");
      this.personCanvas = document.createElement("canvas");
      this.personCtx = this.personCanvas.getContext("2d");
      this.maskCanvas = document.createElement("canvas");
      this.maskCtx = this.maskCanvas.getContext("2d");
      this.holeMaskCanvas = document.createElement("canvas");
      this.holeMaskCtx = this.holeMaskCanvas.getContext("2d");
      this.bgCanvas = document.createElement("canvas");
      this.bgCtx = this.bgCanvas.getContext("2d");
      this.padCanvas = document.createElement("canvas");
      this.padCtx = this.padCanvas.getContext("2d");
      this.holeCanvas = document.createElement("canvas");
      this.holeCtx = this.holeCanvas.getContext("2d");
      this.fillCanvas = document.createElement("canvas");
      this.fillCtx = this.fillCanvas.getContext("2d");
    }
    this.canvas.width = w;
    this.canvas.height = h;
    if (this.personCanvas) {
      this.personCanvas.width = w;
      this.personCanvas.height = h;
    }
    // Background stage at half resolution (+ the edge-replication band).
    const bw = Math.max(2, Math.round(w / 2));
    const bh = Math.max(2, Math.round(h / 2));
    const pad = Math.ceil((BLUR_SIGMA / 2) * 3);
    for (const c of [this.bgCanvas, this.fillCanvas]) {
      if (c) {
        c.width = bw;
        c.height = bh;
      }
    }
    for (const c of [this.padCanvas, this.holeCanvas]) {
      if (c) {
        c.width = bw + pad * 2;
        c.height = bh + pad * 2;
      }
    }

    if (!this.video) {
      this.video = document.createElement("video");
      this.video.muted = true;
      this.video.playsInline = true;
      this.video.autoplay = true;
    }
    this.video.srcObject = new MediaStream([track]);
    void this.video.play().catch(() => undefined);
    // A new source means a new silhouette — don't blend against the old one.
    this.maskPrev = null;
    this.lastFrameCount = -1;
    this.lastFrameTime = -1;

    if (!this.output || this.output.readyState !== "live") {
      const stream = this.canvas.captureStream(30);
      this.output = stream.getVideoTracks()[0] ?? null;
    }
    this.startLoop();
    return this.output ?? track;
  }

  /**
   * Stops the pipeline and the output track. The source camera track is
   * left running unless `stopSource` — callers that still publish the raw
   * track (effect turned off mid-call) keep it alive.
   */
  release(opts: { stopSource?: boolean } = {}): void {
    this.running = false;
    if (this.timer != null) {
      clearTimeout(this.timer);
      this.timer = null;
    }
    if (this.rafHandle != null) {
      cancelAnimationFrame(this.rafHandle);
      this.rafHandle = null;
    }
    if (this.video) this.video.srcObject = null;
    if (this.output) this.output.stop();
    this.output = null;
    this.maskPrev = null;
    if (opts.stopSource && this.source) this.source.stop();
    this.source = null;
  }

  private loadBackdrop(url: string): void {
    if (this.backdropLoadedUrl === url && this.backdrop) return;
    const img = new Image();
    img.crossOrigin = "anonymous";
    img.onload = () => {
      this.backdrop = img;
      this.backdropLoadedUrl = url;
    };
    img.onerror = () => {
      if (this.backdropLoadedUrl !== url) this.backdrop = null;
    };
    img.src = url;
  }

  private ensureSegmenter(): Promise<void> {
    if (this.segmenter || this.segmenterFailed) return Promise.resolve();
    if (this.segmenterLoading) return this.segmenterLoading;
    // Pick the model that matches the frame shape — webcams are landscape.
    const settings = this.source?.getSettings();
    const landscape = (settings?.width ?? 16) >= (settings?.height ?? 9) * 1.2;
    this.segmenterLoading = (async () => {
      const vision = await FilesetResolver.forVisionTasks(WASM_BASE).catch((err: unknown) => {
        console.warn("[VideoFx] Vision runtime failed to load — effects disabled:", err);
        return null;
      });
      if (!vision) {
        this.segmenterFailed = true;
        this.segmenterLoading = null;
        return;
      }
      const build = (url: string, gpu: boolean): Promise<ImageSegmenter> =>
        ImageSegmenter.createFromOptions(vision, {
          baseOptions: { modelAssetPath: url, delegate: gpu ? "GPU" : "CPU" },
          runningMode: "VIDEO",
          outputConfidenceMasks: true,
          outputCategoryMask: false,
        });
      // Landscape GPU → square GPU → square CPU: quality first, then survival.
      const attempts: Array<[string, boolean, boolean]> = landscape
        ? [[MODEL_URL_LANDSCAPE, true, true], [MODEL_URL, true, false], [MODEL_URL, false, false]]
        : [[MODEL_URL, true, false], [MODEL_URL, false, false]];
      for (const [url, gpu, isLandscape] of attempts) {
        try {
          this.segmenter = await build(url, gpu);
          this.segmenterLandscape = isLandscape;
          break;
        } catch (err) {
          console.warn(`[VideoFx] Segmenter (${isLandscape ? "landscape" : "square"}, ${gpu ? "GPU" : "CPU"}) failed:`, err);
        }
      }
      if (!this.segmenter) this.segmenterFailed = true;
      this.segmenterLoading = null;
    })();
    return this.segmenterLoading;
  }

  /**
   * Frame loop. A visible page rides requestAnimationFrame and composites
   * only when the camera has actually produced a NEW frame (frame counter /
   * currentTime change) — every frame exactly once, no beat frequency, and
   * no dependency on video-frame callbacks firing for a detached element.
   * Hidden pages fall back to a 30 Hz timer because rAF pauses there.
   */
  private startLoop(): void {
    if (this.running) return;
    this.running = true;
    if (!this.visibilityBound) {
      this.visibilityBound = true;
      document.addEventListener("visibilitychange", () => {
        if (!this.running) return;
        if (this.rafHandle != null) {
          cancelAnimationFrame(this.rafHandle);
          this.rafHandle = null;
        }
        if (this.timer != null) {
          clearTimeout(this.timer);
          this.timer = null;
        }
        this.schedule();
      });
    }
    this.schedule();
  }

  private schedule(): void {
    if (!this.running) return;
    if (!document.hidden) {
      this.rafHandle = requestAnimationFrame(() => {
        this.rafHandle = null;
        this.tick();
        this.schedule();
      });
    } else {
      this.timer = window.setTimeout(() => {
        this.timer = null;
        this.tick();
        this.schedule();
      }, 1000 / 30);
    }
  }

  private tick(): void {
    const video = this.video;
    if (!video) return;
    let changed = true;
    const quality = typeof video.getVideoPlaybackQuality === "function"
      ? video.getVideoPlaybackQuality()
      : null;
    if (quality && quality.totalVideoFrames > 0) {
      changed = quality.totalVideoFrames !== this.lastFrameCount;
      this.lastFrameCount = quality.totalVideoFrames;
    } else {
      changed = video.currentTime !== this.lastFrameTime;
      this.lastFrameTime = video.currentTime;
    }
    if (changed) this.renderFrame();
  }

  private renderFrame(): void {
    const video = this.video;
    const canvas = this.canvas;
    const ctx = this.ctx;
    if (!video || !canvas || !ctx || video.readyState < 2) return;
    const w = canvas.width;
    const h = canvas.height;
    const override = this.overrideImg;
    const overrideReady = override != null && override.complete && override.naturalWidth > 0;
    const mode: VideoFxMode = overrideReady ? "backdrop" : this.mode;
    const activeBackdrop = overrideReady ? override : this.backdrop;
    const backdropReady =
      activeBackdrop != null && activeBackdrop.complete && activeBackdrop.naturalWidth > 0;

    // Passthrough: no effect, model unavailable, or backdrop still loading.
    if (
      mode === "none" ||
      !this.segmenter ||
      (mode === "backdrop" && !backdropReady)
    ) {
      ctx.drawImage(video, 0, 0, w, h);
      return;
    }

    const personReady = this.updatePersonLayer(video, w, h);
    if (!personReady || !this.personCanvas) {
      ctx.drawImage(video, 0, 0, w, h);
      return;
    }

    if (mode === "blur") {
      this.paintBlurredBackground(video, w, h);
    } else if (activeBackdrop) {
      const img = activeBackdrop;
      const cover = Math.max(w / img.naturalWidth, h / img.naturalHeight);
      const dw = img.naturalWidth * cover;
      const dh = img.naturalHeight * cover;
      ctx.drawImage(img, (w - dw) / 2, (h - dh) / 2, dw, dh);
    }
    ctx.drawImage(this.personCanvas, 0, 0, w, h);
  }

  /**
   * Segments the CURRENT frame (synchronously — the mask always belongs to
   * the frame it's composited with) and rebuilds the sharp person layer.
   * Temporal smoothing is MOTION-ADAPTIVE: a pixel whose confidence jumped
   * is real movement and takes the new value almost outright, a pixel that
   * barely changed is model flicker and is averaged away. The old fixed
   * average lagged a moving head by several frames — the sharp cut-out
   * trailed the person while the blurred copy underneath showed through
   * ahead of it: two heads.
   */
  private updatePersonLayer(video: HTMLVideoElement, w: number, h: number): boolean {
    if (!this.segmenter || !this.maskCanvas || !this.maskCtx || !this.personCanvas || !this.personCtx) {
      return false;
    }
    let ready = false;
    try {
      const result = this.segmenter.segmentForVideo(video, performance.now());
      const masks = result.confidenceMasks;
      const mask = masks && masks.length > 0 ? masks[masks.length - 1] : null;
      if (mask) {
        const mw = mask.width;
        const mh = mask.height;
        const values = mask.getAsFloat32Array();
        if (this.maskCanvas.width !== mw || this.maskCanvas.height !== mh || !this.maskImage) {
          this.maskCanvas.width = mw;
          this.maskCanvas.height = mh;
          this.maskImage = this.maskCtx.createImageData(mw, mh);
          if (this.holeMaskCanvas && this.holeMaskCtx) {
            this.holeMaskCanvas.width = mw;
            this.holeMaskCanvas.height = mh;
            this.holeImage = this.holeMaskCtx.createImageData(mw, mh);
          }
          this.maskPrev = null;
        }
        let prev = this.maskPrev;
        if (!prev || prev.length !== values.length) {
          prev = new Float32Array(values);
          this.maskPrev = prev;
        }
        const px = this.maskImage.data;
        const hpx = this.holeImage?.data ?? null;
        const curve = WhisperVideoFxEngine.MASK_CURVE;
        const holeCurve = WhisperVideoFxEngine.HOLE_CURVE;
        for (let i = 0; i < values.length; i++) {
          const nv = values[i];
          const pv = prev[i];
          const delta = nv > pv ? nv - pv : pv - nv;
          // Big jump → movement → trust the new frame; tiny jitter → smooth.
          const a = delta > 0.28 ? 0.92 : MASK_EMA;
          const v = pv + (nv - pv) * a;
          prev[i] = v;
          const q = (v * 255) | 0;
          px[i * 4 + 3] = curve[q];
          if (hpx) hpx[i * 4 + 3] = holeCurve[q];
        }
        this.maskCtx.putImageData(this.maskImage, 0, 0);
        if (hpx && this.holeMaskCtx && this.holeImage) {
          this.holeMaskCtx.putImageData(this.holeImage, 0, 0);
        }
        const pctx = this.personCtx;
        pctx.globalCompositeOperation = "source-over";
        pctx.filter = "none";
        pctx.clearRect(0, 0, w, h);
        pctx.drawImage(video, 0, 0, w, h);
        pctx.globalCompositeOperation = "destination-in";
        // Feather the upscaled mask so the cut-out edge is a soft ramp at
        // output resolution instead of the model's 256-wide blocks.
        pctx.imageSmoothingEnabled = true;
        pctx.imageSmoothingQuality = "high";
        pctx.filter = `blur(${MASK_FEATHER_PX}px)`;
        pctx.drawImage(this.maskCanvas, 0, 0, w, h);
        pctx.filter = "none";
        pctx.globalCompositeOperation = "source-over";
        ready = true;
      }
      result.close();
    } catch {
      /* fall through to passthrough */
    }
    return ready;
  }

  /**
   * Background blur WITHOUT the person bleeding into it. A plain blur of
   * the whole frame smears the person's colours ~radius px outward — that
   * smear peeking around the sharp cut-out was the ghostly "second head".
   * Meet's trick, done in three cheap half-resolution passes:
   *   1. base: the whole frame blurred (fills everything, including the
   *      spot under the person, which the sharp layer covers anyway);
   *   2. hole: the frame with the person PUNCHED OUT (a generous mask),
   *      then blurred — transparent pixels contribute nothing, so the rim
   *      of the hole fills with BACKGROUND colours only;
   *   3. the hole layer is stacked over the base a few times so its partial
   *      alpha near the rim wins over the base's person-tinted pixels.
   */
  private paintBlurredBackground(video: HTMLVideoElement, w: number, h: number): void {
    const ctx = this.ctx;
    const bg = this.bgCanvas;
    const bctx = this.bgCtx;
    const padC = this.padCanvas;
    const pctx = this.padCtx;
    const hole = this.holeCanvas;
    const hctx = this.holeCtx;
    const fill = this.fillCanvas;
    const fctx = this.fillCtx;
    const holeMask = this.holeMaskCanvas;
    if (!ctx || !bg || !bctx || !padC || !pctx || !hole || !hctx || !fill || !fctx || !holeMask) {
      ctx?.filter && (ctx.filter = "none");
      if (ctx) {
        ctx.filter = `blur(${BLUR_SIGMA}px)`;
        ctx.drawImage(video, 0, 0, w, h);
        ctx.filter = "none";
      }
      return;
    }
    const bw = bg.width;
    const bh = bg.height;
    const sigma = BLUR_SIGMA / 2;
    const pad = Math.ceil(sigma * 3);
    const vw = video.videoWidth || bw;
    const vh = video.videoHeight || bh;

    // The edge-replicated frame every blur pass reads from.
    pctx.globalCompositeOperation = "source-over";
    pctx.filter = "none";
    drawEdgePadded(pctx, video, vw, vh, bw, bh, pad);

    // 1) Base — the whole frame blurred.
    bctx.filter = `blur(${sigma}px)`;
    bctx.drawImage(padC, -pad, -pad);
    bctx.filter = "none";

    // 2) Hole — the frame with the person (and a margin around them)
    //    removed, edges replicated so a person touching the frame edge
    //    can't leak back in through the pad band.
    hctx.globalCompositeOperation = "source-over";
    hctx.filter = "none";
    hctx.clearRect(0, 0, hole.width, hole.height);
    hctx.drawImage(padC, 0, 0);
    hctx.globalCompositeOperation = "destination-out";
    hctx.imageSmoothingEnabled = true;
    hctx.filter = "blur(1.5px)";
    drawEdgePadded(hctx, holeMask, holeMask.width, holeMask.height, bw, bh, pad);
    hctx.filter = "none";
    hctx.globalCompositeOperation = "source-over";

    fctx.clearRect(0, 0, bw, bh);
    fctx.filter = `blur(${sigma}px)`;
    fctx.drawImage(hole, -pad, -pad);
    fctx.filter = "none";

    // 3) Stack the background-only fill over the base — each pass raises
    //    the rim's alpha (a → 1-(1-a)^n) so background colours win there.
    bctx.drawImage(fill, 0, 0);
    bctx.drawImage(fill, 0, 0);
    bctx.drawImage(fill, 0, 0);

    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = "high";
    ctx.drawImage(bg, 0, 0, bw, bh, 0, 0, w, h);
  }
}

/** Shared engine — one camera, one pipeline, every call surface. */
export const videoFx = new WhisperVideoFxEngine();
