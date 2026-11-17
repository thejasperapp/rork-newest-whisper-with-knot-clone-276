import { supabase } from "@/lib/supabase";
import { uploadMedia } from "@/lib/api";

/** Bare video URLs share the existing attachment wire with iOS. */
export function chatVideoUrl(body: string | null | undefined): string | null {
  const text = (body ?? "").trim();
  if (!/^https?:\/\/\S+$/i.test(text)) return null;
  try {
    const url = new URL(text);
    return /\.(mp4|mov|m4v|webm|m3u8)$/i.test(url.pathname) ? text : null;
  } catch { return null; }
}

/** Validates before upload; rejects unsupported formats instead of sending broken image URLs. */
export async function uploadChatMedia(file: File, userId: string, assertCurrent: () => void = () => {}): Promise<string> {
  assertCurrent();
  if (!file.size || file.size > 50 * 1024 * 1024) throw new Error("Choose an attachment under 50 MB.");
  const isVideo = file.type.startsWith("video/");
  if (isVideo) {
    if (!/\.(mp4|mov|m4v|webm)$/i.test(file.name)) throw new Error("Choose an MP4, MOV, M4V or WebM video.");
    await new Promise<void>((resolve, reject) => {
      const video = document.createElement("video");
      const url = URL.createObjectURL(file);
      const cleanup = (): void => { clearTimeout(timer); video.onloadedmetadata = null; video.onerror = null; video.removeAttribute("src"); video.load(); URL.revokeObjectURL(url); };
      const timer = window.setTimeout(() => { cleanup(); reject(new Error("Couldn't read this video. Try an H.264 MP4.")); }, 15000);
      video.preload = "metadata";
      video.onloadedmetadata = () => {
        const valid = Number.isFinite(video.duration) && video.duration > 0 && video.duration <= 180;
        cleanup();
        if (valid) resolve(); else reject(new Error("Choose a video up to 3 minutes long."));
      };
      video.onerror = () => { cleanup(); reject(new Error("Couldn't read this video. Try an H.264 MP4.")); };
      video.src = url;
    });
  } else if (!/^image\/(jpeg|png|gif|webp|heic|heif)$/i.test(file.type)) {
    throw new Error("Choose a photo or video.");
  }
  const { data } = await supabase.auth.getSession();
  assertCurrent();
  if (data.session?.user.id !== userId) throw new Error("Your account changed. Reopen the conversation.");
  let url: string;
  try { url = await uploadMedia(file, userId); }
  catch { throw new Error("Couldn't upload this attachment. Please try again."); }
  const current = await supabase.auth.getSession();
  assertCurrent();
  if (current.data.session?.user.id !== userId) throw new Error("Your account changed. The attachment was not sent.");
  return url;
}
