/**
 * The pop-out mosaic. Classic video Picture-in-Picture can only show ONE
 * <video> element, so a meeting popped out that way showed a single person.
 * This paints EVERY participant into one canvas — a Meet-style grid, or the
 * shared screen large with the people stacked beside it — and exposes the
 * canvas as a MediaStream the PiP element can play. Chrome's Document PiP
 * (when allowed) still renders real tiles; this is the path for everything
 * else: embedded previews, Safari, and the automatic tab-switch dock.
 */

import { localShareStage, type MeetingStageSnapshot } from "./meetingStageCapture";

export interface PipMosaicSource {
  id: string;
  name: string;
  stream: MediaStream | null;
  hasVideo: boolean;
  isSelf: boolean;
  isScreenShare: boolean;
  isSpeaking: boolean;
  micOn: boolean;
}

interface Cell {
  x: number;
  y: number;
  w: number;
  h: number;
}

const FPS = 12;
const MAX_TILES = 9;

export class MeetPipMosaic {
  readonly canvas: HTMLCanvasElement;
  stageSnapshot: (() => MeetingStageSnapshot | null) | undefined;
  private sourcePool: PipMosaicSource[] = [];
  private readonly avatars = new Map<string, HTMLImageElement>();
  private readonly ctx: CanvasRenderingContext2D | null;
  private readonly host: HTMLDivElement;
  private readonly videos = new Map<string, HTMLVideoElement>();
  private sources: PipMosaicSource[] = [];
  private timer: number | null = null;
  private stream: MediaStream | null = null;

  constructor(width = 640, height = 360, private readonly recordingLayout = false) {
    this.canvas = document.createElement("canvas");
    this.canvas.width = width;
    this.canvas.height = height;
    this.ctx = this.canvas.getContext("2d");
    // Source <video> elements live in a zero-size host so the browser keeps
    // decoding frames for us without anything showing on the page.
    this.host = document.createElement("div");
    this.host.setAttribute("aria-hidden", "true");
    this.host.style.cssText =
      "position:fixed;left:0;bottom:0;width:0;height:0;overflow:hidden;opacity:0;pointer-events:none;";
    document.body.appendChild(this.host);
  }

  /** The stream to hand to the PiP <video>. Stable for the mosaic's life. */
  get mediaStream(): MediaStream {
    if (!this.stream) {
      this.stream = this.canvas.captureStream(FPS);
    }
    return this.stream;
  }

  get running(): boolean {
    return this.timer !== null;
  }

  /** Sync the roster — attaches new streams, drops people who left. */
  update(sources: PipMosaicSource[]): void {
    // Screen share first (it takes the big cell), then remote people, then
    // you — the pop-out exists to keep OTHERS visible while you're away.
    const ordered = [...sources].sort((a, b) => {
      const rank = (s: PipMosaicSource): number => (s.isScreenShare && (this.recordingLayout || !s.isSelf) ? 0 : s.isSelf ? 2 : 1);
      return rank(a) - rank(b);
    });
    this.sourcePool = ordered;
    this.syncSources(ordered.slice(0, this.recordingLayout ? 25 : MAX_TILES));
    if (this.running) this.draw();
  }

  private syncSources(sources: PipMosaicSource[]): void {
    this.sources = sources;
    const seen = new Set<string>();
    for (const source of this.sources) {
      seen.add(source.id);
      let video = this.videos.get(source.id);
      if (!video) {
        video = document.createElement("video");
        video.muted = true;
        video.playsInline = true;
        video.autoplay = true;
        this.host.appendChild(video);
        this.videos.set(source.id, video);
      }
      const want = source.hasVideo ? source.stream : null;
      if (video.srcObject !== want) {
        video.srcObject = want;
        if (want) void video.play().catch(() => undefined);
      }
    }
    for (const [id, video] of Array.from(this.videos.entries())) {
      if (seen.has(id)) continue;
      video.srcObject = null;
      video.remove();
      this.videos.delete(id);
    }
  }

  start(): void {
    if (this.timer !== null) return;
    this.draw();
    this.timer = window.setInterval(() => this.draw(), Math.round(1000 / FPS));
  }

  stop(): void {
    if (this.timer !== null) {
      window.clearInterval(this.timer);
      this.timer = null;
    }
  }

  /** Stop drawing and release every source element + the canvas stream. */
  dispose(): void {
    this.stop();
    for (const video of this.videos.values()) {
      video.srcObject = null;
      video.remove();
    }
    this.videos.clear();
    this.avatars.clear();
    this.sourcePool = []; this.sources = []; this.stageSnapshot = undefined;
    this.stream?.getTracks().forEach((t) => t.stop());
    this.stream = null;
    this.host.remove();
  }

