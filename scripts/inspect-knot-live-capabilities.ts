// Read-only live discovery. Does not create a workspace, job or session, or print credentials.
// Run with rork env run -- bun scripts/inspect-knot-live-capabilities.ts
import { discoverKnotShell, liveShellTools } from '../functions/knot-shell-discovery';
const token = process.env.SIDECAR_TOKEN_WHISPER;
if (!token) throw new Error('Installed backend credential is unavailable to this read-only inspection.');
const capabilities = await discoverKnotShell({ SIDECAR_TOKEN_WHISPER: token, DO: { fetch: async () => { throw new Error('No executor dispatch is allowed in discovery inspection.'); } } });
console.log(JSON.stringify({
  authenticatedDiscovery: capabilities.ok,
  service: capabilities.service,
  principal: capabilities.principal,
  providerTime: capabilities.server_time,
  advertisedEndpointNames: capabilities.tools.map(t => t.name),
  browserContracts: capabilities.tools.filter(t => t.name.startsWith('browser_')),
  fileContracts: capabilities.tools.filter(t => t.name === 'file_read'),
  jobContracts: capabilities.tools.filter(t => ['job_status', 'job_read'].includes(t.name)),
  fixedReadContracts: capabilities.tools.filter(t => t.name === 'exec_once'),
  sessionContracts: capabilities.tools.filter(t => ['session_open', 'session_input', 'session_read', 'session_status'].includes(t.name)),
  limits: capabilities.limits,
  nativeReviewProjection: liveShellTools(capabilities, true, false).map(t => t.function.name),
  receiptProjection: liveShellTools(capabilities, false, true).map(t => t.function.name),
  skills: capabilities.skills,
  memoryFile: capabilities.memory.file,
  remoteExecutionPerformed: false,
}, null, 2));
