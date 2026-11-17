import { knotVoiceBridgeURL } from './knot-voice-bridge';

// Shared by the token gate and the one-time private-agent provisioning script.
// Official schema: https://api.elevenlabs.io/openapi.json
export const knotVoiceIDs = {
  boy: 'UgBBYS2sOqTuMpoF3BR0',
  girl: 'DODLEQrClDo8wCz460ld',
} as const;
export const knotVoiceConsent = 'knot_rork_elevenlabs_voice_consent_v2';
export function knotVoiceCustomLLM(secretID: string) {
  return { url: knotVoiceBridgeURL, model_id: 'knot-shared-rork', api_type: 'chat_completions', api_key: null, auth_connection: null,
    request_headers: { 'X-Knot-Voice-Authorization': { secret_id: secretID } } };
}
function validatedCustomLLM(value: unknown, secretID: string): boolean {
  const config = object(value), headers = object(config.request_headers), auth = object(headers['X-Knot-Voice-Authorization']);
  return config.url === knotVoiceBridgeURL && config.model_id === 'knot-shared-rork' && config.api_type === 'chat_completions' && config.api_key == null && config.auth_connection == null && config.api_version == null &&
    Object.keys(headers).length === 1 && Object.keys(auth).length === 1 && auth.secret_id === secretID &&
    Object.keys(config).every(k => ['url', 'model_id', 'api_type', 'api_key', 'auth_connection', 'request_headers', 'api_version'].includes(k));
}

export const knotVoiceRelayConsent = 'knot_voice_chat_tools_v1';
export const knotVoiceRelayTool = {
  type: 'client', name: 'ask_knot',
  description: 'For each finalized spoken user request, delegate exactly once to the native Knot chat engine. No arguments: the app supplies the real finalized transcript, not model-authored instructions. Speak only the returned answer; never solve or execute independently.',
  expects_response: true, response_timeout_secs: -1, pre_tool_speech: 'off', interruption_mode: 'allow',
  parameters: { type: 'object', required: [], properties: {} },
};
export function validatedKnotVoiceRelayTool(raw: unknown): boolean {
  const root = object(raw), config = object(root.tool_config ?? raw), parameters = object(config.parameters);
  return config.type === 'client' && config.name === 'ask_knot' && config.expects_response === true && config.response_timeout_secs === -1 &&
    config.pre_tool_speech === 'off' && config.interruption_mode === 'allow' &&
    parameters.type === 'object' && emptyArray(parameters.required) && emptyOptionalObject(parameters.properties) &&
    emptyOptionalArray(config.assignments) && emptyOptionalObject(object(config.dynamic_variables).dynamic_variable_placeholders);
}

// A single inherited conversation node makes the entry route explicit. It
// adds no tools, prompt, knowledge, transfer or account-action authority.
export const knotVoiceEntryWorkflow = {
  nodes: {
    start_node: { type: 'start', position: { x: 0, y: 0 }, edge_order: ['start_to_conversation'] },
    conversation_node: { type: 'override_agent', position: { x: 0, y: 120 }, edge_order: [], label: 'Knot', conversation_config: {}, additional_prompt: '', additional_knowledge_base: [], additional_tool_ids: [], entry_behavior: 'auto' },
  },
  edges: { start_to_conversation: { source: 'start_node', target: 'conversation_node', forward_condition: { type: 'unconditional' } } },
  prevent_subagent_loops: true,
};
export function privateKnotVoiceAgent(relay = false, bridgeSecretID?: string) {
  if (!bridgeSecretID) throw new Error('The private shared-Rork voice bridge must be configured first.');
  return {
    name: relay ? 'Whisper Knot — private chat voice relay' : 'Whisper Knot — private voice',
    tags: ['whisper-knot', relay ? 'native-chat-relay' : 'voice-only-no-tools'],
    conversation_config: {
      agent: {
        first_message: 'Hi, I’m Knot. What would you like to work on?',
        prompt: {
          prompt: 'You are Knot, the everyday AI assistant inside Whisper. Respond naturally in the user’s language. Voice has no tools or ability to execute actions. Never claim otherwise.',
          llm: 'custom-llm', custom_llm: knotVoiceCustomLLM(bridgeSecretID), backup_llm_config: { preference: 'disabled' },
          ignore_default_personality: true, enable_reasoning_summary: false, enable_parallel_tool_calls: false,
          tool_ids: [], tools: relay ? [knotVoiceRelayTool] : [], built_in_tools: {}, mcp_server_ids: [], native_mcp_server_ids: [], knowledge_base: [],
        },
      },
      tts: { voice_id: knotVoiceIDs.boy },
      conversation: {
        text_only: false, max_duration_seconds: 1200, monitoring_enabled: false,
        client_events: ['audio', 'interruption', 'user_transcript', 'agent_response', 'agent_response_correction'],
      },
    },
    workflow: knotVoiceEntryWorkflow,
    platform_settings: {
      auth: { enable_auth: true, allowlist: [] },
      privacy: { record_voice: false, retention_days: 1, delete_transcript_and_pii: true, delete_audio: true },
      analysis_llm: 'gpt-6.1-terra',
      evaluation: { criteria: [] }, data_collection: {},
      workspace_overrides: { webhooks: { post_call_webhook_id: null, events: [], send_audio: false } },
      overrides: {
        conversation_config_override: { agent: { prompt: { prompt: true }, first_message: true }, tts: { voice_id: true } },
        custom_llm_extra_body: false,
        enable_conversation_initiation_client_data_from_webhook: false,
        enable_starting_workflow_node_id_from_client: false,
        enable_procedure_ids_from_client: false,
      },
    },
  };
}

