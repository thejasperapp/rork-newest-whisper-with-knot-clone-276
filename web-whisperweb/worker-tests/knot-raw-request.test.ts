// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { documentRequest, knotArtifactRouting } from '../../functions/knot-document-proof';
import { documentHandoffNeedsClarification, plainPDFSourceRequested, requestedDocumentFormat } from '../../functions/knot-document-format';
describe('descriptive format handoffs do not invent a second format', () => {
  const suffix = ' This is new authoring, not retrieval or repair. Deliver the actual original-format file, not a chat explanation or substitute.';
  it.each([['Create a new actual CSV file. Use exactly the three columns Plant, Containers, WeeklyWaterChecks and exactly these data rows: Basil,2,3 and Mint,1,4. No extra rows or columns.', 'csv'], ['Create and deliver a new actual PDF using the guide@1.0.0 house template. Title Balcony Herb Plan. Include Basil and Mint, practical setup steps, watering and harvesting advice, and a safety note to keep mint contained. Use concise but useful complete explanations.', 'pdf']])('retains the exact matrix request format: %s', (ask, format) => {
    expect(requestedDocumentFormat(ask + suffix)).toMatchObject({ status: 'bound', format });
  });
  it.each(['original-format', 'requested-format', 'specified-format'])('ignores the descriptive modifier %s', modifier => {
    expect(requestedDocumentFormat('Create a CSV file. Deliver the ' + modifier + ' file.')).toMatchObject({ status: 'bound', format: 'csv' });
  });
  it.each(['Create a CSV file and an EPUB file.', 'Deliver CSV or JSON files.'])('preserves genuine multi-format ambiguity: %s', ask => expect(requestedDocumentFormat(ask).status).toBe('ambiguous'));
  it.each(['Create a document in xyz format', 'Create a report as an EPUB file'])('preserves unsupported formats: %s', ask => expect(requestedDocumentFormat(ask).status).toBe('unsupported'));
});
describe('explicit plain PDF source selection', () => {
  it.each(['Create a plain PDF', 'Create an explicitly plain PDF from complete Markdown source using house-v1 styling.', 'Create a PDF using Markdown'])('selects the plain lane: %s', ask => expect(plainPDFSourceRequested(ask)).toBe(true));
  it.each(['Create a PDF, not a plain PDF.', 'Create a PDF without plain styling.', 'Create a designed PDF about Markdown syntax.', 'Create a PDF using the guide@1.0.0 house template.'])('does not accidentally select plain: %s', ask => expect(plainPDFSourceRequested(ask)).toBe(false));
});
describe('Office aliases retain their requested original format', () => {
  it.each([['Create slides about forest ecology', 'pptx'], ['Create five slides about safe hiking', 'pptx'], ['Create a Word file about the game', 'docx'], ['Make an Excel file for app costs', 'xlsx'], ['Deliver the brief as slides', 'pptx']])('routes %s as %s', (request, format) => {
    expect(requestedDocumentFormat(request)).toMatchObject({ status: 'bound', format });
    expect(knotArtifactRouting(request)).toMatchObject({ generalCreate: false, documentTask: true, documentFormat: { status: 'bound', format } });
  });
  it.each(['Create a PDF about slides', 'Create a PDF using existing slides', 'Create a PDF, not slides', 'Create a PDF instead of slides'])('does not substitute an incidental/negative alias: %s', request => {
    expect(requestedDocumentFormat(request)).toMatchObject({ status: 'bound', format: 'pdf' });
  });
  it.each(['Create slides or PDF', 'Deliver as slides and PDF'])('retains explicit multi-format ambiguity: %s', request => {
    expect(requestedDocumentFormat(request).status).toBe('ambiguous');
  });
});
describe('explicit raw requests without a file noun', () => {
  it.each([['Write Markdown about safe hiking', 'md'], ['Write me plain text about safe hiking', 'txt'], ['Send this in MD', 'md'], ['Export that to CSV', 'csv'], ['Write the notes as Markdown', 'md'], ['Generate JSON containing the requested values', 'json']])('binds %s to %s', (request, format) => {
    expect(documentRequest(request)).toBe(true); expect(requestedDocumentFormat(request)).toMatchObject({ status: 'bound', format });
  });
  it.each(['What is Markdown?', 'Explain Markdown syntax', 'Create a JSON parser', 'Write an HTML game', 'Create a CSV validator', 'What does MD mean?'])('does not turn ordinary discussion/code into a document: %s', request => {
    expect(documentRequest(request)).toBe(false);
  });
  it.each(['share it', 'Please send it.', 'attach the file', 'export that please'])('requires current file/format clarification for %s', request => {
    expect(documentHandoffNeedsClarification(request)).toBe(true);
  });
  it.each(['Send notes.md', 'Share it as Markdown', 'Create a PDF report', 'Tell me about sharing'])('does not suppress an explicit request: %s', request => {
    expect(documentHandoffNeedsClarification(request)).toBe(false);
  });
});
