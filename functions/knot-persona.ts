import { knotAITransport, type KnotAIEnv } from './knot-ai-transport';
import { avatarReviewer, staticAvatarWebP, requireH264Avatar, reviewAvatar, type AvatarQuality } from './knot-avatar-quality';

// Private account actor storage only. No public media URLs or client-selected owner.
type ChatSource = { bot: 'main'; conversationID: string; sourceMessageID: string };
const chatSource = (v: unknown): ChatSource | undefined => {
  const s = v as Partial<ChatSource> | undefined;
  return s?.bot === 'main' && uuid(s.conversationID) && uuid(s.sourceMessageID) ? { bot: 'main', conversationID: s.conversationID.toLowerCase(), sourceMessageID: s.sourceMessageID.toLowerCase() } : undefined;
};
type Media = { id: string; kind: string; status: string; quality?: AvatarQuality };
type SetRecord = { source?: ChatSource; id: string; masterMediaID: string; createdAt: number; media: Media[]; previousSetID?: string | null; states?: Record<string, string>; quality?: AvatarQuality };
type Job = { source?: ChatSource; id: string; setID?: string; kind: string; status: string; count: number; completed: number; createdAt: number; error?: string };
type Persona = { pendingAvatar?: { id: string; source?: ChatSource; prompt: string; count: number; edit: boolean }; restoreRequested?: boolean; restoreSource?: ChatSource; consentScope?: string; version: number; epoch: string; name: string; vibe: string; consent: boolean; consentModel: string | null; masterID: string | null; sets: SetRecord[]; candidates: { source?: ChatSource; jobID?: string; id: string; mediaID: string; quality?: AvatarQuality }[]; jobs: Job[] };
type Model = { id: string; name: string; kind: 'image' | 'video' | 'review'; provider: string; available: boolean; duration?: number };
const running = new WeakMap<DurableObjectState, AbortController>();
const cancelRunning = (ctx: DurableObjectState) => { running.get(ctx)?.abort(); running.delete(ctx); };
const uuid = (v: unknown): v is string => typeof v === 'string' && /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(v);
const json = (value: unknown, status = 200) => Response.json(value, { status, headers: { 'Cache-Control': 'private, no-store' } });
const fresh = (): Persona => ({ version: 0, epoch: crypto.randomUUID(), name: 'Knot', vibe: '', consent: false, consentModel: null, masterID: null, sets: [], candidates: [], jobs: [] });
export function initializeKnotPersona(ctx: DurableObjectState): void {
  ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS knot_persona (id INTEGER PRIMARY KEY, data TEXT NOT NULL)');
  ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS knot_persona_media (id TEXT NOT NULL, part INTEGER NOT NULL, mime TEXT NOT NULL, data BLOB NOT NULL, PRIMARY KEY(id,part))');
  ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS knot_persona_jobs (id TEXT PRIMARY KEY)');
}
function read(ctx: DurableObjectState): Persona {
  const row = ctx.storage.sql.exec<{ data: string }>('SELECT data FROM knot_persona WHERE id=1').toArray()[0];
  if (row) return JSON.parse(row.data) as Persona;
  const value = fresh(); save(ctx, value); return value;
}
function save(ctx: DurableObjectState, p: Persona): void { ctx.storage.sql.exec('INSERT INTO knot_persona VALUES (1,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data', JSON.stringify(p)); }
export function eraseKnotPersona(ctx: DurableObjectState): void {
  // Retain job tombstones and replace the epoch before any suspended I/O returns.
  cancelRunning(ctx);
  const previous = read(ctx), p = fresh(); p.version = previous.version + 1;
  ctx.storage.transactionSync(() => { save(ctx, p); ctx.storage.sql.exec('DELETE FROM knot_persona_media'); });
}
function media(ctx: DurableObjectState, id: string): { bytes: Uint8Array; mime: string } | undefined {
  const rows = ctx.storage.sql.exec<{ data: ArrayBuffer; mime: string }>('SELECT data,mime FROM knot_persona_media WHERE id=? ORDER BY part', id).toArray();
  if (!rows.length) return;
  const bytes = new Uint8Array(rows.reduce((n,r) => n + r.data.byteLength, 0)); let offset = 0;
  for (const r of rows) { bytes.set(new Uint8Array(r.data), offset); offset += r.data.byteLength; }
  return { bytes, mime: rows[0].mime };
}
function store(ctx: DurableObjectState, bytes: Uint8Array, mime: string): string {
  const used = ctx.storage.sql.exec<{ total: number }>('SELECT COALESCE(SUM(length(data)),0) AS total FROM knot_persona_media').toArray()[0].total;
  if (!bytes.length || used + bytes.length > 64 * 1024 * 1024) throw new Error('private_media_capacity');
  const id = crypto.randomUUID();
  for (let offset = 0, part = 0; offset < bytes.length; offset += 64000, part++) ctx.storage.sql.exec('INSERT INTO knot_persona_media VALUES (?,?,?,?)', id, part, mime, bytes.slice(offset, offset + 64000).buffer);
  return id;
}
function base64(bytes: Uint8Array): string { let value = ''; for (let n = 0; n < bytes.length; n += 16000) value += String.fromCharCode(...bytes.subarray(n, n + 16000)); return btoa(value); }
function decode(value: string, limit: number): Uint8Array {
  if (value.length > Math.ceil(limit / 3) * 4 || !/^[A-Za-z0-9+/]*={0,2}$/.test(value)) throw new Error('media_too_large_or_invalid');
  const binary = atob(value); if (binary.length > limit) throw new Error('media_too_large_or_invalid');
  return Uint8Array.from(binary, c => c.charCodeAt(0));
}
async function bodyText(response: Response, limit: number): Promise<string> {
  const reader = response.body?.getReader(); if (!reader) throw new Error('missing_response');
  const decoder = new TextDecoder(); let text = '', size = 0;
  try { for (;;) { const part = await reader.read(); if (part.done) break; size += part.value.byteLength; if (size > limit) throw new Error('response_too_large'); text += decoder.decode(part.value, { stream: true }); } return text + decoder.decode(); }
  finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
}
async function models(env: KnotAIEnv, signal: AbortSignal): Promise<Model[]> {
  const transport = knotAITransport(env); if (!transport) throw new Error('cloud_unavailable');
  const response = await fetch(transport.chatURL.replace('/chat/completions', '/models'), { headers: { Authorization: `Bearer ${transport.token}` }, signal });
  if (!response.ok) { await response.body?.cancel(); throw new Error('catalogue_unavailable'); }
  const raw = JSON.parse(await bodyText(response, 4000000)) as { data?: Record<string, any>[] };
  return (raw.data ?? []).flatMap((m): Model[] => {
    if (typeof m.id !== 'string' || typeof m.name !== 'string') return [];
    const common = { id: m.id, name: m.name, provider: typeof m.owned_by === 'string' ? m.owned_by : m.id.split('/')[0], available: true };
    if (m.type === 'language' && m.modalities?.input?.includes('image') && m.modalities?.output?.includes('image')) return [{ ...common, kind: 'image' }];
    if (m.id === avatarReviewer && m.type === 'language' && ['image', 'video'].every(k => m.modalities?.input?.includes(k)) && m.modalities?.output?.includes('text')) return [{ ...common, kind: 'review' }];
    const caps = m.video_capabilities;
    if (m.type === 'video' && caps?.supported_operations?.includes('image-to-video') && caps?.input_limits?.image?.supported_sources?.some((s: string) => ['base64', 'file', 'buffer'].includes(s))) {
      const duration = (caps.supported_durations_seconds as unknown[])?.filter((n): n is number => typeof n === 'number' && n >= 2 && n <= 6).sort((a,b) => a-b)[0];
      if (duration) return [{ ...common, kind: 'video', duration }];
    }
    return [];
  });
}
export const avatarSharingScope = 'google_avatar_media_quality_v2';
const avatarImageModel = 'google/gemini-2.5-flash-image';
const avatarVideoModel = 'google/veo-3.1-fast-generate-001';
const fixedStates = ['connecting', 'idle', 'working', 'waiting_for_subagents', 'making_something', 'milestone_level_up'];
const activationStates = ['call_portrait', ...fixedStates];
const motions: Record<string, string> = {
  call_portrait: 'Create a static call portrait from this exact master: same being, style, markings and outfit, centered readable face with comfortable margins on plain pure white.',
  connecting: 'Gently become attentive and greet once.',
  waiting_for_subagents: 'A seamless patient attentive waiting loop.',
  making_something: 'A seamless creative concentration loop.',
  milestone_level_up: 'One short joyful celebration, then return to resting pose.',
  idle: 'A seamless quiet breathing and blinking loop.', working: 'A seamless focused thinking loop, subtle eyes and movement.',
  'making-something': 'A seamless creative concentration loop, with a small floating orb.', waking: 'Wake up once and greet gently.', milestone: 'One short joyful celebration.',
  dance: 'One playful short full-body dance, distinct choreography.', 'call-listening': 'A seamless attentive listening loop, no speech.', 'call-speaking': 'A seamless expressive conversational speaking loop, silent video.',
};
export async function knotPersonaActor(ctx: DurableObjectState, env: KnotAIEnv, path: string, input: Record<string, unknown>, signal: AbortSignal): Promise<Response> {
  let p = read(ctx);
  if (path === '/persona/read') {
    // Lost requests are not replayed; expiration is explicitly uncertain.
    let changed = false;
    for (const j of p.jobs) if (j.status === 'generating' && Date.now() - j.createdAt > 12 * 60000) { j.status = 'unconfirmed'; j.error = 'Generation ended without a confirmed result. It will not restart automatically.'; const set = p.sets.find(s => s.id === j.setID); if (set?.states?.[j.kind] === 'pending') set.states[j.kind] = 'unconfirmed'; changed = true; }
    if (changed) { p.version++; save(ctx, p); }
    return json(p);
  }
  if (path === '/persona/models') { try { return json({ models: await models(env, AbortSignal.any([signal, AbortSignal.timeout(15000)])) }); } catch { return json({ error: 'catalogue_unavailable' }, 503); } }
  if (path === '/persona/media') {
    const item = uuid(input.id) ? media(ctx, input.id) : undefined;
    return item ? new Response(item.bytes, { headers: { 'Content-Type': item.mime, 'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff' } }) : json({ error: 'not_found' }, 404);
  }
  if (!['name','vibe','consent','request','restore-options','pick','revert','approve','candidates','generate'].some(a => path === '/persona/' + a)) return json({ error: 'not_found' }, 404);
  // Revocation must never lose a race to a just-saved clip or another device.
  if (input.version !== p.version && !(path === '/persona/consent' && input.allowed === false)) return json({ error: 'persona_changed' }, 409);
  const text = (value: unknown, max: number) => typeof value === 'string' && value.length <= max && !/[\x00-\x1f<>`]/.test(value) ? value.trim() : undefined;
  if (path === '/persona/name') { const name = text(input.name, 40); if (!name) return json({ error: 'invalid_name' }, 400); p.name = name; }
  if (path === '/persona/vibe') { const vibe = text(input.vibe, 500); if (vibe === undefined) return json({ error: 'invalid_vibe' }, 400); p.vibe = vibe; }
  if (path === '/persona/request') {
    const prompt = text(input.prompt, 1500), count = Number(input.count);
    if (!prompt || !Number.isInteger(count) || count < 1 || count > 4 || typeof input.edit !== 'boolean') return json({ error: 'invalid_generation' }, 400);
    const source = chatSource(input.source); if (!source) return json({ error: 'chat_source_required' }, 400);
    p.pendingAvatar = { id: crypto.randomUUID(), source, prompt, count, edit: input.edit }; p.restoreRequested = false;
  }
  if (path === '/persona/restore-options') {
    const source = chatSource(input.source); if (!source) return json({ error: 'chat_source_required' }, 400);
    p.restoreRequested = true; p.restoreSource = source;
  }
  if (path === '/persona/consent') {
    if (typeof input.allowed !== 'boolean' || input.allowed && input.scope !== avatarSharingScope) return json({ error: 'invalid_consent' }, 400);
    cancelRunning(ctx);
    p.consent = input.allowed; p.consentScope = input.allowed ? avatarSharingScope : undefined;
    p.consentModel = null; p.epoch = crypto.randomUUID();
    for (const j of p.jobs) if (j.status === 'generating') {
      j.status = 'cancelled'; j.error = 'Sharing permission changed; late results are discarded. Already-sent provider work is not confirmed stopped.';
      const set = p.sets.find(s => s.id === j.setID); if (set?.states?.[j.kind] === 'pending') set.states[j.kind] = 'unconfirmed';
    }
  }
  if (path === '/persona/pick') {
    const candidate = p.candidates.find(c => c.id === input.candidateID); if (!candidate) return json({ error: 'candidate_unavailable' }, 404);
    if (!candidate.quality || candidate.quality.version !== 1) return json({ error: 'candidate_quality_required' }, 409);
    if (p.sets.length >= 8) return json({ error: 'avatar_history_full' }, 409);
    const set: SetRecord = { id: crypto.randomUUID(), masterMediaID: candidate.mediaID, createdAt: Date.now(), media: [], previousSetID: p.masterID,
      source: candidate.source, quality: candidate.quality, states: Object.fromEntries(activationStates.map(kind => [kind, 'not_started'])) };
    p.sets.push(set); p.masterID = set.id;
  }
  if (path === '/persona/revert') {
    if (input.setID !== null && !p.sets.some(s => s.id === input.setID)) return json({ error: 'set_unavailable' }, 404);
    p.masterID = input.setID as string | null; p.restoreRequested = false;
  }
  if (path === '/persona/approve') {
    const clip = p.sets.flatMap(s => s.media).find(m => m.id === input.mediaID);
    if (!clip || !['review','ready'].includes(clip.status)) return json({ error: 'media_unavailable' }, 404);
    clip.status = 'ready';
    const set = p.sets.find(s => s.media.includes(clip)); if (set?.states) set.states[clip.kind] = 'completed';
  }
  if (['/persona/pick','/persona/revert'].includes(path)) {
    // A newer master wins even if the user switches away and back during I/O.
    cancelRunning(ctx);
    p.epoch = crypto.randomUUID();
    for (const j of p.jobs) if (j.status === 'generating') {
      j.status = 'cancelled'; j.error = 'The master changed. Late media is discarded, not mixed into this set.';
      const set = p.sets.find(s => s.id === j.setID); if (set?.states?.[j.kind] === 'pending') set.states[j.kind] = 'unconfirmed';
    }
  }
  if (!['/persona/candidates','/persona/generate'].includes(path)) {
    p.version++; save(ctx, p);
    if (path === '/persona/pick' && p.consent && p.consentScope === avatarSharingScope) {
      const selectedID = p.masterID, epoch = p.epoch;
      // One owned attempt per state. Eviction/lost responses are never replayed.
      ctx.waitUntil((async () => {
        for (const kind of activationStates) {
          const current = read(ctx);
          if (current.epoch !== epoch || current.masterID !== selectedID || !current.consent) return;
          const response = await knotPersonaActor(ctx, env, '/persona/generate', { version: current.version, jobID: crypto.randomUUID(), kind, count: 1 }, AbortSignal.timeout(10 * 60000));
          await response.body?.cancel();
        }
      })().catch(() => { /* Pending state remains honestly unconfirmed on read. */ }));
    }
    return json(p);
  }
  const image = path === '/persona/candidates', kind = image ? 'candidate' : String(input.kind), portrait = kind === 'call_portrait', still = image || portrait, count = Number(input.count), prompt = text(input.prompt ?? '', 1500);
  if (!uuid(input.jobID) || !Number.isInteger(count) || count < 1 || count > (image ? 4 : 6) || !image && !motions[kind] || image && !prompt) return json({ error: 'invalid_generation' }, 400);
  if (!p.consent || p.consentScope !== avatarSharingScope) return json({ error: 'generation_consent_required' }, 403);
  const set = p.sets.find(s => s.id === p.masterID), master = set ? media(ctx, set.masterMediaID) : undefined;
  if ((!image || input.edit === true) && !master) return json({ error: 'master_required' }, 409);
  if (p.jobs.some(j => j.status === 'generating') || p.jobs.length >= 80 || image && p.candidates.length + count > 24 || !image && set!.media.length + count > 48) return json({ error: 'generation_capacity' }, 409);
  if (ctx.storage.sql.exec('SELECT 1 FROM knot_persona_jobs WHERE id=?', input.jobID).toArray().length) return json({ error: 'generation_already_consumed' }, 409);
  // Consent continuation uses the actor-saved source, never a client reanchor.
  const pending = input.pendingID === p.pendingAvatar?.id ? p.pendingAvatar : undefined;
  if (image && input.pendingID !== undefined && (!pending || pending.prompt !== prompt || pending.count !== count || pending.edit !== (input.edit === true))) return json({ error: 'persona_changed' }, 409);
  const source = image ? pending?.source ?? chatSource(input.source) : set?.source;
  if (image && !source) return json({ error: 'chat_source_required' }, 400);
  if (image) delete p.pendingAvatar;
  if (!image && set?.states) set.states[kind] = 'pending';
  const job: Job = { source, id: input.jobID, ...(!image && set ? { setID: set.id } : {}), kind, status: 'generating', count, completed: 0, createdAt: Date.now() }, epoch = p.epoch, masterID = p.masterID;
  ctx.storage.transactionSync(() => { ctx.storage.sql.exec('INSERT INTO knot_persona_jobs VALUES (?)', job.id); p.jobs.push(job); p.version++; save(ctx, p); });
  const active = () => { const now = read(ctx); return now.epoch === epoch && now.consent && now.consentScope === avatarSharingScope && now.masterID === masterID && now.jobs.some(j => j.id === job.id && j.status === 'generating') ? now : undefined; };
  const controller = new AbortController(); running.set(ctx, controller);
  let providerDispatched = false;
  try {
    const deadline = AbortSignal.any([controller.signal, signal, AbortSignal.timeout(10 * 60000)]), transport = knotAITransport(env);
    if (!transport) throw new Error('cloud_unavailable');
    const catalogue = await models(env, AbortSignal.any([deadline, AbortSignal.timeout(15000)]));
    const selected = catalogue.find(m => m.id === (still ? avatarImageModel : avatarVideoModel) && m.kind === (still ? 'image' : 'video'));
    if (!selected || !catalogue.some(m => m.id === avatarReviewer && m.kind === 'review')) throw new Error('compatible_model_unavailable');
    let batchReference = input.edit === true ? master : undefined;
    for (let index = 0; index < count; index++) {
      if (!active()) throw new Error('generation_superseded');
      const identity = 'Preserve the exact character identity, body shape, facial features, materials, colours and proportions of the attached master. Never substitute a different character. Plain pure white background, centered single subject, complete portrait and readable face; no captions, logos or extra characters. ';
      const content: unknown[] = [{ type: 'text', text: image ? `${batchReference ? identity : 'Create a distinctive friendly assistant avatar: plain pure white background, centered single subject, readable face, complete portrait. '}${prompt}. Candidate ${index + 1} of ${count}.` : identity + motions[kind] + ` Variation ${index + 1}. Keep camera and framing fixed. No audio.` }];
      const reference = image ? batchReference : master;
      if (still && reference) content.push({ type: 'image_url', image_url: { url: `data:${reference.mime};base64,${base64(reference.bytes)}` } });
      const payload = still ? { model: selected.id, modalities: ['text','image'], stream: false, messages: [{ role: 'user', content }] } : { model: selected.id, prompt: (content[0] as { text: string }).text, duration: selected.duration, generateAudio: false, providerOptions: { vertex: { generateAudio: false, pollIntervalMs: 5000, pollTimeoutMs: 9 * 60000 } }, image: { type: 'file', data: base64(master!.bytes), mediaType: master!.mime } };
      const encoded = JSON.stringify(payload); if (new TextEncoder().encode(encoded).length > 4400000) throw new Error('master_too_large');
      if (!active()) throw new Error('generation_superseded');
      providerDispatched = true;
      const response = await fetch(still ? transport.chatURL : transport.chatURL.replace('/v1/chat/completions', '/v4/ai/video-model'), { method: 'POST', headers: { Authorization: `Bearer ${transport.token}`, 'Content-Type': 'application/json', 'idempotency-key': `${job.id}:${index}`, ...(!still ? { accept: 'text/event-stream', 'ai-gateway-protocol-version': '0.0.1', 'ai-video-model-specification-version': '4', 'ai-model-id': selected.id } : {}) }, body: encoded, signal: deadline });
      if (!response.ok) { await response.body?.cancel(); throw new Error([400, 401, 403, 404, 422].includes(response.status) ? 'generation_rejected' : 'generation_unconfirmed'); }
      const raw = await bodyText(response, still ? 4500000 : 17000000);
      let bytes: Uint8Array, mime: string;
      if (still) {
        const result = JSON.parse(raw), entry = result.choices?.[0]?.message?.images?.[0], uri = typeof entry === 'string' ? entry : entry?.image_url?.url;
        const match = typeof uri === 'string' ? /^data:(image\/(?:png|jpeg|webp));base64,([A-Za-z0-9+/=]+)$/.exec(uri) : null;
        if (!match) throw new Error('private_image_not_returned'); mime = match[1]; bytes = decode(match[2], 2900000);
        try { const normalized = staticAvatarWebP({ bytes, mime }); bytes = normalized.bytes; mime = normalized.mime; }
        catch { throw new Error('avatar_format_rejected'); }
      } else {
        let video: { data?: string; base64?: string; mediaType?: string } | undefined;
        for (const event of raw.split(/\r?\n\r?\n/)) {
          const data = event.split(/\r?\n/).filter(l => l.startsWith('data:')).map(l => l.slice(5).trimStart()).join('\n');
          if (!data || data === '[DONE]') continue;
          const item = JSON.parse(data); if (item.type === 'error' || item.error) throw new Error('generation_unconfirmed');
          if (Array.isArray(item.videos) && item.videos.length) video = item.videos[0];
        }
        // Never follow an upstream hosted URL for private avatar output.
        if (!video || typeof (video.data ?? video.base64) !== 'string') throw new Error('private_video_not_returned');
        mime = 'video/mp4';
        const value = (video.data ?? video.base64)!;
        bytes = decode(value.startsWith('data:video/mp4;base64,') ? value.slice('data:video/mp4;base64,'.length) : value, 12000000);
        try { requireH264Avatar(bytes); } catch { throw new Error('avatar_format_rejected'); }
      }
      if (!active()) throw new Error('generation_superseded');
      // A separate model invocation inspects these exact normalized/output bytes.
      // Over-envelope clips fail closed: never publish a private URL or pass by prompt.
      const quality = await reviewAvatar(env, { bytes, mime }, reference, image && input.edit === true ? 'edited candidate' : kind, deadline, () => !!active());
      if (image && !batchReference) batchReference = { bytes, mime };
      const current = active(); if (!current) throw new Error('generation_superseded');
      ctx.storage.transactionSync(() => {
        const id = store(ctx, bytes, mime);
        if (image) current.candidates.push({ source: job.source, jobID: job.id, id: crypto.randomUUID(), mediaID: id, quality });
        else {
          const target = current.sets.find(s => s.id === masterID)!;
          // Picking this master authorizes its fixed derived set. Independent
          // exact-byte quality checks above still gate activation, not extra taps.
          const activate = activationStates.includes(kind);
          target.media.push({ id, kind, status: activate ? 'ready' : 'review', quality });
          if (target.states) target.states[kind] = activate ? 'completed' : 'review';
        }
        const saved = current.jobs.find(j => j.id === job.id)!; saved.completed++; current.version++; save(ctx, current);
      });
    }
    p = read(ctx); const saved = p.jobs.find(j => j.id === job.id); if (saved?.status === 'generating') { saved.status = 'completed'; p.version++; save(ctx, p); }
    return json(p);
  } catch (error) {
    p = read(ctx); const saved = p.jobs.find(j => j.id === job.id);
    const knownFailures = ['cloud_unavailable','compatible_model_unavailable','master_too_large','private_media_capacity','private_image_not_returned','private_video_not_returned','invalid_media','media_too_large_or_invalid','generation_rejected','avatar_format_rejected','avatar_review_too_large','avatar_quality_rejected'];
    const definiteFailure = !providerDispatched || error instanceof Error && knownFailures.includes(error.message);
    if (saved?.status === 'generating') {
      saved.status = definiteFailure ? 'failed' : 'unconfirmed';
      saved.error = error instanceof Error && knownFailures.includes(error.message) ? error.message : 'Generation ended without a confirmed result. It will not restart automatically.';
      p.version++; save(ctx, p);
    }
    const target = p.sets.find(s => s.id === masterID);
    if (!image && target?.states && target.states[kind] === 'pending') { target.states[kind] = definiteFailure ? 'failed' : 'unconfirmed'; p.version++; save(ctx, p); }
    return json(p);
  } finally { if (running.get(ctx) === controller) running.delete(ctx); }
}
