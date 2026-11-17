/** Fresh workflow policy only. Historical commands/receipts keep their policy.
 * Conservative deterministic binding: uncertain/multiple outputs require a choice,
 * never a renderer-selected substitute. Source mentions do not choose the final. */
export type DocumentFormatBinding = { version: 'original_format_v1'; status: 'bound' | 'ambiguous' | 'unsupported'; format: string };
const supported = new Set(['txt', 'md', 'html', 'csv', 'json', 'pdf', 'docx', 'xlsx', 'pptx']);
export const rawDocumentFormat = (format: string | undefined): boolean => !!format && ['txt', 'md', 'html', 'csv', 'json'].includes(format);
const aliases: Record<string, string> = { markdown: 'md', 'plain text': 'txt', text: 'txt', word: 'docx', excel: 'xlsx', slides: 'pptx', powerpoint: 'pptx' };
const words = /\b(?:plain text|markdown|pdf|docx|xlsx|pptx|txt|md|html|csv|json|rtf|odt|ods|odp|epub|doc|xls|ppt|pages|numbers|keynote|latex|tex|word|excel|powerpoint|slides|yaml|yml|xml|png|jpg|jpeg|svg|webp|zip|rar|7z)\b|\b[a-z0-9_-]+\.([a-z][a-z0-9]{0,15})(?=$|[\s,;:!?"'`)\]])/gi;
export function requestedDocumentFormat(request: string): DocumentFormatBinding {
  const candidates: { format: string; target: boolean; position?: number; end?: number; uncertain?: boolean }[] = [];
  for (const match of request.matchAll(words)) {
    const start = match.index!, before = request.slice(Math.max(0, start - 180), start);
    const after = request.slice(start + match[0].length, start + match[0].length + 60);
    // Exclude explicit negative choices, including 'instead of PDF'.
    if (/(?:\bnot|\bno|\bwithout|\brather than|\binstead of)\s+(?:(?:a|an|the)\s+)?(?:\w+[ -]){0,2}$/i.test(before)) continue;
    const format = match[1]?.toLowerCase() ?? aliases[match[0].toLowerCase()] ?? match[0].toLowerCase();
    const target = /\b(?:to|into|as|in)\s+(?:(?:a|an|the|raw|final|native|actual)\s+)*\.?$/i.test(before);
    // Ordinary word counts/page counts and spreadsheet values are not format names.
    const bare = match[0].toLowerCase();
    if (!match[1] && bare === 'slides' && !target && !/^\s+(?:file|format)\b/i.test(after) && !/\b(?:create|make|build|write|generate|produce|deliver|export|send|share)\s+(?:(?:me|us|a|an|the|new|actual|final|native|some|powerpoint|training|teaching|lecture|presentation|concise|\d+|one|two|three|four|five|six|seven|eight|nine|ten)\s+){0,6}$/i.test(before)) continue;
    if (!match[1] && bare === 'word' && (/(?:[-\d]|\b\d+[\s-]+)$/.test(before) || !target && !/\bmicrosoft\s+$/i.test(before) && !/^\s+(?:document|file|format)\b/i.test(after))) continue;
    if (!match[1] && ['pages', 'numbers', 'keynote'].includes(bare) && (!target || /\b(?:\d+|one|two|three|four|five|six|seven|eight|nine|ten)\s+$/i.test(before)) && !/\bapple\s+$/i.test(before) && !/^\s+(?:file|format)\b/i.test(after)) continue;
    const source = /\b(?:from|using|read|source|input|attached|existing|about|regarding)\b(?:(?!\b(?:to|into|as|in|deliver|return|create|write|save|export|make|produce|generate|output)\b)[^\n.;,]){0,150}$/i.test(before) || /^\s*(?:source|input)\b/i.test(after);
    if (!source || target) candidates.push({ format, target, position: start, end: start + match[0].length });
  }
  // Explicit arbitrary format names must fail honestly as well.
  for (const match of request.matchAll(/\b(?:as\s+|in\s+|into\s+)?(?:an?\s+)?([a-z][a-z0-9_-]{0,15})\s+(?:file|format)\b/gi)) {
    const name = match[1].toLowerCase();
    const before = request.slice(Math.max(0, match.index! - 180), match.index!);
    if (/\b(?:from|using|read|source|input|attached|existing|not|without|instead of)\b(?:(?!\b(?:to|into|as|deliver|return|create|write|save|export|make|produce|generate|output)\b)[^\n.;,]){0,150}$/i.test(before)) continue;
    if (name === 'word' && /(?:[-\d]|\b\d+[\s-]+)$/.test(before)) continue;
    const format = aliases[name] ?? name, target = /^(?:as|in|into)\s/i.test(match[0]);
    // A bare noun such as “budget file” is not a known unsupported format.
    // Ask for its format rather than claim “budget” is an extension or choose PDF.
    const uncertain = !target && !/\sformat$/i.test(match[0]) && !supported.has(format) && !candidates.some(candidate => candidate.format === format);
    if (!['new', 'single', 'separate', 'readable', 'downloadable', 'native', 'raw', 'final', 'document', 'source', 'input', 'output', 'reference', 'existing', 'attached', 'original', 'original-format', 'requested-format', 'specified-format', 'complete', 'another', 'this', 'that', 'my', 'your', 'our', 'one', 'the', 'a', 'an'].includes(name)) candidates.push({ format, target, uncertain });
  }
  const targets = candidates.filter(candidate => candidate.target);
  const selected = targets.length ? targets : candidates;
  const formats = [...new Set(selected.map(candidate => candidate.format))];
  const multipleTargets = candidates.some(a => a.target && a.end !== undefined && candidates.some(b => b.position !== undefined && b.position > a.end! && b.format !== a.format && /^\s*(?:(?:files?|formats?|documents?)\s*)?(?:,?\s*(?:and|or)|[,/])\s*(?:(?:a|an|the)\s+)?$/i.test(request.slice(a.end, b.position))));
  const format = formats[0] ?? 'pdf';
  return { version: 'original_format_v1', status: formats.length > 1 || multipleTargets || selected.some(candidate => candidate.uncertain) ? 'ambiguous' : supported.has(format) ? 'bound' : 'unsupported', format };
}
/** Bare handoffs identify neither current bytes nor format; history is not retrieval authority. */
export function documentHandoffNeedsClarification(request: string): boolean {
  return /^(?:please\s+)?(?:share|send|attach|export|save|download|give me)\s+(?:it|this|that|the file|the document)(?:\s+(?:please|with me|to me|now))?[.!?\s]*$/i.test(request.trim());
}
/** Explicit plain PDFs retain the Markdown/house lane in fresh workflows;
 * merely mentioning a Markdown input or declining a plain design is not consent. */
export function plainPDFSourceRequested(request: string): boolean {
  if (/\b(?:not|no|without|rather than)\s+(?:(?:a|an|the|explicitly)\s+)*plain\b/i.test(request)) return false;
  return /\bplain\s+pdf\b/i.test(request) || /\bpdf\b[^\n.;]{0,80}\b(?:from|using)\s+(?:(?:a|an|the|complete|plain)\s+)*markdown\b/i.test(request);
}
/** Explicit Office aliases must route like their extensions, even when their
 * subject is a game/app. Ordinary discussion and source mentions are excluded. */
export function officeAliasDocumentRequest(request: string): boolean {
  const binding = requestedDocumentFormat(request);
  return ['docx', 'xlsx', 'pptx'].includes(binding.format) &&
    /\b(?:create|make|build|write|save|generate|produce|deliver|export|send|share|convert|rebuild)\b/i.test(request) &&
    /\b(?:slides|powerpoint|word|excel)\b/i.test(request);
}
export function documentFormatIssue(binding: DocumentFormatBinding | undefined, path: string, format: string): string | undefined {
  if (!binding) return undefined;
  if (binding.version !== 'original_format_v1' || binding.status === 'ambiguous') return 'document_output_format_ambiguous';
  if (binding.status !== 'bound' || !supported.has(binding.format)) return 'document_output_format_unsupported';
  return format !== binding.format || !path.endsWith('.' + binding.format) ? 'document_output_format_mismatch' : undefined;
}
export const rawDocumentContract = `ORIGINAL-FORMAT DOCUMENT DELIVERY: The original request's bound output format is authoritative, not memory, drafts, intermediate source format or a renderer default. For TXT/MD/HTML/CSV/JSON use document_script stage=final: author complete NEW UTF-8 final bytes at a NEW path with exactly the bound extension, with pure agent-authored code and explicit interpreter. Do NOT convert these requests through HTML/PDF, rename a PDF or claim rendered-page verification. HTML is self-contained; no resource fetches. CSV must retain actual requested rows/columns/values. Markdown remains Markdown. Read indispensable original/reference files completely first. A named existing final is inspection-only and allowed only for explicit retrieval, not an editing/creation substitute. Backend-owned execution/measurement, complete-byte rehash, independent complete-text comparison against the original ask and actual full sources, and immutable capture are required. pages=1 is one logical raw file, NOT rendered-page proof. No renderer/proof command is needed for raw text; PDF/Office still require their separate source/build/every-page proof. Preserve collision refusal, ownership, consent, Stop, rejected files, no-replay, the shared runaway work ceiling, unmetered plumbing and complete same-session installed-guide caching without an ordinary skill cap. Tools do not authorize a success claim: only the actual captured record does. Any draft learning/acceptance must be about this original format and request, never success inferred from a substituted PDF. Muse reports the pinned knot-doc 1.0.0 installed and accepted, but it is a mechanical Markdown/HTML-to-PDF transport only. Never use it for these raw final formats or as independent delivery/content proof.`;
