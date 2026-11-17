// Real wall-clock browser observation of the captured Kraalu artifact only.
// No network, source/state mutations, injected clocks, random overrides or replay.
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { pathToFileURL } from 'node:url';
import { chromium } from '/usr/local/lib/node_modules/playwright/index.mjs';
const directory = join(tmpdir(), 'knot-acceptance-uf26aun6d49w1tsjsm2u9', 'battery-2026-11-14T00-59-25-344Z', 'battle-game');
const source = join(directory, '0e213a02d8694fa2cb8736cc3c62a985d09498ce381d52a1d25aab83c085d6de.html');
const expectedHash = 'c1d9486a616c8476c7376fa9d6fadaa5cbdab1a4c367d72b02d703dd0b73113b';
const hash = () => createHash('sha256').update(readFileSync(source)).digest('hex');
if (hash() !== expectedHash || readFileSync(source).length !== 25837) throw new Error('artifact_identity_mismatch');
const output = join(directory, 'browser-observation');
mkdirSync(output, { recursive: false }); // Existing observation is never overwritten.
const url = pathToFileURL(source).href;
const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
const observations = [];
try {
  for (const viewport of [{ width: 390, height: 844 }, { width: 1280, height: 800 }]) {
    const context = await browser.newContext({ viewport, serviceWorkers: 'block' });
    const page = await context.newPage();
    const result = { viewport, errors: [], blockedRequests: [], actions: [], outcomes: [], screenshots: [] };
    page.on('pageerror', error => result.errors.push({ type: 'pageerror', message: error.message }));
    page.on('console', message => { if (message.type() === 'error') result.errors.push({ type: 'console', message: message.text() }); });
    await context.route('**/*', route => {
      if (route.request().url() === url) return route.continue();
      result.blockedRequests.push(route.request().url()); return route.abort();
    });
    const screenshot = async label => {
      const path = join(output, viewport.width + '-' + label + '.png');
      await page.screenshot({ path, fullPage: true }); result.screenshots.push(path);
    };
    const health = () => page.evaluate(() => ({ player: document.getElementById('player-hp-num').textContent.trim(), enemy: document.getElementById('enemy-hp-num').textContent.trim(), playerFill: document.getElementById('player-hp-fill').style.width, enemyFill: document.getElementById('enemy-hp-fill').style.width }));
    const buttons = () => page.locator('.atk-btn').evaluateAll(elements => elements.map((element, index) => ({ index, disabled: element.disabled, text: element.textContent })));
    let started, round = 0, roundMoves = 0, moves = 0;
    try {
      await page.goto(url, { waitUntil: 'load', timeout: 15000 });
      await page.locator('#btn-start').waitFor({ state: 'visible', timeout: 5000 });
      result.title = await page.title();
      await screenshot('title');
      await page.locator('#btn-start').click();
      await page.locator('#atk-btn-0').waitFor({ state: 'visible', timeout: 5000 });
      started = Date.now(); result.playStartedAt = new Date(started).toISOString();
      result.initialHealth = await health(); result.initialButtons = await buttons();
      result.layout = await page.evaluate(() => {
        const rect = document.getElementById('game-wrap').getBoundingClientRect();
        const panel = document.getElementById('bottom-panel').getBoundingClientRect();
        return { viewportWidth: innerWidth, viewportHeight: innerHeight, documentWidth: document.documentElement.scrollWidth, documentHeight: document.documentElement.scrollHeight, game: { x: rect.x, y: rect.y, width: rect.width, height: rect.height }, bottomPanel: { bottom: panel.bottom } };
      });
      await screenshot('battle-start');
      while (Date.now() - started < 65000) {
        if (await page.locator('#overlay').evaluate(element => element.classList.contains('visible'))) {
          const outcome = await page.locator('#overlay-title').innerText();
          const label = outcome === 'VICTORY!' ? 'win' : 'loss';
          result.outcomes.push({ round, outcome, health: await health(), elapsedMs: Date.now() - started });
          if (!result.screenshots.some(path => path.endsWith('-' + label + '.png'))) await screenshot(label);
          await page.locator('#btn-restart').click();
          await page.waitForFunction(() => !document.getElementById('overlay').classList.contains('visible') && !document.getElementById('atk-btn-0').disabled, undefined, { timeout: 5000 });
          const resetHealth = await health(), resetButtons = await buttons();
          const resetVerified = resetHealth.player === '130 / 130' && resetHealth.enemy === '120 / 120' && resetButtons.every((button, i) => !button.disabled && button.text.includes(['5/5 PP', '3/3 PP', '2/2 PP', '2/2 PP'][i]));
          result.actions.push({ action: 'restart', elapsedMs: Date.now() - started, resetHealth, resetButtons, resetVerified });
          if (!resetVerified) throw new Error('observed_restart_did_not_reset');
          round++; roundMoves = 0; continue;
        }
        const available = (await buttons()).filter(button => !button.disabled);
        if (!available.length) throw new Error('no_available_move_without_outcome');
        // Initial round exercises all controls. Later rounds alternate strong
        // attacks and a healing/weak-attack strategy; outcomes remain random.
        const preferred = round === 0 ? [0, 1, 2, 3][moves % 4] : round % 2 ? [3, 3, 1, 0][Math.min(roundMoves, 3)] : roundMoves < 2 ? 2 : 0;
        const index = available.find(button => button.index === preferred)?.index ?? available[0].index;
        const before = { health: await health(), buttons: await buttons(), log: await page.locator('#log-box').innerText() };
        await page.locator('#atk-btn-' + index).click({ timeout: 5000 });
        const immediate = { health: await health(), buttons: await buttons(), log: await page.locator('#log-box').innerText() };
        const inputLocked = immediate.buttons.every(button => button.disabled);
        if (moves === 0) await screenshot('first-attack');
        await page.waitForFunction(() => document.getElementById('overlay').classList.contains('visible') || [...document.querySelectorAll('.atk-btn')].some(button => !button.disabled), undefined, { timeout: 5000 });
        result.actions.push({ action: 'move', index, round, elapsedMs: Date.now() - started, inputLocked, before, immediate, after: { health: await health(), buttons: await buttons(), log: await page.locator('#log-box').innerText() } });
        moves++; roundMoves++;
      }
      await screenshot('after-play');
      result.elapsedPlayMs = Date.now() - started;
    } catch (error) {
      result.observationIssue = error.message;
      result.elapsedPlayMs = started ? Date.now() - started : 0;
    }
    observations.push(result);
    await context.close();
  }
} finally { await browser.close(); }
if (hash() !== expectedHash) throw new Error('artifact_changed_during_observation');
const report = { observedAt: new Date().toISOString(), artifactSHA256: expectedHash, unchangedArtifact: true, mode: 'real_browser_observation_not_unit_suite', observations };
writeFileSync(join(output, 'observations.json'), JSON.stringify(report, null, 2), { flag: 'wx', mode: 0o600 });
console.log(JSON.stringify({ ...report, observations: observations.map(({ actions, ...rest }) => ({ ...rest, moveActions: actions.filter(action => action.action === 'move').length, restarts: actions.filter(action => action.action === 'restart').length, moveIndexesObserved: [...new Set(actions.filter(action => action.action === 'move').map(action => action.index))], everyInputLocked: actions.filter(action => action.action === 'move').every(action => action.inputLocked), everyRestartReset: actions.filter(action => action.action === 'restart').every(action => action.resetVerified) })) }, null, 2));
if (observations.some(item => item.observationIssue || item.errors.length || item.blockedRequests.length || item.elapsedPlayMs < 65000)) process.exitCode = 2;
