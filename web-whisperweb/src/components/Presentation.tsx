import type { ReactNode } from "react";
import { ArrowUpRight } from "lucide-react";
import { Link } from "react-router-dom";
import "@/presentation.css";

export function PresentationIntro({ eyebrow, title, description, children }: { eyebrow: string; title: string; description: string; children?: ReactNode }) {
  return <header className="presentation-intro">
    <p className="presentation-eyebrow">{eyebrow}</p>
    <h1>{title}</h1>
    <p className="presentation-lede">{description}</p>
    {children && <div className="presentation-actions">{children}</div>}
  </header>;
}

export function PresentationLink({ to, children, primary = false }: { to: string; children: ReactNode; primary?: boolean }) {
  return <Link to={to} className={`presentation-link ${primary ? "presentation-link-primary" : ""}`}>{children}<ArrowUpRight size={16} aria-hidden="true" /></Link>;
}

export function PresentationFAQ({ items }: { items: { q: string; a: string }[] }) {
  return <div className="presentation-faq">{items.map(item => <details key={item.q}>
    <summary>{item.q}<span aria-hidden="true">+</span></summary><p>{item.a}</p>
  </details>)}</div>;
}
