import { afterEach, describe, expect, it } from "vitest";
import { localShareStage, readMeetingStage } from "./meetingStageCapture";
function box(element: HTMLElement, x: number, y: number, w: number, h: number): void { element.getBoundingClientRect = () => ({ x, y, left: x, top: y, width: w, height: h, right: x + w, bottom: y + h, toJSON: () => ({}) }); }
function fixture(): { root: HTMLDivElement; stage: HTMLElement; tile: HTMLElement } {
  const root = document.createElement("div"); root.innerHTML = '<main data-recording-stage><div data-recording-peer="visible" data-recording-fit="contain" data-recording-focused="true" style="border-radius:18px">Public name</div></main><aside><div data-recording-peer="private">PRIVATE NOTE</div></aside>';
  document.body.append(root); const stage = root.querySelector("main")!, tile = stage.querySelector("div")!;
  box(root, 0, 0, 1000, 700); box(stage, 0, 0, 1000, 600); box(tile, 10, 30, 600, 400); return { root, stage, tile };
}
afterEach(() => document.body.replaceChildren());
describe("allowlisted recording stage geometry", () => {
  it("uses the live tile position, fit and focus without reading private panels or text", () => {
    const { root } = fixture(), snapshot = readMeetingStage(root)!;
    expect(snapshot.cells).toHaveLength(1); expect(snapshot.cells[0]).toMatchObject({ id: "visible", x: 10, y: 30, w: 600, h: 400, fit: "contain", focused: true, radius: 18 });
    expect(JSON.stringify(snapshot)).not.toContain("PRIVATE"); expect(JSON.stringify(snapshot)).not.toContain("Public name");
  });
  it("subtracts control/sidebar space and clips partially visible filmstrip tiles", () => {
    const { root, stage, tile } = fixture(); stage.style.padding = "60px 300px 90px 10px"; box(tile, -30, 50, 800, 500);
    const snapshot = readMeetingStage(root)!; expect(snapshot.width).toBe(690); expect(snapshot.height).toBe(450);
    expect(snapshot.cells[0].clip).toEqual({ x: 0, y: 0, w: 690, h: 450 });
  });
  it("excludes hidden and paginated-out tiles but includes the explicitly marked self dock", () => {
    const { root, tile } = fixture(); tile.style.visibility = "hidden";
    const dock = document.createElement("div"); dock.dataset.recordingDock = ""; const self = document.createElement("div"); self.dataset.recordingPeer = "self"; dock.append(self); root.append(dock); box(dock, 800, 400, 120, 90); box(self, 800, 400, 120, 90);
    expect(readMeetingStage(root)?.cells.map((cell) => cell.id)).toEqual(["self"]);
    box(self, 1001, 400, 120, 90); expect(readMeetingStage(root)?.cells).toEqual([]);
  });
  it("keeps the full viewport dock on ultrawide displays without expanding main-stage clipping", () => {
    const { root, stage, tile } = fixture(); box(root, 0, 0, 2560, 1440); box(stage, 400, 0, 1760, 1340); box(tile, 410, 50, 1700, 1000);
    const dock = document.createElement("div"); dock.dataset.recordingDock = ""; dock.innerHTML = '<div data-recording-peer="self"></div>'; root.append(dock); box(dock, 2356, 1000, 172, 230); box(dock.firstElementChild as HTMLElement, 2356, 1000, 172, 230);
    const result = readMeetingStage(root)!; expect(result.width).toBe(2128); expect(result.cells[1].clip.w).toBe(172); expect(result.cells[0].clip.w).toBe(1700);
  });
  it("does not sample an invisible or minimized meeting", () => { const { root, stage } = fixture(); stage.style.opacity = "0"; expect(readMeetingStage(root)?.cells).toEqual([]); stage.style.opacity = "1"; root.style.visibility = "hidden"; expect(readMeetingStage(root)).toBeNull(); });
  it("only adds the local shared source; other participants remain allowlisted with their crop and clipping", () => {
    const { root } = fixture(); const stage = readMeetingStage(root)!, share = localShareStage(stage, "self");
    expect(share.cells.map((cell) => cell.id)).toEqual(["self", "visible"]); expect(share.cells[0].fit).toBe("contain"); expect(share.cells[0].w).toBeGreaterThan(share.width * 0.7);
    expect(share.cells[1].fit).toBe(stage.cells[0].fit); expect(share.cells[1].clip.w / share.cells[1].w).toBeCloseTo(stage.cells[0].clip.w / stage.cells[0].w);
    expect(localShareStage({ ...stage, cells: [] }, "self").cells[0].w).toBe(stage.width);
  });
  it("returns no layout once the stage is gone", () => { const { root } = fixture(); root.remove(); expect(readMeetingStage(root)).toBeNull(); expect(readMeetingStage(null)).toBeNull(); });
});
