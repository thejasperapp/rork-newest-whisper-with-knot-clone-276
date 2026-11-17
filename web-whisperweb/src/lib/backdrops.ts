/**
 * Shared meeting backdrops — the cloud library behind "Generate with Jasper".
 *
 * Generated virtual backgrounds upload to the public `meeting-backdrops`
 * bucket and are recorded in `whisper_meeting_backdrops`, so the SAME
 * library appears on every device — the web Backgrounds sheet and the iOS
 * effects sheet read one list. Requires supabase/meeting-backdrops.sql;
 * every call degrades gracefully (local-only mode) until it runs.
 */
import { supabase } from "@/lib/supabase";

export interface CloudBackdrop {
  id: string;
  user_id: string;
  url: string;
  prompt: string | null;
  created_at: string;
}

export interface CloudBackdropsResult {
  items: CloudBackdrop[];
  /** True when supabase/meeting-backdrops.sql hasn't been applied yet. */
  missing: boolean;
}

/** The signed-in user's synced backdrops, newest first. */
export async function fetchCloudBackdrops(): Promise<CloudBackdropsResult> {
  const { data, error } = await supabase
    .from("whisper_meeting_backdrops")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(12);
  if (error) {
    return { items: [], missing: error.code === "42P01" };
  }
  return { items: (data as CloudBackdrop[] | null) ?? [], missing: false };
}

function dataUrlToBlob(dataUrl: string): Blob | null {
  try {
    const [head, body] = dataUrl.split(",");
    if (!head || body === undefined) return null;
    const mime = /data:([^;]+)/.exec(head)?.[1] ?? "image/png";
    const bin = atob(body);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return new Blob([bytes], { type: mime });
  } catch {
    return null;
  }
}

/**
 * Persist a generated backdrop to the shared library. Data URLs upload to
 * storage first; already-hosted URLs are recorded directly. Returns the new
 * row, or null when the cloud isn't available (the local copy still works).
 */
export async function saveCloudBackdrop(
  userId: string,
  url: string,
  prompt?: string
): Promise<CloudBackdrop | null> {
  try {
    let publicUrl = url;
    if (url.startsWith("data:")) {
      const blob = dataUrlToBlob(url);
      if (!blob) return null;
      const ext = blob.type.includes("jpeg") ? "jpg" : "png";
      const path = `${userId}/${Date.now()}-backdrop.${ext}`;
      const { error: uploadError } = await supabase.storage
        .from("meeting-backdrops")
        .upload(path, blob, { contentType: blob.type, upsert: false });
      if (uploadError) return null;
      publicUrl = supabase.storage
        .from("meeting-backdrops")
        .getPublicUrl(path).data.publicUrl;
    }
    const { data, error } = await supabase
      .from("whisper_meeting_backdrops")
      .insert({
        user_id: userId,
        url: publicUrl,
        prompt: prompt?.slice(0, 300) ?? null,
      })
      .select()
      .limit(1);
    if (error) return null;
    return ((data as CloudBackdrop[] | null) ?? [])[0] ?? null;
  } catch {
    return null;
  }
}

/** Remove a backdrop from the shared library (+ best-effort storage file). */
export async function deleteCloudBackdrop(item: CloudBackdrop): Promise<void> {
  await supabase.from("whisper_meeting_backdrops").delete().eq("id", item.id);
  const marker = "/meeting-backdrops/";
  const index = item.url.indexOf(marker);
  if (index >= 0) {
    const path = decodeURIComponent(item.url.slice(index + marker.length));
    void supabase.storage.from("meeting-backdrops").remove([path]);
  }
}
