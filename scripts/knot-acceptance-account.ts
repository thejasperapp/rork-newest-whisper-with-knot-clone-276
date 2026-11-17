// Dedicated acceptance only. Never prints credentials or reads an existing user's data.
// Run: rork env run -- bun scripts/knot-acceptance-account.ts
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { randomBytes, randomUUID } from 'node:crypto';
const ref = 'uryyyegnbtlmyhqlgndy';
const url = `https://${ref}.supabase.co`;
function privateEnv(path: string): Record<string, string> {
  try { return Object.fromEntries(readFileSync(path, 'utf8').split('\n').flatMap(line => {
    const match = /^([A-Z0-9_]+)=(.*)$/.exec(line); if (!match) return [];
    let value = match[2].trim();
    if (value.startsWith('"')) { try { value = JSON.parse(value); } catch { return []; } }
    else if (value.startsWith("'") && value.endsWith("'")) value = value.slice(1, -1);
    return [[match[1], value]];
  })); } catch { return {}; }
}
const files = [privateEnv('.env'), privateEnv('functions/.env'), privateEnv('web-whisperweb/.env')];
const candidates = [process.env.KNOT_ACCEPTANCE_SUPABASE_SERVICE_ROLE_KEY, process.env.SUPABASE_SERVICE_ROLE_KEY, ...files.flatMap(env => [env.KNOT_ACCEPTANCE_SUPABASE_SERVICE_ROLE_KEY, env.SUPABASE_SERVICE_ROLE_KEY])].filter((key): key is string => !!key);
const originalAdmin = (value: string) => { try { const claim = JSON.parse(Buffer.from(value.split('.')[1], 'base64url').toString()); return claim.role === 'service_role' && claim.ref === ref; } catch { return false; } };
let key = candidates.find(originalAdmin);
const directory = join(tmpdir(), 'knot-acceptance-uf26aun6d49w1tsjsm2u9');
const statePath = join(directory, 'account.json');
async function main() {
  if (!key) {
    const access = process.env.SUPABASE_ACCESS_TOKEN ?? files.map(env => env.SUPABASE_ACCESS_TOKEN).find(Boolean);
    if (access) {
      // Official read-only management endpoint; no reveal flag, key creation,
      // rotation, project change or credentials printed to terminal.
      const response = await fetch(`https://api.supabase.com/v1/projects/${ref}/api-keys`, { headers: { Authorization: 'Bearer ' + access }, signal: AbortSignal.timeout(20000) });
      if (response.ok) {
        const values = await response.json() as { api_key?: string }[];
        if (Array.isArray(values)) key = values.map(value => value.api_key).find((value): value is string => typeof value === 'string' && originalAdmin(value));
      } else console.log(JSON.stringify({ step: 'original_project_admin_lookup', status: response.status, secretPrinted: false }));
    }
  }
  if (!key) { console.log(JSON.stringify({ observedAt: new Date().toISOString(), projectRef: ref, status: 'blocked', reason: 'original_project_admin_credential_unavailable', candidatesPresent: candidates.length, accountProvisioned: false })); process.exitCode = 2; return; }
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  let state: { accountID?: string; email: string; password: string; accessToken?: string; refreshToken?: string; projectRef: string };
  if (existsSync(statePath)) {
    state = JSON.parse(readFileSync(statePath, 'utf8'));
    if (state.projectRef !== ref || !/^knot-acceptance-[0-9a-f-]+@example\.com$/.test(state.email)) throw new Error('invalid_acceptance_state');
  } else {
    state = { projectRef: ref, email: `knot-acceptance-${randomUUID()}@example.com`, password: randomBytes(32).toString('base64url') };
    // Durable private intent before admin mutation; an uncertain creation is never repeated.
    writeFileSync(statePath, JSON.stringify({ ...state, creationIntentAt: new Date().toISOString() }), { mode: 0o600, flag: 'wx' });
    const created = await fetch(url + '/auth/v1/admin/users', { method: 'POST', headers: { apikey: key!, Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' }, body: JSON.stringify({ email: state.email, password: state.password, email_confirm: true, user_metadata: { dedicated_knot_acceptance: true } }), signal: AbortSignal.timeout(20000) });
    if (!created.ok) throw new Error('acceptance_create_http_' + created.status);
    const user = await created.json() as { id?: string };
    if (!user.id) throw new Error('acceptance_create_missing_id');
    state.accountID = user.id;
    writeFileSync(statePath, JSON.stringify(state), { mode: 0o600 });
  }
  if (!state.accountID) throw new Error('acceptance_creation_uncertain_no_replay');
  const signed = await fetch(url + '/auth/v1/token?grant_type=password', { method: 'POST', headers: { apikey: key!, 'Content-Type': 'application/json' }, body: JSON.stringify({ email: state.email, password: state.password }), signal: AbortSignal.timeout(20000) });
  if (!signed.ok) throw new Error('acceptance_signin_http_' + signed.status);
  const session = await signed.json() as { access_token?: string; refresh_token?: string; user?: { id?: string } };
  if (!session.access_token || session.user?.id !== state.accountID) throw new Error('acceptance_identity_mismatch');
  writeFileSync(statePath, JSON.stringify({ ...state, accessToken: session.access_token, refreshToken: session.refresh_token }), { mode: 0o600 });
  console.log(JSON.stringify({ observedAt: new Date().toISOString(), projectRef: ref, status: 'authenticated', accountID: state.accountID, expectedNewWorkspaceID: 'whisper-' + state.accountID, privateStatePath: statePath }));
}
main().catch(error => { console.error(JSON.stringify({ status: 'blocked', reason: error instanceof Error && /^[a-z0-9_]+$/.test(error.message) ? error.message : 'acceptance_provisioning_unavailable', accountProvisioned: 'unconfirmed' })); process.exitCode = 2; });
