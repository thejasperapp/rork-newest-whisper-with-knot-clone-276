// Install only the explicitly labeled Whisper credential using the CLI's stdin.
// Never print values, pass them as arguments, or import this in an app.
import { readFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
const file = process.argv[2];
if (!file) throw new Error('Private handoff path required.');
const text = await readFile(file, 'utf8');
if (text.length > 10000) throw new Error('Invalid handoff size.');
const lines = text.split(/\r?\n/).map(line => line.trim()).filter(Boolean);
const matches = lines.flatMap((line, i) => /\bSIDECAR_TOKEN_WHISPER\b/.test(line) ? [lines[i + 1]] : []);
if (matches.length !== 1 || !matches[0] || !/^[A-Za-z0-9_+\/=-]{32,256}$/.test(matches[0])) throw new Error('Exactly one labeled Whisper secret is required; no value was emitted.');
if (process.argv.includes('--verify')) {
  console.log(JSON.stringify({ dedicatedWhisperSecretMatchesHandoff: process.env.SIDECAR_TOKEN_WHISPER === matches[0] }));
  if (process.env.SIDECAR_TOKEN_WHISPER !== matches[0]) process.exitCode = 1;
} else if (process.argv.includes('--install')) {
  const child = spawn('rork', ['env', 'set', 'SIDECAR_TOKEN_WHISPER', '--secret', '-e', 'all'], { stdio: ['pipe', 'inherit', 'inherit'] });
  child.stdin.end(matches[0]);
  const exit = await new Promise<number>((resolve, reject) => {
    child.once('error', () => reject(new Error('Secret installation could not start.')));
    child.once('exit', code => resolve(code ?? 1));
  });
  process.exitCode = exit;
} else console.log(JSON.stringify({ validDedicatedWhisperCredential: true }));
