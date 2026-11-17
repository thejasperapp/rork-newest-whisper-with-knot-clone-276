// Metadata/equality only. Never prints credential values, prefixes, suffixes or digests.
// env -u EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY -u RORK_TOOLKIT_SECRET_KEY -u EXPO_PUBLIC_RORK_APP_KEY rork env run -- bun scripts/inspect-knot-credential-sources.ts
// Protected managed keys are excluded by env run. Process values may be inherited
// and stale; presence, absence or equality here cannot certify runtime key identity.
import { readFileSync } from 'node:fs';
const name = 'EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY';
const injected = process.env[name];
function dotenv(path: string): string | undefined {
  try {
    const raw = readFileSync(path, 'utf8');
    const match = raw.match(new RegExp('^' + name + '=(.*)$', 'm'));
    if (!match) return undefined;
    const text = match[1].trim();
    if (text.startsWith('"')) { try { return JSON.parse(text); } catch { return undefined; } }
    return text.startsWith("'") && text.endsWith("'") ? text.slice(1, -1) : text;
  } catch { return undefined; }
}
function swift(): string | undefined {
  try {
    const raw = readFileSync('ios/Whisper/Config.swift', 'utf8');
    const match = raw.match(new RegExp('"' + name + '"\\s*:\\s*("(?:[^"\\\\]|\\\\.)*")'));
    return match ? JSON.parse(match[1]) : undefined;
  } catch { return undefined; }
}
function metadata(value: string | undefined) {
  return { present: !!value, length: value?.length ?? 0, trimmed: value ? value === value.trim() : null,
    printableASCII: value ? /^[\x21-\x7e]+$/.test(value) : null,
    placeholderLike: value ? /placeholder|redacted|your[_-]?(?:api)?[_-]?key|managed[_-]?(?:secret|credential)|undefined|null/i.test(value) : null,
    matchesInjected: value && injected ? value === injected : null };
}
console.log(JSON.stringify({ check: 'credential_source_metadata', observedAt: new Date().toISOString(),
  injected: metadata(injected), privateBinding: metadata(process.env.RORK_TOOLKIT_SECRET_KEY),
  rootManagedFile: metadata(dotenv('.env')), webManagedFile: metadata(dotenv('web-whisperweb/.env')), nativeGeneratedConfig: metadata(swift()),
  managedRuntimeIdentityVerified: false, gatewayRequestPerformed: false }));
export {};
