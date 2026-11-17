import * as Y from 'yjs';
import { getSchema, type JSONContent } from '@tiptap/core';
import { prosemirrorJSONToYDoc, yDocToProsemirrorJSON } from '@tiptap/y-tiptap';
import { sharedEditorExtensions } from './sharedNotesExtensions';

export function encodeSharedBytes(bytes:Uint8Array):string {let raw='';for(let i=0;i<bytes.length;i+=8192)raw+=String.fromCharCode(...bytes.subarray(i,i+8192));return btoa(raw);}
export function decodeSharedBytes(value:string):Uint8Array {if(value.length>1500000)throw new Error('Document update is too large.');return Uint8Array.from(atob(value),c=>c.charCodeAt(0));}
/** Import once into a fresh collaborative identity. All later saves retain Yjs history. */
export function seedSharedDocument(content:JSONContent):Y.Doc{return prosemirrorJSONToYDoc(getSchema(sharedEditorExtensions),content,'default');}
export function sharedJSON(doc:Y.Doc):JSONContent{return yDocToProsemirrorJSON(doc,'default') as JSONContent;}
/** Untrusted peer attributes are allowlisted before use in preview/export, never injected as HTML. */
export function checkedSharedJSON(input:unknown):JSONContent {
 if(JSON.stringify(input).length>1500000)throw new Error('Document limit reached.');
 const schema=getSchema(sharedEditorExtensions);const node=schema.nodeFromJSON(input);node.check();return node.toJSON() as JSONContent;
}
