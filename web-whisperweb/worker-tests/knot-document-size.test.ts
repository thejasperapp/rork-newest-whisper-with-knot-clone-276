// @vitest-environment node
// Local contract/transport tests only; no provider, droplet or delivery claim.
import { describe, expect, it } from 'vitest';
import { createHash } from 'node:crypto';
import { documentInvocationCommand, documentScriptTool, validatedDocumentInvocation } from '../../functions/knot-document-build';
import { validatedKnotDocumentDecision } from '../../functions/knot-tool-selection';
import { safeKnotActivityDetail } from '../../functions/knot-activity';
import { documentSizeFacts, shellCommandWithinBudget } from '../../functions/knot-document-limits';
import { attachedShellInput } from '../../functions/knot-shell-protocol';

const invocation = (code: string) => ({ stage: 'source' as const, interpreter: 'python3' as const, code, path: 'fresh-source.html', title: '', deliveryLabel: '' });
const decision = (code: string) => ({ choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({ selection: { tool: 'document_script', arguments: invocation(code) } }) } }] });
describe('bounded complete document programs', () => {
  it('accepts a developed program beyond the former 8000-byte ceiling', () => {
    const code = '# Authored complete source\n' + '# substantive content\n'.repeat(700);
    expect(new TextEncoder().encode(code).length).toBeGreaterThan(8000);
    expect(validatedDocumentInvocation(invocation(code)).code).toBe(code);
    expect(validatedKnotDocumentDecision(decision(code), [documentScriptTool], new Set(), true)).toHaveLength(1);
    expect(documentInvocationCommand(invocation(code))).toContain(JSON.stringify(JSON.stringify(invocation(code))));
  });
  it('accepts 64000 ASCII characters within the complete argument byte budget', () => {
    const code = '#'.repeat(64000);
    expect(documentScriptTool.function.parameters.properties.code.maxLength).toBe(64000);
    expect(documentScriptTool.function.description).toContain('64000 Unicode code points');
    expect(documentScriptTool.function.description).toContain('74000 UTF-8 bytes');
    expect(documentScriptTool.function.description).not.toContain('12 KB total invocation');
    expect(validatedKnotDocumentDecision(decision(code), [documentScriptTool], new Set(), true)).toHaveLength(1);
    expect(documentInvocationCommand(invocation(code)).length).toBeGreaterThan(64000);
  });
  it('uses Unicode code points and UTF-8 encoded argument bytes as separate bounds', () => {
    const code = '🪢'.repeat(17000);
    expect(code.length).toBe(34000);
    expect(new TextEncoder().encode(code).length).toBe(68000);
    expect(validatedKnotDocumentDecision(decision(code), [documentScriptTool], new Set(), true)).toHaveLength(1);
    expect(documentInvocationCommand(invocation(code))).toContain(code);
  });
  it('accounts for JSON escaping and shell framing in source and raw-final lanes without clipping accepted code', () => {
    for (const stage of ['source', 'final'] as const) for (const code of ["'".repeat(64000), '"\\\n'.repeat(10000), '\u0001'.repeat(12000)]) {
      const value = { ...invocation(code), stage };
      expect(new TextEncoder().encode(JSON.stringify(value)).length).toBeLessThanOrEqual(74000);
      expect(validatedKnotDocumentDecision(decision(code), [documentScriptTool], new Set(), true)).toHaveLength(1);
      const command = documentInvocationCommand(value);
      expect(new TextEncoder().encode(command).length).toBeLessThanOrEqual(160000);
      const framed = attachedShellInput(command, 120000, 'a'.repeat(32), true);
      expect(new TextEncoder().encode(JSON.stringify({ data: framed })).length).toBeLessThanOrEqual(600000);
      expect(command).toContain(JSON.stringify(JSON.stringify(value)));
      const proposal = { command, documentInvocation: value };
      const wire = 'data: ' + JSON.stringify({ type: 'complete', reply: '```message\n' + JSON.stringify({ shellProposal: proposal }) + '\n```' }) + '\n\n';
      expect(new TextEncoder().encode(wire).length).toBeLessThanOrEqual(800000);
    }
  });
  it.each(['#'.repeat(64001), '🪢'.repeat(19000), '\u0001'.repeat(12500)])('rejects a complete oversized program with exact numeric facts (%#)', code => {
    const value = invocation(code);
    try { validatedKnotDocumentDecision(decision(code), [documentScriptTool], new Set(), true); throw new Error('expected rejection'); }
    catch (error) {
      expect(error).toMatchObject({ tool: 'document_script', sizeFacts: { codeCharacters: Array.from(code).length, codeBytes: new TextEncoder().encode(code).length, codeCharacterLimit: 64000, argumentBytes: new TextEncoder().encode(JSON.stringify(value)).length, argumentByteLimit: 74000 } });
      expect(JSON.stringify(error)).not.toContain('code\":');
    }
  });
  it('retains ordinary command limits and allowlists only private numeric size facts', () => {
    const command = '#'.repeat(12001);
    expect(shellCommandWithinBudget(command, 'session_input')).toBe(false);
    expect(shellCommandWithinBudget(command, 'document_script')).toBe(false);
    expect(shellCommandWithinBudget(command, 'document_script', invocation('#'))).toBe(true); // ingress only; actor must regenerate.
    expect(safeKnotActivityDetail({ sizeFacts: { ...documentSizeFacts(invocation('🪢')), commandBytes: 160001, commandByteLimit: 160000, privateSource: 'not retained', codeBytes: -1, argumentBytes: Infinity, codeCharacterLimit: 0.2, path: 200 } })).toEqual({ sizeFacts: { codeCharacters: 1, argumentByteLimit: 74000, commandBytes: 160001, commandByteLimit: 160000 } });
  });
  it('keeps historical short-program command bytes identical', () => {
    // Frozen before the size expansion; provenance must still regenerate exactly.
    const command = documentInvocationCommand(invocation('# legacy fixture'));
    expect(createHash('sha256').update(command).digest('hex')).toBe('01b0a3df3b8c309646665ead2c6cbc739b36d386dcc150ebb60af69d7e0ccf70');
  });
});
