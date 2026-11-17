// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { creatorSnapshot, creatorFinding, creatorMaterialChange, creatorReport, type CreatorSnapshot } from '../../functions/knot-creator-performance';

const owner = '00000000-0000-4000-8000-000000000001';
const postA = '00000000-0000-4000-8000-000000000002';
const postB = '00000000-0000-4000-8000-000000000003';
const now = Date.parse('2026-11-12T12:00:00Z');
const snapshot = (followers = 516): CreatorSnapshot => creatorSnapshot([], followers, owner, false, undefined, now);
const withTop = (base: CreatorSnapshot, median: number, id: string, likes: number): CreatorSnapshot => ({ ...base, medianInteractions: median, topPosts: [{ id, publishedAt: '2026-11-12T10:00:00Z', likes, comments: 0 }] });

describe('creator material-change reporting', () => {
  it('computes an actual median from the authorized observed post window', () => {
    const posts = [10, 20, 30, 100].map((likes_count, index) => ({ id: `00000000-0000-4000-8000-00000000000${index + 2}`, user_id: owner, created_at: new Date(now - index * 1000).toISOString(), likes_count, comments_count: 0 }));
    const value = creatorSnapshot(posts, 516, owner, false, undefined, now);
    expect(value.medianInteractions).toBe(25);
    expect(value.interactions).toBe(160);
    expect(value.creatorScoreEstimate).toBeNull();
  });
  it('establishes a first baseline but does not call a new timestamp a change', () => {
    const before = snapshot();
    expect(creatorMaterialChange(before, '')).toBe(true);
    expect(creatorMaterialChange({ ...before, asOf: '2026-11-12T13:00:00Z' }, creatorFinding(before))).toBe(false);
  });
  it('requires the larger of five accounts or one percent of the last reported count', () => {
    const before = snapshot(516), saved = creatorFinding(before);
    expect(creatorMaterialChange(snapshot(521), saved)).toBe(false);
    expect(creatorMaterialChange(snapshot(522), saved)).toBe(true);
    expect(creatorMaterialChange(snapshot(510), saved)).toBe(true);
    expect(creatorMaterialChange(snapshot(104), creatorFinding(snapshot(100)))).toBe(false);
    expect(creatorMaterialChange(snapshot(105), creatorFinding(snapshot(100)))).toBe(true);
    expect(creatorMaterialChange(snapshot(1099), creatorFinding(snapshot(1000)))).toBe(true);
    expect(creatorMaterialChange(snapshot(1009), creatorFinding(snapshot(1000)))).toBe(false);
  });
  it('accumulates quiet drift against the delivered baseline and ignores score/window churn', () => {
    const saved = creatorFinding(snapshot(100));
    expect(creatorMaterialChange(snapshot(102), saved)).toBe(false);
    expect(creatorMaterialChange(snapshot(104), saved)).toBe(false);
    expect(creatorMaterialChange(snapshot(105), saved)).toBe(true);
    expect(creatorMaterialChange({ ...snapshot(100), coverageLimited: true, creatorScoreEstimate: 90, likes: 20 }, saved)).toBe(false);
  });
  it('reports newly exceptional posts without repeating still-performing posts', () => {
    const previous = withTop(snapshot(), 20, postA, 45);
    const saved = creatorFinding(previous);
    expect(creatorMaterialChange(withTop(snapshot(), 20, postA, 60), saved)).toBe(false);
    expect(creatorMaterialChange(withTop(snapshot(), 20, postB, 40), saved)).toBe(true);
    expect(creatorMaterialChange(withTop(snapshot(), 20, postB, 39), saved)).toBe(false);
    expect(creatorMaterialChange(withTop(snapshot(), 0, postB, 100), saved)).toBe(false);
    expect(creatorMaterialChange(withTop(snapshot(), 20, postA, 45), creatorFinding(withTop(snapshot(), 20, postA, 30)))).toBe(true);
  });
  it('supports legacy findings conservatively without inventing their observation date or median', () => {
    const legacy = JSON.stringify({ followers: 516, topPosts: [{ id: postA, likes: 45, comments: 0 }] });
    expect(creatorMaterialChange(withTop(snapshot(), 20, postA, 100), legacy)).toBe(false);
    expect(creatorReport(snapshot(522), legacy)).toContain('date unavailable');
    expect(creatorMaterialChange(snapshot(), '{broken')).toBe(true);
  });
  it('dates actual reported changes and retains honest count and coverage scope', () => {
    const report = creatorReport(snapshot(522), creatorFinding(snapshot(516)));
    expect(report).toContain('since 2026-11-12T12:00:00.000Z: +6');
    expect(report).toContain('not reach or interactions occurring only in the last 30 days');
    expect(report).toContain('requires verified or staff access');
    expect(report).not.toContain('new followers named');
  });
});
