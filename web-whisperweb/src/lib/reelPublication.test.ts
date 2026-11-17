import { beforeEach, describe, expect, it, vi } from 'vitest';
const db = vi.hoisted(() => ({ insert: vi.fn() }));
vi.mock('@/lib/supabase', () => ({ supabase: { from: () => ({ insert: db.insert }) } }));
import { createReel } from './api';
const input = { userId: 'creator', username: 'creator', caption: 'A finished edit', mediaUrls: ['https://media.example/video.mp4'] };
beforeEach(() => { db.insert.mockReset(); });
describe('reel publication integrity', () => {
  it('does not insert before media upload succeeds', async () => {
    await expect(createReel({ ...input, mediaUrls: [] })).rejects.toThrow('uploading');
    await expect(createReel({ ...input, mediaUrls: ['file:///local/video.mp4'] })).rejects.toThrow('uploading');
    expect(db.insert).not.toHaveBeenCalled();
  });
  it.each(['media_urls', 'is_reel', 'is_ghost'])('never silently drops required %s', async (column) => {
    db.insert.mockResolvedValue({ error: { message: `Could not find the '${column}' column of 'whisper_posts' in the schema cache` } });
    await expect(createReel(input)).rejects.toBeTruthy();
    expect(db.insert).toHaveBeenCalledTimes(1);
  });
  it('keeps the video identity and classification on success', async () => {
    db.insert.mockResolvedValue({ error: null });
    await createReel(input);
    expect(db.insert).toHaveBeenCalledWith(expect.objectContaining({ media_urls: input.mediaUrls, is_reel: true, kind: 'reel', media_count: 1 }));
  });
});
