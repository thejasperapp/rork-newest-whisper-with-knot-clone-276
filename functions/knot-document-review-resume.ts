import type { ShellEvidence } from './knot-shell';
import { documentManifest, type DocumentManifest, type DocumentVisualAdvisory } from './knot-documents';
import { verifiedDocumentProof } from './knot-document-proof';
import { verifiedDocumentExecution } from './knot-document-build';

export type DocumentReviewResume = { id: string; finalSHA256: string; state: 'started' | 'finished'; issue?: string; documentID?: string };
export type DocumentReviewResumeAuthorization = {
  version: 'knot_document_review_resume_v1'; id: string; taskID: string; sourceMessageID: string;
  sourceProposalID: string; buildProposalID: string; finalSHA256: string; finalSize: number; pages: number;
};
export type DocumentAdvisoryCapture = DocumentReviewResume & Partial<import('./knot-request-trace').KnotRequestTrace>;
export type DocumentAdvisoryCaptureAuthorization = Omit<DocumentReviewResumeAuthorization, 'version'> & { version: 'knot_document_advisory_capture_v1'; reviewResumeID: string; proofProposalID: string; eventSequence: number; noFurtherRepair: true };
const uuid = (value: unknown): value is string => typeof value === 'string' && /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(value);
/** Explicit authenticated owner authorization for read-only review/capture of
 * one exact completed proof. Never a replay, new work budget or history search.
 * The original unavailable finding and all prior Events stay untouched. */
/** Fresh explicit capture-only approval, bound to the exact finished one-shot
 * review and its server-retained finding. Never invent per-page pass verdicts. */
export function validateDocumentAdvisoryCapture(value: unknown, receipt: ShellEvidence, resume: DocumentReviewResume | undefined, event: unknown): { authorization: DocumentAdvisoryCaptureAuthorization; advisory: DocumentVisualAdvisory } {
  const fail = (): never => { throw new Error('document_advisory_capture_unavailable'); };
  try {
    const a = value as DocumentAdvisoryCaptureAuthorization, e = event as Record<string, unknown>;
    if (!a || a.version !== 'knot_document_advisory_capture_v1' || a.noFurtherRepair !== true || a.proofProposalID !== receipt.proposalID || !uuid(a.reviewResumeID) || !Number.isSafeInteger(a.eventSequence) || a.eventSequence < 1 || !resume || resume.id !== a.reviewResumeID || resume.finalSHA256 !== a.finalSHA256 || resume.state !== 'finished' || resume.issue !== 'document_visual_incomplete' || !e || e.kind !== 'document_visual_blocked' || e.proposalID !== receipt.proposalID || e.resumeID !== resume.id || e.issue !== resume.issue || !Array.isArray(e.observations) || e.observations.length < 1 || e.observations.length > 2400 || e.observations.some(v => typeof v !== 'string' || !v.trim() || v.length > 600)) return fail();
    validateDocumentReviewResume({ ...a, version: 'knot_document_review_resume_v1' }, receipt);
    return { authorization: a, advisory: { finalSHA256: a.finalSHA256, status: 'issues', observations: e.observations as string[], basis: 'retained_event', eventSequence: a.eventSequence, resumeID: resume.id } };
  } catch { return fail(); }
}
export function validateDocumentReviewResume(value: unknown, receipt: ShellEvidence): { authorization: DocumentReviewResumeAuthorization; manifest: DocumentManifest } {
  const fail = (): never => { throw new Error('document_review_resume_unavailable'); };
  try {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return fail();
    const a = value as DocumentReviewResumeAuthorization, w = receipt.workflow;
    if (a.version !== 'knot_document_review_resume_v1' || ![a.id, a.taskID, a.sourceMessageID, a.sourceProposalID, a.buildProposalID].every(uuid) ||
        !/^[a-f0-9]{64}$/.test(a.finalSHA256) || !Number.isSafeInteger(a.finalSize) || a.finalSize < 1 || !Number.isSafeInteger(a.pages) || a.pages < 1 ||
        !w || w.documentPolicy !== 'author_v1' || w.documentQuality !== 'quality_v1' || !w.documentTask ||
        w.rootID !== a.taskID || w.sourceMessageID !== a.sourceMessageID || w.documentExecution?.invocation.stage !== 'build' ||
        w.documentExecution.sourceProposalID !== a.sourceProposalID || w.documentProof?.sourceProposalID !== a.buildProposalID ||
        w.documentContentFinding?.proposalID !== receipt.proposalID || w.documentContentFinding.issue !== 'document_visual_review_unavailable') return fail();
    const manifest = documentManifest(receipt);
    if (!manifest || manifest.format !== 'pdf' || manifest.sha256 !== a.finalSHA256 || manifest.size !== a.finalSize || manifest.pages !== a.pages || !verifiedDocumentProof(receipt, manifest)) return fail();
    // Independently bind the measured build to its ID, not just matching bytes
    // or a caller-selected workflow field. All ancestry here is server-owned.
    const build = receipt.evidence.find(item => item.proposalID === a.buildProposalID);
    if (!build || !verifiedDocumentExecution({ ...receipt, evidence: receipt.evidence.filter(item => item.proposalID === a.sourceProposalID || item === build) }, manifest)) return fail();
    return { authorization: a, manifest };
  } catch { return fail(); }
}
