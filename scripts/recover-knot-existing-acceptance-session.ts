// Recover ONLY the original dedicated acceptance user. No new-account branch,
// password change, email delivery, project/config mutation or credential output.
// rork env run -- bun scripts/recover-knot-existing-acceptance-session.ts
import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
const ref = 'uryyyegnbtlmyhqlgndy', accountID = 'e00a9064-5f85-40bb-9f44-8bd60f90d24a';
const url = `https://${ref}.supabase.co`;
const directory = join(tmpdir(), 'knot-acceptance-uf26aun6d49w1tsjsm2u9');
const accountPath = join(directory, 'account.json');
function fact(value: unknown, code: string): asserts value { if (!value) throw new Error(code); }
function originalAdmin(key: string | undefined): key is string { try { const v = JSON.parse(Buffer.from(key!.split('.')[1], 'base64url').toString()); return v.ref === ref && v.role === 'service_role'; } catch { return false; } }
async function main() {
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  if (existsSync(accountPath)) {
    const saved = JSON.parse(readFileSync(accountPath, 'utf8'));
    fact(saved.accountID === accountID && saved.projectRef === ref, 'existing_identity_mismatch');
    const claims = JSON.parse(Buffer.from(saved.accessToken.split('.')[1], 'base64url').toString());
    if (claims.sub === accountID && claims.exp * 1000 > Date.now() + 180000) { console.log(JSON.stringify({ status: 'existing_session_retained', accountID })); return; }
  }
  let key = [process.env.KNOT_ACCEPTANCE_SUPABASE_SERVICE_ROLE_KEY, process.env.SUPABASE_SERVICE_ROLE_KEY].find(originalAdmin);
  if (!key && process.env.SUPABASE_ACCESS_TOKEN) {
    const response = await fetch(`https://api.supabase.com/v1/projects/${ref}/api-keys`, { headers: { Authorization: 'Bearer ' + process.env.SUPABASE_ACCESS_TOKEN }, signal: AbortSignal.timeout(20000) });
    fact(response.ok, 'admin_lookup_http_' + response.status);
    const values = await response.json() as { api_key?: string }[];
    key = values.map(v => v.api_key).find(originalAdmin);
  }
  fact(key, 'original_admin_unavailable');
  const headers = { apikey: key, Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' };
  const response = await fetch(url + '/auth/v1/admin/users/' + accountID, { headers, signal: AbortSignal.timeout(20000) });
  fact(response.ok, 'existing_user_http_' + response.status);
  const user = await response.json() as { id?: string; email?: string; user_metadata?: Record<string, unknown> };
  fact(user.id === accountID && typeof user.email === 'string' && /^knot-acceptance-[a-f0-9-]+@example\.com$/.test(user.email) && user.user_metadata?.dedicated_knot_acceptance === true, 'exact_existing_dedicated_user_required');
  const intent = join(directory, 'existing-session-recovery-intent.json');
  fact(!existsSync(intent), 'session_recovery_already_attempted_no_automatic_replay');
  writeFileSync(intent, JSON.stringify({ accountID, projectRef: ref, startedAt: new Date().toISOString(), method: 'admin_magiclink_verify_no_send', createsAccount: false, passwordReset: false }), { flag: 'wx', mode: 0o600 });
  const generated = await fetch(url + '/auth/v1/admin/generate_link', { method: 'POST', headers, body: JSON.stringify({ type: 'magiclink', email: user.email }), signal: AbortSignal.timeout(20000) });
  fact(generated.ok, 'link_generation_http_' + generated.status);
  const link = await generated.json() as { id?: string; hashed_token?: string };
  fact(link.id === accountID && link.hashed_token, 'generated_link_identity_mismatch');
  const verified = await fetch(url + '/auth/v1/verify', { method: 'POST', headers, body: JSON.stringify({ type: 'email', token_hash: link.hashed_token }), signal: AbortSignal.timeout(20000) });
  fact(verified.ok, 'session_verification_http_' + verified.status);
  const session = await verified.json() as { access_token?: string; refresh_token?: string; user?: { id?: string } };
  fact(session.access_token && session.user?.id === accountID, 'verified_identity_mismatch');
  writeFileSync(accountPath, JSON.stringify({ projectRef: ref, accountID, accessToken: session.access_token, refreshToken: session.refresh_token, recoveredAt: new Date().toISOString() }), { mode: 0o600 });
  console.log(JSON.stringify({ status: 'same_dedicated_user_authenticated', accountID, projectRef: ref, noAccountCreation: true, noEmailSent: true, noPasswordChange: true }));
}
main().catch(error => { console.error(JSON.stringify({ status: 'blocked', reason: error instanceof Error && /^[a-z0-9_]+$/.test(error.message) ? error.message : 'session_recovery_unavailable' })); process.exitCode = 2; });
