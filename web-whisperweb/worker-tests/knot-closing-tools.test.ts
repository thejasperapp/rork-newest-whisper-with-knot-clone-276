// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { closingReadCommands, projectClosingShellTools } from '../../functions/knot-closing-tools';
import { skillDraftReadCommand } from '../../functions/knot-skill-drafts';
import { safeKnotActivityDetail } from '../../functions/knot-activity';
import type { ShellWorkflow } from '../../functions/knot-shell';
const workflow: ShellWorkflow = { rootID: 'synthetic', originalRequest: 'Completed work', mode: 'Create', indexRead: true, memoryRead: true, commands: 7, skills: ['cat /opt/knot-skills/computation/SKILL.md'], memoryWritten: true, skillCreationCommand: 'cat /opt/knot-skills/skill-creation/SKILL.md', workspaceDrafts: ['existing-lesson'] };
const input = { type: 'function', function: { name: 'session_input', description: 'Broad task command', strict: true, parameters: { type: 'object', properties: { data: { type: 'string' } }, required: ['data'], additionalProperties: false } } };
describe('post-work tool projection', () => {
  it('offers only exact unread indexed closing reads, not broad task commands', () => {
    const tools = projectClosingShellTools([input, { ...input, function: { ...input.function, name: 'calculate' } }], workflow);
    expect(tools.map(t => t.function.name)).toEqual(['session_input']);
    expect(tools[0].function.parameters.properties).toEqual({ data: { type: 'string', enum: [workflow.skillCreationCommand, skillDraftReadCommand('existing-lesson')] } });
    expect(closingReadCommands(workflow)).not.toContain('printf 4');
  });
  it('omits session_input entirely when no eligible closing read remains', () => {
    const read = [...workflow.skills, workflow.skillCreationCommand!, skillDraftReadCommand('existing-lesson')];
    expect(projectClosingShellTools([input], { ...workflow, skills: read })).toEqual([]);
    expect(projectClosingShellTools([input], { ...workflow, skillCreationCommand: undefined, workspaceDrafts: [] })).toEqual([]);
  });
  it.each([{ draftWritten: true }, { mode: 'Answer' as const }, { indexRead: false }])('honors actual close state %j', change => {
    expect(projectClosingShellTools([input], { ...workflow, ...change })).toEqual([]);
  });
  it.each([{ commands: 12 }, { commands: 10000 }, { skills: ['a', 'b', 'c', 'd'] }])('keeps free closing reads beyond old ordinary caps %j', change => {
    expect(projectClosingShellTools([input], { ...workflow, ...change })[0].function.parameters.properties.data.enum).toEqual([workflow.skillCreationCommand, skillDraftReadCommand('existing-lesson')]);
  });
  it('never exposes an unadvertised shell adapter or repeats a completed guide', () => {
    expect(projectClosingShellTools([], workflow)).toEqual([]);
    expect(closingReadCommands({ ...workflow, skills: [workflow.skillCreationCommand!] })).toEqual([skillDraftReadCommand('existing-lesson')]);
  });
  it('records only allowlisted tool identity and strips arguments/private text', () => {
    expect(safeKnotActivityDetail({ tool: 'session_input', reason: 'post_delivery_memory_only', stage: 'tool_selection', data: 'private source' })).toEqual({ tool: 'session_input', reason: 'post_delivery_memory_only', stage: 'tool_selection' });
    expect(safeKnotActivityDetail({ tool: 'private made-up command', data: 'secret' })).toBeUndefined();
  });
});
