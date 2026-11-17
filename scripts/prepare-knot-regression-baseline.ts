// Prepare an isolated HEAD-source comparison for explicitly selected failing
// suites (or the two original comparison suites). Source copies stay outside the repository; generated test copies
// must be removed after rork test. No git mutation, service or credentials.
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = fileURLToPath(new URL('../', import.meta.url));
const revision = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim();
const directory = mkdtempSync(resolve(tmpdir(), 'knot-regression-baseline-'));
const paths = execFileSync('git', ['ls-tree', '-r', '--name-only', revision, 'functions'], { cwd: root, encoding: 'utf8' }).trim().split('\n').filter(path => path.endsWith('.ts'));
for (const path of paths) {
  const target = resolve(directory, path); mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, execFileSync('git', ['show', revision + ':' + path], { cwd: root, maxBuffer: 4000000 }));
}
const generated: string[] = [];
const selected = process.argv.flatMap((arg, index) => arg === '--only' ? [process.argv[index + 1]] : []);
if (selected.some(name => !/^knot-[a-z0-9-]+$/.test(name ?? ''))) throw new Error('explicit_test_basename_required');
for (const name of selected.length ? selected : ['knot-live-sliced-authoring', 'knot-build-continuation']) {
  const path = 'web-whisperweb/worker-tests/' + name + '.test.ts';
  const baseline = execFileSync('git', ['show', revision + ':' + path], { cwd: root, encoding: 'utf8', maxBuffer: 4000000 });
  const target = path.replace('.test.ts', '.baseline.test.ts');
  writeFileSync(resolve(root, target), baseline.replaceAll('../../functions/', resolve(directory, 'functions') + '/'));
  generated.push(target);
}
console.log(JSON.stringify({ revision, isolatedSource: directory, generated, scope: 'HEAD tests against complete HEAD functions, synthetic network only' }));
