// @vitest-environment node
import { it, expect } from 'vitest';
import * as Y from 'yjs';
import { seedToUpdate } from './meetSeed';
import { checkedSharedJSON, decodeSharedBytes, sharedJSON } from './sharedNotesDocument';

it('converts a rich server seed without a DOM or credentials into the production default fragment', () => {
 const seed = { type: 'doc', content: [
  { type: 'heading', attrs: { level: 2 }, content: [{ type: 'text', text: 'Summary' }] },
  { type: 'taskList', content: [{ type: 'taskItem', attrs: { checked: false }, content: [{ type: 'paragraph', content: [{ type: 'text', text: 'Review café launch.' }] }] }] },
  { type: 'pageBreak' },
  { type: 'paragraph', content: [{ type: 'text', text: 'Actual speech · 00:05:18' }] },
 ] };
 const frozen = JSON.stringify(seed), bytes = seedToUpdate(seed), doc = new Y.Doc();
 try {
  Y.applyUpdate(doc, decodeSharedBytes(bytes));
  expect(checkedSharedJSON(sharedJSON(doc))).toEqual(checkedSharedJSON(seed));
  expect(doc.getXmlFragment('default').length).toBe(4);
  Y.applyUpdate(doc, decodeSharedBytes(bytes));
  expect(checkedSharedJSON(sharedJSON(doc))).toEqual(checkedSharedJSON(seed));
  expect(JSON.stringify(seed)).toBe(frozen);
 } finally { doc.destroy(); }
});
it('rejects non-document and invalid structural seeds', () => {
 expect(() => seedToUpdate({ type: 'paragraph' })).toThrow('Expected a document seed');
 expect(() => seedToUpdate({ type: 'doc', content: [{ type: 'unknown' }] })).toThrow();
});
