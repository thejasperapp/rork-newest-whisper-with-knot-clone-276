// Browser observations of the exact captured HTML, never a repaired substitute.
import { chromium } from '/usr/local/lib/node_modules/playwright/index.mjs';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createServer } from 'node:http';
import { createHash } from 'node:crypto';
const directory = join(tmpdir(), 'knot-artifact-acceptance-mayokn2749ag072e3uvbh-20261115/game');
const outcome = JSON.parse(readFileSync(join(directory, 'outcome.json'), 'utf8'));
const doc = outcome.documents[0];
const bytes = readFileSync(doc.originalPath);
if (createHash('sha256').update(bytes).digest('hex') !== doc.sha256) throw new Error('captured_bytes_changed');
const screenshotDirectory = '.rork/verification/knot-artifacts-20261115';
mkdirSync(screenshotDirectory, { recursive: true });
const observations = { title: doc.title, sha256: doc.sha256, viewport: { width: 390, height: 844 }, pageErrors: [], missingResources: [], checks: {} };
const server = createServer((req, res) => {
  if (req.url === '/') { res.writeHead(200, { 'Content-Type': 'text/html' }); res.end(bytes); }
  else { res.writeHead(404); res.end('Not included in captured artifact'); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage({ viewport: observations.viewport });
  page.on('pageerror', error => observations.pageErrors.push(error.message));
  page.on('response', response => { if (response.status() >= 400) observations.missingResources.push(new URL(response.url()).pathname); });
  const address = server.address();
  await page.goto(`http://127.0.0.1:${address.port}/`, { waitUntil: 'networkidle' });
  const cards = page.getByTestId('card');
  observations.checks.cardCount = await cards.count();
  observations.checks.initialMoves = await page.getByTestId('moves').innerText();
  observations.checks.missingArtworkCount = await page.locator('.card img').evaluateAll(images => images.filter(img => !img.complete || img.naturalWidth === 0).length);
  const herbs = await cards.evaluateAll(elements => [...new Set(elements.map(card => card.querySelector('img')?.alt))]);
  observations.checks.observedHerbs = herbs;
  for (const herb of herbs) {
    const pair = page.locator('.card').filter({ has: page.locator(`img[alt="${herb}"]`) });
    await pair.nth(0).click(); await pair.nth(1).click();
  }
  observations.checks.movesAfterSixPairs = await page.getByTestId('moves').innerText();
  observations.checks.matchedCount = await page.locator('.matched').count();
  observations.checks.winMessageVisible = await page.getByTestId('win').evaluate(el => getComputedStyle(el).visibility !== 'hidden');
  await page.screenshot({ path: screenshotDirectory + '/delivered-game-win.png', fullPage: true });
  await page.getByTestId('restart').click();
  observations.checks.restartMoves = await page.getByTestId('moves').innerText();
  observations.checks.restartMatchedCount = await page.locator('.matched').count();
  observations.checks.restartResets = observations.checks.restartMoves === '0' && observations.checks.restartMatchedCount === 0;
  observations.checks.horizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
  observations.screenshot = screenshotDirectory + '/delivered-game-win.png';
} finally { await browser.close(); await new Promise(resolve => server.close(resolve)); }
writeFileSync('deliveries/artifact-20261115-game-browser.json', JSON.stringify(observations, null, 2) + '\n');
console.log(JSON.stringify(observations, null, 2));
