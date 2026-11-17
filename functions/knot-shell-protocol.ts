/** Harness-owned command boundaries in the provider's cumulative byte-offset log.
 * These are shell-reported command receipts, not provider session exit records.
 * Missing/duplicate markers, log gaps or surviving background jobs never prove completion. */
export type ShellBoundary = { nonce: string; offset: number; stdoutBefore: number; stderrBefore: number; startedAt: string; endedAt?: string };
export type BoundaryResult = { stdout: string; stderr: string; exitCode: number; stdoutStart: number; stdoutEnd: number; stderrStart: number; stderrEnd: number; background: boolean };
const quote = (v: string) => "'" + v.replace(/'/g, "'\\''") + "'";
export function memoryAppendText(command: string): string | undefined {
  const header = "cat >> MEMORY.md <<'KNOT_MEMORY'\n";
  if (!command.startsWith(header) || !command.endsWith('\nKNOT_MEMORY')) return undefined;
  const text = command.slice(header.length, -'\nKNOT_MEMORY'.length);
  return text.trim() && !text.split('\n').includes('KNOT_MEMORY') && /^\d{4}-\d{2}-\d{2}/m.test(text) ? text + '\n' : undefined;
}
export function attachedShellInput(command: string, timeoutMs: number, nonce: string, workspaceMemory = false): string {
  if (!/^[a-f0-9]{32}$/.test(nonce)) throw new Error('invalid_boundary');
  const prefix = `KNOT_${nonce}`, variable = `__knot_${nonce}`;
  // Work eval runs in the same shell: cwd and exported environment persist.
  // Memory and inventory use the shell's original workspace directory in a subshell,
  // so a prior task's cd cannot move the account's durable MEMORY.md.
  const append = memoryAppendText(command);
  // The model authors the append. The harness only reads it back and verifies
  // the exact appended bytes; exit zero alone cannot mark durable memory saved.
  const verification = append === undefined ? '' : `\nif [ $? -eq 0 ]; then\npython3 - <<'KNOT_MEMORY_READBACK'\nfrom pathlib import Path\nimport hashlib, json\np=Path('MEMORY.md')\nassert not p.is_symlink() and p.is_file()\ndata=p.read_bytes()\nexpected=${JSON.stringify(append)}.encode('utf-8')\nassert data.endswith(expected)\nprint('KNOT_MEMORY_VERIFIED_V1 '+json.dumps(dict(bytes=len(data),sha256=hashlib.sha256(data).hexdigest()),separators=(',',':')))\nKNOT_MEMORY_READBACK\nelse false; fi`;
  const evaluate = workspaceMemory
    ? `(builtin cd -- "$__knot_harness_workspace_root_v1" && { ${append === undefined ? '' : 'test ! -L MEMORY.md && '}builtin eval -- ${quote(command)}${verification}\n}) </dev/null`
    : `builtin eval -- ${quote(command)} </dev/null`;
  // The watchdog bounds shell execution; the actor also enforces the deadline and
  // DELETEs the owned session on timeout/cancellation. No timed-out input is replayed.
  return `set +e\nif [ -z "\${__knot_harness_workspace_root_v1+x}" ]; then readonly __knot_harness_workspace_root_v1="$PWD"; fi\n(/bin/sleep ${Math.ceil(timeoutMs / 1000)}; kill -TERM $$) >/dev/null 2>&1 &\n${variable}_watch=$!\nbuiltin printf '\\036${prefix}:BEGIN\\037\\n'\nbuiltin printf '\\036${prefix}:BEGIN\\037\\n' >&2\n${evaluate}\n${variable}_code=$?\nset +e\n${variable}_background=0\nfor ${variable}_pid in $(builtin jobs -p); do\n  if [ "$${variable}_pid" != "$${variable}_watch" ]; then ${variable}_background=1; fi\ndone\nkill "$${variable}_watch" 2>/dev/null\nwait "$${variable}_watch" 2>/dev/null\nbuiltin printf '\\036${prefix}:END:%s:%s\\037\\n' "$${variable}_code" "$${variable}_background"\nbuiltin printf '\\036${prefix}:END:%s:%s\\037\\n' "$${variable}_code" "$${variable}_background" >&2\nunset ${variable}_watch ${variable}_code ${variable}_background ${variable}_pid\n`;
}
export function validShellLog(log: Record<string, unknown>, offset = 0): boolean {
  const encoder = new TextEncoder();
  return ['stdout', 'stderr'].every(stream => typeof log[stream] === 'string' &&
    Number.isSafeInteger(log[stream + '_from']) && (log[stream + '_from'] as number) >= 0 &&
    Number.isSafeInteger(log[stream + '_len']) && (log[stream + '_len'] as number) >= (log[stream + '_from'] as number) &&
    // Provider *_from describes the retained buffer; the requested absolute
    // offset may advance the returned slice beyond that buffer base.
    encoder.encode(log[stream] as string).byteLength === (log[stream + '_len'] as number) - Math.max(offset, log[stream + '_from'] as number)) && typeof log.truncated === 'boolean';
}
export function attachedShellResult(log: Record<string, unknown>, boundary: ShellBoundary): BoundaryResult | undefined {
  if (!validShellLog(log, boundary.offset)) return undefined;
  const encoder = new TextEncoder();
  const parse = (stream: string, before: number) => {
    const text = log[stream] as string, from = Math.max(boundary.offset, log[stream + '_from'] as number);
    if (from > before) return undefined;
    const begin = `\x1eKNOT_${boundary.nonce}:BEGIN\x1f\n`;
    const at = text.indexOf(begin);
    if (at < 0 || text.indexOf(begin, at + 1) !== -1 || from + encoder.encode(text.slice(0, at)).byteLength < before) return undefined;
    const start = at + begin.length;
    const expression = new RegExp(`\\x1eKNOT_${boundary.nonce}:END:(\\d{1,3}):([01])\\x1f\\n`, 'g');
    expression.lastIndex = start;
    const end = expression.exec(text);
    if (!end || expression.exec(text) || Number(end[1]) > 255) return undefined;
    return { text: text.slice(start, end.index), code: Number(end[1]), background: end[2] === '1',
      start: from + encoder.encode(text.slice(0, start)).byteLength, end: from + encoder.encode(text.slice(0, end.index)).byteLength };
  };
  const out = parse('stdout', boundary.stdoutBefore), err = parse('stderr', boundary.stderrBefore);
  if (!out || !err || out.code !== err.code || out.background !== err.background) return undefined;
  return { stdout: out.text, stderr: err.text, exitCode: out.code, background: out.background,
    stdoutStart: out.start, stdoutEnd: out.end, stderrStart: err.start, stderrEnd: err.end };
}
