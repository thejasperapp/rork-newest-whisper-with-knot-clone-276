// Read-only local browser inspection of one immutable synthetic captured HTML.
// No private-site access, artifact editing, new authoring, admission or replay.
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';
const [outcomeFile, output] = process.argv.slice(2);
if (!outcomeFile || !output || existsSync(output)) throw new Error('new_inspection_output_required');
const outcome = JSON.parse(readFileSync(outcomeFile, 'utf8'));
if (!outcome.syntheticOnly || !outcome.automatedChecksPassed || outcome.document?.format !== 'html') throw new Error('verified_synthetic_html_required');
const source = resolve(outcome.document.originalPath), bytes = readFileSync(source);
const sha256 = createHash('sha256').update(bytes).digest('hex');
if (sha256 !== outcome.document.sha256) throw new Error('immutable_file_changed');
mkdirSync(output, { recursive: false });
const { chromium } = await import('/usr/local/lib/node_modules/playwright/index.mjs');
const browser = await chromium.launch();
const result = { sourceOutcome: outcomeFile, taskID: outcome.taskID, sha256, syntheticOnly: true, originalOutcomeUnchanged: true, whisperUIExercised: false, viewports: [] };
try {
  for (const viewport of [{ width: 390, height: 844 }, { width: 1280, height: 800 }]) {
    const context = await browser.newContext({ viewport, javaScriptEnabled: false });
    const networkRequests = [], pageErrors = [];
    await context.route(/^https?:/, route => { networkRequests.push(route.request().url()); return route.abort(); });
    const page = await context.newPage();
    page.on('pageerror', error => pageErrors.push(error.name));
    await page.goto(pathToFileURL(source).href, { waitUntil: 'load' });
    const text = await page.locator('body').innerText();
    if (!/Balcony Herb Plan/i.test(text) || !['basil', 'mint', 'water', 'harvest'].every(word => text.toLowerCase().includes(word))) throw new Error('visible_content_missing');
    const metrics = await page.evaluate(() => ({ horizontalOverflow: document.documentElement.scrollWidth > innerWidth, height: document.documentElement.scrollHeight }));
    const fullScreenshot = join(output, 'html-' + viewport.width + '-full.png');
    await page.screenshot({ path: fullScreenshot, fullPage: true });
    await page.mouse.wheel(0, metrics.height);
    await page.waitForFunction(() => scrollY + innerHeight >= document.documentElement.scrollHeight - 2);
    const endScreenshot = join(output, 'html-' + viewport.width + '-end.png');
    await page.screenshot({ path: endScreenshot });
    result.viewports.push({ viewport, ...metrics, fullScreenshot, endScreenshot, actualEndScroll: true, pageErrors, blockedNetworkRequests: networkRequests.length, text, scriptsDisabled: true });
    await context.close();
  }
  result.loadedAndScrolled = true;
  result.visualReview = 'pending';
} finally {
  await browser.close();
  writeFileSync(join(output, 'browser-inspection.json'), JSON.stringify(result, null, 2) + '\n', { flag: 'wx' });
}
console.log(JSON.stringify(result));
