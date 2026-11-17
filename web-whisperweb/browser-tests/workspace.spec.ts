import { expect, test, type Page } from '@playwright/test';
import { workspaceRoute } from '../../functions/workspace';
const owner = '10000000-0000-4000-8000-000000000001', guest = '10000000-0000-4000-8000-000000000003';
async function review(page: Page, title: string): Promise<void> {
  const form = page.getByRole('form', { name: title, exact: true });
  const submit = form.locator('button[type=submit]');
  await expect(submit).toBeDisabled(); await form.getByRole('checkbox').check(); await submit.click(); await expect(form).toHaveCount(0);
}
for (const width of [1280, 390]) test(`workspace decisions, client snapshots and intake at ${width}px`, async ({ page }) => {
  test.setTimeout(45000);
  const errors: string[] = []; page.on('pageerror', (error) => errors.push(error.message));
  await page.setViewportSize({ width, height: 900 });
  const data = new Map<string, unknown>();
  const store = { read: <T,>(key: string): T | undefined => structuredClone(data.get(key)) as T | undefined, write: (key: string, value: unknown) => { data.set(key, structuredClone(value)); }, list: <T,>(prefix: string) => [...data].filter(([k]) => k.startsWith(prefix)).map(([key, value]) => ({ key, value: structuredClone(value) as T })) };
  const rows = async <T,>(table: string, params: Record<string, string>): Promise<T[]> => (table === 'whisper_profiles' ? params.username ? [{ user_id: guest, username: 'client' }] : [{ user_id: owner, username: 'owner' }] : []) as T[];
  await page.route('**/*', (route) => new URL(route.request().url()).origin === 'http://127.0.0.1:4176' ? route.fallback() : route.abort());
  await page.route(/\/fixture\//, async (route) => {
    const request = route.request(); const url = new URL(request.url());
    if (url.pathname.endsWith('/clients/teams')) return route.fulfill({ json: { teams: [] } });
    try { const value = await workspaceRoute(new Request(`https://test/jasper-meetings/${url.pathname.split('/fixture/')[1]}${url.search}`, { method: request.method() }), request.headers()['x-caller'], owner, store, rows, async () => request.postDataJSON()); await route.fulfill({ json: value }); }
    catch (error) { await route.fulfill({ status: 403, json: { error: (error as Error).message } }); }
  });
  await page.route(/\/src\/hooks\/useAuth\.tsx(?:\?.*)?$/, (route) => route.fulfill({ contentType: 'application/javascript', body: 'export const useAuth=()=>({user:null});' }));
  await page.route(/\/src\/lib\/supabase\.ts(?:\?.*)?$/, (route) => route.fulfill({ contentType: 'application/javascript', body: 'export const supabase={auth:{onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})}};' }));
  await page.route(/\/src\/lib\/jasperMeetings\.ts(?:\?.*)?$/, (route) => route.fulfill({ contentType: 'application/javascript', body: `export async function jasperMeetingRequest(owner,path,body){const r=await fetch('/fixture/'+path,{method:body?'POST':'GET',headers:{'Content-Type':'application/json','X-Caller':owner},body:body?JSON.stringify(body):undefined}); const value=await r.json(); if(!r.ok)throw new Error(value.error);return value;} export async function loadJasperLibrary(){return {}} export async function askJasperMeetings(){throw new Error('AI not expected')}` }));
  await page.route(/\/workspace-harness$/, (route) => route.fulfill({ contentType: 'text/html', body: `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body><div id="root"></div><script type="module">import RefreshRuntime from '/@react-refresh'; RefreshRuntime.injectIntoGlobalHook(window); window.$RefreshReg$=()=>{};window.$RefreshSig$=()=>(type)=>type;window.__vite_plugin_react_preamble_installed__=true;</script><script type="module" src="/browser-tests/workspace-harness.tsx"></script></body></html>` }));
  await page.goto('/workspace-harness');
  await page.getByRole('button', { name: 'New decision', exact: true }).click();
  await page.getByLabel('Title', { exact: true }).fill('Pilot decision'); await page.getByLabel('Brief and desired outcome').fill('Private pilot rationale'); await page.getByLabel('Alternatives and trade-offs').fill('Small pilot or full launch'); await page.getByLabel('Due date (UTC day)', { exact: true }).fill('2026-10-01'); await page.getByLabel('Outcome review date (UTC day)').fill('2026-11-01');
  await review(page, 'New decision'); await page.getByRole('button', { name: /Pilot decision/ }).click();
  await page.getByRole('button', { name: 'Open discussion', exact: true }).click(); await review(page, 'Open discussion');
  await page.getByRole('button', { name: 'Add contribution', exact: true }).click(); await page.getByLabel('Contribution or objection', { exact: true }).fill('Start with ten teams.'); await review(page, 'Add contribution or objection');
  await page.getByRole('button', { name: 'Record decision', exact: true }).click(); await page.getByLabel('Reason, feedback or outcome').fill('Choose the small pilot.'); await review(page, 'Record decision');
  await page.getByRole('button', { name: 'Record outcome review', exact: true }).click(); await page.getByLabel('Reason, feedback or outcome').fill('Pilot succeeded.'); await review(page, 'Record outcome review'); await expect(page.getByText('reviewed', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'All work', exact: true }).click(); await page.getByRole('button', { name: 'New delivery', exact: true }).click();
  await page.getByLabel('Title', { exact: true }).fill('Internal delivery'); await page.getByLabel('Brief and desired outcome').fill('Confidential delivery margin'); await review(page, 'New delivery');
  await page.getByRole('button', { name: /Internal delivery/ }).click(); await page.getByRole('button', { name: 'Publish a version' }).click(); await page.getByLabel('Client’s exact Whisper username').fill('client'); await page.getByLabel('Client-facing title').fill('Your design'); await page.getByLabel('Reviewed delivery update').fill('Design is ready for review.'); await review(page, 'Publish reviewed version');
  await page.getByRole('button', { name: 'Test client', exact: true }).click(); await expect(page.getByRole('heading', { name: 'Your design', exact: true }).first()).toBeVisible(); await expect(page.getByText('Confidential delivery margin')).toHaveCount(0);
  await page.getByRole('button', { name: 'Accept this version', exact: true }).click(); await review(page, 'Accept this version'); await expect(page.getByRole('button', { name: 'Accept this version', exact: true })).toHaveCount(0);
  await page.screenshot({ path: `../tmp/workspace-delivery-${width}.png`, fullPage: true });
  await page.getByRole('button', { name: 'Test owner', exact: true }).click(); await page.getByRole('button', { name: 'Revoke access', exact: true }).click(); await review(page, 'Revoke client access');
  await page.getByRole('button', { name: 'Test client', exact: true }).click(); await expect(page.getByRole('alert')).toContainText('workspace_access_denied'); await expect(page.getByText('Design is ready for review.')).toHaveCount(0);
  await page.getByRole('button', { name: 'Test owner', exact: true }).click(); await page.getByRole('button', { name: 'All work', exact: true }).click(); await page.getByRole('button', { name: 'Intake setup', exact: true }).click();
  await page.getByRole('button', { name: 'Invite requester', exact: true }).click(); await page.getByLabel('Exact Whisper username').fill('client'); await review(page, 'Invite requester');
  await page.getByRole('button', { name: 'Test client', exact: true }).click(); await page.getByRole('button', { name: 'New request', exact: true }).click(); await page.getByLabel('Title', { exact: true }).fill('New campaign'); await page.getByLabel('What do you need, and why?').fill('Launch our campaign.'); await review(page, 'New request');
  await page.getByRole('button', { name: /New campaign/ }).click(); await expect(page.getByRole('button', { name: 'Approve request' })).toHaveCount(0);
  await page.getByRole('button', { name: 'Test owner', exact: true }).click();
  for (const title of ['Accept for triage', 'Request approval', 'Approve request', 'Start work', 'Mark complete']) { await page.getByRole('button', { name: title, exact: true }).click(); if (title === 'Approve request') await page.getByLabel('Reason, feedback or outcome').fill('Scope approved.'); await review(page, title); }
  await expect(page.getByText('completed', { exact: true })).toBeVisible(); await page.getByRole('button', { name: 'All work', exact: true }).click();
  await page.screenshot({ path: `../tmp/workspace-board-${width}.png`, fullPage: true });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true); expect(errors).toEqual([]);
});
