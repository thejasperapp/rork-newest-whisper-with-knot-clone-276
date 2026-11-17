import { groupThemeSession } from "@/lib/groupThemeSession";

const databaseName = "whisper-personal-wallpapers-v1";
export const appearanceEvent = "whisper-chat-appearance";
export const appearanceKey = (accountID: string, thread: string): string => `whisper-appearance:${accountID.toLowerCase()}:${thread.toLowerCase()}`;

/** Owner-qualified local blobs; no public bucket, signed URL, or prompt persistence. */
async function database(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(databaseName, 1);
    request.onupgradeneeded = () => request.result.createObjectStore("wallpapers");
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(new Error("Browser storage is unavailable."));
    request.onblocked = () => reject(new Error("Close other Whisper tabs and try again."));
  });
}

export async function readWallpaper(key: string): Promise<Blob | null> {
  const db = await database();
  try {
    return await new Promise((resolve, reject) => {
      const transaction = db.transaction("wallpapers", "readonly");
      const request = transaction.objectStore("wallpapers").get(key);
      request.onsuccess = () => resolve(request.result instanceof Blob ? request.result : null);
      request.onerror = () => reject(new Error("Couldn't read this wallpaper."));
    });
  } finally { db.close(); }
}

export async function saveWallpaper(key: string, blob: Blob | null, check: () => void, signal: AbortSignal): Promise<void> {
  if (blob && (blob.size > 1_500_000 || blob.type !== "image/jpeg")) throw new Error("This wallpaper is too large to save.");
  const db = await database();
  try {
    check();
    if (signal.aborted) throw new Error("Wallpaper save cancelled.");
    await new Promise<void>((resolve, reject) => {
      const transaction = db.transaction("wallpapers", "readwrite");
      const abort = (): void => { try { transaction.abort(); } catch { /* Already completed. */ } };
      const cleanup = (): void => signal.removeEventListener("abort", abort);
      signal.addEventListener("abort", abort);
      transaction.oncomplete = () => { cleanup(); resolve(); };
      transaction.onerror = () => { cleanup(); reject(new Error("Couldn't save locally. Free some browser storage and retry.")); };
      transaction.onabort = () => { cleanup(); reject(new Error("Wallpaper save interrupted.")); };
      check();
      if (signal.aborted) { abort(); return; }
      if (blob) transaction.objectStore("wallpapers").put(blob, key);
      else transaction.objectStore("wallpapers").delete(key);
    });
    check();
    window.dispatchEvent(new Event(appearanceEvent));
  } finally { db.close(); }
}

/** Uses the same GPT Image 2 model as iOS; the browser runtime supplies delegated proxy authentication. */
export async function generateWallpaper(accountID: string, brief: string, signal: AbortSignal): Promise<Blob> {
  if (!brief.trim() || brief.length > 400) throw new Error("Describe your wallpaper in 400 characters or fewer.");
  const session = await groupThemeSession(accountID);
  const controller = new AbortController();
  const abort = (): void => controller.abort();
  const timer = window.setTimeout(abort, 120_000);
  signal.addEventListener("abort", abort); session.signal.addEventListener("abort", abort);
  try {
    if (signal.aborted || session.signal.aborted) throw new Error("Generation cancelled.");
    const base = String(import.meta.env.VITE_TOOLKIT_URL ?? "https://toolkit.rork.com").replace(/\/$/, "");
    const response = await fetch(`${base}/v2/vercel/v3/ai/image-model`, {
      method: "POST", signal: controller.signal,
      headers: { "Content-Type": "application/json", "ai-gateway-protocol-version": "0.0.1", "ai-image-model-specification-version": "4", "ai-model-id": "openai/gpt-image-2" },
      body: JSON.stringify({ model: "openai/gpt-image-2", n: 1, size: "1024x1536", providerOptions: {}, prompt: `Create an original elegant chat wallpaper, quiet negative space in the center for readable messages, soft dimensional materials, diffused lighting, no text, no letters, no UI. Design brief: ${brief.trim()}` }),
    });
    session.check();
    if (!response.ok) throw new Error(response.status === 429 ? "Image generation is busy. Try again shortly." : "Couldn't generate a wallpaper. Your background is unchanged.");
    const result: unknown = await response.json();
    const images = result && typeof result === "object" ? (result as Record<string, unknown>).images : null;
    if (!Array.isArray(images) || typeof images[0] !== "string" || images[0].length > 28_000_000) throw new Error("Couldn't read the generated image.");
    const binary = atob(images[0]);
    const bytes = Uint8Array.from(binary, char => char.charCodeAt(0));
    const bitmap = await createImageBitmap(new Blob([bytes]));
    try {
      const scale = Math.min(1, 1536 / Math.max(bitmap.width, bitmap.height));
      const canvas = document.createElement("canvas");
      canvas.width = Math.round(bitmap.width * scale); canvas.height = Math.round(bitmap.height * scale);
      const context = canvas.getContext("2d");
      if (!context) throw new Error("Image preview isn't supported in this browser.");
      context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
      const blob = await new Promise<Blob | null>(resolve => canvas.toBlob(resolve, "image/jpeg", 0.78));
      session.check();
      if (controller.signal.aborted) throw new Error("Generation cancelled.");
      if (!blob || blob.size > 1_500_000) throw new Error("This wallpaper is too large. Try a simpler scene.");
      return blob;
    } finally { bitmap.close(); }
  } finally {
    clearTimeout(timer); session.dispose(); signal.removeEventListener("abort", abort); session.signal.removeEventListener("abort", abort);
  }
}
