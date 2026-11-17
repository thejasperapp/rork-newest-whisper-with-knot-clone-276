// Read-only configuration checks for this clone's managed backend only.
// No generation, account/session access, workspace access, key writes or retries.
// Run: rork env run -p mayokn2749ag072e3uvbh -- bun scripts/inspect-knot-clone-cloud-binding.ts
import { createHmac, randomBytes } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { parseEnv } from 'node:util';

const project = 'mayokn2749ag072e3uvbh';
const originalProject = 'uf26aun6d49w1tsjsm2u9';
const managedKeyID = 'sk_0gbdem17'; // Observed owner-requested second rotation metadata; not a credential.
const backend = 'https://newest-whisper-with-knot-clone-t6ui3ur-backend.rork.app';
const operator = process.env.BROADCAST_SECRET;
if (!operator) throw new Error('Operator configuration unavailable; no requests made.');
const credentialName = 'EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY';
function isPlaceholder(token: string | undefined) {
  return !!token && /placeholder|redacted|delegated|__rork/i.test(token);
}
function hints(token: string | undefined) {
  let decoded: unknown = null;
  try {
    const parts = token?.split('.');
    if (parts?.length === 3) decoded = JSON.parse(Buffer.from(parts[1]!, 'base64url').toString('utf8'));
  } catch { /* Opaque credentials remain opaque. */ }
  const claimText = decoded && typeof decoded === 'object' ? JSON.stringify(decoded) : '';
  return {
    present: !!token,
    decodableUnverifiedClaims: !!claimText,
    referencesCurrentProject: !!token?.includes(project) || claimText.includes(project),
    referencesOriginalProject: !!token?.includes(originalProject) || claimText.includes(originalProject),
    referencesReportedManagedKeyID: !!token?.includes(managedKeyID) || claimText.includes(managedKeyID),
  };
}
async function get(path: '/admin/knot-text-policy' | '/admin/knot-key-binding', proofHeaders: Record<string, string> = {}) {
  const response = await fetch(backend + path, {
    method: 'GET', redirect: 'error', signal: AbortSignal.timeout(15000),
    headers: { 'X-Whisper-Operator': operator!, ...proofHeaders },
  });
  if (!response.ok) return { status: response.status, value: null };
  return { status: response.status, value: await response.json() as Record<string, unknown> };
}
async function compare(token: string) {
  const nonce = randomBytes(32).toString('hex');
  const result = await get('/admin/knot-key-binding', {
    'X-Whisper-Key-Nonce': nonce,
    'X-Whisper-Key-Proof': createHmac('sha256', token).update('whisper-knot-key-binding-v1:' + nonce).digest('hex'),
  });
  return {
    status: result.status,
    credentialPresent: result.value?.credentialPresent === true,
    credentialSource: result.value?.credentialSource === 'managed' ? 'managed' : result.value?.credentialSource === 'missing' ? 'missing' : 'unavailable',
    matchesCandidate: result.value ? result.value.credentialMatches === true : null,
  };
}
try {
  const policy = await get('/admin/knot-text-policy');
  const candidates: { source: string; token: string }[] = [];
  const inherited = process.env[credentialName];
  if (inherited && !isPlaceholder(inherited)) candidates.push({ source: 'inherited_process_not_authoritative', token: inherited });
  const localPresence: { source: string; present: boolean; explicitPlaceholderMarker: boolean }[] = [];
  let generatedNativeStructure: Record<string, boolean> | undefined;
  for (const file of ['.env', 'ios/.env', 'web-whisperweb/.env', 'functions/.env']) {
    const path = resolve(file);
    if (!existsSync(path)) continue;
    // Consume only public configuration; never print file contents or other values.
    const token = parseEnv(readFileSync(path, 'utf8'))[credentialName];
    const explicitPlaceholderMarker = isPlaceholder(token);
    localPresence.push({ source: file, present: !!token, explicitPlaceholderMarker });
    // Browser delegated-auth placeholders are not a managed-key identity source.
    if (token && !explicitPlaceholderMarker) candidates.push({ source: file, token });
  }
  if (process.argv.includes('--native-generated-candidate')) {
    const path = resolve('ios/Whisper/Config.swift');
    if (existsSync(path)) {
      const source = readFileSync(path, 'utf8');
      generatedNativeStructure = {
        containsManagedCredentialName: source.includes(credentialName),
        usesAllValues: source.includes('allValues'),
        usesBase64: /base64Encoded|base64EncodedString/.test(source),
        usesJSONSerialization: source.includes('JSONSerialization'),
        usesEnvironmentLookup: source.includes('ProcessInfo'),
        usesBundleLookup: source.includes('Bundle.main'),
      };
      // Support dictionary literals and typed/untyped static assignments
      // without printing source or credential bytes.
      const match = /"EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY"\s*:\s*("(?:[^"\\]|\\.)*")/.exec(source)
        ?? /EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY\s*(?::\s*String\s*)?=\s*("(?:[^"\\]|\\.)*")/.exec(source);
      const token = match ? JSON.parse(match[1]!) as string : undefined;
      generatedNativeStructure.literalFound = !!match;
      generatedNativeStructure.literalEmpty = !!match && token === '';
      const explicitPlaceholderMarker = isPlaceholder(token);
      localPresence.push({ source: 'generated_native_configuration_not_independent_key_authority', present: !!token, explicitPlaceholderMarker });
      if (token && !explicitPlaceholderMarker) candidates.push({ source: 'generated_native_configuration_not_independent_key_authority', token });
    }
  }
  const comparisons = [];
  const seen = new Map<string, number>();
  for (const candidate of candidates) {
    const sameAs = seen.get(candidate.token);
    if (sameAs !== undefined) {
      comparisons.push({ source: candidate.source, hints: hints(candidate.token), sameCandidateAsIndex: sameAs });
    } else {
      seen.set(candidate.token, comparisons.length);
      comparisons.push({ source: candidate.source, hints: hints(candidate.token), runtimeComparison: await compare(candidate.token) });
    }
  }
  const audit = {
    check: 'clone_managed_cloud_configuration', observedAt: new Date().toISOString(), project, backend,
    reportedManagedKeyID: managedKeyID, reportedIdentityIsNotRuntimeByteProof: true,
    policy: {
      status: policy.status,
      tokenPresent: policy.value?.tokenPresent === true,
      gatewayValid: policy.value?.gatewayValid === true,
      provider: policy.value?.provider === 'rork' ? 'rork' : 'unavailable',
      routingPolicy: policy.value?.routingPolicy === 'rork_cloud_only_v1' ? 'rork_cloud_only_v1' : 'unavailable',
      credentialSource: policy.value?.credentialSource === 'managed' ? 'managed' : 'unavailable',
      addressOverridePresent: policy.value?.addressOverridePresent === true,
    },
    inheritedCandidate: { present: !!inherited, explicitPlaceholderMarker: isPlaceholder(inherited) },
    localPresence, generatedNativeStructure, comparisons,
    managedRuntimeIdentityVerified: false, billingAssociationVerified: false,
    gatewayRequestPerformed: false, generationPerformed: false,
  };
  const serialized = JSON.stringify(audit, null, 2) + '\n';
  if (process.argv.includes('--record-rotation-02')) {
    writeFileSync(resolve('deliveries/clone-cloud-binding-20261114-rotation-02.json'), serialized, { flag: 'wx' });
  }
  console.log(serialized);
  if (policy.status !== 200) process.exitCode = 1;
} catch {
  console.error('Read-only Cloud configuration check unavailable; no credential contents logged.');
  process.exitCode = 1;
}
export {};
