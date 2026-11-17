import type { JasperAnswer, JasperAnswerItem } from './jasperMeetings';

/** Pure answer-shape helpers, kept apart from the network module so views and tests can use them freely. */
export const isKnowledgeItem = (item: JasperAnswerItem): boolean => item.kind === 'knowledge';

/** Jasper Intelligence handoff: prefills its composer with the question; the user still sends it there. */
export function jasperIntelligenceLink(question: string): string { return `/ember?q=${encodeURIComponent(question.slice(0, 600))}`; }

export type JasperGroundingLabel = 'evidence' | 'knowledge' | 'mixed';

/** Client-derived grounding label, so older answers without the field still read correctly. */
export function jasperGrounding(answer: JasperAnswer): JasperGroundingLabel {
  if (answer.result.grounding) return answer.result.grounding;
  const items = answer.result.sections.flatMap((section) => section.items);
  const knowledge = items.filter(isKnowledgeItem).length;
  return knowledge === 0 ? 'evidence' : knowledge === items.length && !answer.result.actions.length ? 'knowledge' : 'mixed';
}

export type JasperReadingSummary = { passages: number; meetings: { id: string; title: string; date: string }[]; notes: number; recording: boolean };

/** Human-readable reading summary: what Jasper actually read, derived from the returned sources. */
export function jasperReadingSummary(answer: JasperAnswer): JasperReadingSummary {
  const meetings = new Map<string, { id: string; title: string; date: string }>();
  for (const source of answer.sources) {
    const current = meetings.get(source.meetingId);
    if (!current || source.spokenAt < current.date) meetings.set(source.meetingId, { id: source.meetingId, title: source.meetingTitle, date: source.spokenAt });
  }
  return { passages: answer.sources.length, meetings: [...meetings.values()], notes: answer.sources.filter((source) => source.kind === 'summary').length, recording: answer.sources.some((source) => source.kind === 'recording') };
}
