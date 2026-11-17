import { useMemo, useState, type Dispatch, type SetStateAction } from 'react';

type Utility = 'notebook' | 'recruiter' | 'coach' | 'creator' | 'recording' | 'activities' | 'voice';
type Selection<T extends string> = { kind: Utility } | { kind: 'standard'; tab: T } | null;
/** Presentation only: switching tools must never change media or discard their saved drafts. */
export function useMeetingPanels<T extends string>() {
  const [active, setActive] = useState<Selection<T>>(null);
  const setters = useMemo(() => {
    const toggle = (kind: Utility): Dispatch<SetStateAction<boolean>> => (value) => setActive((prior) => {
      const open = typeof value === 'function' ? value(prior?.kind === kind) : value;
      return open ? { kind } : prior?.kind === kind ? null : prior;
    });
    const setPanelTab: Dispatch<SetStateAction<T | null>> = (value) => setActive((prior) => {
      const tab = typeof value === 'function' ? value(prior?.kind === 'standard' ? prior.tab : null) : value;
      return tab ? { kind: 'standard', tab } : prior?.kind === 'standard' ? null : prior;
    });
    return { setNotebookOpen: toggle('notebook'), setShowRecruiterTools: toggle('recruiter'), setShowCoachTools: toggle('coach'), setShowCreatorTools: toggle('creator'), setRecordingOpen: toggle('recording'), setActivitiesOpen: toggle('activities'), setEmberPanelOpen: toggle('voice'), setPanelTab };
  }, []);
  return { ...setters, notebookOpen: active?.kind === 'notebook', showRecruiterTools: active?.kind === 'recruiter', showCoachTools: active?.kind === 'coach', showCreatorTools: active?.kind === 'creator', recordingOpen: active?.kind === 'recording', activitiesOpen: active?.kind === 'activities', emberPanelOpen: active?.kind === 'voice', panelTab: active?.kind === 'standard' ? active.tab : null };
}
