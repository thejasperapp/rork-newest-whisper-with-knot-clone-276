import { memo } from 'react';
import { cn } from '@/lib/utils';
import { EmberMascot } from './EmberMascot';

/** The same regular animated Jasper used throughout Whisper. */
export const JasperSidekickMascot = memo(function JasperSidekickMascot({ className, working = false }: { className?: string; working?: boolean }): JSX.Element {
  return <span role="img" aria-label="Jasper" className={cn('inline-flex aspect-square h-14 shrink-0 items-center justify-center [&>div]:!h-full [&>div]:!w-full', className)}><EmberMascot size={56} isActive={working} expression={working ? 'thinking' : 'calm'} /></span>;
});
