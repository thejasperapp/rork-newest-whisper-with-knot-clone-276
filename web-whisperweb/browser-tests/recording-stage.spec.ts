import { expect, test } from "@playwright/test";

test("recorded canvas follows live order, framing, pin/resize, page changes and excludes private overlays", async ({ page }) => {
  await page.route("**/stage-harness", (route) => route.fulfill({ contentType: "text/html", body: "<!doctype html><html><body></body></html>" }));
  await page.goto("/stage-harness");
  const result = await page.evaluate(async () => {
    const path = "/src/lib/meetPipMosaic.ts", geometryPath = "/src/lib/meetingStageCapture.ts";
    const { MeetPipMosaic } = await import(path) as typeof import("../src/lib/meetPipMosaic");
    const { readMeetingStage } = await import(geometryPath) as typeof import("../src/lib/meetingStageCapture");
    const root = document.createElement("div"); root.style.cssText = "position:fixed;inset:0;background:#202124";
    root.innerHTML = '<main data-recording-stage style="position:absolute;left:0;top:0;width:800px;height:400px"><div data-recording-peer="remote" data-recording-fit="cover" style="position:absolute;left:0;top:0;width:400px;height:400px"></div><div data-recording-peer="self" data-recording-fit="cover" style="position:absolute;left:400px;top:0;width:400px;height:400px"></div></main><aside style="position:absolute;inset:0;background:magenta">PRIVATE NOTES AND JASPER</aside>';
    document.body.append(root);
    const stripes = document.createElement("canvas"); stripes.width = 160; stripes.height = 80; const stripeContext = stripes.getContext("2d")!;
    stripeContext.fillStyle = "red"; stripeContext.fillRect(0, 0, 80, 80); stripeContext.fillStyle = "blue"; stripeContext.fillRect(80, 0, 80, 80);
    const green = document.createElement("canvas"); green.width = 160; green.height = 80; const greenContext = green.getContext("2d")!; greenContext.fillStyle = "lime"; greenContext.fillRect(0, 0, 160, 80);
    const localStream = stripes.captureStream(12), remoteStream = green.captureStream(12);
    const sources = [{ id: "self", name: "Me", stream: localStream, hasVideo: true, isSelf: true, isScreenShare: false, isSpeaking: false, micOn: true }, { id: "remote", name: "Guest", stream: remoteStream, hasVideo: true, isSelf: false, isScreenShare: false, isSpeaking: false, micOn: true }];
    const mosaic = new MeetPipMosaic(800, 400, true); mosaic.stageSnapshot = () => readMeetingStage(root); mosaic.update(sources); mosaic.start();
    const ctx = mosaic.canvas.getContext("2d")!; const pixel = (x: number, y: number): number[] => [...ctx.getImageData(x, y, 1, 1).data].slice(0, 3);
    const tick = async (): Promise<void> => { await new Promise((resolve) => setTimeout(resolve, 350)); };
    await tick(); const grid = [pixel(200, 150), pixel(450, 150), pixel(750, 150)];
    const self = root.querySelector<HTMLElement>('[data-recording-peer="self"]')!, remote = root.querySelector<HTMLElement>('[data-recording-peer="remote"]')!;
    self.style.cssText = "position:absolute;left:0;top:0;width:800px;height:400px"; self.dataset.recordingFit = "contain"; remote.style.display = "none";
    await tick(); const pin = [pixel(200, 150), pixel(600, 150)];
    self.dataset.recordingFit = "cover"; mosaic.update([{ ...sources[0], isScreenShare: true }, sources[1]]);
    await tick(); const share = [pixel(200, 150), pixel(600, 150)];
    self.style.display = "none"; remote.style.cssText = "position:absolute;left:0;top:0;width:800px;height:400px";
    mosaic.update(sources); await tick(); const nextPage = pixel(200, 150);
    mosaic.update([{ ...sources[0], hasVideo: false }, { ...sources[1], hasVideo: false }]); await tick(); const cameraOff = pixel(200, 150);
    root.remove(); await tick(); const missingStage = pixel(200, 150);
    mosaic.dispose(); const states = [...localStream.getTracks(), ...remoteStream.getTracks()].map((track) => track.readyState);
    [...localStream.getTracks(), ...remoteStream.getTracks()].forEach((track) => track.stop());
    return { grid, pin, share, nextPage, cameraOff, missingStage, states };
  });
  expect(result.grid).toEqual([[0, 255, 0], [0, 0, 255], [255, 0, 0]]);
  expect(result.pin).toEqual([[0, 0, 255], [255, 0, 0]]);
  // Local presentation intentionally uses the full shared source rather than the presenter's placeholder.
  expect(result.share[0]).toEqual([255, 0, 0]);
  expect(result.nextPage).toEqual([0, 255, 0]); expect(result.cameraOff).not.toEqual([0, 255, 0]);
  expect(result.missingStage).toEqual([7, 7, 7]); expect(result.states).toEqual(["live", "live"]);
});
