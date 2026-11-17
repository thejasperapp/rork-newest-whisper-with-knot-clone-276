import { describe,it,expect } from 'vitest';
import * as Y from 'yjs';
import { getSchema } from '@tiptap/core';
import { prosemirrorJSONToYDoc,yDocToProsemirrorJSON } from '@tiptap/y-tiptap';
import { sharedEditorExtensions,safeSharedImage } from './sharedNotesExtensions';
import { decodeSharedBytes,encodeSharedBytes } from './sharedNotesDocument';

describe('shared document content',()=>{
 it('preserves concurrent insertions regardless of delivery order and duplicate retries',()=>{
  const original=prosemirrorJSONToYDoc(getSchema(sharedEditorExtensions),{type:'doc',content:[{type:'paragraph',content:[{type:'text',text:'Hello'}]}]});
  const first=new Y.Doc(),second=new Y.Doc();const seed=Y.encodeStateAsUpdate(original);Y.applyUpdate(first,seed);Y.applyUpdate(second,seed);
  const vector=Y.encodeStateVector(original);
  const a=(first.getXmlFragment('prosemirror').get(0) as Y.XmlElement).get(0) as Y.XmlText;
  const b=(second.getXmlFragment('prosemirror').get(0) as Y.XmlElement).get(0) as Y.XmlText;
  a.insert(5,' from Alex');b.insert(5,' from Sam');const ua=Y.encodeStateAsUpdate(first,vector),ub=Y.encodeStateAsUpdate(second,vector);
  Y.applyUpdate(first,ub);Y.applyUpdate(second,ua);Y.applyUpdate(second,ua);
  expect(yDocToProsemirrorJSON(first)).toEqual(yDocToProsemirrorJSON(second));
  expect(first.getXmlFragment('prosemirror').toString()).toContain('from Alex');expect(first.getXmlFragment('prosemirror').toString()).toContain('from Sam');
  original.destroy();first.destroy();second.destroy();
 });
 it('round trips binary updates without encoding loss',()=>{const b=new Uint8Array([0,255,128,1,2]);expect(decodeSharedBytes(encodeSharedBytes(b))).toEqual(b);});
 it('refuses remote and executable image sources',()=>{for(const value of ['https://track.invalid/x.png','javascript:alert(1)','data:image/svg+xml;base64,PHN2Zz4='])expect(safeSharedImage(value)).toBe(false);expect(safeSharedImage('data:image/png;base64,AA==')).toBe(true);});
});
