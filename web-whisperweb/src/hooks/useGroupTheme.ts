import { useEffect } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/lib/supabase";
import { loadGroupTheme } from "@/lib/groupThemes";

export function useGroupTheme(groupID: string, accountID: string) {
  const queryClient = useQueryClient();
  const query = useQuery({ queryKey: ["group-theme", accountID, groupID], queryFn: () => loadGroupTheme(groupID, accountID), refetchInterval: 6000, staleTime: 1000 });
  useEffect(() => {
    const channel = supabase.channel(`group-theme-${accountID}-${groupID}-${crypto.randomUUID()}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "whisper_group_themes", filter: `group_id=eq.${groupID}` }, () => { void queryClient.invalidateQueries({ queryKey: ["group-theme", accountID, groupID] }); }).subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, [accountID, groupID, queryClient]);
  return query;
}
