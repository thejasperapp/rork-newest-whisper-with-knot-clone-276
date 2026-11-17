// Static compilation only. Compare changed tracked backend modules with HEAD,
// not just the entrypoint. No app, network or document code runs.
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { resolve, relative } from 'node:path';
import ts from '../web-whisperweb/node_modules/typescript/lib/typescript.js';

const root = fileURLToPath(new URL('../', import.meta.url));
const entry = resolve(root, 'functions/index.ts');
const changed = execFileSync('git', ['diff', '--name-only', 'HEAD', '--', 'functions'], { cwd: root, encoding: 'utf-8' }).trim().split('\n').filter(path => /\.[cm]?tsx?$/.test(path));
const trackedAtHead = new Set(execFileSync('git', ['ls-tree', '-r', '--name-only', 'HEAD', '--', 'functions'], { cwd: root, encoding: 'utf-8' }).trim().split('\n'));
// Newly added modules have no HEAD contents; validate their diagnostics in the
// current graph rather than attempting a failing git show or treating them as a baseline.
const baseline = new Map(changed.filter(path => trackedAtHead.has(path)).map(path => [resolve(root, path), execFileSync('git', ['show', 'HEAD:' + path], { cwd: root, encoding: 'utf-8', maxBuffer: 4000000 })]));
const options: ts.CompilerOptions = {
  noEmit: true, strict: true, target: ts.ScriptTarget.ES2022,
  module: ts.ModuleKind.ESNext, moduleResolution: ts.ModuleResolutionKind.Bundler,
  lib: ['lib.es2022.d.ts'], types: ['@cloudflare/workers-types'],
  typeRoots: [resolve(root, 'functions/node_modules/@types'), resolve(root, 'functions/node_modules')],
  skipLibCheck: true,
};
function diagnostics(useBaseline: boolean): ts.Diagnostic[] {
  const host = ts.createCompilerHost(options);
  const original = host.getSourceFile.bind(host);
  host.getSourceFile = (name, languageVersion, onError, shouldCreateNewSourceFile) =>
    useBaseline && baseline.has(resolve(name))
      ? ts.createSourceFile(name, baseline.get(resolve(name))!, languageVersion)
      : original(name, languageVersion, onError, shouldCreateNewSourceFile);
  return ts.getPreEmitDiagnostics(ts.createProgram([entry], options, host)).filter(item => item.category === ts.DiagnosticCategory.Error);
}
function counts(items: ts.Diagnostic[]): Map<string, number> {
  const result = new Map<string, number>();
  for (const item of items) {
    const key = (item.file ? relative(root, item.file.fileName) : 'compiler') + ':' + item.code + ':' + ts.flattenDiagnosticMessageText(item.messageText, '\n');
    result.set(key, (result.get(key) ?? 0) + 1);
  }
  return result;
}
const before = diagnostics(true), after = diagnostics(false);
const inherited = counts(before), current = counts(after);
const added = [...current].filter(([key, count]) => count > (inherited.get(key) ?? 0));
if (added.length) {
  console.error('New backend static diagnostics:', added);
  const keys = new Set(added.map(([key]) => key));
  for (const item of after) {
    const key = (item.file ? relative(root, item.file.fileName) : 'compiler') + ':' + item.code + ':' + ts.flattenDiagnosticMessageText(item.messageText, '\n');
    if (keys.has(key)) console.error(ts.formatDiagnosticsWithColorAndContext([item], { getCanonicalFileName: name => relative(root, name), getCurrentDirectory: () => root, getNewLine: () => '\n' }));
  }
  process.exit(1);
}
console.log('Full backend entrypoint: ' + after.length + ' current errors; ' + before.length + ' baseline errors; no added diagnostic signatures/counts.');
console.log('This baseline comparison is NOT a clean full-entrypoint typecheck or runtime acceptance.');
console.log(ts.formatDiagnosticsWithColorAndContext(after, {
  getCanonicalFileName: name => relative(root, name), getCurrentDirectory: () => root, getNewLine: () => '\n',
}));
