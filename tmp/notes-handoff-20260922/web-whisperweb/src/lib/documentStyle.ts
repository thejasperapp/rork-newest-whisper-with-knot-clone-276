import { z } from 'zod';

export const documentFonts = ['Arial', 'Georgia', 'Times New Roman', 'Courier New', 'Verdana'] as const;
/** Only explicit safe URLs are saved; document text is never executable markup. */
export function safeDocumentLink(value: string): boolean {
  if (value.length > 2048) return false;
  try { const u = new URL(value); return ['https:', 'http:', 'mailto:'].includes(u.protocol) && !u.username && !u.password; } catch { return false; }
}
const hex = z.string().regex(/^#[0-9a-fA-F]{6}$/);
export const documentStyleSchema = z.object({
  start: z.number().int().nonnegative(), length: z.number().int().positive(), bold: z.boolean(), italic: z.boolean(), underline: z.boolean(), heading: z.number().int().min(0).max(6),
  blockStyle: z.enum(['title','subtitle']).optional(), paragraphSpacing: z.number().min(0).max(48).optional(),
  strike: z.boolean().optional(), fontFamily: z.enum(documentFonts).optional(), fontSize: z.number().min(8).max(96).optional(),
  color: hex.optional(), highlight: hex.optional(), alignment: z.enum(['left','center','right','justify']).optional(), lineHeight: z.number().min(1).max(3).optional(), indent: z.number().int().min(0).max(8).optional(), script: z.enum(['sub','super']).optional(), link: z.string().refine(safeDocumentLink).optional(),
});
export type DocumentStyle = z.infer<typeof documentStyleSchema>;
