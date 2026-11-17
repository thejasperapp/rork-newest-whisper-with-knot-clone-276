import { supabase } from "@/lib/supabase";

/** Per-operation epoch invalidates A→B→A as well as a simple switch. */
export async function groupThemeSession(accountID: string) {
  const controller = new AbortController();
  let changed = false;
  const { data } = supabase.auth.onAuthStateChange((_event, session) => {
    if (session?.user.id !== accountID) { changed = true; controller.abort(); }
  });
  const check = (): void => { if (changed) throw new Error("Your account changed. Reopen this group to continue."); };
  try {
    const { data: result, error } = await supabase.auth.getSession();
    check();
    if (error || result.session?.user.id !== accountID) throw new Error("Sign in again to continue.");
    return { token: result.session.access_token, signal: controller.signal, check, dispose: () => data.subscription.unsubscribe() };
  } catch (error) { data.subscription.unsubscribe(); throw error; }
}
