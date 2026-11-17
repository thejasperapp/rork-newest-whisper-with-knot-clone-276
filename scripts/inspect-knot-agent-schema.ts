// Read-only setup diagnostics: count matching agents and inspect official
// schema definitions. Never print agent IDs, credentials or provider bodies.
const key = process.env.ELEVENLABS_API_KEY;
if (!key) throw new Error('Missing server-only key.');
const response = await fetch('https://api.elevenlabs.io/v1/convai/agents?page_size=100&search=Whisper%20Knot', { headers: { 'xi-api-key': key }, signal: AbortSignal.timeout(15000), redirect: 'error' });
if (!response.ok) { await response.body?.cancel(); throw new Error(`Agent list read failed (${response.status}).`); }
const body = await response.json() as { agents?: { name?: string }[]; has_more?: boolean };
console.log(JSON.stringify({ matchingAgents: body.agents?.filter(agent => agent.name === 'Whisper Knot — private voice').length, hasMore: body.has_more, savedAgentPresent: Boolean(process.env.ELEVENLABS_AGENT_ID) }));
if (!process.argv.includes('--schema')) process.exit(0);
const schemaResponse = await fetch('https://api.elevenlabs.io/openapi.json', { signal: AbortSignal.timeout(30000) });
if (!schemaResponse.ok) throw new Error('Official schema unavailable.');
const schema = await schemaResponse.json() as { components: { schemas: Record<string, unknown> } };
for (const [name, definition] of Object.entries(schema.components.schemas)) {
  if (/^(AnalysisLLM|LLM$|PrivacyConfig-Input$)/.test(name)) console.log(JSON.stringify({ name, definition }));
}
export {};
