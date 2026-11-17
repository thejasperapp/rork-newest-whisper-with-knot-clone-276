import type { ShellWorkflow } from './knot-shell';
import type { liveShellTools } from './knot-shell-discovery';
import { skillDraftReadCommand } from './knot-skill-drafts';

type Tool = ReturnType<typeof liveShellTools>[number];
/** Projection only. The actor still admits every exact owned command itself. */
export function closingReadCommands(workflow: ShellWorkflow | undefined): string[] {
  if (!workflow || workflow.mode !== 'Create' || !workflow.indexRead || workflow.conversationMemoryOnly || workflow.draftWritten) return [];
  return [...new Set([
    ...(workflow.skillCreationCommand ? [workflow.skillCreationCommand] : []),
    ...(workflow.workspaceDrafts ?? []).map(skillDraftReadCommand),
  ])].filter(command => !workflow.skills.includes(command));
}
export function projectClosingShellTools(tools: Tool[], workflow: ShellWorkflow | undefined): Tool[] {
  const commands = closingReadCommands(workflow);
  if (!commands.length) return [];
  return tools.filter(tool => tool.function.name === 'session_input').map(tool => ({ ...tool, function: { ...tool.function,
    description: 'Optional closing read ONLY. Choose exactly one unread indexed skill-creation guide or catalogued full workspace-draft read from data.enum. No task execution, arithmetic, memory append, file authoring, build or repeated read. No call is needed without a worthwhile lesson; existing results remain valid.',
    parameters: { ...tool.function.parameters, properties: { data: { type: 'string', enum: commands } }, required: ['data'], additionalProperties: false },
  } }));
}