type ObjectValue = Record<string, unknown>;
const isObject = (value: unknown): value is ObjectValue => value !== null && typeof value === 'object' && !Array.isArray(value);
const object = (value: unknown): ObjectValue => isObject(value) ? value : {};
const emptyArray = (value: unknown): boolean => Array.isArray(value) && value.length === 0;
const emptyOptionalArray = (value: unknown): boolean => value == null || emptyArray(value);
const emptyOptionalObject = (value: unknown): boolean => value == null || (isObject(value) && Object.keys(value).length === 0);

/** No automatic conversation forwarding to customer-configured webhooks. */
function noForwarding(raw: unknown): boolean {
  if (!isObject(raw) || raw.conversation_initiation_client_data_webhook != null) return false;
  const hooks = raw.webhooks;
  // Event defaults alone do not forward anything without a destination.
  const storage = raw.cloud_storage_export;
  if (storage != null && (!isObject(storage) || storage.destination_id != null)) return false;
  return isObject(hooks) && hooks.post_call_webhook_id == null && hooks.send_audio !== true &&
    (hooks.events == null || (Array.isArray(hooks.events) && hooks.events.every(event => typeof event === 'string')));
}
export function validatedKnotVoiceWorkspace(raw: unknown): boolean { return noForwarding(raw); }
export function validatedKnotVoiceEntry(raw: unknown): boolean {
  if (!isObject(raw) || Object.keys(raw).some(k => !['nodes', 'edges', 'subgraphs', 'prevent_subagent_loops'].includes(k)) || !emptyOptionalObject(raw.subgraphs) || raw.prevent_subagent_loops !== true) return false;
  const nodes = object(raw.nodes), edges = object(raw.edges), start = object(nodes.start_node), node = object(nodes.conversation_node), edge = object(edges.start_to_conversation);
  const position = (v: unknown) => v == null || isObject(v) && Object.entries(v).every(([k, n]) => ['x', 'y'].includes(k) && typeof n === 'number' && Number.isFinite(n));
  return Object.keys(nodes).length === 2 && Object.keys(edges).length === 1 && start.type === 'start' && start.parent_subgraph_id == null && position(start.position) &&
    Array.isArray(start.edge_order) && start.edge_order.length === 1 && start.edge_order[0] === 'start_to_conversation' &&
    Object.keys(start).every(k => ['type', 'position', 'edge_order', 'parent_subgraph_id'].includes(k)) &&
    node.type === 'override_agent' && node.label === 'Knot' && node.additional_prompt === '' && emptyOptionalObject(node.conversation_config) && emptyArray(node.additional_knowledge_base) && emptyArray(node.additional_tool_ids) && emptyArray(node.edge_order) && node.entry_behavior === 'auto' && node.parent_subgraph_id == null && node.forced_tool_name == null && position(node.position) &&
    Object.keys(node).every(k => ['type', 'position', 'edge_order', 'label', 'conversation_config', 'additional_prompt', 'additional_knowledge_base', 'additional_tool_ids', 'entry_behavior', 'parent_subgraph_id', 'forced_tool_name'].includes(k)) &&
    edge.source === 'start_node' && edge.target === 'conversation_node' && emptyOptionalArray(edge.reroutes) && edge.backward_condition == null &&
    object(edge.forward_condition).type === 'unconditional' && object(edge.forward_condition).label == null && (object(edge.forward_condition).exit_slot == null || object(object(edge.forward_condition).exit_slot).type === 'any' && Object.keys(object(object(edge.forward_condition).exit_slot)).length === 1) && Object.keys(object(edge.forward_condition)).every(k => ['type', 'label', 'exit_slot'].includes(k)) &&
    Object.keys(edge).every(k => ['source', 'target', 'forward_condition', 'backward_condition', 'reroutes'].includes(k));
}

/** Reject tool-bearing/unknown workflows and extra enabled client overrides.
 * Validate every call; pin token issuance to this exact inspected version.
 * No API key, configuration, transcript or provider error body is logged.
 */
