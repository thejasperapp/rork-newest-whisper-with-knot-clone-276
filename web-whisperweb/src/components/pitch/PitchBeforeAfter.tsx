import { ArrowRight, X } from "lucide-react";

interface BeforeAfterItem {
  before: string;
  after: string;
}

export function PitchBeforeAfter({
  eyebrow,
  title,
  lead,
  items,
}: {
  eyebrow: string;
  title: string;
  lead: string;
  items: BeforeAfterItem[];
}) {
  return (
    <div className="rounded-[20px] border border-border bg-card p-4 shadow-sm">
      <p className="text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
        {eyebrow}
      </p>
      <h3 className="mt-1 text-[16px] font-extrabold">{title}</h3>
      <p className="mt-1 text-[13px] leading-snug text-muted-foreground">{lead}</p>
      <div className="mt-4 space-y-2">
        {items.map((item, i) => (
          <div
            key={i}
            className="grid items-center gap-2 rounded-2xl bg-secondary/40 p-3 sm:grid-cols-[1fr_auto_1fr]"
          >
            <div className="text-[13px] font-medium text-muted-foreground line-through decoration-foreground/30">
              {item.before}
            </div>
            <div className="flex h-6 w-6 items-center justify-center justify-self-center rounded-full bg-foreground text-background">
              <ArrowRight className="h-3.5 w-3.5" />
            </div>
            <div className="text-[13px] font-bold text-foreground">{item.after}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

export function PitchBeforeAfterCompact({
  items,
  className,
}: {
  items: BeforeAfterItem[];
  className?: string;
}) {
  return (
    <div className={className}>
      {items.map((item, i) => (
        <div
          key={i}
          className="flex items-start gap-3 rounded-xl bg-secondary/40 p-3"
        >
          <X className="mt-0.5 h-4 w-4 shrink-0 text-red-500/70" />
          <div className="min-w-0 flex-1">
            <p className="text-[12.5px] text-muted-foreground line-through decoration-foreground/30">
              {item.before}
            </p>
            <p className="text-[12.5px] font-bold text-foreground">{item.after}</p>
          </div>
        </div>
      ))}
    </div>
  );
}
