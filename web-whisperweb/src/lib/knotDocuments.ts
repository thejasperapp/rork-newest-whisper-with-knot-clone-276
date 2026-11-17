import { groupThemeSession } from '@/lib/groupThemeSession';
import { knotBackendOrigin } from '@/lib/knotBackend';
import { consentChanged, knotAllowed, KnotHTTPError, type KnotBot } from '@/lib/knotService';

export interface KnotDocument {
  id: string; name: string; format: string; title?: string; deliveryLabel?: string; contentType: string; size: number; sha256: string;
  pages: number; proofPages: number[]; createdAt: string; expiresAt: string; proposalID: string;
  review: 'visual_ai' | 'not_requested' | 'unavailable' | 'issues'; sampled: boolean;
  visualReview?: { version: string; finalSHA256: string; scope: string; status: string; pages: { page: number; sha256: string; verdict: string; issues: string[] }[] };
  qualityShortfalls?: string[];
}
export function knotDocumentReviewDescription(file: KnotDocument): string {
  if (Array.isArray(file.qualityShortfalls) && file.qualityShortfalls.length) return 'Delivered after review with remaining quality shortfalls recorded in Events, not an overall quality pass.';
  const visual = file.visualReview;
  const allPages = visual?.version === 'knot_document_visual_v1' && visual.finalSHA256 === file.sha256 && visual.scope === 'all_pages' && visual.status === 'pass' && Array.isArray(visual.pages) && visual.pages.length === file.pages && new Set(visual.pages.map(p => p.page)).size === file.pages && visual.pages.every(p => Number.isInteger(p.page) && p.page > 0 && p.page <= file.pages && /^[a-f0-9]{64}$/.test(p.sha256) && p.verdict === 'pass' && Array.isArray(p.issues) && !p.issues.length);
  if (file.review === 'visual_ai' && allPages) return 'Every rendered page passed visual AI review. Only selected previews may be stored here. This is not human certification or a guarantee of factual, formula or accessibility correctness.';
  if (visual) return 'All-page visual review is not verified as a pass for this delivery. See Events for the recorded result.';
  return file.review === 'visual_ai' ? (file.sampled ? 'Visual AI review passed on the first, middle and last pages only. Other pages were not visually reviewed.' : 'Visual AI review passed on the supplied rendered pages. This is not human certification or a guarantee of factual, formula or accessibility correctness.') : file.review === 'issues' ? 'The file is delivered. Visual review recorded observations in Events; it did not pass.' : 'Visual AI review was not completed for this delivery. Mechanical proof images are not a visual AI verdict. Verified identity does not certify contents or design.';
}
/** Presentation only: never use this label as a filename or receipt identity. */
export function knotDocumentTitle(name: string, customTitle?: string): string {
  if (customTitle?.trim()) return customTitle.trim();
  const title = name.replace(/\.[^.]+$/, '')
    .replace(/^knot-(?:[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}|[a-f0-9]{8})[-_ ]+/i, '')
    .replace(/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/ig, ' ')
    .replace(/(?:^|[-_ ])(?:attempt|retry|revision|rev|v)[-_ ]?[0-9]+(?=$|[-_ ])/ig, ' ')
    .replace(/(?:[-_ ]+(?:final|corrected|revised|complete|attempt[0-9]*|v[0-9]+))+$/i, '')
    .replace(/[-_ ]+/g, ' ').trim();
  return title ? title.split(' ').map(word => word === word.toUpperCase() ? word : word[0].toUpperCase() + word.slice(1)).join(' ') : 'Your file';
}
export function knotDocumentStyle(file: KnotDocument): string {
  return file.deliveryLabel?.trim() || ({ pdf: 'PDF document', docx: 'Word document', xlsx: 'Spreadsheet', pptx: 'Slide deck', html: 'Interactive file', md: 'Text document', txt: 'Text document', csv: 'Data file', json: 'Data file' } as Record<string, string>)[file.format] || `${file.format.toUpperCase()} file`;
}
const validLabel = (value: unknown, limit: number): boolean => value === undefined || typeof value === 'string' && value.length <= limit && !/[\x00-\x1f\x7f]/.test(value);
export function knotDocumentDetails(file: KnotDocument): string {
  const unit = file.size >= 1000000 ? 'MB' : 'KB';
  const size = new Intl.NumberFormat(undefined, { maximumFractionDigits: 1 }).format(file.size / (unit === 'MB' ? 1000000 : 1000));
  return `${file.format.toUpperCase()} · ${size} ${unit}`;
}
export function knotDocumentIdentity(file: KnotDocument): string {
  return `${knotDocumentDetails(file)} · Verified identity`;
}
export function validKnotDocuments(value: unknown): value is KnotDocument[] {
  return Array.isArray(value) && value.length <= 500 && value.every((d: KnotDocument) => d &&
    /^[a-f0-9]{64}$/.test(d.id) && /^[a-f0-9]{64}$/.test(d.sha256) &&
    typeof d.name === 'string' && d.name.length > 0 && d.name.length <= 240 && !/[/\\]/.test(d.name) &&
    typeof d.format === 'string' && /^[a-z0-9][a-z0-9_-]{0,15}$/.test(d.format) && validLabel(d.title, 120) && validLabel(d.deliveryLabel, 48) && d.name.toLowerCase().endsWith('.' + d.format) &&
    Number.isSafeInteger(d.size) && d.size > 0 && d.size <= 50000000 &&
    Number.isSafeInteger(d.pages) && d.pages > 0 && d.pages <= 300 &&
    Array.isArray(d.proofPages) && d.proofPages.length <= 12 && new Set(d.proofPages).size === d.proofPages.length && d.proofPages.every(p => Number.isInteger(p) && p > 0 && p <= d.pages) &&
    /^[0-9a-f-]{36}$/i.test(d.proposalID) && ['visual_ai', 'not_requested', 'unavailable', 'issues'].includes(d.review) && typeof d.sampled === 'boolean' &&
    Number.isFinite(Date.parse(d.createdAt)) && Number.isFinite(Date.parse(d.expiresAt)));
}

