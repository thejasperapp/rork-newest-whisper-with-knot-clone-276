import { lazy, memo, Suspense, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useAuth } from "@/hooks/useAuth";
import { loadQuotedPost } from "@/lib/quotedPost";
import type { SharedPostPayload } from "@/lib/postShare";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";

const OriginalPostCard = lazy(() => import("@/components/PostCard").then(module => ({ default: module.PostCard })));

function QuotedPostCardBase({ payload, depth = 0 }: { payload: SharedPostPayload; depth?: number }) {
  const { user } = useAuth();
  const [open, setOpen] = useState<boolean>(false);
  if (depth > 0) return <>
    <button type="button" className="mt-2 min-h-11 rounded-xl border border-border px-4 text-sm font-medium" onClick={() => setOpen(true)}>Open quoted post</button>
    <Dialog open={open} onOpenChange={setOpen}><DialogContent className="max-h-[85dvh] overflow-y-auto sm:max-w-xl"><DialogTitle>Quoted post</DialogTitle><DialogDescription>Original post and discussion</DialogDescription>{open && <QuotedPostCardBase payload={payload} />}</DialogContent></Dialog>
  </>;
  if (!user) return <p className="mt-2 rounded-2xl border border-border p-4 text-sm text-muted-foreground">Sign in to view this quoted post.</p>;
  return <HydratedQuote key={`${user.id}:${payload.postID}`} postID={payload.postID} accountID={user.id} />;
}

function HydratedQuote({ postID, accountID }: { postID: string; accountID: string }) {
  const [instance] = useState<string>(() => crypto.randomUUID());
  const query = useQuery({ queryKey: ["quoted-post", accountID, postID, instance], queryFn: ({ signal }) => loadQuotedPost(postID, accountID, signal), staleTime: 0, gcTime: 0, retry: 1, refetchOnWindowFocus: "always" });
  return <section aria-label="Quoted post" className="mt-3 min-w-0 overflow-hidden rounded-2xl border border-border bg-background" onClick={event => event.stopPropagation()}>
    {query.isPending ? <p role="status" className="p-4 text-sm text-muted-foreground">Loading original post…</p> : query.isError ? <div className="p-4 text-sm"><p>Couldn’t load this post.</p><button type="button" className="mt-1 min-h-11 font-semibold underline" onClick={() => void query.refetch()}>Try again</button></div> : !query.data ? <p className="p-4 text-sm text-muted-foreground">This post is no longer available to you.</p> : <div className="relative">{query.isFetching && <p role="status" className="absolute inset-x-0 top-0 p-4 text-sm text-muted-foreground">Checking original post…</p>}<div className={query.isFetching ? "invisible pointer-events-none" : ""}><Suspense fallback={<p role="status" className="p-4 text-sm">Loading post…</p>}><OriginalPostCard post={query.data.post} author={query.data.author} liked={query.data.liked} quoteDepth={1} /></Suspense></div></div>}
  </section>;
}

export const QuotedPostCard = memo(QuotedPostCardBase);
