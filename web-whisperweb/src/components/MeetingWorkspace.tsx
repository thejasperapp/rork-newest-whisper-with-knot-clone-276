import type { ReactNode } from 'react';
import { cn } from '@/lib/utils';

/** Stage and private drawer occupy separate layout cells; neither remounts on collapse. */
export function MeetingWorkspace({ open, children, drawer }: { open: boolean; children: ReactNode; drawer: ReactNode }): JSX.Element {
  return <div data-meeting-workspace className="mx-auto flex min-h-0 w-full max-w-[1760px] flex-1 px-2 pb-24 pt-16 sm:px-3 lg:px-4">
    <div className={cn('grid min-h-0 w-full gap-3', open ? 'grid-rows-[minmax(80px,0.6fr)_minmax(0,1.4fr)] md:grid-cols-[minmax(0,1fr)_minmax(320px,380px)] md:grid-rows-[minmax(0,1fr)]' : 'grid-cols-[minmax(0,1fr)] grid-rows-[minmax(0,1fr)]')}>
      <div data-meeting-tile-region className="relative isolate min-h-0 min-w-0 overflow-hidden rounded-[28px] bg-black/10">{children}</div>
      {drawer}
    </div>
  </div>;
}