/** Authenticated immutable-byte delivery only. No shell command or file capture. */
export async function readKnotDocument(owner: string, bot: KnotBot, conversationID: string, document: KnotDocument, signal: AbortSignal, pageIndex?: number): Promise<Blob> {
  if (!validKnotDocuments([document]) || !/^[0-9a-f-]{36}$/i.test(conversationID)) throw new Error('File expired or unavailable');
  if (pageIndex !== undefined && (!Number.isInteger(pageIndex) || pageIndex < 0 || pageIndex >= document.proofPages.length)) throw new Error('Preview unavailable');
  const withdrawal = new AbortController();
  const stop = () => withdrawal.abort();
  const stored = (event: StorageEvent) => { if (event.key === null || event.key.startsWith(`knot_ai_consent_v3:${owner.toLowerCase()}`)) stop(); };
  window.addEventListener(consentChanged, stop); window.addEventListener('storage', stored);
  const auth = await groupThemeSession(owner).catch(error => { window.removeEventListener(consentChanged, stop); window.removeEventListener('storage', stored); throw error; });
  const combined = AbortSignal.any([auth.signal, signal, withdrawal.signal, AbortSignal.timeout(75000)]);
  const check = () => { auth.check(); if (combined.aborted || !knotAllowed(owner)) throw new DOMException('Stopped', 'AbortError'); };
  let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
  try {
    check();
    const response = await fetch(knotBackendOrigin + '/knot/shell/documents', {
      method: 'POST', redirect: 'error', cache: 'no-store', signal: combined,
      headers: { 'Content-Type': 'application/json', 'X-Whisper-Authorization': `Bearer ${auth.token}` },
      body: JSON.stringify({ bot, conversationID: conversationID.toLowerCase(), documentID: document.id, action: pageIndex === undefined ? 'file' : 'preview', ...(pageIndex === undefined ? {} : { pageIndex }) }),
    });
    check();
    if (!response.ok || !response.body) { await response.body?.cancel(); throw new KnotHTTPError(response.status); }
    reader = response.body.getReader();
    const limit = pageIndex === undefined ? 50000000 : 1800000, chunks: Uint8Array[] = []; let size = 0;
    for (;;) { const part = await reader.read(); check(); if (part.done) break; size += part.value.byteLength; if (size > limit) throw new Error('File too large'); chunks.push(part.value); }
    const bytes = new Uint8Array(size); let at = 0;
    for (const chunk of chunks) { bytes.set(chunk, at); at += chunk.length; }
    if (pageIndex === undefined) {
      const digest = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), b => b.toString(16).padStart(2, '0')).join('');
      if (size !== document.size || digest !== document.sha256) throw new Error('File integrity check failed');
    } else if (![137, 80, 78, 71, 13, 10, 26, 10].every((b, i) => bytes[i] === b) || response.headers.get('Content-Type') !== 'image/png') throw new Error('Invalid preview');
    check();
    // Files download as opaque data, including HTML. Never embed active file content.
    return new Blob([bytes], { type: pageIndex === undefined ? 'application/octet-stream' : 'image/png' });
  } finally {
    await reader?.cancel().catch(() => undefined); reader?.releaseLock(); auth.dispose();
    window.removeEventListener(consentChanged, stop); window.removeEventListener('storage', stored);
  }
}
