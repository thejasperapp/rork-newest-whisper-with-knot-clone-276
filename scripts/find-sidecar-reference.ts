// Recover attachment references only. Never output chat text or credential data.
import { readdir, readFile } from 'node:fs/promises';
const root = new URL('../.rork/history/', import.meta.url);
const files = await readdir(root, { recursive: true });
const found = new Set<string>();
function visit(value: unknown, file: string): void {
  if (typeof value === 'string' && /droplet|sidecar|shell setup/i.test(value)) {
    for (const match of value.matchAll(/https:\/\/r2-pub\.rork\.com\/attachments\/[a-z0-9]+\.(?:txt|md|pdf|docx|tsx?|jsx?|json|zip|html)/gi)) found.add(match[0]);
  } else if (Array.isArray(value)) { for (const item of value) visit(item, file); }
  else if (value && typeof value === 'object') { for (const item of Object.values(value)) visit(item, file); }
}
for (const file of files.filter(file => file.endsWith('.json'))) {
  try { visit(JSON.parse(await readFile(new URL(file, root), 'utf8')), file); } catch { /* no raw text/errors */ }
}
console.log(JSON.stringify({ attachmentReferences: [...found] }, null, 2));
