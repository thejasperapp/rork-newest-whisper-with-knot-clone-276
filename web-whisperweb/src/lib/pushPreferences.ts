import { z } from "zod";
import { groupThemeSession } from "./groupThemeSession";
import { supabaseUrl, supabaseAnonKey } from "./supabase";
export const pushFields = ["master_enabled","quiet_mode","dms","mentions","likes","comments","follows","story_responses","new_posts"] as const;
export type PushField = typeof pushFields[number];
export type PushPreferences = Partial<Record<PushField, boolean>>;
/** Current-account transport; no redirects, silent writes, or optimistic consent. */
export async function pushPreferenceRequest(owner: string, patch?: { field: PushField; value: boolean }): Promise<PushPreferences> {
  const session = await groupThemeSession(owner);
  try {
    const headers = { apikey: supabaseAnonKey, Authorization: `Bearer ${session.token}`, "Content-Type":"application/json" };
    const signal = AbortSignal.any([session.signal,AbortSignal.timeout(15_000)]);
    if (patch) {
      const newPosts = patch.field === "new_posts";
      const result = await fetch(`${supabaseUrl}/rest/v1/rpc/${newPosts ? "whisper_new_post_preference" : "whisper_update_push_preferences"}`, { method:"POST",headers,signal,redirect:"error",cache:"no-store",body:JSON.stringify(newPosts ? {p_owner:owner,p_enabled:patch.value} : {p_owner:owner,p_patch:{[patch.field]:patch.value}}) });
      session.check();
      if (!result.ok) throw new Error("That preference wasn't confirmed. Refresh and try again.");
      const saved: unknown = await result.json();session.check();
      if (!saved || typeof saved !== "object" || (saved as Record<string,unknown>)[patch.field] !== patch.value) throw new Error("That preference wasn't confirmed. Refresh before retrying.");
    }
    const params = new URLSearchParams({user_id:`eq.${owner}`,select:"*"});
    const result = await fetch(`${supabaseUrl}/rest/v1/whisper_notification_prefs?${params}`,{headers,signal,redirect:"error",cache:"no-store"});session.check();
    if (!result.ok) throw new Error("Couldn't load notification preferences.");
    const rows=z.array(z.object({user_id:z.string().uuid()}).passthrough()).max(1).parse(await result.json());session.check();
    if(rows[0] && rows[0].user_id.toLowerCase()!==owner.toLowerCase()) throw new Error("The account changed. Please reopen settings.");
    const prefs:PushPreferences={};
    for(const key of pushFields){const value=rows[0]?.[key];if(typeof value === "boolean")prefs[key]=value;else if(value!==undefined)throw new Error("Couldn't verify notification preferences.");}
    return prefs;
  } finally {session.dispose();}
}
