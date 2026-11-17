// Refresh ONLY the existing dedicated acceptance session. No account creation,
// magic links, email, password reset, old work or capture/resume requests.
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
const repairScopes = process.argv.flatMap((arg, index) => arg === '--repair-scope' ? [process.argv[index + 1]] : []);
if (repairScopes.length > 1 || repairScopes.length && !/^20261114-[a-z][a-z0-9-]{0,60}$/.test(repairScopes[0] ?? '')) throw new Error('explicit_unique_repair_scope_required');
const repair = repairScopes.length === 1;
const diagnostic = process.argv.includes('--diagnostic-paid');
const replacement = process.argv.includes('--structured-replacement');
const structured = process.argv.includes('--structured');
if ([repair, diagnostic, replacement, structured].filter(Boolean).length > 1) throw new Error('distinct_refresh_scope_required');
const refreshIntentName = repair ? 'repair-' + repairScopes[0] + '-session-refresh-intent.json' : diagnostic ? 'diagnostic-paid-session-refresh-intent.json' : replacement ? 'structured-replacement-session-refresh-intent.json' : structured ? 'structured-session-refresh-intent.json' : 'speed-session-refresh-intent.json';
const projectRef = 'uryyyegnbtlmyhqlgndy', accountID = 'e00a9064-5f85-40bb-9f44-8bd60f90d24a';
const root = join(tmpdir(), 'knot-acceptance-uf26aun6d49w1tsjsm2u9');
function fact(value: unknown, reason: string): asserts value { if (!value) throw new Error(reason); }
function originalKey(value: string | undefined): value is string { try { return JSON.parse(Buffer.from(value!.split('.')[1], 'base64url').toString()).ref === projectRef; } catch { return false; } }
async function main() {
  const path = join(root, 'account.json'), state = JSON.parse(readFileSync(path, 'utf8'));
  fact(state.accountID === accountID && state.projectRef === projectRef && typeof state.accessToken === 'string', 'existing_identity_required');
  let key = [process.env.KNOT_ACCEPTANCE_SUPABASE_SERVICE_ROLE_KEY, process.env.SUPABASE_SERVICE_ROLE_KEY, process.env.SUPABASE_ANON_KEY, process.env.VITE_SUPABASE_ANON_KEY].find(originalKey);
  if (!key && process.env.SUPABASE_ACCESS_TOKEN) {
    const result = await fetch(`https://api.supabase.com/v1/projects/${projectRef}/api-keys`, { headers: { Authorization: 'Bearer ' + process.env.SUPABASE_ACCESS_TOKEN }, signal: AbortSignal.timeout(20000) });
    fact(result.ok, 'original_key_lookup_failed');
    key = ((await result.json()) as { api_key?: string }[]).map(item => item.api_key).find(originalKey);
  }
  fact(key, 'original_project_key_unavailable');
  const headers = { apikey: key, 'Content-Type': 'application/json' }, url = `https://${projectRef}.supabase.co`;
  const claims = JSON.parse(Buffer.from(state.accessToken.split('.')[1], 'base64url').toString());
  fact(claims.sub === accountID && claims.iss === url + '/auth/v1', 'existing_token_identity_mismatch');
  if (claims.exp * 1000 < Date.now() + 1200000) {
    fact(typeof state.refreshToken === 'string' && state.refreshToken, 'existing_refresh_token_required');
    writeFileSync(join(root, refreshIntentName), JSON.stringify({ accountID, projectRef, startedAt: new Date().toISOString(), method: 'existing_refresh_token', ...(repair ? { authorization: 'explicit_user_paid_document_repair_iterations_2026_11_14', scope: repairScopes[0] } : diagnostic ? { authorization: 'explicit_user_one_new_paid_document_request_2026_11_14' } : replacement ? { authorization: 'explicit_user_yes_one_replacement_fresh_measurement' } : {}), noAutomaticRetry: true }), { flag: 'wx', mode: 0o600 });
    const response = await fetch(url + '/auth/v1/token?grant_type=refresh_token', { method: 'POST', headers, body: JSON.stringify({ refresh_token: state.refreshToken }), signal: AbortSignal.timeout(20000) });
    fact(response.ok, 'existing_refresh_rejected');
    const session = await response.json() as { access_token?: string; refresh_token?: string; user?: { id?: string } };
    fact(session.user?.id === accountID && session.access_token && session.refresh_token, 'refreshed_identity_mismatch');
    state.accessToken = session.access_token; state.refreshToken = session.refresh_token;
    // Save refresh rotation immediately; never recreate or replay its intent.
    writeFileSync(path, JSON.stringify(state), { mode: 0o600 });
  }
  const response = await fetch(url + '/auth/v1/user', { headers: { ...headers, Authorization: 'Bearer ' + state.accessToken }, signal: AbortSignal.timeout(20000) });
  fact(response.ok, 'existing_user_read_failed');
  const user = await response.json() as { id?: string; email?: string; user_metadata?: Record<string, unknown> };
  fact(user.id === accountID && typeof user.email === 'string' && /^knot-acceptance-[a-f0-9-]+@example\.com$/.test(user.email) && user.user_metadata?.dedicated_knot_acceptance === true, 'dedicated_user_metadata_required');
  writeFileSync(path, JSON.stringify({ ...state, email: user.email, speedSessionPreparedAt: new Date().toISOString() }), { mode: 0o600 });
  console.log(JSON.stringify({ status: 'existing_dedicated_session_ready', accountID, projectRef, accountCreated: false, emailSent: false, credentialsPrinted: false }));
}
main().catch(error => { console.error(JSON.stringify({ status: 'blocked', reason: error instanceof Error && /^[a-z0-9_]+$/.test(error.message) ? error.message : 'session_preparation_unavailable' })); process.exitCode = 2; });
