import { describe, expect, it, vi } from 'vitest';
import { MeetingCaptureDrain } from './meetingCaptureDrain';

describe('retiring microphone sessions', () => {
  it('awaits speech from a paused capture before final transcript writes', async () => {
    const drain = new MeetingCaptureDrain(); const events: string[] = [];
    let complete!: () => void;
    drain.retire({ stop: () => new Promise<void>((resolve) => { complete = () => { events.push('last speech'); resolve(); }; }) });
    const done = drain.finish().then(() => events.push('flush writes'));
    await Promise.resolve(); expect(events).toEqual([]);
    complete(); await done; expect(events).toEqual(['last speech', 'flush writes']);
  });
  it('releases the room at its deadline without cancelling delayed transcription', async () => {
    vi.useFakeTimers();
    try {
      const drain = new MeetingCaptureDrain(); let complete!: () => void;
      drain.retire({ stop: () => new Promise<void>((resolve) => { complete = resolve; }) });
      const result = drain.finishWithin(2500); await vi.advanceTimersByTimeAsync(2501);
      expect(await result).toBe(false);
      let completeSpeech = false; const remaining = drain.finish().then(() => { completeSpeech = true; });
      await Promise.resolve(); expect(completeSpeech).toBe(false);
      complete(); await remaining; expect(completeSpeech).toBe(true);
    } finally { vi.useRealTimers(); }
  });
  it('drains replacement captures added while finalization is pending', async () => {
    const drain = new MeetingCaptureDrain(); let complete!: () => void; let second!: () => void;
    drain.retire({ stop: () => new Promise<void>((resolve) => { complete = resolve; }) });
    let finished = false; const done = drain.finish().then(() => { finished = true; });
    drain.retire({ stop: () => new Promise<void>((resolve) => { second = resolve; }) });
    complete(); await Promise.resolve(); expect(finished).toBe(false); second(); await done; expect(finished).toBe(true);
  });
});
