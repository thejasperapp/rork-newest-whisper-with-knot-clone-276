import { afterEach, describe, expect, it, vi } from "vitest";
vi.mock("@/lib/groupThemeSession", () => ({ groupThemeSession: vi.fn() }));
import { saveWallpaper } from "./chatWallpapers";

afterEach(() => vi.unstubAllGlobals());
describe("cancelled wallpaper persistence", () => {
  it("does not start a transaction when scope expires while the database opens", async () => {
    const db = { transaction: vi.fn(), close: vi.fn() };
    const request: { result: typeof db; onsuccess?: () => void } = { result: db };
    vi.stubGlobal("indexedDB", { open: () => request });
    let valid = true;
    const save = saveWallpaper("owner:thread", null, () => { if (!valid) throw new Error("Scope changed"); }, new AbortController().signal);
    valid = false; request.onsuccess?.();
    await expect(save).rejects.toThrow("Scope changed");
    expect(db.transaction).not.toHaveBeenCalled(); expect(db.close).toHaveBeenCalledOnce();
  });
  it("does not start a transaction after cancellation", async () => {
    const db = { transaction: vi.fn(), close: vi.fn() };
    const request: { result: typeof db; onsuccess?: () => void } = { result: db };
    vi.stubGlobal("indexedDB", { open: () => request });
    const controller = new AbortController();
    const save = saveWallpaper("owner:thread", null, () => {}, controller.signal);
    controller.abort(); request.onsuccess?.();
    await expect(save).rejects.toThrow("cancelled");
    expect(db.transaction).not.toHaveBeenCalled();
  });
});
