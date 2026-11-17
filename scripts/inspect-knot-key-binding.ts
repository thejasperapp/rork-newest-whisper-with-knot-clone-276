// Operator-only configuration observation. No network requests, member data,
// credential values, arbitrary JWT claims, or billing/account mutations.
// rork env run -- bun scripts/inspect-knot-key-binding.ts
import { createHmac, randomBytes } from 'node:crypto';
import { execFileSync } from 'node:child_process';
const credentialNames = ['EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY', 'RORK_TOOLKIT_SECRET_KEY', 'EXPO_PUBLIC_RORK_APP_KEY'] as const;
// Compare the injected project environment with Bun's local managed .env loading.
// Child output is nonce-qualified HMAC only, consumed here and never logged.
if (process.argv.includes('--local-proof')) {
  const nonce = process.env.KNOT_KEY_COMPARISON_NONCE;
  if (!nonce) throw new Error('Comparison nonce missing.');
  console.log(JSON.stringify(Object.fromEntries(credentialNames.map(name => [name,
    process.env[name] ? createHmac('sha256', nonce).update(process.env[name]!).digest('hex') : null]))));
  process.exit(0);
}
const nonce = randomBytes(32).toString('hex');
const localEnvironment = { ...process.env, KNOT_KEY_COMPARISON_NONCE: nonce };
for (const name of credentialNames) delete localEnvironment[name];
let localProof: Record<string, string | null>;
try {
  localProof = JSON.parse(execFileSync(process.execPath, [import.meta.path, '--local-proof'], {
    env: localEnvironment, encoding: 'utf8', timeout: 15000, stdio: ['ignore', 'pipe', 'pipe'],
  }));
} catch { throw new Error('Local managed-environment comparison unavailable.'); }
const localComparisons = Object.fromEntries(credentialNames.map(name => {
  const value = process.env[name];
  return [name, { injectedPresent: !!value, localPresent: !!localProof[name],
    matches: value && localProof[name] ? createHmac('sha256', nonce).update(value).digest('hex') === localProof[name] : null }];
}));
const currentProject = 'uf26aun6d49w1tsjsm2u9';
const legacyProject = 'spotxaa2tx3bjiagxo5lh';
const reportedKeyID = 'sk_wl7gqruv';
function hints(value: string | undefined) {
  let decoded: Record<string, unknown> | undefined;
  if (value) {
    const parts = value.split('.');
    if (parts.length === 3) {
      try {
        const parsed: unknown = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
        if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) decoded = parsed as Record<string, unknown>;
      } catch { /* Opaque credentials need platform-side binding verification. */ }
    }
  }
  const references: Record<string, 'current' | 'legacy' | 'other'> = {};
  for (const field of ['projectId', 'project_id', 'appId', 'app_id', 'aud']) {
    const claim = decoded?.[field];
    if (typeof claim === 'string') references[field] = claim === currentProject ? 'current' : claim === legacyProject ? 'legacy' : 'other';
  }
  return { present: !!value, containsReportedKeyID: !!value?.includes(reportedKeyID),
    literalCurrentProjectReference: !!value?.includes(currentProject), literalLegacyProjectReference: !!value?.includes(legacyProject),
    decodableUnverifiedClaims: !!decoded, unverifiedProjectHints: references };
}
const managed = process.env.EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY;
const override = process.env.RORK_TOOLKIT_SECRET_KEY;
let backend: 'current' | 'legacy' | 'other' | 'unset' = 'unset';
try {
  const value = process.env.EXPO_PUBLIC_RORK_FUNCTIONS_URL;
  if (value) {
    const hostname = new URL(value).hostname;
    backend = hostname === `${currentProject}-backend.rork.app` ? 'current' : hostname === `${legacyProject}-backend.rork.app` ? 'legacy' : 'other';
  }
} catch { backend = 'other'; }
console.log(JSON.stringify({ check: 'local_key_binding_hints', observedAt: new Date().toISOString(),
  managedCredential: hints(managed), privateOverride: hints(override), appKey: hints(process.env.EXPO_PUBLIC_RORK_APP_KEY),
  selectedCredentialMatchesManaged: !!managed && (override || managed) === managed,
  configuredFunctionsHost: backend, localManagedEnvironmentComparison: localComparisons,
  billingAssociationVerified: false, gatewayRequestPerformed: false }));
export {};
