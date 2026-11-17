// Read-only service schema inspection. No workspace id, file listing, member
// content, commands, tasks or credentials are printed or executed.
const token = process.env.SIDECAR_TOKEN_WHISPER;
if (!token) throw new Error('The server-only sidecar key is unavailable.');
const shape = (v: any, depth = 0): any => {
  if (!v || typeof v !== 'object' || depth > 8) return undefined;
  return {
    ...(typeof v.type === 'string' ? { type: v.type } : {}),
    ...(typeof v.format === 'string' ? { format: v.format } : {}),
    ...(typeof v.$ref === 'string' ? { reference: v.$ref } : {}),
    ...(Array.isArray(v.required) ? { required: v.required.filter((x: unknown) => typeof x === 'string') } : {}),
    ...(v.properties ? { properties: Object.fromEntries(Object.entries(v.properties).map(([k, child]) => [k, shape(child, depth + 1)])) } : {}),
    ...(v.items ? { items: shape(v.items, depth + 1) } : {}),
    ...(Array.isArray(v.anyOf) ? { anyOf: v.anyOf.map((x: unknown) => shape(x, depth + 1)) } : {}),
  };
};
const response = await fetch('https://knot-shell.mydailywhisper.com/openapi.json', { headers: { Authorization: 'Bearer ' + token }, redirect: 'error', signal: AbortSignal.timeout(15000) });
console.log(JSON.stringify({ schemaReadStatus: response.status }));
if (!response.ok) { await response.body?.cancel(); process.exit(0); }
const schema = await response.json() as any;
for (const [path, route] of Object.entries(schema.paths ?? {}) as [string, any][]) {
  if (!['/files', '/workspace-view'].includes(path)) continue;
  for (const [method, spec] of Object.entries(route) as [string, any][]) {
    console.log(JSON.stringify({ path, method, parameters: spec.parameters?.map((p: any) => ({ name: p.name, in: p.in, required: p.required, schema: shape(p.schema) })), responses: Object.fromEntries(Object.entries(spec.responses ?? {}).map(([code, value]: [string, any]) => [code, { content: Object.fromEntries(Object.entries(value.content ?? {}).map(([type, content]: [string, any]) => [type, shape(content.schema)])) }])) }));
  }
}
for (const [name, value] of Object.entries(schema.components?.schemas ?? {})) if (/Workspace|File.*(?:Response|Entry|Info|View|List)/i.test(name)) console.log(JSON.stringify({ component: name, schema: shape(value) }));
