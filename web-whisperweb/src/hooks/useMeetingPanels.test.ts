import { act, renderHook } from '@testing-library/react';
import { describe, it, expect } from 'vitest';
import { useMeetingPanels } from './useMeetingPanels';

describe('meeting panel coordination', () => {
  it('replaces Jasper with recording, tools and chat without stacking surfaces', () => {
    const { result } = renderHook(() => useMeetingPanels<'chat' | 'people'>());
    act(() => result.current.setNotebookOpen(true)); expect(result.current.notebookOpen).toBe(true);
    act(() => result.current.setRecordingOpen(true)); expect(result.current.notebookOpen).toBe(false);
    act(() => result.current.setShowRecruiterTools(true)); expect(result.current.recordingOpen).toBe(false);
    act(() => result.current.setPanelTab('chat')); expect(result.current.showRecruiterTools).toBe(false); expect(result.current.panelTab).toBe('chat');
    act(() => { result.current.setNotebookOpen(true); result.current.setActivitiesOpen(false); });
    expect(result.current.notebookOpen).toBe(true); expect(result.current.panelTab).toBeNull();
  });
  it('supports toggle and stale close without dismissing the new panel', () => {
    const { result } = renderHook(() => useMeetingPanels<'chat'>());
    act(() => result.current.setActivitiesOpen((open) => !open));
    act(() => { result.current.setEmberPanelOpen(true); result.current.setActivitiesOpen(false); });
    expect(result.current.emberPanelOpen).toBe(true);
    act(() => result.current.setEmberPanelOpen((open) => !open)); expect(result.current.emberPanelOpen).toBe(false);
  });
});