export function validatedKnotVoiceVersion(raw: unknown, agentID: string, relayToolID?: string, bridgeSecretID?: string): string | null {
  const agent = object(raw), config = object(agent.conversation_config), settings = object(agent.platform_settings);
  const prompt = object(object(config.agent).prompt), privacy = object(settings.privacy), auth = object(settings.auth);
  const version = agent.version_id;
  if (agent.agent_id !== agentID || typeof version !== 'string' || !/^[a-zA-Z0-9_-]{8,120}$/.test(version) ||
      (bridgeSecretID ? prompt.llm !== 'custom-llm' || !validatedCustomLLM(prompt.custom_llm, bridgeSecretID) : prompt.llm !== 'gpt-4o' || prompt.custom_llm != null) || object(prompt.backup_llm_config).preference !== 'disabled' ||
      !(relayToolID ? Array.isArray(prompt.tool_ids) && prompt.tool_ids.length === 1 && prompt.tool_ids[0] === relayToolID : emptyArray(prompt.tool_ids)) || !emptyArray(prompt.mcp_server_ids) || !emptyArray(prompt.native_mcp_server_ids) ||
      !(emptyOptionalArray(prompt.tools) || relayToolID && Array.isArray(prompt.tools) && prompt.tools.length === 1 && validatedKnotVoiceRelayTool(prompt.tools[0])) || !emptyOptionalArray(prompt.knowledge_base) ||
      !isObject(prompt.built_in_tools) || Object.values(prompt.built_in_tools).some(value => value != null) ||
      auth.enable_auth !== true || !emptyOptionalArray(auth.allowlist) || auth.shareable_token != null ||
      privacy.record_voice !== false || privacy.retention_days !== 1 || privacy.delete_transcript_and_pii !== true || privacy.delete_audio !== true ||
      object(privacy.user_memory).enabled === true ||
      !emptyOptionalObject(config.language_presets) || !emptyOptionalObject(agent.procedures)) return null;
  if (bridgeSecretID && (prompt.ignore_default_personality !== true || prompt.enable_reasoning_summary !== false || prompt.enable_parallel_tool_calls !== false)) return null;
  // Disable optional custom post-call analysis and any agent-level forwarding.
  // The provider may still perform its documented standard operational analysis.
  if (settings.analysis_llm !== 'gpt-6.1-terra' || !emptyArray(object(settings.evaluation).criteria) ||
      !emptyOptionalObject(settings.data_collection) || !emptyOptionalObject(settings.data_collection_scopes) ||
      settings.auto_translate_transcript_to_app_language === true || !noForwarding(settings.workspace_overrides) ||
      (settings.alerting != null && (!isObject(settings.alerting) || !emptyOptionalArray(settings.alerting.notifiers)))) return null;
  if (settings.analysis_items != null && (!isObject(settings.analysis_items) ||
      !Object.entries(settings.analysis_items).every(([key, value]) =>
        ['evaluation_criteria', 'data_collection'].includes(key) && emptyArray(value)))) return null;
  // Only a plain legacy marker or our exact, authority-free inherited entry
  // route is permitted. No tool/transfer/conditional or additional agent node.
  const explicitEntry = validatedKnotVoiceEntry(agent.workflow);
  if (agent.workflow != null && !explicitEntry) {
    if (typeof agent.workflow !== 'object' || Array.isArray(agent.workflow)) return null;
    for (const [key, value] of Object.entries(object(agent.workflow))) {
      if (key === 'prevent_subagent_loops' && typeof value === 'boolean') continue;
      if (key === 'nodes' && isObject(value) && Object.keys(value).length === 1 && isObject(value.start_node)) {
        const start = value.start_node;
        if (start.type !== 'start' || !emptyArray(start.edge_order) || start.parent_subgraph_id != null ||
            Object.keys(start).some(field => !['type', 'position', 'edge_order', 'parent_subgraph_id'].includes(field)) ||
            (start.position != null && (!isObject(start.position) || Object.entries(start.position).some(([axis, coordinate]) =>
              !['x', 'y'].includes(axis) || typeof coordinate !== 'number' || !Number.isFinite(coordinate))))) return null;
        continue;
      }
      if (!['nodes', 'edges', 'subgraphs'].includes(key) || !emptyOptionalObject(value)) return null;
    }
  }
  const conversation = object(config.conversation);
  if (conversation.text_only !== false || conversation.monitoring_enabled !== false || typeof conversation.max_duration_seconds !== 'number' ||
      conversation.max_duration_seconds <= 0 || conversation.max_duration_seconds > 1200) return null;
  const overrides = object(settings.overrides);
  const permitted = new Set(['conversation_config_override.agent.prompt.prompt', 'conversation_config_override.agent.first_message', 'conversation_config_override.tts.voice_id']);
  function safeFlags(value: unknown, path = ''): boolean {
    if (value === false || value == null) return true;
    if (value === true) return permitted.has(path);
    if (typeof value !== 'object' || Array.isArray(value)) return false;
    return Object.entries(object(value)).every(([key, child]) => safeFlags(child, path ? path + '.' + key : key));
  }
  const flags = object(overrides.conversation_config_override);
  if (object(object(flags.agent).prompt).prompt !== true || object(flags.tts).voice_id !== true || !safeFlags(overrides)) return null;
  return version;
}
