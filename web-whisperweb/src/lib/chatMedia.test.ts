import { describe, expect, it, vi } from "vitest";

vi.mock("@/lib/supabase", () => ({ supabase: { auth: { getSession: vi.fn(async () => ({ data: { session: { user: { id: "viewer" } } } })) } } }));
vi.mock("@/lib/api", () => ({ uploadMedia: vi.fn(async () => "https://media.example/photo.jpg") }));

import { chatVideoUrl, uploadChatMedia } from "./chatMedia";
import { uploadMedia } from "./api";

describe("chat attachment wire", () => {
  it.each(["mp4", "MOV", "m4v", "webm", "m3u8"])("recognizes a bare %s URL with a query", (extension) => {
    const url = `https://media.example/clip.${extension}?download=1`;
    expect(chatVideoUrl(url)).toBe(url);
  });
  it.each(["javascript:clip.mp4", "https://media.example/photo.jpg", "watch https://media.example/a.mp4", "", "https://media.example/a.mp4\ncaption"])("rejects non-video bodies", (body) => {
    expect(chatVideoUrl(body)).toBeNull();
  });
  it("rejects oversized attachments before uploading", async () => {
    const file = new File(["x"], "large.mp4", { type: "video/mp4" });
    Object.defineProperty(file, "size", { value: 51 * 1024 * 1024 });
    await expect(uploadChatMedia(file, "viewer")).rejects.toThrow("50 MB");
  });
  it("does not upload when an operation has been invalidated", async () => {
    vi.mocked(uploadMedia).mockClear();
    await expect(uploadChatMedia(new File(["x"], "photo.jpg", { type: "image/jpeg" }), "viewer", () => { throw new Error("Conversation changed"); })).rejects.toThrow("Conversation changed");
    expect(uploadMedia).not.toHaveBeenCalled();
  });
  it("checks the operation again after upload", async () => {
    let valid = true;
    vi.mocked(uploadMedia).mockImplementationOnce(async () => { valid = false; return "https://media.example/photo.jpg"; });
    await expect(uploadChatMedia(new File(["x"], "photo.jpg", { type: "image/jpeg" }), "viewer", () => { if (!valid) throw new Error("Conversation changed"); })).rejects.toThrow("Conversation changed");
  });
});
