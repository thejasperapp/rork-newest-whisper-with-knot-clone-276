// Summarize a private handoff without ever printing its text or credentials.
// Usage: bun scripts/inspect-sidecar-handoff.ts <file outside the repository>
import { readFile } from 'node:fs/promises';
const file = process.argv[2];
if (!file) throw new Error('A private handoff path is required.');
const text = await readFile(file, 'utf8');
if (Buffer.byteLength(text) > 100000) throw new Error('Handoff exceeds the inspection limit.');
const labels = ['SIDECAR_TOKEN_WHISPER', 'SIDECAR_TOKEN', 'SIDECAR_TOKEN_INSPECT', 'SIDECAR_TOKEN_WORKER'];
const placeholder = /^(?:<.*>|\[.*\]|\$\{?.*|redacted|placeholder|pending|tbd|not.set|your[_ -].*|new[_ -]token|rotated[_ -]value)$/i;
const inlineAssignments = [...text.matchAll(/\b([A-Z][A-Z0-9_]*(?:TOKEN|KEY|SECRET|PASSWORD)[A-Z0-9_]*)[^\S\n]*(?:=|:)[^\S\n]*["']?([^\s"'`,;]+)/g)];
const multilineAssignments = [...text.matchAll(/\b(SIDECAR_[A-Z_]+)\b[^\n]*\n([A-Za-z0-9_+\/=-]{24,})\s*(?:\n|$)/g)];
const assignments = [...inlineAssignments, ...multilineAssignments];
if (process.argv.includes('--labels')) {
  const lines = text.split(/\r?\n/).map(line => line.trim()).filter(Boolean);
  console.log(JSON.stringify({ labels: lines.flatMap((line, index) => {
    const label = line.match(/\bSIDECAR_[A-Z_]+\b/);
    if (!label) return [];
    const next = lines[index + 1] ?? '';
    return [{ label: label[0], nextLineLooksLikeValue: /^[A-Za-z0-9_+\/=-]{24,}$/.test(next) && !placeholder.test(next) }];
  }) }, null, 2));
  process.exit(0);
}
const possibleCredentialValues = assignments.filter(match => !placeholder.test(match[2]) && match[2].length >= 16).length;
if (process.argv.includes('--contract')) {
  // Redact the entire credential-bearing line, not just an assumed token shape.
  const sanitized = text.split('\n').map(line => /token|password|secret|authorization|bearer|private.key/i.test(line) ? '[credential-related line omitted]' : line)
    .join('\n').replace(/[A-Za-z0-9_+\/=-]{28,}/g, '[long value omitted]');
  console.log(sanitized);
  process.exit(0);
}
console.log(JSON.stringify({
  bytes: Buffer.byteLength(text),
  knownLabelsPresent: labels.filter(label => text.includes(label)),
  possibleCredentialAssignments: possibleCredentialValues,
  whisperCredentialLooksLikeSecret: assignments.some(match => match[1] === 'SIDECAR_TOKEN_WHISPER' && !placeholder.test(match[2]) && (/[a-f0-9]{32,}/i.test(match[2]) || (match[2].length >= 24 && /[a-z]/i.test(match[2]) && /[0-9]/.test(match[2])))),
  missingProtocolDocument: !/\/sessions\b/.test(text),
  mentionsBearer: /\bbearer\b/i.test(text),
  mentionsRotation: /rotat/i.test(text),
  mentionsDylan: /\bdylan\b/i.test(text),
  mentionsBackendSecrets: /backend[\s\S]{0,60}(?:secret|environment)|server[ -]only/i.test(text),
  protocol: {
    sessions: /\/sessions\b/.test(text),
    polling: /poll|terminal/i.test(text),
    stdout: /stdout/i.test(text), stderr: /stderr/i.test(text),
    exitCode: /exit[_ -]?code/i.test(text),
    cancellation: /cancel|abort/i.test(text),
    isolation: /isolat|container|sandbox/i.test(text),
  },
  // Presence of prose never proves rotation or a deployed credential.
  rotationIndependentlyVerified: false,
}, null, 2));
