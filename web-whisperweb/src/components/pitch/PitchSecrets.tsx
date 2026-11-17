import { Eye, EyeOff, X } from "lucide-react";

import { usePitch } from "@/components/pitch/PitchContext";
import { cn } from "@/lib/utils";

export function PitchSecret({
  children,
  label,
}: {
  children: React.ReactNode;
  label: string;
}) {
  return (
    <div className="rounded-2xl border border-foreground/20 bg-foreground/5 p-3">
      <p className="flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wider text-foreground/70">
        <EyeOff className="h-3 w-3" /> Presenter secret: {label}
      </p>
      <div className="mt-1.5 text-[12px] leading-snug text-foreground/80">
        {children}
      </div>
    </div>
  );
}

export function PitchSecretsPanel({ secrets }: { secrets: { label: string; content: React.ReactNode }[] }) {
  const { secrets: secretsOpen, setSecrets } = usePitch();
  if (!secretsOpen) return null;

  return (
    <div className="fixed left-4 top-20 z-[60] hidden h-[calc(100vh-6rem)] w-80 flex-col rounded-[24px] border border-border bg-card p-4 shadow-2xl backdrop-blur-md lg:flex">
      <div className="flex items-center justify-between border-b border-dashed border-border pb-3">
        <p className="flex items-center gap-2 text-[13px] font-bold">
          <Eye className="h-4 w-4" /> Presenter secrets
        </p>
        <button
          onClick={() => setSecrets(false)}
          className="flex h-7 w-7 items-center justify-center rounded-full text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground"
          aria-label="Close secrets"
        >
          <X className="h-3.5 w-3.5" />
        </button>
      </div>
      <div className="mt-3 flex-1 space-y-3 overflow-y-auto pr-1 pb-4">
        {secrets.map((s, i) => (
          <PitchSecret key={i} label={s.label}>
            {s.content}
          </PitchSecret>
        ))}
      </div>
    </div>
  );
}

export function PitchSecretsMobile({ secrets }: { secrets: { label: string; content: React.ReactNode }[] }) {
  return (
    <div className={cn(
      "rounded-[20px] border border-border bg-card p-4 shadow-sm lg:hidden",
      "animate-in fade-in slide-in-from-bottom-4 duration-300"
    )}>
      <p className="flex items-center gap-2 text-[13px] font-bold">
        <Eye className="h-4 w-4" /> Presenter secrets
      </p>
      <div className="mt-3 space-y-3">
        {secrets.map((s, i) => (
          <PitchSecret key={i} label={s.label}>
            {s.content}
          </PitchSecret>
        ))}
      </div>
    </div>
  );
}
