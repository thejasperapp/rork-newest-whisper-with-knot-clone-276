import { expect, test } from '@playwright/test';

test('meeting-first sidekick shows transcripts, searches with consent and retains cited answers at desktop and phone sizes', async ({ page }) => {
  const errors: string[] = [], external: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.route('**/*', (route) => { const url = new URL(route.request().url()); if (url.origin === 'http://127.0.0.1:4176') return route.fallback(); if (url.hostname === 'fonts.googleapis.com') return route.fulfill({ contentType: 'text/css', body: '' }); external.push(url.origin); return route.abort(); });
  await page.route(/\/src\/lib\/jasperMeetings\.ts(?:\?.*)?$/, (route) => route.fulfill({ contentType: 'application/javascript', body: `
    export async function loadJasperLibrary(){return {revision:0,folders:[{id:'creators',name:'Creators'},{id:'coaches',name:'Coaches'},{id:'team',name:'Team'}],filings:{},preferences:{focus:['Client numbers'],instructions:''}}}
    export async function jasperMeetingRequest(){return {saved:true}}
    export async function askJasperMeetings(owner,input){ await new Promise(r=>setTimeout(r,500)); if(input.mode==='connections') return {id:input.requestId,question:input.question,generatedAt:'2026-09-13',scope:'Private note + 1 selected meeting',coverage:'Only explicitly selected context.',meetingId:null,noteContext:input.noteContext,sources:[{id:'S1',meetingId:'00000000-0000-4000-8000-000000000002',meetingTitle:'Creator weekly',segmentId:'00000000-0000-4000-8000-000000000003',spokenAt:'2026-09-02',speaker:'Alex',text:'The pilot will include ten teams.',offset:0}],result:{insufficient:false,sections:[{title:'Possible connections',items:[{text:'Your smaller pilot idea relates to the ten-team pilot discussed in this meeting.',noteQuote:'smaller pilot',sourceIds:['S1']}]}],actions:[]}}; return {id:'00000000-0000-4000-8000-000000000005',question:input.question,generatedAt:'2026-09-13T12:00:00Z',scope:'Creator weekly',coverage:'Searched saved transcript excerpts, not an exhaustive count.',meetingId:'00000000-0000-4000-8000-000000000002',sources:[{id:'S1',meetingId:'00000000-0000-4000-8000-000000000002',meetingTitle:'Creator weekly',segmentId:'00000000-0000-4000-8000-000000000003',spokenAt:'2026-09-02T12:00:00Z',speaker:'Alex',text:'Josh reported 24 clients in August.',offset:0}],result:{insufficient:false,sections:[{title:'Client numbers',items:[{text:'Josh reported 24 clients for August.',sourceIds:['S1']}]}],actions:[]}} }
  ` }));
  await page.route(/\/src\/lib\/supabase\.ts(?:\?.*)?$/, (route) => route.fulfill({ contentType: 'application/javascript', body: `
    const rows=[{id:'00000000-0000-4000-8000-000000000003',meeting_id:'00000000-0000-4000-8000-000000000002',username:'Alex',text:'Josh reported 24 clients in August.',spoken_at:'2026-09-02T12:00:00Z'}];
    const query={select(){return this},eq(){return this},order(){return this},limit(){return this},abortSignal(){return Promise.resolve({data:rows,error:null})}};
    export const supabase={from:()=>query,auth:{getSession:async()=>({data:{session:{user:{id:'00000000-0000-4000-8000-000000000001'}}}}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})}};
  ` }));
  await page.route(/\/src\/lib\/notebookStorage\.ts(?:\?.*)?$/, (route) => route.fulfill({ contentType: 'application/javascript', body: `export async function listNotebookDocuments(){return [{id:'00000000-0000-4000-8000-000000000009',title:'Pilot ideas',notes:'Try a smaller pilot.',revision:1}]}` }));
  await page.route(/\/src\/lib\/notebookArchive\.ts(?:\?.*)?$/, (route) => route.fulfill({ contentType: 'application/javascript', body: `export async function fetchNotebookArchive(){return {meetings:[{id:'00000000-0000-4000-8000-000000000002',title:'Creator weekly',created_at:'2026-09-02'}],hasMore:false}}` }));
  await page.route(/\/sidekick-harness(?:\?.*)?$/, (route) => route.fulfill({ contentType: 'text/html', body: `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body><div id="root"></div><script type="module">import RefreshRuntime from '/@react-refresh'; RefreshRuntime.injectIntoGlobalHook(window); window.$RefreshReg$ = () => {}; window.$RefreshSig$ = () => (type) => type; window.__vite_plugin_react_preamble_installed__ = true;</script><script type="module" src="/@vite/client"></script><script type="module" src="/browser-tests/sidekick-harness.tsx"></script></body></html>` }));
  await page.goto('/sidekick-harness');
  await expect(page.getByRole('button', { name: /Jasper sidekick/ })).toHaveCount(0);
  const fullStage = await page.locator('[data-meeting-tile-region]').boundingBox();
  await expect(page.getByRole('button', { name: 'Ask Jasper', exact: true })).toBeVisible();
  await expect(page.locator('[data-jasper-launcher] > div')).toHaveCSS('opacity', '1');
  for (const size of [{ width: 1280, height: 900 }, { width: 390, height: 844 }, { width: 844, height: 390 }]) {
    await page.setViewportSize(size);
    const launcher = await page.locator('[data-jasper-launcher]').boundingBox();
    expect(launcher!.x).toBeGreaterThanOrEqual(16);
    expect(launcher!.x).toBeLessThan(40);
    expect(launcher!.y).toBeGreaterThan(size.height / 2);
    expect(launcher!.y + launcher!.height).toBeLessThanOrEqual(size.height - (size.width < 1024 ? 90 : 20));
    await expect(page.getByRole('button', { name: 'Send to Jasper' })).toHaveCSS('min-height', '44px');
    await expect(page.getByRole('textbox', { name: 'Ask Jasper question' })).toBeVisible();
    await page.screenshot({ path: `../tmp/jasper-restored-pill-${size.width}.png` });
  }
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.getByRole('textbox', { name: 'Ask Jasper question' }).fill('Help me prepare');
  await expect(page.getByRole('region', { name: 'Jasper questions' })).toHaveCount(0);
  await page.getByRole('button', { name: 'Ask Jasper', exact: true }).click();
  await expect(page.getByRole('region', { name: 'Jasper questions' })).toContainText('Sent: 0');
  await expect(page.getByRole('complementary', { name: 'Jasper meeting sidekick' })).toBeHidden();
  await page.getByRole('button', { name: 'Close questions' }).click();
  await expect(page.getByRole('textbox', { name: 'Ask Jasper question' })).toHaveValue('Help me prepare');
  await page.getByRole('textbox', { name: 'Ask Jasper question' }).press('Enter');
  await expect(page.getByRole('region', { name: 'Jasper questions' })).toContainText('Sent: 1');
  await page.getByRole('button', { name: 'Close questions' }).click();
  await page.getByRole('button', { name: 'Tools', exact: true }).click();
  await page.getByRole('button', { name: /Jasper sidekick/ }).click();
  await expect(page.locator('[data-jasper-launcher]')).toBeHidden();
  const openStage = await page.locator('[data-meeting-tile-region]').boundingBox();
  const drawer = await page.getByRole('complementary', { name: 'Jasper meeting sidekick' }).boundingBox();
  expect(openStage!.width).toBeLessThan(fullStage!.width);
  expect(openStage!.x + openStage!.width).toBeLessThanOrEqual(drawer!.x);
  await page.getByRole('button', { name: /^Transcript/ }).click();
  await expect(page.getByText('Josh reported 24 clients in August.')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Open meeting notepad' })).toHaveCount(0);
  await page.getByLabel('Ask Jasper about meetings').fill('How many clients did Josh have last month?');
  await page.getByLabel('Search meeting scope').selectOption('all');
  await page.getByRole('button', { name: 'Send Jasper question' }).click();
  await expect(page.getByRole('region', { name: 'Approve Jasper search' })).toBeVisible();
  await page.getByRole('button', { name: 'Continue with Jasper' }).click();
  await expect(page.getByText('Josh reported 24 clients for August.')).toBeVisible();
  await page.getByText('1 source · inspect quotes').click();
  await expect(page.getByRole('link', { name: 'Open original meeting notes' })).toHaveAttribute('href', /meeting=00000000-0000-4000-8000-000000000002/);
  await page.getByRole('button', { name: 'Keep with meeting notes' }).click();
  await expect(page.getByText('Saved with meeting')).toBeVisible();
  await page.getByLabel('Ask Jasper about meetings').fill('Keep this question');
  await page.getByRole('button', { name: 'Minimize Jasper sidekick' }).click();
  await page.getByRole('button', { name: 'Tools', exact: true }).click();
  await page.getByRole('button', { name: /Jasper sidekick/ }).click();
  await expect(page.getByLabel('Ask Jasper about meetings')).toHaveValue('Keep this question');
  await page.screenshot({ path: '../tmp/jasper-drawer-desktop.png' });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.getByLabel('Ask Jasper about meetings').scrollIntoViewIfNeeded();
  await page.screenshot({ path: '../tmp/jasper-drawer-phone.png' });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  const send = await page.getByRole('button', { name: 'Send Jasper question' }).boundingBox();
  expect(send!.y + send!.height).toBeLessThan(844 - 80);
  for (const size of [{ width: 390, height: 844 }, { width: 1024, height: 768 }, { width: 844, height: 390 }]) {
    await page.setViewportSize(size);
    const tile = await page.locator('[data-meeting-tile-region]').boundingBox();
    const panel = await page.getByRole('complementary', { name: 'Jasper meeting sidekick' }).boundingBox();
    const controls = await page.locator('[data-call-controls]').boundingBox();
    expect(tile!.width).toBeGreaterThan(80); expect(tile!.height).toBeGreaterThan(60);
    expect(size.width < 768 ? tile!.y + tile!.height <= panel!.y : tile!.x + tile!.width <= panel!.x).toBe(true);
    expect(panel!.y + panel!.height).toBeLessThanOrEqual(controls!.y);
    const composer = await page.getByLabel('Ask Jasper about meetings').boundingBox();
    expect(composer!.y + composer!.height).toBeLessThanOrEqual(panel!.y + panel!.height);
  }
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.getByRole('button', { name: 'Find connections in my notes' }).click();
  const connections = page.getByRole('region', { name: 'Note connections' });
  await connections.getByLabel('Start from saved private writing').selectOption('00000000-0000-4000-8000-000000000009');
  await connections.getByLabel(/Creator weekly/).check();
  await expect(connections.getByRole('button', { name: 'Analyze selected context' })).toBeDisabled();
  await connections.getByLabel(/Allow cloud AI/).check();
  await connections.getByRole('button', { name: 'Analyze selected context' }).click();
  await expect(connections.locator('mark')).toHaveText('smaller pilot');
  await connections.locator('mark').scrollIntoViewIfNeeded();
  await page.screenshot({ path: '../tmp/jasper-connections-desktop.png' });
  await page.setViewportSize({ width: 390, height: 844 });
  await connections.locator('mark').scrollIntoViewIfNeeded();
  await page.screenshot({ path: '../tmp/jasper-connections-phone.png' });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await expect(connections.getByRole('button', { name: 'Keep reviewed connections' })).toBeDisabled();
  await connections.getByLabel(/I’ve reviewed/).check();
  await connections.getByLabel('Save connections with meeting').selectOption('00000000-0000-4000-8000-000000000002');
  await connections.getByRole('button', { name: 'Keep reviewed connections' }).click();
  await expect(connections.getByText('Connections kept privately')).toBeVisible();
  await page.getByRole('button', { name: 'Back to meeting questions' }).click();
  await expect(page.getByLabel('Ask Jasper about meetings')).toHaveValue('Keep this question');
  expect(errors).toEqual([]); expect(external).toEqual([]);
});
