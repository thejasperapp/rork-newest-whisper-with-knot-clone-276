import { useState } from "react";
import { ChevronDown } from "lucide-react";
import { cn } from "@/lib/utils";

interface ViewMoreListProps<T> {
  items: T[];
  renderItem: (item: T, index: number) => React.ReactNode;
  maxVisible?: number;
  className?: string;
  itemClassName?: string;
  expandLabel?: string;
  collapseLabel?: string;
}

export function ViewMoreList<T>({
  items,
  renderItem,
  maxVisible = 6,
  className,
  itemClassName,
  expandLabel = "View more",
  collapseLabel = "Show less",
}: ViewMoreListProps<T>) {
  const [expanded, setExpanded] = useState(false);
  const visible = expanded ? items : items.slice(0, maxVisible);
  const hasMore = items.length > maxVisible;

  return (
    <div className={className}>
      <div className={itemClassName}>
        {visible.map((item, i) => renderItem(item, i))}
      </div>
      {hasMore && (
        <button
          onClick={() => setExpanded(!expanded)}
          className="mt-1 flex w-full items-center justify-center gap-1 rounded-xl py-2 text-[13px] font-semibold text-muted-foreground transition-colors hover:bg-secondary/60"
        >
          <ChevronDown
            className={cn(
              "h-4 w-4 transition-transform",
              expanded && "rotate-180"
            )}
          />
          {expanded ? collapseLabel : expandLabel}
        </button>
      )}
    </div>
  );
}
