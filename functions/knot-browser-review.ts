import { browserURL } from './knot-browser';

export type BrowserReviewScope = 'none' | 'page' | 'site';
type Page = { url: string; title: string; contentReads: number; sections: number; scrolls: number; bottom: boolean; imageHash?: string; unchanged: number };
type Finding = { url: string; findings: string; rating: number | null };

/** Ephemeral evidence, not a provider receipt or persisted browsing history.
 * Only successful tool responses advance coverage. Model-written prose never does. */
export class KnotBrowserReview {
  scope: BrowserReviewScope = 'none';
  ratingRequested = false;
  private pages = new Map<string, Page>();
  private links = new Set<string>();
  private enumerated = new Set<string>();
  private current?: string;
  private rootOrigin?: string;
  private pendingScroll?: string;
  private needsFrame = true;
  report?: string;
  complete = false;
  private findings = new Map<string, Finding>();
  private overallRating: number | null = null;
  private remaining = '';

  /** Server-owned checkpoint contains only coverage and submitted findings, never
   * raw page text/images or authority to replay an input. A resumed run must
   * observe its actual current page again before any new input. */
  checkpoint(): Record<string, unknown> {
    return { v: 1, scope: this.scope, ratingRequested: this.ratingRequested, pages: [...this.pages.values()], links: [...this.links], enumerated: [...this.enumerated], rootOrigin: this.rootOrigin, findings: [...this.findings.values()], overallRating: this.overallRating, remaining: this.remaining };
  }
  restore(value: Record<string, unknown>): void {
    if (value.v !== 1 || !['page', 'site'].includes(String(value.scope)) || !Array.isArray(value.pages) || value.pages.length > 100 || !Array.isArray(value.links) || value.links.length > 100 || !Array.isArray(value.enumerated) || !Array.isArray(value.findings) || value.findings.length > 100) throw new Error('invalid_browser_checkpoint');
    this.scope = value.scope as BrowserReviewScope; this.ratingRequested = value.ratingRequested === true;
    this.pages = new Map((value.pages as Page[]).map(page => [page.url, { ...page }]));
    this.links = new Set(value.links as string[]); this.enumerated = new Set(value.enumerated as string[]);
    this.findings = new Map((value.findings as Finding[]).map(finding => [finding.url, finding]));
    this.rootOrigin = typeof value.rootOrigin === 'string' ? value.rootOrigin : undefined;
    this.overallRating = typeof value.overallRating === 'number' ? value.overallRating : null;
    this.remaining = typeof value.remaining === 'string' ? value.remaining : '';
    this.current = undefined; this.pendingScroll = undefined; this.needsFrame = true;
  }
  get remainingURLs(): string[] {
    return [...new Set([...this.pages.keys(), ...this.links])].filter(url => !this.findings.has(url) || !this.pages.get(url)?.bottom);
  }
  progressReport(): string {
    const safe = (text: string) => text.replace(/```[\s\S]*?(?:```|$)/g, '').replace(/`/g, '’').trim();
    const sections = [...this.findings.values()].map(item => '### ' + safe(this.pages.get(item.url)?.title || 'Reviewed page').replace(/[\r\n]/g, ' ') + (item.rating !== null ? ' — ' + item.rating + '/10' : '') + '\n' + item.url + '\n' + safe(item.findings));
    const outstanding = this.remainingURLs;
    return (this.complete ? 'Review of the observed public pages' : 'Review in progress — coverage remains partial') + '\n\n' +
      (sections.length ? sections.join('\n\n') : 'Traversal is in progress; no page has a verified per-page finding yet.') +
      (this.overallRating !== null ? '\n\nOverall opinion of the inspected pages: ' + this.overallRating + '/10.' : '') +
      (this.complete ? '' : '\n\nRemaining work: ' + (outstanding.length ? outstanding.join(', ') + '. ' : '') +
        (this.scope === 'site' && !this.enumerated.size ? 'Discover and verify the remaining public navigation; the browser has not supplied a complete link list. ' : '') + (safe(this.remaining) || 'Finish unverified sections and per-page findings.'));
  }

  private url(value: unknown): string | undefined {
    try { const url = new URL(browserURL(value)); url.hash = ''; return url.href; } catch { return undefined; }
  }
  private page(url: string, title = ''): Page {
    let page = this.pages.get(url);
    if (!page) { page = { url, title, contentReads: 0, sections: 0, scrolls: 0, bottom: false, unchanged: 0 }; this.pages.set(url, page); }
    if (title.trim()) page.title = title.slice(0, 300);
    return page;
  }
  async observe(name: string, args: Record<string, unknown>, result: string, image?: string): Promise<void> {
    if (this.scope === 'none') return;
    const resultData = JSON.parse(result) as { ok?: boolean; evidence?: Record<string, unknown> };
    if (resultData.ok !== true) return;
    const evidence = resultData.evidence;
    if (name === 'browser_start' || name === 'browser_navigate' || name === 'browser_input') {
      const landed = this.url(evidence?.url);
      const scrolledObservedPage = name === 'browser_input' && args.kind === 'scroll' && landed && landed === this.current && !this.needsFrame && typeof args.dy === 'number' && args.dy > 0;
      this.pendingScroll = scrolledObservedPage ? landed : undefined;
      this.current = landed;
      if (landed) { this.rootOrigin ??= new URL(landed).origin; this.page(landed, typeof evidence?.title === 'string' ? evidence.title : ''); }
      this.needsFrame = true;
    }
    if (name === 'browser_content' && evidence && typeof evidence.text === 'string' && evidence.text.trim()) {
      const url = this.url(evidence.url); if (!url) return;
      if (url !== this.current) { this.pendingScroll = undefined; this.needsFrame = true; }
      this.current = url; this.rootOrigin ??= new URL(url).origin;
      this.page(url, typeof evidence.title === 'string' ? evidence.title : '').contentReads++;
      // Use actual returned link data when present; do not invent a DOM/link API.
      // Text URLs can guide exploration but cannot establish complete enumeration.
      const returned = Array.isArray(evidence.links) ? evidence.links : [];
      // An array alone is not proof that the provider returned every link.
      // Require an explicit completeness stamp, and never certify a capped list.
      let completeLinks = Array.isArray(evidence.links) && evidence.linksComplete === true && evidence.textTruncated !== true && returned.length <= 200;
      const candidates: unknown[] = returned.map(link => typeof link === 'string' ? link : link && typeof link === 'object' ? (link as Record<string, unknown>).href ?? (link as Record<string, unknown>).url : undefined);
      candidates.push(...(evidence.text.match(/https?:\/\/[^\s<>"')]+/g) ?? []));
      for (const candidate of candidates.slice(0, 200)) {
        if (typeof candidate !== 'string') continue;
        let absolute: string; try { absolute = new URL(candidate, url).href; } catch { continue; }
        const link = this.url(absolute);
        if (link && new URL(link).origin === this.rootOrigin && !/\.(?:pdf|zip|png|jpe?g|webp|mp4|mp3)(?:$|\?)/i.test(new URL(link).pathname)) {
          if (this.links.has(link) || this.links.size < 100) this.links.add(link);
          else completeLinks = false;
        }
      }
      if (completeLinks) this.enumerated.add(url); else this.enumerated.delete(url);
    }
    if (name === 'browser_screenshot' && image && this.current) {
      const page = this.page(this.current);
      const hash = [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(image)))].map(n => n.toString(16).padStart(2, '0')).join('');
      if (!page.imageHash) page.sections++;
      if (this.pendingScroll === this.current && page.imageHash) {
        page.scrolls++; page.sections++;
        page.unchanged = hash === page.imageHash ? page.unchanged + 1 : 0;
        // Two independently acknowledged downward scrolls with unchanged fresh
        // frames support an apparent end, not a claim about hidden/lazy content.
        page.bottom = page.unchanged >= 2;
      } else if (hash !== page.imageHash) { page.unchanged = 0; page.bottom = false; }
      page.imageHash = hash; this.pendingScroll = undefined; this.needsFrame = false;
    }
  }
  before(name: string): string | undefined {
    if (this.scope !== 'none' && name === 'browser_input' && this.needsFrame) return 'Observe a fresh browser_screenshot before another input. Each scroll must be followed by a genuine fresh image; repeated content fetches alone are not traversal.';
    return undefined;
  }
  private traversed(page: Pick<Page, 'contentReads' | 'sections' | 'scrolls'>): boolean { return page.contentReads > 0 && page.sections >= 3 && page.scrolls >= 2; }
  get canReport(): boolean { return [...this.pages.values()].some(page => this.traversed(page)); }
  state(): string {
    return JSON.stringify({ scope: this.scope, ratingRequested: this.ratingRequested, pages: [...this.pages.values()].map(({ imageHash: _hash, unchanged: _unchanged, ...page }) => ({ ...page, traversed: this.traversed(page) })), discoveredInternalURLs: [...this.links], missingLinkEnumeration: this.scope === 'site' && !this.enumerated.size, nextObservation: this.needsFrame ? 'browser_screenshot before further input' : undefined });
  }
  submit(args: Record<string, unknown>): { ok: boolean; error?: string } {
    if (this.scope === 'none' || !Array.isArray(args.pages) || args.pages.length < 1 || args.pages.length > 12 || typeof args.remaining !== 'string' || args.remaining.length > 1500) return { ok: false, error: 'Provide per-page findings for genuinely traversed pages and a concise coverage limitation.' };
    const validRating = (value: unknown) => value === null || typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 10;
    if (!validRating(args.overallRating) || this.ratingRequested && args.overallRating === null) return { ok: false, error: 'The requested overall rating must be between 0 and 10, explicitly based only on inspected pages.' };
    const findings: Finding[] = [], seen = new Set<string>();
    for (const raw of args.pages) {
      if (!raw || typeof raw !== 'object') return { ok: false, error: 'Invalid per-page finding.' };
      const item = raw as Record<string, unknown>, url = this.url(item.url), page = url ? this.pages.get(url) : undefined;
      if (!url || !page || seen.has(url) || !this.traversed(page) || typeof item.findings !== 'string' || !item.findings.trim() || item.findings.length > 2000 || !validRating(item.rating) || this.ratingRequested && item.rating === null) return { ok: false, error: 'Each reported URL needs actual page content, an initial screenshot and at least two acknowledged downward scrolls followed individually by fresh screenshots; include the requested per-page rating. Check the server coverage ledger.' };
      seen.add(url); findings.push({ url, findings: item.findings.trim(), rating: item.rating as number | null });
    }
    for (const item of findings) this.findings.set(item.url, item);
    this.overallRating = args.overallRating as number | null;
    this.remaining = args.remaining.trim();
    this.complete = this.scope === 'page'
      ? [...this.findings.keys()].every(url => this.pages.get(url)!.bottom)
      : this.findings.size >= 2 && this.enumerated.size > 0 && [...new Set([...this.links, ...this.pages.keys()])].every(url => this.findings.has(url) && this.enumerated.has(url) && this.pages.get(url)?.bottom === true);
    this.report = this.progressReport();
    return { ok: true };
  }
}

export const browserReviewReportTool = { type: 'function', function: {
  name: 'browser_review_report', strict: true,
  description: 'Finish a requested review with per-page findings grounded in actual traversal. The server checks content plus fresh screenshots after at least two downward scrolls on each reported URL. A report cannot manufacture coverage. Use concise specific findings, requested subjective ratings out of ten, and honest remaining limitations. Full site coverage is downgraded unless actual returned link enumeration and end-of-page observations support it.',
  parameters: { type: 'object', properties: {
    pages: { type: 'array', minItems: 1, maxItems: 12, items: { type: 'object', properties: { url: { type: 'string' }, findings: { type: 'string' }, rating: { type: ['number', 'null'] } }, required: ['url', 'findings', 'rating'], additionalProperties: false } },
    overallRating: { type: ['number', 'null'] }, remaining: { type: 'string' },
  }, required: ['pages', 'overallRating', 'remaining'], additionalProperties: false },
} };
