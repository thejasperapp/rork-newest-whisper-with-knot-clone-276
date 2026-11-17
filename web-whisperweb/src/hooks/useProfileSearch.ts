import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { searchProfiles } from "@/lib/api";

/** Change the key immediately so typing never shows the previous term's people.
 * Only start the request once typing settles; consuming the signal also aborts
 * the old request on a new term, closing the picker, or changing accounts. */
export function useProfileSearch(owner: string | undefined, input: string, enabled = true) {
  const term = input.trim();
  const [settledTerm, setSettledTerm] = useState("");
  useEffect(() => {
    const timer = window.setTimeout(() => setSettledTerm(term), 250);
    return () => window.clearTimeout(timer);
  }, [term]);
  const eligible = enabled && !!owner && term.length > 0 && !term.startsWith("#");
  const waiting = eligible && term !== settledTerm;
  const query = useQuery({
    queryKey: ["profile-search", owner, eligible ? term : ""],
    queryFn: ({ signal }) => searchProfiles(term, signal),
    enabled: eligible && !waiting,
    staleTime: 30_000,
    gcTime: 5 * 60_000,
    retry: 1,
  });
  return { ...query, data: eligible && !waiting ? query.data : undefined, isWaiting: waiting,
    isSearching: eligible && (waiting || query.isLoading),
    // Do not surface a cached failure belonging to an unsettled/closed search.
    isError: eligible && !waiting && query.isError };
}
