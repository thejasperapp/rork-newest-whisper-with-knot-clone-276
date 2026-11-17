import { z } from "zod";

const text = (limit: number) => z.string().min(1).max(limit).refine(v => v.trim().length > 0 && !/[<>\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/u.test(v));
const utc = z.string().max(40).regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?Z$/).refine(v => Number.isFinite(Date.parse(v)));
const preview = z.discriminatedUnion("mode", [
  z.object({ mode: z.literal("title_only"), title: text(160), excerpt: z.null(), captured_at: utc }).strict(),
  z.object({ mode: z.literal("approved_excerpt"), title: text(160), excerpt: text(280), captured_at: utc }).strict(),
]);
const common = { version: z.literal(1), source_app: z.literal("whisper-notes"), delivery_id: z.string().uuid(), preview };
const schema = z.discriminatedUnion("kind", [
  z.object({ ...common, kind: z.literal("whisper.notes.invitation"), document_id: z.string().uuid(), invitation_id: z.string().uuid(), source_seq: z.number().int().min(0).max(Number.MAX_SAFE_INTEGER), role_at_send: z.enum(["viewer", "commenter", "editor"]) }).strict(),
  z.object({ ...common, kind: z.literal("whisper.sign.request"), request_id: z.string().uuid(), source_sha256: z.string().regex(/^[0-9a-f]{64}$/), page_count: z.number().int().min(1).max(10), expires_at: utc }).strict(),
]);
export type NotesDocumentCardCandidate = z.infer<typeof schema>;

/** Decoding is NOT provenance. Keep plain fallback until the Notes receipt resolver is deployed. */
export function notesDocumentCardCandidate(embed: unknown, messageID: string): NotesDocumentCardCandidate | null {
  try {
    const encoded = JSON.stringify(embed);
    if (!encoded || new TextEncoder().encode(encoded).length > 8192) return null;
    const result = schema.safeParse(embed);
    return result.success && result.data.delivery_id.toLowerCase() === messageID.toLowerCase() ? result.data : null;
  } catch { return null; }
}

/** Lock-screen/inbox privacy: never include titles or excerpts by default. */
export function notesMessageSummary(body: string): string | null {
  return body.startsWith("Document invitation:") ? "Document invitation" : body.startsWith("Signature request:") ? "Signature request" : null;
}
