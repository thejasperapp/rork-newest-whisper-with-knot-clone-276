// Non-mutating discovery against the fixed sidecar origin. No session creation,
// workspace listing, old credentials, provider error bodies, or command execution.
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
const token = process.env.SIDECAR_TOKEN_WHISPER;
const temporary = process.env.TMPDIR;
if (!token || !temporary) throw new Error('Backend credential and private temporary directory required.');
const directory = join(temporary, 'knot-private');
await mkdir(directory, { recursive: true, mode: 0o700 });
for (const path of ['/openapi.json', '/capabilities', '/sessions/whisper-contract-inspection-nonexistent']) {
  try {
    const response = await fetch('https://knot-shell.mydailywhisper.com' + path, {
      headers: { Authorization: `Bearer ${token}` }, redirect: 'manual', signal: AbortSignal.timeout(10000),
    });
    const body = (await response.text()).slice(0, 100000);
    const filename = path === '/openapi.json' ? 'sidecar-openapi.json' : path === '/capabilities' ? 'sidecar-capabilities.json' : 'sidecar-session-missing.json';
    await writeFile(join(directory, filename), body, { mode: 0o600 });
    let keys: string[] = [];
    try { const parsed = JSON.parse(body); if (parsed && typeof parsed === 'object') keys = Object.keys(parsed).slice(0, 40); } catch { /* body stays private */ }
    console.log(JSON.stringify({ path, status: response.status, keys }));
  } catch { console.log(JSON.stringify({ path, unavailable: true })); }
}
