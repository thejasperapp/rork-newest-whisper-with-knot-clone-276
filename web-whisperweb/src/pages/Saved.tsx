import { useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { ArrowLeft, Bookmark } from "lucide-react";

import { Header } from "@/components/Header";
import { PostCard } from "@/components/PostCard";
import { useAuth } from "@/hooks/useAuth";
import {
  fetchMyBookmarkIds,
  fetchMyLikedPostIds,
  fetchMyRepostIds,
  fetchPostsByIds,
  fetchProfilesByIds,
} from "@/lib/api";

/**
 * Saved posts — the web twin of the iOS Settings → "Saved posts" sheet.
 * Lists every whisper the signed-in user has bookmarked.
 */
export default function Saved() {
  const { user } = useAuth();
  const navigate = useNavigate();

  const bookmarkIdsQuery = useQuery({
    queryKey: ["my-bookmarks", user?.id],
    queryFn: ({ signal }) => fetchMyBookmarkIds(user!.id, { signal }),
    enabled: !!user,
  });
  const ids = bookmarkIdsQuery.data ?? [];

  const postsQuery = useQuery({
    queryKey: ["saved-posts", user?.id, ids],
    queryFn: ({ signal }) => fetchPostsByIds(ids, { signal, requireSuccess: true }),
    enabled: ids.length > 0,
  });
  const posts = postsQuery.data ?? [];

  const authorIds = [...new Set(posts.map((p) => p.user_id))].sort();
  const profilesQuery = useQuery({
    queryKey: ["profiles", user?.id, authorIds],
    queryFn: ({ signal }) => fetchProfilesByIds(authorIds, { signal }),
    enabled: authorIds.length > 0,
  });
  const profiles = profilesQuery.data ?? {};

  const likesQuery = useQuery({
    queryKey: ["my-likes", user?.id],
    queryFn: () => fetchMyLikedPostIds(user!.id),
    enabled: !!user,
  });
  const repostsQuery = useQuery({
    queryKey: ["my-reposts", user?.id],
    queryFn: () => fetchMyRepostIds(user!.id),
    enabled: !!user,
  });
  const likedSet = new Set(likesQuery.data ?? []);
  const repostedSet = new Set(repostsQuery.data ?? []);

  const loading =
    bookmarkIdsQuery.isLoading || (ids.length > 0 && postsQuery.isLoading);

  return (
    <div>
      <Header
        title="Saved"
        left={
          <button
            onClick={() => navigate(-1)}
            aria-label="Back"
            className="glass flex h-10 w-10 items-center justify-center rounded-full border border-border/60 shadow-sm transition-transform active:scale-90"
          >
            <ArrowLeft className="h-5 w-5" />
          </button>
        }
        right={<span className="h-10 w-10" />}
      />

      <div className="overflow-hidden border-y border-border bg-background sm:mt-2 sm:rounded-[22px] sm:border sm:shadow-sm">
        {loading && (
          <p className="px-6 py-16 text-center text-sm text-muted-foreground">
            Loading saved posts…
          </p>
        )}

        {(bookmarkIdsQuery.isError || postsQuery.isError) && <div role="status" className="px-6 py-8 text-center text-sm text-muted-foreground">
          <p>Saved posts couldn’t refresh. Your bookmarks are still saved.</p>
          <button className="mt-2 min-h-11 rounded-full bg-secondary px-5 font-semibold text-foreground" disabled={bookmarkIdsQuery.isFetching || postsQuery.isFetching} onClick={() => void (bookmarkIdsQuery.isError ? bookmarkIdsQuery.refetch() : postsQuery.refetch())}>Try again</button>
        </div>}
        {!loading && !bookmarkIdsQuery.isError && !postsQuery.isError && posts.length === 0 && (
          <div className="flex flex-col items-center gap-3 px-6 py-24 text-center">
            <div className="flex h-14 w-14 items-center justify-center rounded-full bg-secondary">
              <Bookmark className="h-6 w-6 text-muted-foreground" />
            </div>
            <h2 className="font-display text-lg font-bold">Nothing saved yet</h2>
            <p className="max-w-xs text-sm text-muted-foreground">
              Tap the bookmark on any whisper to keep it here for later.
            </p>
          </div>
        )}

        {posts.map((post) => (
          <PostCard
            key={post.id}
            post={post}
            author={profiles[post.user_id]}
            liked={likedSet.has(post.id)}
            reposted={repostedSet.has(post.id)}
            bookmarked
          />
        ))}
      </div>
    </div>
  );
}