  // ── Painting ──────────────────────────────────────────────────────────────

  private layout(count: number, share: boolean): Cell[] {
    const W = this.canvas.width;
    const H = this.canvas.height;
    const gap = 6;
    if (count <= 0) return [];
    if (share && count > 1) {
      // Shared screen large on the left, everyone else stacked on the right.
      const sideW = Math.round(W * 0.27);
      const mainW = W - sideW - gap * 3;
      const others = count - 1;
      const cellH = Math.floor((H - gap * (others + 1)) / others);
      const cells: Cell[] = [{ x: gap, y: gap, w: mainW, h: H - gap * 2 }];
      for (let i = 0; i < others; i += 1) {
        cells.push({ x: gap * 2 + mainW, y: gap + i * (cellH + gap), w: sideW, h: cellH });
      }
      return cells;
    }
    const cols = Math.ceil(Math.sqrt(count));
    const rows = Math.ceil(count / cols);
    const cellW = Math.floor((W - gap * (cols + 1)) / cols);
    const cellH = Math.floor((H - gap * (rows + 1)) / rows);
    const cells: Cell[] = [];
    for (let i = 0; i < count; i += 1) {
      const r = Math.floor(i / cols);
      const c = i % cols;
      // Center a short last row, like the stage grid does.
      const inRow = r === rows - 1 ? count - r * cols : cols;
      const rowOffset = Math.floor(((cols - inRow) * (cellW + gap)) / 2);
      cells.push({ x: gap + c * (cellW + gap) + rowOffset, y: gap + r * (cellH + gap), w: cellW, h: cellH });
    }
    return cells;
  }

  private roundRect(x: number, y: number, w: number, h: number, r: number): void {
    const ctx = this.ctx;
    if (!ctx) return;
    const radius = Math.min(r, w / 2, h / 2);
    ctx.beginPath();
    ctx.moveTo(x + radius, y);
    ctx.arcTo(x + w, y, x + w, y + h, radius);
    ctx.arcTo(x + w, y + h, x, y + h, radius);
    ctx.arcTo(x, y + h, x, y, radius);
    ctx.arcTo(x, y, x + w, y, radius);
    ctx.closePath();
  }

