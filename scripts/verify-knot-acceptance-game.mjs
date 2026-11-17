// Manual browser observation of an immutable, already-downloaded acceptance artifact.
// No app login, remote requests, altered clocks/randomness, source mutation or shell replay.
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { pathToFileURL } from 'node:url';
import { chromium } from '/usr/local/lib/node_modules/playwright/index.mjs';

const [battery, artifact, expectedHash] = process.argv.slice(2);
if (!/^battery-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-\d{3}Z$/.test(battery ?? '') || !/^[a-f0-9]{64}\.html$/.test(artifact ?? '') || !/^[a-f0-9]{64}$/.test(expectedHash ?? '')) throw new Error('explicit_acceptance_artifact_required');
const source = join(tmpdir(), 'knot-acceptance-uf26aun6d49w1tsjsm2u9', battery, 'battle-game', artifact);
const sha = () => createHash('sha256').update(readFileSync(source)).digest('hex');
if (sha() !== expectedHash) throw new Error('artifact_hash_mismatch');
const url = pathToFileURL(source).href;
const output = resolve('verification/web', 'knot-' + battery);
mkdirSync(output, { recursive: true });
const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
const observations = [];
try {
  for (const viewport of [{ width: 390, height: 844 }, { width: 1280, height: 800 }]) {
    const context = await browser.newContext({ viewport, serviceWorkers: 'block' });
    const page = await context.newPage();
    const errors = [], blockedRequests = [], actions = [], outcomes = [];
    page.on('pageerror', error => errors.push({ type: 'pageerror', message: error.message }));
    page.on('console', message => { if (message.type() === 'error') errors.push({ type: 'console', message: message.text() }); });
    await context.route('**/*', route => {
      if (route.request().url() === url) return route.continue();
      blockedRequests.push(route.request().url()); return route.abort();
    });
    const started = Date.now(), prefix = join(output, String(viewport.width));
    const result = { viewport, artifactSHA256: expectedHash, errors, blockedRequests, actions, outcomes, screenshots: [], elapsedMs: 0 };
    const screenshot = async label => {
      const path = prefix + '-' + label + '.png';
      await page.screenshot({ path, fullPage: true }); result.screenshots.push(path);
    };
    try {
      await page.goto(url, { waitUntil: 'load', timeout: 15000 });
      await page.locator('.move-btn').first().waitFor({ state: 'visible' });
      result.title = await page.title();
      result.layout = await page.evaluate(() => ({ viewportWidth: innerWidth, documentWidth: document.documentElement.scrollWidth, game: (() => { const r = document.getElementById('game').getBoundingClientRect(); return { x: r.x, y: r.y, width: r.width, height: r.height }; })() }));
      await screenshot('loaded');
      let move = 0, rounds = 0;
      while (Date.now() - started < 65000) {
        const outcome = (await page.locator('#outcome').innerText()).trim();
        if (outcome) {
          outcomes.push(outcome);
          if (!result.screenshots.some(path => path.endsWith(outcome.includes('won') ? '-win.png' : '-loss.png'))) await screenshot(outcome.includes('won') ? 'win' : 'loss');
          await page.getByRole('button', { name: 'Play Again' }).click();
          await page.waitForFunction(() => document.getElementById('outcome').textContent === '' && !document.querySelector('.move-btn').disabled);
          actions.push({ elapsedMs: Date.now() - started, action: 'restart', log: await page.locator('#log-text').innerText() });
          rounds++; continue;
        }
        // Exercise all four actual buttons; later rounds favor the weaker move
        // to observe failure when ordinary random play reaches it. Never force HP.
        const index = move < 4 ? move % 4 : rounds % 2 ? 1 : move % 4;
        const button = page.locator('.move-btn').nth(index);
        const before = await page.locator('#log-text').innerText();
        await button.click({ timeout: 5000 });
        const immediate = await page.locator('#log-text').innerText();
        const inputLocked = await page.locator('.move-btn').first().isDisabled();
        await page.waitForFunction(() => !document.querySelector('.move-btn').disabled || document.getElementById('outcome').textContent !== '', undefined, { timeout: 5000 });
        actions.push({ elapsedMs: Date.now() - started, action: 'move', index, before, immediate, inputLocked, after: await page.locator('#log-text').innerText(), healthWidths: await page.evaluate(() => ({ player: document.getElementById('php').style.width, enemy: document.getElementById('ehp').style.width })) });
        move++;
      }
      await screenshot('after-play');
    } catch (error) { result.observationIssue = error.message; }
    result.elapsedMs = Date.now() - started;
    observations.push(result);
    await context.close();
  }
} finally { await browser.close(); }
if (sha() !== expectedHash) throw new Error('artifact_changed_during_observation');
const report = { observedAt: new Date().toISOString(), battery, artifactSHA256: expectedHash, unchangedArtifact: true, mode: 'manual_browser_observation_not_unit_suite', observations };
writeFileSync(join(output, 'observations.json'), JSON.stringify(report, null, 2));
console.log(JSON.stringify({ ...report, observations: observations.map(({ actions, ...rest }) => ({ ...rest, moveActions: actions.filter(action => action.action === 'move').length, restarts: actions.filter(action => action.action === 'restart').length, moveIndexesObserved: [...new Set(actions.filter(action => action.action === 'move').map(action => action.index))] })) }, null, 2));
