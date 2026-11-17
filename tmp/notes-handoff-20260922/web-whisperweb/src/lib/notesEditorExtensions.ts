import { Extension } from '@tiptap/core';
import StarterKit from '@tiptap/starter-kit';
import { TextStyleKit } from '@tiptap/extension-text-style';
import TextAlign from '@tiptap/extension-text-align';
import Highlight from '@tiptap/extension-highlight';
import Subscript from '@tiptap/extension-subscript';
import Superscript from '@tiptap/extension-superscript';
import { safeDocumentLink } from './documentStyle';

const ParagraphLayout = Extension.create({name:'notesParagraphLayout',addGlobalAttributes(){return [{types:['paragraph','heading'],attributes:{blockStyle:{default:null,parseHTML:el=>['title','subtitle'].includes(el.dataset.notesStyle??'')?el.dataset.notesStyle:null,renderHTML:attrs=>['title','subtitle'].includes(attrs.blockStyle)?{'data-notes-style':attrs.blockStyle,style:`font-size:${attrs.blockStyle==='title'?36:22}px`}:{}},paragraphSpacing:{default:null,parseHTML:el=>el.style.marginBottom?parseFloat(el.style.marginBottom):null,renderHTML:attrs=>attrs.paragraphSpacing!=null?{style:`margin-bottom:${Math.min(48,Math.max(0,Number(attrs.paragraphSpacing)||0))}px`}:{}},lineHeight:{default:null,parseHTML:el=>parseFloat(el.style.lineHeight)||null,renderHTML:attrs=>attrs.lineHeight?{style:`line-height:${Math.min(3,Math.max(1,Number(attrs.lineHeight)))}`} : {}},indent:{default:null,parseHTML:el=>Number(el.dataset.indent)||null,renderHTML:attrs=>attrs.indent?{'data-indent':attrs.indent,style:`margin-left:${Math.min(8,Math.max(0,Number(attrs.indent)))*24}px`}: {}}}}];}});
/** Shared editor allowlist; complex structures remain disabled until both platforms can preserve them. */
export const notesEditorExtensions = [StarterKit.configure({heading:{levels:[1,2,3,4,5,6]},bulletList:false,orderedList:false,listItem:false,listKeymap:false,blockquote:false,codeBlock:false,code:false,horizontalRule:false,link:{openOnClick:false,autolink:false,isAllowedUri:url=>safeDocumentLink(url)}}),TextStyleKit,TextAlign.configure({types:['paragraph','heading']}),Highlight.configure({multicolor:true}),Subscript,Superscript,ParagraphLayout];
