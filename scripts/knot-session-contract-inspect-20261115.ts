// Read-only provider contract inspection. No listing of other accounts, session
// creation, command input, cancellation, capture or changes to historical scopes.
import { sidecarRequest, readSidecarText } from '../functions/knot-shell-discovery';
const env = { SIDECAR_TOKEN_WHISPER: process.env.SIDECAR_TOKEN_WHISPER };
if (!env.SIDECAR_TOKEN_WHISPER) throw new Error('server_credential_unavailable');
for (const path of ['/capabilities', '/openapi.json']) {
  try {
    const response = await sidecarRequest(env, path, 'GET', undefined, 10000);
    const raw = JSON.parse(await readSidecarText(response, 150000));
    if (path === '/capabilities') console.log(JSON.stringify({ path, service: raw.service, sessionTools: raw.tools?.filter((tool: { name: string }) => /session|workspace/.test(tool.name)) }));
    else console.log(JSON.stringify({ path, sessionContracts: Object.entries(raw.paths ?? {}).filter(([route]) => /session|workspace/.test(route)) }));
  } catch (error) { console.log(JSON.stringify({ path, unavailable: true, status: error && typeof error === 'object' && 'status' in error ? error.status : undefined })); }
}
