// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { knotCraftSkills, knotCraftGuidance, knotCraftForTurn, normalizedKnotCraftSkills, knotSearchEvidenceContract, knotSearchEvidenceNote } from '../../functions/knot-crafted-skills';

const context = { shared: false, browser: false, research: false, create: false, document: false };
describe('reviewed Knot craft standards', () => {
  it('bundles all eight complete source guides with matching names, hashes and attribution', () => {
    expect(knotCraftSkills.map(skill => skill.name)).toEqual(['web-research', 'spreadsheet-craft', 'gmail-behavior', 'creator-analytics', 'artefact-creation', 'browser-driving', 'memory-craft', 'build-verification']);
    for (const skill of knotCraftSkills) {
      const source = readFileSync(new URL(`../../.agents/skills/knot-${skill.name}/SKILL.md`, import.meta.url), 'utf8');
      expect(source).toContain(`name: knot-${skill.name}\n`);
      expect(source).toContain(`runtime-name: ${skill.name}\n`);
      expect(source).toContain(skill.source);
      expect(createHash('sha256').update(source).digest('hex')).toBe(skill.sha256);
      expect(source.split('\n---\n\n')[1].trim()).toBe(skill.body);
      expect(skill.description.length).toBeLessThanOrEqual(1024);
    }
  });
  it('rejects unknown hints, argument-like objects and duplicate catalog names', () => {
    expect(normalizedKnotCraftSkills(['gmail-behavior', 'invented-mail-send', { tool: 'send' }, 'gmail-behavior'])).toEqual(['gmail-behavior']);
    expect(normalizedKnotCraftSkills('memory-craft')).toEqual([]);
    expect(knotCraftGuidance([])).toBe('');
  });
  it('loads only memory guidance for an ordinary private conversation, not the whole catalog', () => {
    const selected = knotCraftForTurn(context);
    expect(selected).toEqual(['memory-craft']);
    const guide = knotCraftGuidance(selected);
    expect(guide).toContain('append-only dated supersession');
    expect(guide).not.toContain('# Spreadsheet Craft');
    expect(guide).toContain('never satisfy or bypass required complete actual live skill/reference reads');
  });
  it('keeps artifact and spreadsheet standards across typed document continuations', () => {
    expect(knotCraftForTurn({ ...context, create: true, document: true, format: 'xlsx' })).toEqual(['memory-craft', 'artefact-creation', 'spreadsheet-craft']);
    const guide = knotCraftGuidance(['spreadsheet-craft']);
    expect(guide).toContain('$598.15');
    expect(guide).toContain('actual computed results');
    expect(guide).toContain('not a replacement workbook');
  });
  it('loads runtime verification for non-document creations without adding a capability', () => {
    const selected = knotCraftForTurn({ ...context, create: true });
    expect(selected).toContain('build-verification');
    const guide = knotCraftGuidance(selected);
    expect(guide).toContain('390 by 844 and 1280 by 800');
    expect(guide).toContain('real wall-clock time');
    expect(guide).toContain('does not replace required live guide reads');
  });
  it('uses semantic hints independent of request language but cannot acquire browser authority', () => {
    expect(knotCraftForTurn({ ...context, hints: ['gmail-behavior', 'browser-driving'] })).toEqual(['memory-craft', 'gmail-behavior']);
    const guide = knotCraftGuidance(['gmail-behavior']);
    expect(guide).toContain('Gmail is not connected in this app');
    expect(guide).toContain('exact recipients and exact content');
    expect(guide).toContain('does not support Gmail rules');
  });
  it('isolates autonomous public browsing and shared answers from private craft context', () => {
    expect(knotCraftForTurn({ ...context, browser: true, hints: ['memory-craft', 'gmail-behavior', 'creator-analytics'] })).toEqual(['browser-driving', 'web-research']);
    expect(knotCraftForTurn({ ...context, shared: true, hints: ['memory-craft', 'gmail-behavior'] })).toEqual([]);
    expect(knotCraftForTurn({ ...context, shared: true, research: true, hints: ['gmail-behavior'] })).toEqual(['web-research']);
  });
  it('never upgrades search summary citations into complete source-read receipts', () => {
    expect(knotSearchEvidenceContract).toContain('do not establish full-page reads');
    expect(knotSearchEvidenceNote).toContain('fullTextReadConfirmed=false');
    expect(knotSearchEvidenceNote).toContain('not an indispensable full-reference receipt');
    const guide = knotCraftGuidance(['web-research']);
    expect(guide).toContain('Degrade per source');
    expect(guide).toContain('Never waive mandatory full-reference');
  });
});
