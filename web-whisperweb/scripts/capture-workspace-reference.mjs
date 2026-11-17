import { chromium } from '@playwright/test';

// Read-only reference capture; keep research images outside the app bundle.
const browser = await chromium.launch({ headless: true, executablePath: '/ms-playwright/chromium_headless_shell-1223/chrome-headless-shell-linux64/chrome-headless-shell' });
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 }, reducedMotion: 'reduce' });
  await page.route('**/*', route => ['GET', 'HEAD', 'OPTIONS'].includes(route.request().method()) ? route.continue() : route.abort());
  await page.goto('https://workspace.mydailywhisper.com', { waitUntil: 'domcontentloaded' });
  await page.locator('.workspace-page:not([inert]) #hero-title').waitFor({ state: 'visible', timeout: 60000 });
  await page.locator('[data-workspace-preloader]').waitFor({ state: 'detached', timeout: 60000 });
  await page.screenshot({ path: '/tmp/whisper-workspace-reference.png', fullPage: false });
  console.log('/tmp/whisper-workspace-reference.png');
} finally {
  await browser.close();
}
