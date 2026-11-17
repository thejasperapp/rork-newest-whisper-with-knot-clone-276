// Read-only operator diagnostic. No gateway, member, workspace or task calls.
// rork env run -- bun scripts/inspect-knot-environment-parity.ts
// Compares CLI-visible values using an ephemeral proof; never prints values or proofs.
// Protected managed keys are excluded by env run. Absent production values do not
// imply missing runtime bindings, and inherited development values may be stale.
import { createHmac, randomBytes } from 'node:crypto';
import { execFileSync } from 'node:child_process';
const names = ['EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY', 'RORK_TOOLKIT_SECRET_KEY', 'EXPO_PUBLIC_RORK_APP_KEY'] as const;
if (process.argv.includes('--proof')) {
  const nonce = process.env.KNOT_ENV_COMPARISON_NONCE;
  if (!nonce || !/^[a-f0-9]{64}$/.test(nonce)) throw new Error('Comparison configuration missing.');
  console.log(JSON.stringify(Object.fromEntries(names.map(name => [name, process.env[name]
    ? createHmac('sha256', nonce).update(process.env[name]!).digest('hex') : null]))));
  process.exit(0);
}
const nonce = randomBytes(32).toString('hex');
const childEnv = { ...process.env, KNOT_ENV_COMPARISON_NONCE: nonce };
for (const name of names) delete childEnv[name];
let production: Record<string, string | null>;
try {
  production = JSON.parse(execFileSync('rork', ['env', 'run', '-e', 'production', '--', 'bun', import.meta.path, '--proof'], {
    env: childEnv, encoding: 'utf8', timeout: 30000, stdio: ['ignore', 'pipe', 'pipe'],
  }));
  for (const name of names) if (production[name] !== null && !/^[a-f0-9]{64}$/.test(production[name] ?? '')) throw new Error();
} catch { throw new Error('Production credential comparison unavailable. No credential contents logged.'); }
console.log(JSON.stringify({ check: 'ai_environment_parity', observedAt: new Date().toISOString(),
  credentials: Object.fromEntries(names.map(name => [name, {
    developmentPresent: !!process.env[name], productionPresent: !!production[name],
    matches: process.env[name] && production[name]
      ? createHmac('sha256', nonce).update(process.env[name]!).digest('hex') === production[name] : null,
  }])), managedRuntimeIdentityVerified: false, gatewayRequestPerformed: false }));
export {};
