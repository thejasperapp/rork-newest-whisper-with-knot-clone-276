import { useCallback, useEffect, useRef } from "react";
import { supabase } from "@/lib/supabase";

/** Invalidates a pending attachment after account/thread changes, including switch-away-and-back. */
export function useChatOperationGuard(userId: string, threadId: string): () => () => void {
  const generation = useRef<number>(0);
  const identity = useRef<string>(`${userId}:${threadId}`);
  identity.current = `${userId}:${threadId}`;
  useEffect(() => {
    ++generation.current;
    const { data } = supabase.auth.onAuthStateChange((_event, session) => {
      if (session?.user.id !== userId) ++generation.current;
    });
    return () => { ++generation.current; data.subscription.unsubscribe(); };
  }, [userId, threadId]);
  return useCallback(() => {
    const started = generation.current;
    const expected = `${userId}:${threadId}`;
    return () => {
      if (generation.current !== started || identity.current !== expected) throw new Error("Your account or conversation changed. The attachment was not sent.");
    };
  }, [userId, threadId]);
}
