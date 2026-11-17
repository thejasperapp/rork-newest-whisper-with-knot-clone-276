import { describe, expect, it, vi } from 'vitest';
vi.mock('@/lib/groupThemeSession', () => ({ groupThemeSession: vi.fn() }));
vi.mock('@/lib/knotService', () => ({ consentChanged: 'synthetic-consent', knotAllowed: vi.fn(), KnotHTTPError: class extends Error {} }));
import { knotDocumentReviewDescription, type KnotDocument } from './knotDocuments';
const file: KnotDocument = { id: 'a'.repeat(64), name: 'report.pdf', format: 'pdf', contentType: 'application/pdf', size: 100, sha256: 'b'.repeat(64), pages: 13, proofPages: [1, 7, 13], createdAt: '2026-11-12T00:00:00Z', expiresAt: '2026-11-19T00:00:00Z', proposalID: '00000000-0000-4000-8000-000000000001', review: 'visual_ai', sampled: true };
const visual = { version: 'knot_document_visual_v1', finalSHA256: file.sha256, scope: 'all_pages', status: 'pass', pages: Array.from({ length: 13 }, (_, index) => ({ page: index + 1, sha256: 'c'.repeat(64), verdict: 'pass', issues: [] as string[] })) };
describe('honest document-review display', () => {
  it('keeps historical sampled and optional review meanings without upgrading them', () => {
    expect(knotDocumentReviewDescription(file)).toContain('first, middle and last pages only');
    expect(knotDocumentReviewDescription({ ...file, review: 'unavailable' })).toContain('was not completed');
  });
  it('distinguishes full pixel review from selected stored previews', () => {
    const text = knotDocumentReviewDescription({ ...file, visualReview: visual });
    expect(text).toContain('Every rendered page passed'); expect(text).toContain('Only selected previews'); expect(text).toContain('not human certification');
  });
  it('does not call qualified delivery an overall pass', () => {
    expect(knotDocumentReviewDescription({ ...file, visualReview: visual, qualityShortfalls: ['Sizing remains thin.'] })).toContain('not an overall quality pass');
  });
  it.each(['wrong-final', 'omission', 'duplicate', 'uncertain', 'issues'] as const)('never falls back to a historical pass claim for invalid/current %s metadata', scenario => {
    const value = structuredClone(visual);
    if (scenario === 'wrong-final') value.finalSHA256 = 'f'.repeat(64);
    if (scenario === 'omission') value.pages.pop();
    if (scenario === 'duplicate') value.pages[1] = value.pages[0];
    if (scenario === 'uncertain') value.pages[0].verdict = 'uncertain';
    if (scenario === 'issues') { value.status = 'issues'; value.pages[0].verdict = 'issues'; value.pages[0].issues = ['Clipped title']; }
    expect(knotDocumentReviewDescription({ ...file, visualReview: value })).not.toContain('passed');
  });
});