  private drawStage(stage: MeetingStageSnapshot): void {
    const ctx = this.ctx;
    if (!ctx || stage.width <= 0 || stage.height <= 0) return;
    const visibleIds = new Set(stage.cells.slice(0, 25).map((cell) => cell.id));
    this.syncSources(this.sourcePool.filter((source) => visibleIds.has(source.id)));
    const sources = new Map(this.sources.map((source) => [source.id, source]));
    const scale = Math.min(this.canvas.width / stage.width, this.canvas.height / stage.height);
    const usedAvatars = new Set<string>();
    ctx.save();
    ctx.translate((this.canvas.width - stage.width * scale) / 2, (this.canvas.height - stage.height * scale) / 2);
    ctx.scale(scale, scale);
    ctx.fillStyle = stage.background; ctx.fillRect(0, 0, stage.width, stage.height);
    for (const cell of stage.cells.slice(0, 25)) {
      const source = sources.get(cell.id); if (!source) continue;
      ctx.save(); ctx.beginPath(); ctx.rect(cell.clip.x, cell.clip.y, cell.clip.w, cell.clip.h); ctx.clip();
      this.roundRect(cell.x, cell.y, cell.w, cell.h, cell.radius); ctx.clip();
      ctx.fillStyle = "#141414"; ctx.fillRect(cell.x, cell.y, cell.w, cell.h);
      const video = this.videos.get(source.id);
      if (source.hasVideo && video && video.readyState >= 2 && video.videoWidth > 0 && video.videoHeight > 0) {
        const fit = source.isScreenShare || cell.fit === "contain" ? Math.min : Math.max;
        const ratio = fit(cell.w / video.videoWidth, cell.h / video.videoHeight);
        const w = video.videoWidth * ratio, h = video.videoHeight * ratio;
        ctx.save(); ctx.translate(cell.x + cell.w / 2, cell.y + cell.h / 2);
        if (source.isSelf && !source.isScreenShare) ctx.scale(-1, 1);
        ctx.drawImage(video, -w / 2, -h / 2, w, h); ctx.restore();
      } else {
        let avatar: HTMLImageElement | undefined;
        if (cell.avatarURL && /^(https?:|blob:|data:image\/)/.test(cell.avatarURL)) {
          usedAvatars.add(cell.avatarURL); avatar = this.avatars.get(cell.avatarURL);
          if (!avatar) { avatar = new Image(); avatar.crossOrigin = "anonymous"; avatar.referrerPolicy = "no-referrer"; avatar.src = cell.avatarURL; this.avatars.set(cell.avatarURL, avatar); }
        }
        const ready = avatar?.complete && avatar.naturalWidth > 0;
        if (ready && avatar) {
          ctx.save(); ctx.filter = "blur(36px) saturate(0.9)"; ctx.globalAlpha = 0.9;
          const ratio = Math.max(cell.w * 1.24 / avatar.naturalWidth, cell.h * 1.24 / avatar.naturalHeight);
          const w = avatar.naturalWidth * ratio, h = avatar.naturalHeight * ratio;
          ctx.drawImage(avatar, cell.x + (cell.w - w) / 2, cell.y + (cell.h - h) / 2, w, h); ctx.restore();
          ctx.fillStyle = "rgba(0,0,0,0.42)"; ctx.fillRect(cell.x, cell.y, cell.w, cell.h);
        } else {
          const gradient = ctx.createLinearGradient(cell.x, cell.y, cell.x + cell.w, cell.y + cell.h);
          gradient.addColorStop(0, "#27272a"); gradient.addColorStop(1, "#09090b"); ctx.fillStyle = gradient; ctx.fillRect(cell.x, cell.y, cell.w, cell.h);
        }
        const size = Math.min(cell.avatarSize, cell.w * 0.65, cell.h * 0.65), x = cell.x + (cell.w - size) / 2, y = cell.y + (cell.h - size) / 2;
        ctx.save(); ctx.beginPath(); ctx.arc(x + size / 2, y + size / 2, size / 2, 0, Math.PI * 2); ctx.clip();
        ctx.fillStyle = "#3f3f46"; ctx.fillRect(x, y, size, size);
        if (ready && avatar) { const ratio = Math.max(size / avatar.naturalWidth, size / avatar.naturalHeight), w = avatar.naturalWidth * ratio, h = avatar.naturalHeight * ratio; ctx.drawImage(avatar, x + (size - w) / 2, y + (size - h) / 2, w, h); }
        else { ctx.fillStyle = "white"; ctx.font = `600 ${size * 0.42}px system-ui`; ctx.textAlign = "center"; ctx.textBaseline = "middle"; ctx.fillText(source.name.slice(0, 1).toUpperCase(), x + size / 2, y + size / 2); }
        ctx.restore();
      }
      if (cell.focused) { this.roundRect(cell.x + 1, cell.y + 1, cell.w - 2, cell.h - 2, cell.radius); ctx.strokeStyle = "rgba(255,255,255,0.85)"; ctx.lineWidth = 2.5; ctx.stroke(); }
      if (source.isSpeaking) { ctx.fillStyle = "#22d3ee"; ctx.beginPath(); ctx.arc(cell.x + 20, cell.y + 20, 12, 0, Math.PI * 2); ctx.fill(); ctx.strokeStyle = "#000"; ctx.lineWidth = 2; ctx.beginPath(); for (let i = 0; i < 3; i++) { const h = i === 1 ? 7 : 4; ctx.moveTo(cell.x + 16 + i * 4, cell.y + 20 - h); ctx.lineTo(cell.x + 16 + i * 4, cell.y + 20 + h); } ctx.stroke(); }
      const label = `${source.name}${source.isSelf ? " (You)" : ""}${source.micOn ? "" : " · muted"}`;
      ctx.font = "600 11px system-ui"; ctx.textAlign = "left"; ctx.textBaseline = "middle";
      const width = Math.max(1, Math.min(cell.w - 16, ctx.measureText(label).width + 20));
      this.roundRect(cell.x + 8, cell.y + cell.h - 30, width, 22, 11); ctx.fillStyle = "rgba(0,0,0,0.65)"; ctx.fill(); ctx.clip(); ctx.fillStyle = "white"; ctx.fillText(label, cell.x + 18, cell.y + cell.h - 19);
      ctx.restore();
    }
    for (const url of this.avatars.keys()) if (!usedAvatars.has(url)) this.avatars.delete(url);
    ctx.restore();
  }

