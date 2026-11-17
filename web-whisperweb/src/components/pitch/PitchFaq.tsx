import { ChevronDown } from "lucide-react";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";

export interface PitchFaqItem {
  question: string;
  answer: string;
}

export function PitchFaq({
  eyebrow,
  title,
  items,
}: {
  eyebrow: string;
  title: string;
  items: PitchFaqItem[];
}) {
  return (
    <div className="rounded-[20px] border border-border bg-card p-4 shadow-sm">
      <p className="text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
        {eyebrow}
      </p>
      <h3 className="mt-1 text-[16px] font-extrabold">{title}</h3>
      <Accordion type="single" collapsible className="mt-3">
        {items.map((item, i) => (
          <AccordionItem key={i} value={`faq-${i}`} className="border-b border-border last:border-0">
            <AccordionTrigger className="py-3 text-left text-[13.5px] font-bold hover:no-underline">
              {item.question}
            </AccordionTrigger>
            <AccordionContent className="pb-3 text-[13px] leading-snug text-muted-foreground">
              {item.answer}
            </AccordionContent>
          </AccordionItem>
        ))}
      </Accordion>
    </div>
  );
}
