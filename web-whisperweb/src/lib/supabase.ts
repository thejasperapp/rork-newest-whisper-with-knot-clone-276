import { createClient } from "@supabase/supabase-js";
import { sharedAuthStorage } from "./authStorage";

// Hardcoded fallbacks for the shared Whisper Supabase project. These keep the
// web app from hard-crashing at module load (createClient throws on an empty
// URL) if the .env file is ever missing or regenerated without these vars.
const FALLBACK_SUPABASE_URL = "https://uryyyegnbtlmyhqlgndy.supabase.co";
const FALLBACK_SUPABASE_ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVyeXl5ZWduYnRsbXlocWxnbmR5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUyMzM3MDcsImV4cCI6MjA5MDgwOTcwN30.fBo6K9yNHmk1nTArspc5ByMsWEiI2SahCFk6Mdp7qUQ";

export const supabaseUrl: string =
  (import.meta.env.EXPO_PUBLIC_SUPABASE_URL as string | undefined) ||
  FALLBACK_SUPABASE_URL;
export const supabaseAnonKey: string =
  (import.meta.env.EXPO_PUBLIC_SUPABASE_ANON_KEY as string | undefined) ||
  FALLBACK_SUPABASE_ANON_KEY;

/** The storage key the auth client persists its session under (shared so the
 *  account switcher can park a login WITHOUT a server sign-out). */
export const AUTH_STORAGE_KEY = "whisper-web-auth";

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
    storageKey: AUTH_STORAGE_KEY,
    // ONE login for every door: the session rides a cookie shared across
    // mydailywhisper.com and all portal subdomains (workspace. · meet. ·
    // coaches. · recruiters. · business. · ads. · brands.) instead of being
    // trapped in each origin's private localStorage.
    storage: sharedAuthStorage,
  },
});

export const MEDIA_BUCKET = "whisper-media";

/** Public URL for a file stored in the shared media bucket. */
export function mediaPublicUrl(path: string): string {
  return supabase.storage.from(MEDIA_BUCKET).getPublicUrl(path).data.publicUrl;
}