  private draw(): void {
    const ctx = this.ctx;
    if (!ctx) return;
    const W = this.canvas.width;
    const H = this.canvas.height;
    ctx.fillStyle = "#070707";
    ctx.fillRect(0, 0, W, H);
    if (this.recordingLayout && this.stageSnapshot) {
      const snapshot = this.stageSnapshot();
      const localShare = this.sourcePool.find((source) => source.isSelf && source.isScreenShare);
      if (snapshot) this.drawStage(localShare ? localShareStage(snapshot, localShare.id) : snapshot);
      return;
    }
    // Classic PiP and call surfaces without a stage provider keep their independent mosaic.
    this.syncSources(this.sourcePool.slice(0, this.recordingLayout ? 25 : MAX_TILES));
    const share = this.sources.some((s) => s.isScreenShare && (this.recordingLayout || !s.isSelf));
    const cells = this.layout(this.sources.length, share);
    this.sources.forEach((source, i) => {
      const cell = cells[i];
      if (!cell) return;
      const video = this.videos.get(source.id);
      const ready = !!video && source.hasVideo && video.readyState >= 2 && video.videoWidth > 0;

      ctx.save();
      this.roundRect(cell.x, cell.y, cell.w, cell.h, 10);
      ctx.clip();
      if (ready && video) {
        const vw = video.videoWidth;
        const vh = video.videoHeight;
        if (source.isScreenShare || this.recordingLayout) {
          // Letterbox the shared screen — never crop a slide.
          ctx.fillStyle = "#141416";
          ctx.fillRect(cell.x, cell.y, cell.w, cell.h);
          const scale = Math.min(cell.w / vw, cell.h / vh);
          const dw = vw * scale;
          const dh = vh * scale;
          ctx.drawImage(video, cell.x + (cell.w - dw) / 2, cell.y + (cell.h - dh) / 2, dw, dh);
        } else {
          // Cover-crop a camera, mirrored for you like the self tile.
          const scale = Math.max(cell.w / vw, cell.h / vh);
          const sw = cell.w / scale;
          const sh = cell.h / scale;
          const sx = (vw - sw) / 2;
          const sy = (vh - sh) / 2;
          if (source.isSelf) {
            ctx.translate(cell.x + cell.w, cell.y);
            ctx.scale(-1, 1);
            ctx.drawImage(video, sx, sy, sw, sh, 0, 0, cell.w, cell.h);
          } else {
            ctx.drawImage(video, sx, sy, sw, sh, cell.x, cell.y, cell.w, cell.h);
          }
        }
      } else {
        const grad = ctx.createLinearGradient(cell.x, cell.y, cell.x + cell.w, cell.y + cell.h);
        grad.addColorStop(0, "#26262b");
        grad.addColorStop(1, "#0f0f12");
        ctx.fillStyle = grad;
        ctx.fillRect(cell.x, cell.y, cell.w, cell.h);
        const r = Math.min(cell.w, cell.h) * 0.2;
        ctx.beginPath();
        ctx.arc(cell.x + cell.w / 2, cell.y + cell.h / 2, r, 0, Math.PI * 2);
        ctx.fillStyle = "#3a3a41";
        ctx.fill();
        ctx.fillStyle = "rgba(255,255,255,0.9)";
        ctx.font = `700 ${Math.max(12, Math.round(r * 1.05))}px ui-sans-serif, system-ui, sans-serif`;
        ctx.textAlign = "center";
        ctx.textBaseline = "middle";
        ctx.fillText((source.name || "?").slice(0, 1).toUpperCase(), cell.x + cell.w / 2, cell.y + cell.h / 2 + 1);
      }
      ctx.restore();

      // Speaking ring — the room's cyan.
      if (source.isSpeaking) {
        ctx.save();
        this.roundRect(cell.x + 1, cell.y + 1, cell.w - 2, cell.h - 2, 10);
        ctx.strokeStyle = "#22d3ee";
        ctx.lineWidth = 2;
        ctx.stroke();
        ctx.restore();
      }

      // Name pill.
      const label = `${source.isSelf ? "You" : source.name}${source.micOn ? "" : " · muted"}`;
      ctx.save();
      ctx.font = "700 11px ui-sans-serif, system-ui, sans-serif";
      ctx.textAlign = "left";
      ctx.textBaseline = "middle";
      const padX = 7;
      const textW = Math.min(ctx.measureText(label).width, cell.w - 16 - padX * 2);
      const pillW = textW + padX * 2;
      const pillH = 18;
      const px = cell.x + 6;
      const py = cell.y + cell.h - pillH - 6;
      this.roundRect(px, py, pillW, pillH, 9);
      ctx.fillStyle = "rgba(0,0,0,0.58)";
      ctx.fill();
      this.roundRect(px, py, pillW, pillH, 9);
      ctx.clip();
      ctx.fillStyle = "#ffffff";
      ctx.fillText(label, px + padX, py + pillH / 2 + 0.5);
      ctx.restore();
    });
  }
}
