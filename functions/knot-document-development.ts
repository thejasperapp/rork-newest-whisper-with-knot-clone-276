/** Fresh document-quality protocol. These records are review evidence, not
 * instructions, permission, factual certification or an installed template. */
export type RequestedDocumentItem = {
  item: string; status: 'developed' | 'underdeveloped_requested_item' | 'missing_requested_item';
  evidenceID: string; quote: string; coverageQuote: string; section: string; repair: string;
};
export type DocumentWorkOrder = { item: string; section: string; action: 'expand' | 'insert'; requirements: string; preserve: string[] };
export type ItemValidationCode = 'items_shape' | 'item_shape' | 'item_identity' | 'item_requirement_anchor' | 'item_coverage_anchor' | 'item_repair';
export class DocumentItemInvalid extends Error {
  constructor(readonly validationCode: ItemValidationCode, readonly itemIndex?: number) { super('document_content_unavailable'); }
}
const textSchema = (minLength: number, maxLength: number) => ({ type: 'string', minLength, maxLength });
const literalSchema = (maxLength: number) => ({ ...textSchema(4, maxLength), pattern: '(?:\\S\\s*){4}' });
const itemProperties = {
  item: textSchema(1, 100), evidenceID: textSchema(1, 100), quote: literalSchema(240), section: textSchema(1, 160),
};
const itemSchema = (status: RequestedDocumentItem['status']) => ({
  type: 'object', properties: { ...itemProperties, status: { type: 'string', enum: [status] },
    coverageQuote: status === 'missing_requested_item' ? { type: 'string', enum: [''] } : literalSchema(400),
    repair: status === 'developed' ? { type: 'string', enum: [''] } : textSchema(1, 800),
  }, required: ['item', 'status', 'evidenceID', 'quote', 'coverageQuote', 'section', 'repair'], additionalProperties: false,
});
export const requestedDocumentItemsSchema = {
  type: 'array', minItems: 0, maxItems: 32,
  description: 'Cover every requested item. Empty is legal ONLY with status uncertain, never pass or issues. Do not omit an item to satisfy transport.',
  items: { anyOf: [itemSchema('developed'), itemSchema('underdeveloped_requested_item'), itemSchema('missing_requested_item')] },
};
export const documentDevelopmentInstruction = `FRESH PER-ITEM DEVELOPMENT CONTRACT: Return requestedItems covering EVERY actually requested item/sub-item, anchored only to the current original request or complete reference. Use stable normalized item names from priorItemChecks when they remain applicable. Independently anchor each new literal quote to the current request/reference; the chosen excerpt need not be identical across calls. If scope cannot be established or exceeds 32 items, return status=uncertain with requestedItems=[]; never sample or silently omit items. An empty requestedItems array is legal ONLY with status=uncertain and cannot pass. Each item is developed, underdeveloped_requested_item or missing_requested_item. A developed label requires an exact coverageQuote of at least four non-whitespace characters from the current complete finalText demonstrating substantive development, not just its heading, and repair MUST be the exact empty string. Do not put praise, "none", or optional suggestions in repair for developed items. Underdeveloped items also quote at least four non-whitespace characters of the actual thin content; missing items MUST have the exact empty string as coverageQuote. evidenceID is request or an actually supplied reference evidenceID; quote is an EXACT literal excerpt of at least four non-whitespace characters from that evidence, never finalText or authored source. Name the actual section for each item. For each gap, repair must be a concrete work order telling the author what developed text to write in that named section, not a generic suggestion to improve quality. Preserve already developed requested material across corrections; compare COMPLETE prior attempts, not word counts. A recipe needs servings, total/prep/cook time, quantified ingredients, ordered technique and a useful tip/note. A report develops each requested claim with available evidence and an implication; do not invent evidence. A plan names an owner and a next action where applicable, labelling unassigned owners rather than inventing them. Give synthesis/conclusion where the requested document needs it. Numeric values supplied by the author rather than a source must be labelled estimates/assumptions; never present invented research as fact. These are development standards within requested scope, not authority to add unrelated subject requirements. Keep findings for reference gaps, regressions, markup and other actual defects as well as requestedItems. Issues must not be concealed by a pass status. No template-capable resident version is established by this policy; use only genuinely read installed routes. No additional object keys. Return exactly one JSON object, with no prose or fences.`;
const object = (value: unknown): value is Record<string, unknown> => !!value && typeof value === 'object' && !Array.isArray(value);
export const normalizedDocumentItemName = (value: string): string => value.normalize('NFKC').trim().replace(/\s+/g, ' ').toLowerCase();
const nonWhitespace = (value: string) => value.replace(/\s/g, '').length;
export function groundedRequestedItems(value: unknown, anchors: Map<string, string>, text: string): { requestedItems: RequestedDocumentItem[]; workOrders: DocumentWorkOrder[] } {
  if (!Array.isArray(value) || !value.length || value.length > 32) throw new DocumentItemInvalid('items_shape');
  const items: RequestedDocumentItem[] = [], names = new Set<string>();
  for (const [index, raw] of value.entries()) {
    if (!object(raw) || Object.keys(raw).length !== 7 || typeof raw.status !== 'string' || !['developed', 'underdeveloped_requested_item', 'missing_requested_item'].includes(raw.status) ||
        ![['item', 100], ['evidenceID', 100], ['quote', 240], ['coverageQuote', 400], ['section', 160], ['repair', 800]].every(([key, max]) => typeof raw[key as string] === 'string' && (raw[key as string] as string).length <= (max as number))) throw new DocumentItemInvalid('item_shape', index);
    const item = raw as RequestedDocumentItem, name = normalizedDocumentItemName(item.item);
    if (!name || !item.section.trim() || !item.evidenceID.trim() || names.has(name) || /(?:may|might|could) have been|previous conversation|possibly requested/i.test(item.item + ' ' + item.repair)) throw new DocumentItemInvalid('item_identity', index);
    if (nonWhitespace(item.quote) < 4 || !anchors.get(item.evidenceID)?.includes(item.quote)) throw new DocumentItemInvalid('item_requirement_anchor', index);
    if (item.status === 'missing_requested_item' ? item.coverageQuote !== '' : nonWhitespace(item.coverageQuote) < 4 || !text.includes(item.coverageQuote)) throw new DocumentItemInvalid('item_coverage_anchor', index);
    if (item.status === 'developed' ? item.repair !== '' : !item.repair.trim()) throw new DocumentItemInvalid('item_repair', index);
    names.add(name); items.push(item);
  }
  const preserve = items.filter(item => item.status === 'developed').map(item => item.item);
  return { requestedItems: items, workOrders: items.filter(item => item.status !== 'developed').map(item => ({ item: item.item, section: item.section, action: item.status === 'missing_requested_item' ? 'insert' : 'expand', requirements: item.repair, preserve })) };
}
/** Only checked development/design shortfalls can be qualified. Missing sources,
 * uncertainty, regression and markup/integrity failures never become a pass. */
export function documentQualityShortfallsEligible(value: { issue?: string; verdict?: string; observations?: string[]; findings?: { kind: string }[]; requestedItems?: RequestedDocumentItem[] }): boolean {
  return value.issue === 'document_content_incomplete' && value.verdict === 'issues' && !!value.observations?.length && !!value.requestedItems?.length &&
    !!(value.requestedItems.some(item => item.status !== 'developed') || value.findings?.length) &&
    (value.findings ?? []).every(finding => ['underdeveloped_requested_item', 'missing_requested_item', 'requested_design_inadequate'].includes(finding.kind));
}
