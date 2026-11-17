import { z } from 'zod';
import { documentScreenshotSchema,documentRecordingSchema,transcriptTimingSchema } from './whisperDocumentMedia';

const identity = z.string().regex(/^[A-Za-z0-9_-]{1,80}$/);
/** Whisper Documents v1: portable meeting snapshots, not HTML and never a room-access grant. */
export const whisperDocumentSchema = z.object({
  version: z.union([z.literal(1),z.literal(2)]), sourceMeetingId: z.string().uuid(), generatedAt: z.string().datetime({offset:true}),
  startedAt: z.string().datetime({offset:true}).optional(), summary: z.string().max(20000),
  quickNotes: z.array(z.object({id:identity,title:z.string().max(180),bullets:z.array(z.string().max(3000)).max(40)})).max(80),
  nextSteps: z.array(z.object({id:identity,text:z.string().max(3000),owner:z.string().max(180)})).max(100),
  details: z.array(z.object({id:identity,title:z.string().max(180),text:z.string().max(12000),transcriptId:identity.optional()})).max(200),
  transcript: z.array(z.object({id:identity,speaker:z.string().max(180),text:z.string().max(12000),offsetSeconds:z.number().int().min(0).max(604800).optional(),timing:transcriptTimingSchema.optional()})).max(4000),
  transcriptStatus: z.enum(['complete','partial','unavailable']),
  screenshots:z.array(documentScreenshotSchema).max(20).optional(),recordings:z.array(documentRecordingSchema).max(10).optional(),
}).superRefine((value,ctx)=>{
  for(const rows of [value.quickNotes,value.nextSteps,value.details,value.transcript]) if(new Set(rows.map(r=>r.id)).size!==rows.length)ctx.addIssue({code:'custom',message:'Document section IDs must be unique.'});
  if(value.version===1&&(value.screenshots!==undefined||value.recordings!==undefined||value.transcript.some(s=>s.timing)))ctx.addIssue({code:'custom',message:'Media and precise timing require packet version 2.'});
  if(value.version===2){
    if(!value.screenshots||!value.recordings||value.transcriptStatus==='unavailable'||!value.transcript.length||value.transcript.some(s=>!s.text.trim()))ctx.addIssue({code:'custom',message:'A version 2 import requires transcript passages, coverage, and media arrays.'});
    const assets=[...(value.screenshots??[]),...(value.recordings??[])];if(new Set(assets.map(a=>a.assetId)).size!==assets.length)ctx.addIssue({code:'custom',message:'Asset IDs must be unique.'});
    for(const speech of value.transcript){const t=speech.timing;if(t&&speech.offsetSeconds!==undefined)ctx.addIssue({code:'custom',message:'Supply timing or legacy offset, not both.'});if(t?.basis==='recording'){const r=value.recordings?.find(r=>r.assetId===t.recordingAssetId);if(!r||t.startMs>r.durationSeconds*1000||(t.endMs??t.startMs)>r.durationSeconds*1000)ctx.addIssue({code:'custom',message:'Timing is outside its recording.'});}}
  }
  const ids=new Set(value.transcript.map(r=>r.id));
  if(value.screenshots?.some(s=>s.transcriptId&&!ids.has(s.transcriptId)))ctx.addIssue({code:'custom',message:'A screenshot references an unavailable passage.'});
  if(value.details.some(d=>d.transcriptId&&!ids.has(d.transcriptId)))ctx.addIssue({code:'custom',message:'A detail references an unavailable passage.'});
  if(new TextEncoder().encode(JSON.stringify(value)).length>1400000)ctx.addIssue({code:'custom',message:'Split this meeting into linked documents; do not truncate it.'});
});
/** New exports require real transcript text; legacy saved snapshots remain readable. */
export const whisperDocumentImportSchema=whisperDocumentSchema.refine(p=>p.transcriptStatus!=='unavailable'&&p.transcript.length>0&&p.transcript.every(s=>s.text.trim().length>0),'Transcript passages are required. Do not import a summary-only meeting.');
export type WhisperDocument = z.infer<typeof whisperDocumentSchema>;
export type DocumentTab = 'quick'|'full'|'transcript';
export const documentTabs = [{id:'quick' as const,title:'Quick notes'},{id:'full' as const,title:'Full notes'},{id:'transcript' as const,title:'Transcript'}];
export const speechTime=(speech:WhisperDocument['transcript'][number]):string=>documentTime(speech.timing?Math.floor(speech.timing.startMs/1000):speech.offsetSeconds);
export function documentTime(seconds?: number): string { if(seconds===undefined)return 'Time not supplied'; return [Math.floor(seconds/3600),Math.floor(seconds/60)%60,seconds%60].map(n=>String(n).padStart(2,'0')).join(':'); }
/** Plain text for explicit Jasper consent and export, never a silent read of other tabs. */
export function documentTabText(packet: WhisperDocument, tab: DocumentTab): string {
  if(tab==='quick')return packet.quickNotes.map(s=>s.title+'\n'+s.bullets.map(b=>'• '+b).join('\n')).join('\n\n');
  if(tab==='transcript')return `Transcript coverage: ${packet.transcriptStatus}. Speaker labels and recognition may contain errors.\n\n`+packet.transcript.map(s=>`${speechTime(s)}\n${s.speaker}: ${s.text}`).join('\n\n');
  return `Summary\n${packet.summary}\n\nNext steps\n`+packet.nextSteps.map(s=>`[${s.owner||'Unassigned'}] ${s.text}`).join('\n')+'\n\nDetails\n'+packet.details.map(s=>s.title+'\n'+s.text).join('\n\n');
}
