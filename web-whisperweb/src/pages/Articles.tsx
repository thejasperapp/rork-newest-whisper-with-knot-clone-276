import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { BookOpen } from "lucide-react";

import { MemberShell, useIsMember } from "@/components/MemberShell";
import { ArticleCover } from "@/components/ArticleCover";
import { Reveal } from "@/components/Reveal";
import { usePageMeta } from "@/hooks/usePageMeta";
import { fetchArticles, type Article } from "@/lib/articles";
import { cn } from "@/lib/utils";

function formatDate(iso: string | null): string {
  if (!iso) return "";
  return new Date(iso).toLocaleDateString(undefined, {
    month: "long",
    day: "numeric",
    year: "numeric",
  });
}

function ArticleCard({ article }: { article: Article }) {
  return (
    <Link
      to={`/articles/${article.slug}`}
      className="group flex flex-col overflow-hidden rounded-[26px] border border-border bg-card transition-shadow hover:shadow-[0_14px_40px_rgba(0,0,0,0.10)]"
    >
      <div className="relative h-48">
        <ArticleCover
          cover={article.cover_url}
          alt={article.title}
          className="absolute inset-0"
          imgClassName="transition-transform duration-500 group-hover:scale-[1.03]"
        />
        <span className="absolute left-3 top-3 rounded-full bg-background/90 px-3 py-1 text-[11.5px] font-extrabold uppercase tracking-wider">
          {article.category}
        </span>
      </div>
      <div className="flex flex-1 flex-col p-5">
        <h2 className="font-display text-[19px] font-extrabold leading-snug">
          {article.title}
        </h2>
        {article.excerpt && (
          <p className="mt-2 line-clamp-3 flex-1 text-[14px] leading-relaxed text-muted-foreground">
            {article.excerpt}
          </p>
        )}
        <p className="mt-4 text-[12.5px] font-semibold text-muted-foreground">
          {article.author_name}
          {article.published_at ? ` · ${formatDate(article.published_at)}` : ""}
        </p>
      </div>
    </Link>
  );
}

/** Public articles index — admin-written content for visitors and members. */
export default function Articles() {
  usePageMeta(
    "Articles",
    "Training, nutrition, and coaching articles from the Whisper team — written by real coaches, not content farms."
  );

  const articles = useQuery({
    queryKey: ["articles"],
    queryFn: fetchArticles,
    staleTime: 60_000,
  });

  const rows = articles.data ?? [];
  const { isMember } = useIsMember();

  return (
    <MemberShell>
      <main>
        <section
          className={cn(
            "px-4 pb-10 sm:px-6 lg:px-8",
            isMember ? "pt-8" : "pt-32 lg:pt-40"
          )}
        >
          <div className="mx-auto max-w-4xl text-center">
            <div className="inline-flex items-center gap-2 rounded-full border border-border bg-card px-4 py-1.5 text-[13px] font-medium text-muted-foreground">
              <BookOpen className="h-4 w-4" />
              From the Whisper team
            </div>
            <h1 className="mt-6 font-display text-[38px] font-extrabold leading-[1.1] tracking-tight sm:text-[52px]">
              Articles.
            </h1>
            <p className="mx-auto mt-5 max-w-2xl text-[17px] leading-relaxed text-muted-foreground sm:text-[19px]">
              Training, nutrition, and coaching — written by the people behind
              Whisper, not a content farm.
            </p>
          </div>
        </section>

        <section className="px-4 pb-20 sm:px-6 lg:px-8">
          <div className="mx-auto max-w-5xl">
            {articles.isLoading ? (
              <div className={cn("grid gap-5 sm:grid-cols-2", !isMember && "lg:grid-cols-3")}>
                {[0, 1, 2].map((i) => (
                  <div
                    key={i}
                    className="h-80 animate-pulse rounded-[26px] bg-secondary"
                  />
                ))}
              </div>
            ) : rows.length === 0 ? (
              <div className="rounded-[28px] border border-dashed border-border p-12 text-center">
                <p className="text-[16px] font-semibold">
                  First articles are being written.
                </p>
                <p className="mx-auto mt-1.5 max-w-md text-[14.5px] text-muted-foreground">
                  Check back soon — training breakdowns, coach spotlights, and
                  honest nutrition guides are on the way.
                </p>
              </div>
            ) : (
              <Reveal stagger className={cn("grid gap-5 sm:grid-cols-2", !isMember && "lg:grid-cols-3")}>
                {rows.map((article) => (
                  <ArticleCard key={article.id} article={article} />
                ))}
              </Reveal>
            )}
          </div>
        </section>
      </main>
    </MemberShell>
  );
}
