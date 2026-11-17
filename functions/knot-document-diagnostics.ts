/** Content-free diagnostics. Never interpolate authored keys, values, filenames,
 * parser messages or exception text into these descriptors. */
export type DocumentDiagnostic = {
  branch: string; fieldPath: string; expectedShape: string; receivedShape: string; unexplained: boolean;
};
const pathWords = new Set(['choices','finish_reason','message','content','tool_calls','function_call','delta','role','index','usage','title','subtitle','sections','id','blocks','kind','text','items','columns','rows','patches','sectionID','layout','state','version','patched','preparation','interpreter','path','stage','authoring','prefix','code','final','arguments','deliveryLabel','envelope','stream','body','receipt','owner','program','retention']);
export function safeDocumentDiagnostic(value: unknown): DocumentDiagnostic | undefined {
  if (!value || typeof value !== 'object') return undefined;
  const v = value as Record<string, unknown>;
  if (typeof v.branch !== 'string' || !/^[a-z][a-z0-9_]{0,79}$/.test(v.branch) || typeof v.fieldPath !== 'string' || v.fieldPath.length > 240 || !/^\$(?:\.[a-zA-Z_]+|\[[0-9]{1,6}\])*$/.test(v.fieldPath) || [...v.fieldPath.matchAll(/\.([a-zA-Z_]+)/g)].some(m => !pathWords.has(m[1]))) return undefined;
  for (const key of ['expectedShape','receivedShape']) if (typeof v[key] !== 'string' || !/^[a-z0-9_ ,:;=|().<>\[\]-]{1,240}$/i.test(v[key] as string)) return undefined;
  if (typeof v.unexplained !== 'boolean') return undefined;
  return { branch: v.branch, fieldPath: v.fieldPath, expectedShape: v.expectedShape as string, receivedShape: v.receivedShape as string, unexplained: v.unexplained };
}
export function documentShape(v: unknown): string {
  if (v === null) return 'null';
  if (Array.isArray(v)) return `array(length=${v.length})`;
  if (typeof v === 'string') return `string(chars=${Array.from(v).length})`;
  if (typeof v === 'object') return `object(fields=${Object.keys(v).length})`;
  return typeof v;
}
export class DocumentContractViolation extends Error {
  constructor(readonly diagnostic: DocumentDiagnostic) { super('document_contract_rejected'); }
}
export function rejectDocument(branch: string, fieldPath: string, expectedShape: string, receivedShape: string, unexplained = false): never {
  const diagnostic = safeDocumentDiagnostic({ branch, fieldPath, expectedShape, receivedShape, unexplained });
  if (!diagnostic) throw new Error('invalid_internal_document_diagnostic');
  throw new DocumentContractViolation(diagnostic);
}
export function documentDiagnostic(error: unknown, branch: string, fieldPath = '$'): DocumentDiagnostic {
  const known = error instanceof DocumentContractViolation ? error.diagnostic : error && typeof error === 'object' && 'detail' in error ? safeDocumentDiagnostic(error.detail) : undefined;
  // A fallback is explicitly unexplained, never an invented schema cause.
  return known ?? { branch, fieldPath, expectedShape: 'validated_contract', receivedShape: 'unclassified_exception', unexplained: true };
}
