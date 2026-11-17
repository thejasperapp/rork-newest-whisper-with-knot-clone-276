import { expect, test } from "@playwright/test";

for (const asPanel of [false, true]) for (const fullscreen of [false, true]) {
  test(`recording ${asPanel ? "activity panel" : "dialog"} is clickable ${fullscreen ? "inside fullscreen" : "above the live meeting"} and Start → consent → Stop saves without ending camera`, async ({ page }) => {
    const errors: string[] = []; page.on("pageerror", (error) => errors.push(error.message));
    await page.route(/\/recording-controls-harness(?:\?.*)?$/, (route) => route.fulfill({ contentType: "text/html", body: `<!doctype html><html><body><div id="root"></div><script type="module">import RefreshRuntime from '/@react-refresh'; RefreshRuntime.injectIntoGlobalHook(window); window.$RefreshReg$ = () => {}; window.$RefreshSig$ = () => (type) => type; window.__vite_plugin_react_preamble_installed__ = true;</script><script type="module" src="/@vite/client"></script><script type="module" src="/browser-tests/recording-controls-harness.tsx"></script></body></html>` }));
    await page.goto(`/recording-controls-harness${asPanel ? "?activities=1" : ""}`);
    await expect(page.getByRole("button", { name: asPanel ? "Activities" : "Record meeting", exact: true })).toBeVisible();
    if (fullscreen) { await page.getByRole("button", { name: "Full screen", exact: true }).click(); await expect.poll(() => page.evaluate(() => !!document.fullscreenElement)).toBe(true); }
    if (asPanel) { await page.getByRole("button", { name: "Activities", exact: true }).click(); await page.getByRole("button", { name: /Recording Record meetings/ }).click(); }
    else await page.getByRole("button", { name: "Record meeting", exact: true }).click();
    const dialog = page.getByRole(asPanel ? "region" : "dialog", { name: "Recording", exact: true });
    await expect(dialog).toBeVisible();
    if (asPanel) {
      await dialog.getByRole("button", { name: "Back to tools" }).click();
      await expect(page.getByRole("region", { name: "Tools", exact: true })).toBeVisible();
      await page.getByRole("button", { name: /Recording Record meetings/ }).click();
      if (!fullscreen) {
        await page.getByRole("button", { name: "Full screen", exact: true }).click();
        await expect(dialog.getByRole("button", { name: "Close recording" })).toBeFocused();
        await page.evaluate(() => document.exitFullscreen());
        await expect.poll(() => page.evaluate(() => document.fullscreenElement === null)).toBe(true);
        await expect(dialog.getByRole("button", { name: "Close recording" })).toBeFocused();
        await page.keyboard.press("Escape"); await expect(dialog).not.toBeVisible();
        await expect(page.getByRole("button", { name: "Activities", exact: true })).toBeFocused();
        await page.getByRole("button", { name: "Activities", exact: true }).click();
        await page.getByRole("button", { name: /Recording Record meetings/ }).click();
      }
    }
    expect(await dialog.evaluate((element) => Number(getComputedStyle(element).zIndex))).toBeGreaterThan(60);
    if (fullscreen) expect(await dialog.evaluate((element) => document.fullscreenElement?.contains(element))).toBe(true);
    await dialog.getByRole("button", { name: "Start recording", exact: true }).click();
    await expect(page.getByText("Waiting for everyone’s permission", { exact: true })).toBeVisible();
    expect(await page.evaluate(() => window.recordingHarness.recordedCount())).toBe(0);
    await page.evaluate(() => window.recordingHarness.approve());
    await expect(page.getByRole("button", { name: /^REC ·/ })).toBeVisible();
    await expect(dialog).not.toBeVisible();
    const liveVideo = page.getByLabel("Live meeting camera");
    expect(await liveVideo.evaluate((element) => ({ controls: (element as HTMLVideoElement).controls, muted: (element as HTMLVideoElement).muted }))).toEqual({ controls: false, muted: true });
    await page.waitForTimeout(1300);
    await page.getByRole("button", { name: "Stop recording", exact: true }).click();
    await expect(page.getByRole("dialog", { name: "Stop recording?" })).toBeVisible();
    await page.getByRole("button", { name: "Keep recording" }).click();
    await expect(page.getByRole("button", { name: /^REC ·/ })).toBeVisible();
    await page.getByRole("button", { name: "Stop recording", exact: true }).click();
    await page.getByRole("button", { name: "Stop and save" }).click();
    await expect(page.getByRole("status").filter({ hasText: "Recording saved to this meeting’s notes in this browser" })).toBeVisible({ timeout: 12000 });
    await dialog.getByRole("button", { name: asPanel ? "Close recording" : "Close", exact: true }).click();
    await expect(page.getByRole("link", { name: "Recording saved · Open" })).toBeVisible();
    expect(await page.evaluate(() => window.recordingHarness.recordedCount())).toBe(1);
    expect(await page.evaluate(() => window.recordingHarness.trackStates())).toEqual(["live", "live", "live"]);
    expect(errors).toEqual([]);
  });
}
