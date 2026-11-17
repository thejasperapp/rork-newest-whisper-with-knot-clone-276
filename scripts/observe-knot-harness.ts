// Bounded live provider observation, NOT authenticated Whisper/device acceptance.
// Run: rork env run -- bun scripts/observe-knot-harness.ts
// Uses a unique synthetic workspace, no member data, and the installed server secret.
import { mkdir, writeFile } from 'node:fs/promises';
import { attachedShellInput, attachedShellResult, type ShellBoundary } from '../functions/knot-shell-protocol';
import { discoverKnotShell, sidecarRequest, readSidecarText, readSidecarBytes } from '../functions/knot-shell-discovery';
const token = process.env.SIDECAR_TOKEN_WHISPER;
if (!token) throw new Error('Installed credential is unavailable.');
const env = { SIDECAR_TOKEN_WHISPER: token, DO: { fetch: async () => { throw new Error('No app actor is invoked by provider observation.'); } } };
const workspace = 'whisper-harness-' + crypto.randomUUID().replace(/-/g, '');
const directory = '.local/knot-references/harness-20261110/observation-' + new Date().toISOString().replace(/[:.]/g, '-');
await mkdir(directory, { recursive: true });
const json = async (path: string, method = 'GET', body?: unknown) => JSON.parse(await readSidecarText(await sidecarRequest(env, path, method, body, 40000), 6500000)) as Record<string, unknown>;
const discovery = await discoverKnotShell(env);
if (!discovery.ok) throw new Error('Discovery failed.');
let sessionID: string | undefined, browserStarted = false;
const receipts: unknown[] = [];
try {
  const commands = [
    "printf '%s\\n' 'HARNESS-ROOT-MEMORY' > MEMORY.md && mkdir -p proj && cd proj && export KNOT_HARNESS_MARKER=MARKER-42 && printf '%s\\n' \"$PWD\" \"$KNOT_HARNESS_MARKER\" > marker.txt && cat marker.txt",
    "pwd; cat marker.txt; printf '%s\\n' \"$KNOT_HARNESS_MARKER\"; python3 - <<'PRIMES'\nprint(sum(n for n in range(2, 1000) if all(n % d for d in range(2, int(n ** 0.5) + 1))))\nPRIMES",
    "cat -- MEMORY.md",
    "pwd; printf '%s\\n' \"$KNOT_HARNESS_MARKER\"",
  ];
  for (let i = 0; i < commands.length; i++) {
    const opened = await json('/sessions', 'POST', { user_id: workspace });
    if (opened.user_id !== workspace || typeof opened.session_id !== 'string' || (i === 0 ? opened.attached !== false : opened.attached !== true || opened.session_id !== sessionID)) throw new Error('Create-or-attach identity mismatch.');
    sessionID = opened.session_id;
    const base = '/sessions/' + encodeURIComponent(sessionID);
    const before = await json(base + '/log?offset=0');
    const boundary: ShellBoundary = { nonce: crypto.randomUUID().replace(/-/g, ''), stdoutBefore: before.stdout_len as number, stderrBefore: before.stderr_len as number,
      offset: 0, startedAt: new Date().toISOString() };
    const submitted = attachedShellInput(commands[i], 20000, boundary.nonce, i === 2);
    const accepted = await json(base + '/input', 'POST', { data: submitted });
    let observed: ReturnType<typeof attachedShellResult>;
    const deadline = Date.now() + 25000;
    do {
      const log = await json(base + '/log?offset=' + boundary.offset);
      await writeFile(directory + '/shell-' + (i + 1) + '-provider-log.json', JSON.stringify(log));
      observed = attachedShellResult(log, boundary);
      if (observed) break;
      await new Promise(resolve => setTimeout(resolve, 400));
    } while (Date.now() < deadline);
    const state = await json(base);
    receipts.push({ opened, command: commands[i], accepted, state, boundary, observed });
    if (!observed || observed.exitCode !== 0 || observed.background || state.status !== 'live') throw new Error('Foreground boundary did not complete in a live shell.');
    if (i === 1 && (!observed.stdout.includes('/proj\n') || !observed.stdout.includes('MARKER-42') || !observed.stdout.includes('76127\n'))) throw new Error('Persistent cwd/environment/file or remote calculation mismatch.');
    if (i === 2 && observed.stdout !== 'HARNESS-ROOT-MEMORY\n') throw new Error('Workspace-root memory changed with the task cwd.');
    if (i === 3 && (!observed.stdout.includes('/proj\n') || !observed.stdout.includes('MARKER-42'))) throw new Error('Memory access changed the retained task cwd or environment.');
    console.log(JSON.stringify({ observation: 'provider_shell_command', step: i + 1, sessionID, attached: opened.attached, exitCode: observed.exitCode, stdout: observed.stdout, stderr: observed.stderr, sessionStillLive: state.status === 'live' }));
  }
  browserStarted = true; // Cleanup even if the Start acknowledgement is lost.
  const start = await json('/browser/start', 'POST', { user_id: workspace });
  if (start.live !== true) throw new Error('Browser did not start.');
  const navigate = await json('/browser/navigate', 'POST', { user_id: workspace, url: 'https://en.wikipedia.org/wiki/Main_Page' });
  const screenshot = async (name: string) => {
    const response = await sidecarRequest(env, '/browser/screenshot?user_id=' + workspace, 'GET', undefined, 15000);
    const bytes = await readSidecarBytes(response, 4000000);
    if (!response.headers.get('Content-Type')?.startsWith('image/png') || bytes.length < 24 || new DataView(bytes.buffer, bytes.byteOffset).getUint32(16) !== 1280 || new DataView(bytes.buffer, bytes.byteOffset).getUint32(20) !== 800) throw new Error('Invalid genuine screenshot.');
    await writeFile(directory + '/' + name + '.png', bytes);
    return { bytes: bytes.length, sha256: new Bun.CryptoHasher('sha256').update(bytes).digest('hex') };
  };
  const beforeImage = await screenshot('browser-before');
  const focus = await json('/browser/input', 'POST', { user_id: workspace, kind: 'focus', selector: 'input[name="search"]' });
  const type = await json('/browser/input', 'POST', { user_id: workspace, kind: 'type', text: 'Prime number' });
  const key = await json('/browser/input', 'POST', { user_id: workspace, kind: 'key', key: 'Enter' });
  const afterImage = await screenshot('browser-after');
  const content = await json('/browser/content?user_id=' + workspace);
  receipts.push({ start, navigate, focus, type, key, beforeImage, afterImage, content });
  if (beforeImage.sha256 === afterImage.sha256 || typeof content.text !== 'string' || !content.text.toLowerCase().includes('prime number')) throw new Error('Changed browser evidence was not observed.');
  console.log(JSON.stringify({ observation: 'provider_browser', url: content.url, title: content.title, realImageChanged: true, beforeImage, afterImage, appAcceptance: false }));
} finally {
  let cleanupFailed = false;
  // Attempt both closures even if one provider response fails. Never replay input.
  if (browserStarted) {
    try { const stopped = await json('/browser?user_id=' + workspace, 'DELETE'); receipts.push({ browserStop: stopped }); if (stopped.stopped !== true) cleanupFailed = true; }
    catch { cleanupFailed = true; receipts.push({ browserStopUnconfirmed: true }); }
  }
  if (sessionID) {
    try { const stopped = await json('/sessions/' + encodeURIComponent(sessionID), 'DELETE'); receipts.push({ shellStop: stopped }); if (!['killed', 'exited', 'reaped'].includes(String(stopped.status))) cleanupFailed = true; }
    catch { cleanupFailed = true; receipts.push({ shellStopUnconfirmed: true }); }
  }
  await writeFile(directory + '/receipts.json', JSON.stringify({ observedAt: new Date().toISOString(), workspace, appAcceptance: false, receipts }, null, 2));
  console.log(JSON.stringify({ privateEvidence: directory, authenticatedWhisperAcceptance: false, cleanupConfirmed: !cleanupFailed }));
  if (cleanupFailed) throw new Error('Provider cleanup was not confirmed. Inspect the private receipts; do not replay work.');
}
