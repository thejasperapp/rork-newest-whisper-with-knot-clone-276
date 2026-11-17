import { expect, test } from '@playwright/test';

test('calm filing library supports animated drag, Undo, keyboard filing and phone layout', async ({ page }) => {
  const errors: string[] = [];
  page.on('pageerror', (error) => { errors.push(error.message); console.error('Filing browser error:', error.message); });
  await page.setViewportSize({ width: 1200, height: 900 });
  await page.route('**/*', (route) => { const url = new URL(route.request().url()); if (url.origin === 'http://127.0.0.1:4176') return route.fallback(); return route.abort(); });
  await page.route(/\/src\/hooks\/useAuth\.tsx?(?:\?.*)?$/, (route) => route.fulfill({ contentType: 'application/javascript', body: `export const useAuth=()=>({user:{id:'00000000-0000-4000-8000-000000000001'}});` }));
  await page.route(/\/src\/lib\/supabase\.ts(?:\?.*)?$/, (route) => route.fulfill({ contentType: 'application/javascript', body: `export const supabaseUrl='http://127.0.0.1:4176'; export const supabaseAnonKey='test-only'; export const supabase={auth:{getSession:async()=>({data:{session:null}}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})}};` }));
  await page.route(/\/src\/lib\/notebookArchive\.ts(?:\?.*)?$/, (route) => route.fulfill({ contentType: 'application/javascript', body: `export async function fetchNotebookArchive(){return {meetings:[{id:'00000000-0000-4000-8000-000000000002',title:'Creator partnerships',host_username:'alex',created_at:'2026-09-12T12:00:00Z',status:'ended'},{id:'00000000-0000-4000-8000-000000000003',title:'Friday team catch-up',host_username:'josh',created_at:'2026-09-11T12:00:00Z',status:'ended'}],hasMore:false}}` }));
  await page.route(/\/src\/lib\/jasperMeetings\.ts(?:\?.*)?$/, (route) => route.fulfill({ contentType: 'application/javascript', body: `
    export const JASPER_MEETINGS_URL='http://127.0.0.1:4176'; export const jasperLibrarySchema={parse:x=>x}; export const jasperAnswerSchema={};
    let library={revision:0,folders:[{id:'creators',name:'Creators'},{id:'coaches',name:'Coaches'},{id:'team',name:'Team'}],filings:{},preferences:{focus:[],instructions:''}};
    export async function loadJasperLibrary(){return structuredClone(library)};
    export async function jasperMeetingRequest(owner,path,input){ if(path!=='library')return {}; if(input.revision!==library.revision)throw Error('revision'); if(Object.hasOwn(input,'expectedFolder')&&(library.filings[input.meetingId]??null)!==input.expectedFolder)throw Error('changed'); await new Promise(r=>setTimeout(r,120)); library=structuredClone(library); if(input.folderId) library.filings[input.meetingId]=input.folderId; else delete library.filings[input.meetingId]; library.revision++; return structuredClone(library)};
    export async function askJasperMeetings(){throw Error('AI should not run while filing')};
  ` }));
  await page.route(/\/src\/lib\/meetings\.ts(?:\?.*)?$/, (route) => route.fulfill({ contentType: 'application/javascript', body: `export const fetchNotebookPrefs=async()=>({prefs:{}});export const saveNotebookPref=async()=>{};export const fetchMeeting=async()=>null;export const fetchMeetingTranscript=async()=>[];export const parseEmberSummary=()=>[];` }));
  // Notes/agenda aren't mounted in this filing-only scenario.
  await page.route(/\/src\/components\/MeetingNotesScreen\.tsx(?:\?.*)?$/, (route) => route.fulfill({ contentType: 'application/javascript', body: 'export const MeetingNotesScreen=()=>null;' }));
  await page.route(/\/filing-harness(?:\?.*)?$/, (route) => route.fulfill({ contentType: 'text/html', body: `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body><div id="root"></div><script type="module">import RefreshRuntime from '/@react-refresh'; RefreshRuntime.injectIntoGlobalHook(window);window.$RefreshReg$=()=>{};window.$RefreshSig$=()=>(type)=>type;window.__vite_plugin_react_preamble_installed__=true;</script><script type="module" src="/@vite/client"></script><script type="module" src="/browser-tests/filing-harness.tsx"></script></body></html>` }));
  await page.goto('/filing-harness');
  const row = page.locator('article').filter({ hasText: 'Creator partnerships' });
  await expect(row).toBeVisible();
  await row.dragTo(page.getByRole('button', { name: 'Creators', exact: true }));
  await expect(page.getByText('Filed in Creators', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Creators', exact: true }).click();
  await expect(page.locator('article')).toHaveCount(1);
  await page.getByRole('button', { name: 'Undo', exact: true }).click();
  await expect(page.locator('article')).toHaveCount(0);
  await page.getByRole('button', { name: 'All meetings', exact: true }).click();
  const file = page.getByRole('button', { name: 'File Creator partnerships', exact: true });
  await file.focus(); await page.keyboard.press('Enter');
  await page.getByRole('menuitem', { name: 'Team', exact: true }).click();
  await expect(page.getByText('Filed in Team', { exact: true })).toBeVisible();
  await page.screenshot({ path: '../tmp/jasper-filing-desktop.png' });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.screenshot({ path: '../tmp/jasper-filing-phone.png' });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  expect(errors).toEqual([]);
});
