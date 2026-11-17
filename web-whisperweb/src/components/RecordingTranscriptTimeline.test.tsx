import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { RecordingTranscriptTimeline } from './RecordingTranscriptTimeline';
import type { TimedPassage } from '@/lib/meetingRecordingModel';
const passages: TimedPassage[] = [{ id: 'a', start: 2, end: 4, text: 'First sentence.', timing: 'speech' }, { id: 'b', start: 9, end: 12, text: 'After a silent gap.', timing: 'chunk' }];
afterEach(cleanup);
describe('recording transcript follows only the media clock', () => {
  it('highlights actual passages, leaves silence unhighlighted and seeks exact source start', () => {
    const seek = vi.fn(); const app = render(<RecordingTranscriptTimeline passages={passages} position={3} onSeek={seek} />);
    expect(screen.getByRole('button', { name: /First sentence/ })).toHaveAttribute('aria-current', 'true');
    app.rerender(<RecordingTranscriptTimeline passages={passages} position={6} onSeek={seek} />);
    expect(screen.getByRole('button', { name: /First sentence/ })).not.toHaveAttribute('aria-current');
    fireEvent.click(screen.getByRole('button', { name: /After a silent gap/ })); expect(seek).toHaveBeenCalledWith(9);
    expect(screen.getByText('Approx.')).toBeVisible();
  });
  it('lets the user turn following off and selects recording context only on request', () => {
    const ask = vi.fn(); render(<RecordingTranscriptTimeline passages={passages} position={0} onSeek={vi.fn()} onAsk={ask} />);
    expect(ask).not.toHaveBeenCalled(); fireEvent.click(screen.getByRole('button', { name: 'Following playback' }));
    expect(screen.getByRole('button', { name: 'Follow playback' })).toHaveAttribute('aria-pressed', 'false');
    fireEvent.click(screen.getByRole('button', { name: 'Ask Jasper about this recording' })); expect(ask).toHaveBeenCalledWith(passages);
  });
  it('offers individual passage context rather than silently truncating a long recording', () => {
    const many = Array.from({ length: 161 }, (_, id) => ({ ...passages[0], id: String(id) }));
    render(<RecordingTranscriptTimeline passages={many} position={0} onSeek={vi.fn()} onAsk={vi.fn()} />);
    expect(screen.queryByRole('button', { name: 'Ask Jasper about this recording' })).not.toBeInTheDocument();
    expect(screen.getAllByRole('button', { name: 'Ask about this passage' })).toHaveLength(161);
  });
});
