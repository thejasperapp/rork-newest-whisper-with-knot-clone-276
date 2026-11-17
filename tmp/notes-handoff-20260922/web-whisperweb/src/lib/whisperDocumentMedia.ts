import { z } from 'zod';
const uuid=z.string().uuid(),id=z.string().regex(/^[A-Za-z0-9_-]{1,80}$/),seconds=z.number().int().min(0).max(604800);
/** References contain stable IDs only. Unknown properties (including signed URLs) fail validation. */
export const documentScreenshotSchema=z.object({version:z.literal(1),assetId:uuid,caption:z.string().max(1000),alt:z.string().min(1).max(500),width:z.number().int().min(1).max(8192),height:z.number().int().min(1).max(8192),mimeType:z.enum(['image/png','image/jpeg','image/webp']),byteCount:z.number().int().min(1).max(5242880),sha256:z.string().regex(/^[a-f0-9]{64}$/),transcriptId:id.optional()}).strict();
export const documentRecordingSchema=z.object({version:z.literal(1),assetId:uuid,recordingId:uuid,sourceRevision:z.number().int().nonnegative(),title:z.string().max(160),durationSeconds:seconds,mediaKind:z.enum(['audio','video'])}).strict();
export const transcriptTimingSchema=z.object({version:z.literal(1),basis:z.enum(['session','recording']),sessionId:uuid,recordingAssetId:uuid.optional(),startMs:z.number().int().min(0).max(604800000),endMs:z.number().int().min(0).max(604800000).optional()}).strict().superRefine((v,c)=>{if((v.basis==='recording')!==!!v.recordingAssetId)c.addIssue({code:'custom',message:'Only recording-relative timing requires a recording asset ID.'});if(v.endMs!==undefined&&v.endMs<v.startMs)c.addIssue({code:'custom',message:'Transcript end precedes its start.'});});
export type DocumentScreenshot=z.infer<typeof documentScreenshotSchema>;
export type DocumentRecording=z.infer<typeof documentRecordingSchema>;
export type TranscriptTiming=z.infer<typeof transcriptTimingSchema>;
