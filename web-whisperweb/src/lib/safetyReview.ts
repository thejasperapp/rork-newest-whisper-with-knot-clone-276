import { groupThemeSession } from "@/lib/groupThemeSession";
import { supabaseUrl, supabaseAnonKey } from "@/lib/supabase";

export interface Correction {
  id: string; report_id: string; post_id: string; author_id: string;
  reviewed_snapshot: { caption?: string; media_urls?: string[]; captured_at?: string };
  explanation: string; sources: string[]; state: "active" | "withdrawn"; updated_at: string;
}
export interface CorrectionAppeal { id: string; correction_id: string; body: string; status: string; outcome: string | null }
export interface ReviewReport { id: string; target_id: string; reason: string; details: string | null; post_snapshot: Correction["reviewed_snapshot"] | null; status: string }
export async function safetyRequest<T>(owner: string, path: string, body?: unknown, signal?: AbortSignal): Promise<T> {
  const session = await groupThemeSession(owner);
  try {
    session.check();
    const response = await fetch(`${supabaseUrl}/rest/v1/${path}`, {
      method: body === undefined ? "GET" : "POST", redirect: "error",
      signal: AbortSignal.any([session.signal, AbortSignal.timeout(15000), ...(signal ? [signal] : [])]),
      headers: { apikey: supabaseAnonKey, Authorization: `Bearer ${session.token}`, "Content-Type": "application/json" },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    session.check();
    if (!response.ok) throw new Error("The service could not confirm this request. Refresh and try again.");
    const result: unknown = await response.json(); session.check(); return result as T;
  } finally { session.dispose(); }
}
export function assertReceipt(value: unknown): asserts value is string {
  if (typeof value !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)) throw new Error("No confirmed receipt. Refresh before trying again.");
}
