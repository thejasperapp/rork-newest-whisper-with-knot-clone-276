// Owner-authorized isolated native UI account. Credentials remain in private OS
// temporary storage, never printed. No personal/existing account is read or changed.
// Prepare once: rork env run -- bun scripts/knot-native-ui-acceptance-account.ts --prepare
// Type observed fields: bun scripts/knot-native-ui-acceptance-account.ts --email e5 --sim <id>
//                     bun scripts/knot-native-ui-acceptance-account.ts --password e6 --sim <id>
import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { randomBytes, randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
const projectRef = 'uryyyegnbtlmyhqlgndy';
const directory = join(tmpdir(), process.argv.includes('--fresh-polish-20261115') ? 'knot-native-polish-mayokn2749ag072e3uvbh-20261115' : 'knot-native-ui-mayokn2749ag072e3uvbh-20261114');
const statePath = join(directory, 'account.json');
const value = (flag: string) => process.argv[process.argv.indexOf(flag) + 1];
function fact(ok: unknown, reason: string): asserts ok { if (!ok) throw new Error(reason); }
type State = { projectRef: string; email: string; password: string; accountID?: string; creationIntentAt: string };
async function main() {
  if (process.argv.includes('--prepare')) {
    const key = process.env.KNOT_ACCEPTANCE_SUPABASE_SERVICE_ROLE_KEY;
    fact(key, 'dedicated_admin_credential_unavailable');
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    fact(!existsSync(statePath), 'native_account_scope_already_attempted_no_replay');
    const state: State = { projectRef, email: `knot-native-ui-${randomUUID()}@example.com`, password: randomBytes(32).toString('base64url'), creationIntentAt: new Date().toISOString() };
    writeFileSync(statePath, JSON.stringify(state), { mode: 0o600, flag: 'wx' });
    const response = await fetch(`https://${projectRef}.supabase.co/auth/v1/admin/users`, { method: 'POST', redirect: 'error', headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ email: state.email, password: state.password, email_confirm: true, user_metadata: { dedicated_knot_acceptance: true, native_ui_acceptance: true, full_name: 'Knot QA' } }), signal: AbortSignal.timeout(20000) });
    fact(response.ok, 'native_account_create_http_' + response.status);
    const user = await response.json() as { id?: string; email?: string; user_metadata?: Record<string, unknown> };
    fact(user.id && user.email === state.email && user.user_metadata?.native_ui_acceptance === true, 'created_native_identity_mismatch');
    writeFileSync(statePath, JSON.stringify({ ...state, accountID: user.id }), { mode: 0o600 });
    console.log(JSON.stringify({ status: 'new_dedicated_native_account_created', accountID: user.id, workspaceID: 'whisper-' + user.id, projectRef, emailSent: false, personalAccountAccessed: false, credentialsPrinted: false }));
    return;
  }
  if (process.argv.includes('--verify-login')) {
    const state = JSON.parse(readFileSync(statePath, 'utf8')) as State;
    const key = process.env.KNOT_ACCEPTANCE_SUPABASE_SERVICE_ROLE_KEY;
    fact(state.projectRef === projectRef && state.accountID && key, 'dedicated_native_identity_required');
    const response = await fetch(`https://${projectRef}.supabase.co/auth/v1/token?grant_type=password`, { method: 'POST', redirect: 'error', headers: { apikey: key, 'Content-Type': 'application/json' }, body: JSON.stringify({ email: state.email, password: state.password }), signal: AbortSignal.timeout(20000) });
    fact(response.ok, 'native_password_verification_http_' + response.status);
    const session = await response.json() as { access_token?: string; refresh_token?: string; user?: { id?: string } };
    fact(session.user?.id === state.accountID && session.access_token && session.refresh_token, 'native_password_identity_mismatch');
    writeFileSync(join(directory, 'api-session.json'), JSON.stringify({ projectRef, accountID: state.accountID, accessToken: session.access_token, refreshToken: session.refresh_token }), { mode: 0o600 });
    console.log(JSON.stringify({ status: 'dedicated_native_password_verified', accountID: state.accountID, credentialsPrinted: false }));
    return;
  }
  const modes = ['--email', '--password'].filter(flag => process.argv.includes(flag));
  fact(modes.length === 1 && process.argv.includes('--sim'), 'one_observed_field_and_sim_required');
  const ref = value(modes[0]), sim = value('--sim');
  fact(/^e\d+$/.test(ref) && /^ios_[a-z0-9_]+$/.test(sim), 'invalid_observed_field_or_sim');
  const state = JSON.parse(readFileSync(statePath, 'utf8')) as State;
  fact(state.projectRef === projectRef && state.accountID && /^knot-native-ui-[a-f0-9-]+@example\.com$/.test(state.email) && state.password.length > 32, 'dedicated_native_identity_required');
  const text = modes[0] === '--email' ? state.email : state.password;
  if (process.argv.includes('--focused')) {
    const focused = spawnSync('rork', ['sim', 'tap', ref, '--sim', sim, '--json'], { encoding: 'utf8', timeout: 60000 });
    fact(focused.status === 0, 'private_native_field_focus_failed');
  }
  const result = spawnSync('rork', ['sim', 'type', ...(process.argv.includes('--focused') ? [text] : [ref, text]), '--sim', sim, '--json'], { encoding: 'utf8', timeout: 60000 });
  // Never forward CLI stdout/stderr: it may repeat supplied text on a failure.
  fact(result.status === 0, 'private_native_field_entry_failed');
  console.log(JSON.stringify({ status: 'private_field_entered', field: modes[0].slice(2), credentialsPrinted: false }));
}
main().catch(error => { console.error(JSON.stringify({ status: 'blocked', reason: error instanceof Error && /^[a-z0-9_]+$/.test(error.message) ? error.message : 'native_account_operation_unconfirmed_no_replay' })); process.exitCode = 2; });
