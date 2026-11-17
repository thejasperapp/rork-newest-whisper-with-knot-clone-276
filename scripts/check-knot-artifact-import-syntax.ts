// Static-only validation. Parses generated transport as shell/Python without
// executing it. No network, credentials, member data, jobs or behavior tests.
import { spawnSync } from 'node:child_process';
import { artifactImportCommand } from '../functions/knot-artifact-import';

const id = '00000000-0000-4000-8000-000000000001';
const input = { messageID: id, sequence: 0, offset: 0, document: {
  id: 'a'.repeat(64), provenance: { senderID: id, senderName: '@Café — "syntax" \\ 🪢', sentAt: '2026-11-14T00:00:00Z', savedAt: '2026-11-14T00:00:00Z', messageID: id, originalDocumentID: 'b'.repeat(64) },
} };
const resource = { resource: 0, size: 48000, sha256: 'b'.repeat(64), path: 'syntax-only.html' };
for (const [label, command] of [
  ['full chunk', artifactImportCommand(input, resource, new Uint8Array(48000))],
  ['provenance', artifactImportCommand(input)],
] as const) {
  const source = command.slice(command.indexOf('\n') + 1, command.lastIndexOf('\n'));
  const python = spawnSync('python3', ['-I', '-c', 'import ast,sys; ast.parse(sys.stdin.read())'], { input: source, encoding: 'utf-8' });
  const shell = spawnSync('bash', ['--noprofile', '--norc', '-n'], { input: command, encoding: 'utf-8' });
  const bodyBytes = Buffer.byteLength(JSON.stringify({ user_id: 'whisper-' + 'a'.repeat(48), command, background: true, timeout_ms: 30000 }));
  if (python.status !== 0 || shell.status !== 0 || bodyBytes > 100000) throw new Error('Invalid generated import transport: ' + label);
  console.log(JSON.stringify({ label, shellSyntax: 'valid', pythonSyntax: 'valid', requestBytes: bodyBytes, executed: false }));
}
