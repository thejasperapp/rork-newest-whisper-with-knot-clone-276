// Operator-authenticated fixed synthetic protocol diagnosis only.
// rork env run -- bun scripts/knot-structured-output-probe.ts [--mode=production-bound|beta|beta-production-bound]
// Managed AI credentials remain in the deployed worker. No member data, workspace,
// command, prompt/schema overrides, automatic retries or fallback.
import { mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const operator = process.env.BROADCAST_SECRET;
if (!operator) throw new Error('operator_configuration_required');
const mode = process.argv.find(arg => arg.startsWith('--mode='))?.slice(7) ?? 'compare';
if (!['compare', 'production-bound', 'beta', 'beta-production-bound'].includes(mode)) throw new Error('invalid_probe_mode');
const directory = join(tmpdir(), 'knot-structured-output-' + new Date().toISOString().replace(/[:.]/g, '-'));
mkdirSync(directory, { mode: 0o700 });
const checks = mode === 'beta-production-bound' ? ['authoring-beta-bound'] : mode === 'beta' ? ['authoring-beta'] : mode === 'production-bound' ? ['authoring-bound'] : ['authoring-chat', 'authoring-messages'];
for (const check of checks) {
  const response = await fetch('https://uf26aun6d49w1tsjsm2u9-backend.rork.app/admin/knot-text-transport?check=' + check, { method: 'POST', redirect: 'error', headers: { 'X-Whisper-Operator': operator }, signal: AbortSignal.timeout(70000) });
  if (!response.ok) { await response.body?.cancel(); throw new Error('operator_check_http_' + response.status); }
  // This route returns only server-allowlisted categories and numeric/hash facts.
  const result = await response.json() as Record<string, unknown>;
  writeFileSync(join(directory, check + '.json'), JSON.stringify(result, null, 2), { mode: 0o600 });
  console.log(JSON.stringify({ ...result, evidence: directory }));
  if (result.completed !== true) process.exitCode = 1;
}
