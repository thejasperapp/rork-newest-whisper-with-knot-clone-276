import { Node, mergeAttributes } from '@tiptap/core';
import StarterKit from '@tiptap/starter-kit';
import { TableKit } from '@tiptap/extension-table';
import { TaskList, TaskItem } from '@tiptap/extension-list';
import { notesEditorExtensions } from './notesEditorExtensions';
import { safeDocumentLink } from './documentStyle';

const PageBreak=Node.create({name:'pageBreak',group:'block',atom:true,parseHTML(){return [{tag:'div[data-page-break]'}];},renderHTML(){return ['div',{'data-page-break':'true',class:'notes-page-break'},'Page break'];}});
// Images are bundled raster data, never remote URLs that leak document views to third parties.
export function safeSharedImage(src:unknown):src is string{return typeof src==='string'&&src.length<=700000&&/^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+/]+=*$/.test(src);}
const Image=Node.create({name:'image',group:'block',atom:true,draggable:true,addAttributes(){return {src:{default:''},alt:{default:''},width:{default:320}};},parseHTML(){return [{tag:'img',getAttrs:el=>safeSharedImage((el as HTMLElement).getAttribute('src'))?{}:false}];},renderHTML({node,HTMLAttributes}){if(!safeSharedImage(node.attrs.src))return ['span',{},'Image unavailable'];return ['img',mergeAttributes(HTMLAttributes,{src:node.attrs.src,alt:String(node.attrs.alt??'').slice(0,500),width:Math.min(720,Math.max(80,Number(node.attrs.width)||320)),loading:'lazy',referrerpolicy:'no-referrer'})];}});
/** Shared documents have their own rich schema; legacy private notebooks are never flattened into it. */
export const sharedEditorExtensions=[StarterKit.configure({undoRedo:false,heading:{levels:[1,2,3,4,5,6]},link:{openOnClick:false,autolink:false,isAllowedUri:safeDocumentLink},codeBlock:false,code:false}),...notesEditorExtensions.filter(e=>e.name!=='starterKit'),TableKit.configure({table:{resizable:false}}),TaskList,TaskItem.configure({nested:true,HTMLAttributes:{'data-type':'taskItem'}}),PageBreak,Image];
