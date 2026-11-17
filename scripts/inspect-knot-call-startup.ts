// Read-only call-startup diagnostic. Never starts calls, retrieves audio, or prints
// transcripts, context, credentials, provider IDs or arbitrary provider errors.
const key = process.env.ELEVENLABS_API_KEY;
if (!key) throw new Error('Server-only voice key is not configured.');
const headers = { 'xi-api-key': key };
const api = 'https://api.elevenlabs.io/v1/convai';
async function read(url: string) {
  const response = await fetch(url, { headers, redirect: 'error', signal: AbortSignal.timeout(15000) });
  if (!response.ok) { await response.body?.cancel(); throw new Error(`Read-only voice inspection failed (${response.status}).`); }
  return response.json();
}
function classify(raw: unknown): string {
  const value = typeof raw === 'string' ? raw.toLowerCase() : '';
  if (!value) return 'none';
  for (const [label, pattern] of [
    ['credits_or_limits', /credit|quota|concurrency|limit|subscription|plan|balance/],
    ['agent_not_initialized', /agent.*not.*initiali[sz]/],
    ['agent_not_published', /agent.*not.*publish/],
    ['agent_not_ready', /agent.*not.*ready/],
    ['agent_not_found', /agent.*not.*(found|exist|available)/],
    ['initiation_timeout', /initiat.*(timeout|timed out)|timed out.*initiat/],
    ['client_disconnected', /client.*disconnect|disconnect.*client/],
    ['agent_timeout', /agent.*(timeout|timed out)/],
    ['inactivity', /inactiv|silence/],
    ['voice_unavailable', /voice.*(not found|unavailable|permission|invalid)/],
    ['tts_failure', /tts|text.to.speech|synthesi/],
    ['override_rejected', /overrid/],
    ['transport_failure', /webrtc|livekit|websocket|connection/],
    ['provider_failure', /internal|server error|llm/],
    ['normal_end', /normal|completed|end.call|user.*end/],
  ] as const) if (pattern.test(value)) return label;
  return 'other_redacted';
}
for (const [label, variable] of [['voice', 'ELEVENLABS_AGENT_ID'], ['relay', 'ELEVENLABS_RELAY_AGENT_ID']] as const) {
  const id = process.env[variable]; if (!id) continue;
  const url = new URL(api + '/conversations'); url.searchParams.set('agent_id', id); url.searchParams.set('page_size', '12');
  const agent = await read(api + '/agents/' + encodeURIComponent(id));
  const branches = await read(api + '/agents/' + encodeURIComponent(id) + '/branches');
  const deployments = await read(api + '/agents/' + encodeURIComponent(id) + '/deployments?page_size=5');
  const safeShape = (value: any): any => value == null || typeof value === 'boolean' || typeof value === 'number' ? value : typeof value === 'string' ? (['main', 'active', 'production', 'available', 'unavailable', 'ready', 'draft', 'published', 'start'].includes(value) ? value : '[redacted]') : Array.isArray(value) ? value.map(safeShape) : Object.fromEntries(Object.entries(value).filter(([key]) => !['name', 'description', 'agent_id', 'version_id', 'branch_id', 'user_id', 'created_by', 'conversation_config', 'platform_settings', 'workflow'].includes(key)).map(([key, child]) => [key, safeShape(child)]));
  console.log(JSON.stringify({ agent: label, branches: safeShape(branches), deployments: safeShape(deployments), limits: safeShape(agent.platform_settings?.limits) }));
  const listing = await read(url.toString());
  const rows = Array.isArray(listing.conversations) ? listing.conversations.slice(0, 12) : [];
  console.log(JSON.stringify({ agent: label, recentCalls: rows.length }));
  for (const row of rows) {
    if (typeof row.conversation_id !== 'string' || !/^[a-zA-Z0-9_-]{5,120}$/.test(row.conversation_id)) continue;
    const detail = await read(api + '/conversations/' + encodeURIComponent(row.conversation_id));
    const metadata = detail.metadata ?? {};
    if (label === 'voice' && detail.status === 'done' && typeof detail.version_id === 'string') {
      const prior = await read(api + '/agents/' + encodeURIComponent(id) + '?version_id=' + encodeURIComponent(detail.version_id));
      console.log(JSON.stringify({ priorWorkingShape: true, workflow: safeShape(prior.workflow), currentWorkflow: safeShape(agent.workflow) }));
    }
    const error = metadata.error ?? {};
    console.log(JSON.stringify({
      agent: label,
      startedAt: typeof metadata.start_time_unix_secs === 'number' ? new Date(metadata.start_time_unix_secs * 1000).toISOString() : null,
      durationSeconds: typeof metadata.call_duration_secs === 'number' ? metadata.call_duration_secs : null,
      status: ['initiated', 'in-progress', 'processing', 'done', 'failed'].includes(detail.status) ? detail.status : 'other_redacted',
      termination: classify(metadata.termination_reason),
      error: classify(typeof error === 'string' ? error : error.reason),
      errorCode: typeof error.code === 'number' ? error.code : null,
      errorVocabulary: typeof error.reason === 'string' ? [...new Set(error.reason.toLowerCase().match(/[a-z_]+/g) ?? [])].filter((word: string) => ['with', 'id', 'is', 'a', 'the', 'in', 'for', 'was', 'when', 'to', 'from', 'start_node', 'requested', 'agent_id', 'has', 'been', 'deleted', 'selected', 'does', 'support', 'on', 'this', 'plan', 'subscription', 'credits', 'quota', 'insufficient', 'concurrency', 'limit', 'monthly', 'budget', 'exceeded', 'balance', 'locked', 'blocked', 'paused', 'currently', 'please', 'contact', 'support', 'because', 'region', 'deployment', 'version_id', 'fetch', 'retrieved', 'loaded', 'loading', 'live', 'snapshot', 'draft', 'production', 'initialized', 'initialised', 'published', 'deployed', 'configured', 'ready', 'exist', 'exists', 'available', 'access', 'accessible', 'allowed', 'inactive', 'branch', 'archived', 'initiation', 'conversation', 'client', 'data', 'timeout', 'timed', 'out', 'missing', 'invalid', 'required', 'override', 'overrides', 'agent', 'version', 'not', 'found', 'authentication', 'failed', 'error', 'permission', 'received', 'connection', 'closed', 'websocket', 'livekit', 'webrtc', 'configuration', 'conversation_config_override', 'first_message', 'prompt', 'tts', 'voice_id', 'voice', 'model', 'llm', 'language', 'secret', 'dynamic', 'variable', 'variables', 'tool', 'tools', 'response', 'pre_tool_speech', 'internal', 'server', 'greeting', 'disabled', 'enabled', 'authorization', 'start', 'event', 'type', 'text_only'].includes(word)).slice(0, 30) : [],
      errorReasonStructure: typeof error.reason === 'string' ? error.reason.replace(/[a-zA-Z0-9_-]+/g, (word: string) => ['agent', 'with', 'id', 'is', 'a', 'the', 'in', 'for', 'was', 'when', 'to', 'from', 'not', 'available', 'version', 'config', 'configuration', 'error', 'start', 'node', 'workflow', 'branch', 'voice', 'llm', 'model', 'language', 'this', 'account', 'tool', 'tools'].includes(word.toLowerCase()) ? word.toLowerCase() : '[redacted]').slice(0, 300) : null,
      currentVersionMatches: detail.version_id === agent.version_id,
      exactAgentUnavailable: typeof error.reason === 'string' && /^agent (?:is )?not available\.?$/i.test(error.reason),
      textOnly: metadata.text_only === true,
      // Only presence, never values, of initiation overrides is inspected.
      openingOverridePresent: typeof detail.conversation_initiation_client_data?.conversation_config_override?.agent?.first_message === 'string',
      promptOverridePresent: typeof detail.conversation_initiation_client_data?.conversation_config_override?.agent?.prompt?.prompt === 'string',
    }));
  }
}
