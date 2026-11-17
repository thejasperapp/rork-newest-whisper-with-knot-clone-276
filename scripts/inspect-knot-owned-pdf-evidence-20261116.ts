// Read-only reduction of retained, secret-free acceptance observations.
import { readFileSync } from 'node:fs';
import { structuredState } from '../functions/knot-document-structured';
const events = JSON.parse(readFileSync(process.argv[2], 'utf8'));
console.log(JSON.stringify({
  sources: events.records.flatMap((r: any) => { const state = structuredState(r.spec?.documentInvocation); return state ? [{ proposalID: r.spec.id, layout: state.layout, sections: state.document.sections.map(s => ({ id: s.id, title: s.title, blocks: s.blocks.length })) }] : []; }),
  documents: (events.documents ?? []).map((d: any) => ({ id: d.id, pages: d.pages, sha256: d.sha256, size: d.size, assessment: d.assessment })),
  findings: (events.activities ?? []).filter((a: any) => /review|quality|capture|content/.test(a.kind)),
}, null, 2));
