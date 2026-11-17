import { describe, expect, it } from "vitest";
import { notesDocumentCardCandidate, notesMessageSummary } from "./notesDocumentCard";

const id = "30000000-0000-4000-8000-000000000001";
const invitation = {
  kind: "whisper.notes.invitation", version: 1, source_app: "whisper-notes", delivery_id: id,
  document_id: "20000000-0000-4000-8000-000000000001", invitation_id: "40000000-0000-4000-8000-000000000001", source_seq: 7, role_at_send: "commenter",
  preview: { mode: "approved_excerpt", title: "Launch review", excerpt: "The launch decisions and next steps.", captured_at: "2026-09-26T12:00:00Z" },
};
const signing = { kind: "whisper.sign.request", version: 1, source_app: "whisper-notes", delivery_id: id, request_id: "50000000-0000-4000-8000-000000000001", source_sha256: "a".repeat(64), page_count: 2, expires_at: "2026-10-26T12:00:00Z", preview: { mode: "title_only", title: "Agreement", excerpt: null, captured_at: "2026-09-26T12:00:00Z" } };

describe("untrusted Notes v1 candidates", () => {
  it("decodes both exact handoff variants without granting authority", () => {
    expect(notesDocumentCardCandidate(invitation, id)?.kind).toBe("whisper.notes.invitation");
    expect(notesDocumentCardCandidate(signing, id)?.kind).toBe("whisper.sign.request");
  });
  it("rejects unknown fields, versions, substituted identity and URLs", () => {
    for (const value of [{ ...invitation, version: 2 }, { ...invitation, open_url: "https://example.com" }, { ...invitation, preview: { ...invitation.preview, extra: true } }]) expect(notesDocumentCardCandidate(value, id)).toBeNull();
    expect(notesDocumentCardCandidate(invitation, signing.request_id)).toBeNull();
  });
  it("counts UTF-16 units and rejects HTML/control formatting without rewriting", () => {
    for (const title of ["<b>Title</b>", "A\u200bB", "a\nb", "\u{1F600}".repeat(81)]) expect(notesDocumentCardCandidate({ ...invitation, preview: { ...invitation.preview, title } }, id)).toBeNull();
    expect(notesDocumentCardCandidate({ ...invitation, preview: { ...invitation.preview, title: "\u{1F600}".repeat(80) } }, id)).not.toBeNull();
  });
  it("requires explicit null for title-only and safe exact revisions", () => {
    expect(notesDocumentCardCandidate({ ...signing, preview: { ...signing.preview, excerpt: undefined } }, id)).toBeNull();
    expect(notesDocumentCardCandidate({ ...invitation, source_seq: Number.MAX_SAFE_INTEGER + 1 }, id)).toBeNull();
    expect(notesDocumentCardCandidate({ ...invitation, source_seq: Number.MAX_SAFE_INTEGER }, id)).not.toBeNull();
  });
  it("rejects unsupported signing pages, hashes and non-UTC timestamps", () => {
    for (const patch of [{ page_count: 11 }, { page_count: 0 }, { source_sha256: "A".repeat(64) }, { expires_at: "2026-10-26T12:00:00+01:00" }]) expect(notesDocumentCardCandidate({ ...signing, ...patch }, id)).toBeNull();
  });
  it("keeps titles and excerpts out of notification summaries", () => {
    expect(notesMessageSummary("Document invitation: Private title\nPrivate excerpt")).toBe("Document invitation");
    expect(notesMessageSummary("Signature request: Confidential")).toBe("Signature request");
  });
});
