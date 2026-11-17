// GET-only, fixed allowlist inspection. No calls/tokens/audio, config mutations,
// transcripts, prompts, provider reason strings, identities or recursive dumps.
import { validatedKnotVoiceVersion, validatedKnotVoiceWorkspace, validatedKnotVoiceRelayTool } from '../functions/knot-voice-policy';
export {};
type Obj = Record<string, unknown>;
const object = (v: unknown): Obj => v !== null && typeof v === 'object' && !Array.isArray(v) ? v as Obj : {};
const key = process.env.ELEVENLABS_API_KEY;
if (!key) throw new Error('Server-only voice key is not configured.');
async function read(path: string): Promise<Obj | undefined> {
  try {
    const response = await fetch('https://api.elevenlabs.io/v1/convai/' + path, { method: 'GET', headers: { 'xi-api-key': key! }, redirect: 'manual', signal: AbortSignal.timeout(12000) });
    if (!response.ok) { await response.body?.cancel(); console.log(JSON.stringify({ readHTTP: response.status })); return; }
    const reader = response.body?.getReader(); if (!reader) return;
    const decoder = new TextDecoder(); let text = '', size = 0;
    try {
      for (;;) { const part = await reader.read(); if (part.done) break; size += part.value.length; if (size > 400000) throw new Error('bounded'); text += decoder.decode(part.value, { stream: true }); }
      return object(JSON.parse(text + decoder.decode()));
    } finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
  } catch { console.log(JSON.stringify({ readFailure: 'unavailable_or_bounded' })); }
}
function category(raw: unknown): string {
  if (typeof raw !== 'string' || !raw) return 'none';
  for (const [label, pattern] of [
    ['agent_not_initialized', /agent.*not.*initiali[sz]/], ['agent_not_published', /agent.*not.*publish/],
    ['agent_not_ready', /agent.*not.*ready/], ['agent_not_found', /agent.*not.*(?:found|exist)/],
    ['agent_not_available', /agent.*not.*available/], ['version_unavailable', /version.*(?:not|invalid|missing)/],
    ['branch_unavailable', /branch.*(?:archived|not|invalid|missing)/], ['workflow_entry', /start.node|workflow|entry.node/],
    ['quota_or_limit', /credit|quota|concurren|balance|subscription|budget|rate.limit/],
    ['authentication', /authenticat|unauthori[sz]|permission/], ['override', /overrid/],
    ['transport', /timeout|timed out|webrtc|livekit|websocket|connection/],
  ] as const) if (pattern.test(raw)) return label;
  return 'other_redacted';
}
const workspace = await read('settings');
console.log(JSON.stringify({ workspaceRead: !!workspace, workspacePolicyValid: workspace ? validatedKnotVoiceWorkspace(workspace) : false }));
for (const [agent, variable, detailBound] of [['legacy', 'ELEVENLABS_AGENT_ID', 1], ['relay', 'ELEVENLABS_RELAY_AGENT_ID', 2]] as const) {
  const id = process.env[variable]; if (!id || !/^agent_[a-zA-Z0-9_-]{5,100}$/.test(id)) { console.log(JSON.stringify({ agent, configured: false })); continue; }
  const path = 'agents/' + encodeURIComponent(id);
  const config = await read(path + '?include_procedure_generated_workflow_elements=true');
  if (!config) continue;
  const version = config.version_id;
  const metadata = typeof version === 'string' && /^[a-zA-Z0-9_-]{8,120}$/.test(version) ? await read(path + '/versions/' + encodeURIComponent(version)) : undefined;
  const branches = await read(path + '/branches?include_archived=true&limit=10&include_commit_status=false');
  const deployments = await read(path + '/deployments?page=1&page_size=5');
  const branchRows = Array.isArray(branches?.results) ? branches.results.slice(0, 10).map(object) : [];
  const branch = metadata && branchRows.find(b => b.id === metadata.branch_id);
  const active = Array.isArray(deployments?.results) ? deployments.results.slice(0, 5).map(object).filter(d => d.is_active === true) : [];
  const prompt = object(object(object(config.conversation_config).agent).prompt);
  const toolIDs = Array.isArray(prompt.tool_ids) ? prompt.tool_ids : [];
  const relayToolID = agent === 'relay' && toolIDs.length === 1 && typeof toolIDs[0] === 'string' && /^[a-zA-Z0-9_-]{8,120}$/.test(toolIDs[0]) ? toolIDs[0] : undefined;
  const tool = relayToolID ? await read('tools/' + encodeURIComponent(relayToolID)) : undefined;
  console.log(JSON.stringify({ agent, configRead: true, versionMetadataRead: !!metadata,
    versionIdentityMatches: !!metadata && metadata.id === version && metadata.agent_id === id,
    policyValid: !!process.env.ELEVENLABS_KNOT_BRIDGE_SECRET_ID && !!validatedKnotVoiceVersion(config, id, relayToolID, process.env.ELEVENLABS_KNOT_BRIDGE_SECRET_ID), relayToolValid: agent !== 'relay' || !!tool && validatedKnotVoiceRelayTool(tool),
    versionCommitted: !!metadata && typeof metadata.time_committed_secs === 'number' && metadata.time_committed_secs > 0,
    branchRows: branchRows.length, versionBranchListed: !!branch, versionBranchArchived: branch ? branch.is_archived === true : null,
    branchDraftExists: branch ? branch.draft_exists === true : null,
    branchHasLiveTraffic: branch ? typeof branch.current_live_percentage === 'number' && branch.current_live_percentage > 0 : null,
    activeDeployments: active.length,
    activeDeploymentIncludesVersionBranch: !!metadata && active.some(d => typeof object(d.traffic_percentage_branch_id_map)[String(metadata.branch_id)] === 'number' && (object(d.traffic_percentage_branch_id_map)[String(metadata.branch_id)] as number) > 0),
  }));
  const listing = await read('conversations?' + new URLSearchParams({ agent_id: id, page_size: String(detailBound) }));
  const rows = Array.isArray(listing?.conversations) ? listing.conversations.slice(0, detailBound) : [];
  for (const row of rows.map(object)) {
    if (typeof row.conversation_id !== 'string' || !/^[a-zA-Z0-9_-]{5,120}$/.test(row.conversation_id)) continue;
    const detail = await read('conversations/' + encodeURIComponent(row.conversation_id)); if (!detail) continue;
    const m = object(detail.metadata), error = object(m.error), reason = typeof m.error === 'string' ? m.error : error.reason;
    const time = m.start_time_unix_secs;
    console.log(JSON.stringify({ agent, startedAt: typeof time === 'number' && Number.isFinite(time) && time > 0 && time < 4102444800 ? new Date(time * 1000).toISOString() : null,
      durationSeconds: typeof m.call_duration_secs === 'number' && Number.isFinite(m.call_duration_secs) ? m.call_duration_secs : null,
      errorCode: typeof error.code === 'number' && Number.isFinite(error.code) ? error.code : null,
      error: category(reason), termination: category(m.termination_reason),
      exactAgentNotAvailable: typeof reason === 'string' && /^agent (?:is )?not available\.?$/i.test(reason),
      currentVersionMatches: typeof detail.version_id === 'string' ? detail.version_id === version : null,
    }));
  }
}
