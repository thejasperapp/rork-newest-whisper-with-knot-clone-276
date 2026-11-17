// Local recorded-evidence planning ONLY. No AI, command, capture or API replay.
// Exclusive prospective declaration before the newly authorized one-run measure.
import { readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const root = join(tmpdir(), 'knot-acceptance-uf26aun6d49w1tsjsm2u9');
const prior = JSON.parse(readFileSync(join(root, 'battery-2026-11-14T03-41-24-088Z/recipe-pdf/result.json'), 'utf8'));
if (prior.taskID !== 'b936a45f-b94a-4c5c-8ac6-b0c92e894466' || prior.accountID !== 'e00a9064-5f85-40bb-9f44-8bd60f90d24a' || prior.completionReceivedMs !== 603097) throw new Error('recorded_baseline_required');
const author = prior.authoringObservations.filter((e: any) => e.kind === 'document_program_sealed').map((e: any) => e.detail);
if (author.length !== 2 || author.reduce((n: number, e: any) => n + e.transportElapsedMs, 0) !== 440082) throw new Error('baseline_generation_required');
const extractedTextBytes = 17580, rate = 215;
// JSON structure is estimated, NOT a content cap. Preserve all substantive
// output even if the actual authored content or elapsed time is larger.
const estimatedStructuredResponseBytes = Math.ceil(extractedTextBytes * 1.25);
const baselineNonGenerationMs = prior.completionReceivedMs - 440082;
const prospectivePlanningMs = Math.ceil(estimatedStructuredResponseBytes / rate * 1000 + baselineNonGenerationMs);
const targetMs = Math.ceil(prospectivePlanningMs * 1.2 / 30000) * 30000;
const plan = { declaredAt: new Date().toISOString(), referenceTaskID: prior.taskID, baselineCompletionMs: prior.completionReceivedMs, baselineProviderGenerationMs: 440082, baselineNonGenerationMs, calibrationBytesPerSecond: rate, completeExtractedTextBytes: extractedTextBytes, estimatedStructuredResponseBytes, prospectivePlanningMs, targetMs,
  policy: 'One full structured content response; at most one affected-section layout-only response. Unpatchable visual advice ships recorded. No model-authored markup/CSS. No output shortening, provider fallback, skipped proof/review or reduced funded deadline.',
  interpretation: 'Prospective working floor, not a physical lower bound or promise. Reuses all observed non-generation overhead conservatively, including the old second build/proof. Actual post-run floor must use actual model-response bytes and separately reported overhead. The former three-minute target is superseded, not retroactively passed.' };
writeFileSync(join(root, 'structured-latency-plan.json'), JSON.stringify(plan, null, 2), { flag: 'wx', mode: 0o600 });
console.log(JSON.stringify(plan, null, 2));
