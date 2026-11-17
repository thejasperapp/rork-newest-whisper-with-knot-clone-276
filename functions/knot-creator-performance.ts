// The only private read granted by creator_performance. Never exposed as a live
// model tool: owner comes from verified auth / the account Durable Object.
const database = 'https://uryyyegnbtlmyhqlgndy.supabase.co/rest/v1';
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const creatorConsentVersion = 'knot_creator_performance_v1';
export type CreatorEnv = { SUPABASE_SERVICE_ROLE_KEY?: string };
export class CreatorAccessRequired extends Error { constructor() { super('creator_access_required'); } }
export type CreatorBaseline = { followers: number; asOf: string };
export type CreatorSnapshot = {
  asOf: string; windowDays: 30; coveredPosts: number; coverageLimited: boolean;
  followers: number; likes: number; comments: number; interactions: number; medianInteractions: number;
  topPosts: { id: string; publishedAt: string; likes: number; comments: number }[];
  creatorScoreEstimate: number | null;
  followerChangeSinceMonitoringStarted: number;
  baseline: CreatorBaseline;
};
type Access = { score: boolean };
type Post = { id: string; user_id: string; created_at: string; likes_count: number; comments_count: number };
function object(raw: unknown): Record<string, unknown> {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new Error('invalid_creator_data');
  return raw as Record<string, unknown>;
}
async function body(response: Response): Promise<unknown> {
  if (!response.body) throw new Error('creator_read_unavailable');
  const reader = response.body.getReader(), decoder = new TextDecoder();
  let size = 0, text = '';
  try {
    for (;;) {
      const item = await reader.read(); if (item.done) break;
      size += item.value.byteLength; if (size > 64000) throw new Error('creator_read_too_large');
      text += decoder.decode(item.value, { stream: true });
    }
    return JSON.parse(text + decoder.decode()) as unknown;
  } finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
}
async function read(env: CreatorEnv, owner: string, path: string, signal: AbortSignal, head = false): Promise<Response> {
  if (!uuid.test(owner) || !env.SUPABASE_SERVICE_ROLE_KEY) throw new Error('creator_read_unavailable');
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  const result = await fetch(database + path, { method: head ? 'HEAD' : 'GET', redirect: 'manual',
    headers: { apikey: key, Authorization: `Bearer ${key}`, ...(head ? { Prefer: 'count=exact' } : {}) },
    signal: AbortSignal.any([signal, AbortSignal.timeout(6000)]) });
  if (!result.ok) { await result.body?.cancel(); throw new Error('creator_read_unavailable'); }
  return result;
}
async function rows(env: CreatorEnv, owner: string, path: string, signal: AbortSignal): Promise<Record<string, unknown>[]> {
  const data = await body(await read(env, owner, path, signal));
  if (!Array.isArray(data)) throw new Error('invalid_creator_data');
  return data.map(object);
}
/** Resolve existing server-owned flags, matching Whisper's badge/analytics
 * ladder. An application, Plus, a supplied handle or model claim is not access.
 * Missing/failed reads never become an eligible account or a zero snapshot. */
export async function requireCreatorAccess(env: CreatorEnv, owner: string, signal: AbortSignal): Promise<Access> {
  if (!uuid.test(owner)) throw new Error('invalid_owner');
  const uid = encodeURIComponent(owner);
  const [social, profiles, admins] = await Promise.all([
    rows(env, owner, `/whisper_profiles?user_id=eq.${uid}&select=user_id,account_type,is_one,is_verified,is_moderator,is_admin,is_owner&limit=1`, signal),
    rows(env, owner, `/profiles?id=eq.${uid}&select=id,is_verified,is_moderator,is_admin,is_owner&limit=1`, signal),
    rows(env, owner, `/whisper_admins?user_id=eq.${uid}&select=user_id,role&limit=1`, signal),
  ]);
  const s = social[0], p = profiles[0], a = admins[0];
  if (!s || s.user_id !== owner || (p && p.id !== owner) || (a && a.user_id !== owner)) throw new Error('invalid_creator_owner');
  const score = [s, p].some(r => r && ['is_verified', 'is_moderator', 'is_admin', 'is_owner'].some(flag => r[flag] === true)) || !!(a && ['owner', 'admin', 'moderator'].includes(String(a.role)));
  if (!score && s.account_type !== 'creator' && s.account_type !== 'business' && s.is_one !== true) throw new CreatorAccessRequired();
  return { score };
}
const count = (value: unknown): value is number => typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;
/** Deterministic calculation from a fixed <=100-post projection, not AI maths.
 * The baseline begins on the first successful approved check, not last week. */
export function creatorSnapshot(raw: unknown[], followers: number, owner: string, scoreAllowed: boolean, baseline?: CreatorBaseline, now = Date.now()): CreatorSnapshot {
  if (!count(followers) || raw.length > 101) throw new Error('invalid_creator_data');
  const all = raw.map(item => {
    const p = object(item);
    if (p.user_id !== owner || typeof p.id !== 'string' || !uuid.test(p.id) || typeof p.created_at !== 'string' || !Number.isFinite(Date.parse(p.created_at)) || Date.parse(p.created_at) > now || !count(p.likes_count) || !count(p.comments_count)) throw new Error('invalid_creator_data');
    return p as unknown as Post;
  });
  if (new Set(all.map(p => p.id)).size !== all.length) throw new Error('invalid_creator_data');
  for (let i = 1; i < all.length; i++) { if (Date.parse(all[i].created_at) > Date.parse(all[i - 1].created_at)) throw new Error('invalid_creator_order'); }
  const cutoff = now - 30 * 86400000;
  const posts = all.slice(0, 100).filter(p => Date.parse(p.created_at) >= cutoff);
  const likes = posts.reduce((n, p) => n + p.likes_count, 0), comments = posts.reduce((n, p) => n + p.comments_count, 0);
  if (![likes, comments, likes + comments].every(count)) throw new Error('invalid_creator_totals');
  const asOf = new Date(now).toISOString();
  if (baseline && (!count(baseline.followers) || !Number.isFinite(Date.parse(baseline.asOf)) || Date.parse(baseline.asOf) > now)) throw new Error('invalid_creator_baseline');
  const start = baseline ?? { followers, asOf }, delta = followers - start.followers;
  const engagement = followers > 0 && posts.length > 0 ? Math.min(100, 100 * (likes + comments) / followers / posts.length) : 0;
  const interactionValues = posts.map(p => p.likes_count + p.comments_count).sort((a, b) => a - b);
  const middle = Math.floor(interactionValues.length / 2);
  const medianInteractions = interactionValues.length === 0 ? 0 : interactionValues.length % 2 ? interactionValues[middle] : interactionValues[middle - 1] + (interactionValues[middle] - interactionValues[middle - 1]) / 2;
  const score = Math.trunc(Math.min(100, Math.min(40, engagement * 8) + Math.min(30, posts.length * 3) + Math.min(20, followers / 50) + (delta > 0 ? 10 : delta < 0 ? 0 : 5)));
  return { asOf, windowDays: 30, coveredPosts: posts.length, coverageLimited: all.length > 100 && Date.parse(all[100].created_at) >= cutoff,
    followers, likes, comments, interactions: likes + comments, medianInteractions,
    topPosts: [...posts].sort((a, b) => (b.likes_count + b.comments_count) - (a.likes_count + a.comments_count) || a.id.localeCompare(b.id)).slice(0, 3).map(p => ({ id: p.id, publishedAt: p.created_at, likes: p.likes_count, comments: p.comments_count })),
    creatorScoreEstimate: scoreAllowed ? score : null, followerChangeSinceMonitoringStarted: delta, baseline: start };
}
export async function readCreatorSnapshot(env: CreatorEnv, owner: string, signal: AbortSignal, baseline?: CreatorBaseline): Promise<CreatorSnapshot> {
  const access = await requireCreatorAccess(env, owner, signal);
  const uid = encodeURIComponent(owner);
  const [posts, response] = await Promise.all([
    rows(env, owner, `/whisper_posts?user_id=eq.${uid}&select=id,user_id,created_at,likes_count,comments_count&order=created_at.desc,id.desc&limit=101`, signal),
    read(env, owner, `/whisper_follows?followee_id=eq.${uid}&select=followee_id&limit=1`, signal, true),
  ]);
  const range = response.headers.get('content-range'); await response.body?.cancel();
  if (!range || !/\/(?:0|[1-9]\d*)$/.test(range)) throw new Error('creator_count_unavailable');
  return creatorSnapshot(posts, Number(range.split('/')[1]), owner, access.score, baseline);
}
export function creatorFinding(s: CreatorSnapshot): string {
  // Keep the actual report date for future comparisons. Materiality below
  // ignores the date itself, so a new observation is never news by itself.
  return JSON.stringify({ asOf: s.asOf, posts: s.coveredPosts, limited: s.coverageLimited, followers: s.followers, likes: s.likes, comments: s.comments, topPosts: s.topPosts, medianInteractions: s.medianInteractions, score: s.creatorScoreEstimate });
}
type ReportedCreatorFinding = { followers: number; asOf?: string; medianInteractions?: number; topPosts: { id: string; likes: number; comments: number }[] };
function reportedFinding(value: string): ReportedCreatorFinding | undefined {
  if (!value || value.length > 6000) return undefined;
  try {
    const parsed: unknown = JSON.parse(value);
    const p = object(parsed);
    if (!count(p.followers) || !Array.isArray(p.topPosts) || p.topPosts.length > 3) return undefined;
    const topPosts = p.topPosts.map(item => {
      const post = object(item);
      if (typeof post.id !== 'string' || !uuid.test(post.id) || !count(post.likes) || !count(post.comments) || !count(post.likes + post.comments)) throw new Error('invalid_previous_creator_finding');
      return { id: post.id, likes: post.likes, comments: post.comments };
    });
    return { followers: p.followers, topPosts,
      ...(typeof p.asOf === 'string' && Number.isFinite(Date.parse(p.asOf)) ? { asOf: p.asOf } : {}),
      ...(typeof p.medianInteractions === 'number' && Number.isFinite(p.medianInteractions) && p.medianInteractions >= 0 ? { medianInteractions: p.medianInteractions } : {}) };
  } catch { return undefined; }
}
/** The stored finding is the last DELIVERED report, not the last quiet check.
 * No following/name/velocity inference from absent data or capped lists. */
export function creatorMaterialChange(s: CreatorSnapshot, lastFinding: string): boolean {
  const previous = reportedFinding(lastFinding);
  if (!previous) return true; // Establish an honest first comparable baseline.
  if (Math.abs(s.followers - previous.followers) >= Math.max(5, Math.ceil(previous.followers * 0.01))) return true;
  if (!(s.medianInteractions > 0)) return false;
  // Legacy findings have no median: known top-post IDs are conservatively
  // treated as already reported rather than inventing a prior comparison.
  const priorExceptional = new Set(previous.topPosts.filter(post => previous.medianInteractions === undefined || previous.medianInteractions <= 0 || post.likes + post.comments >= previous.medianInteractions * 2).map(post => post.id));
  return s.topPosts.some(post => post.likes + post.comments >= s.medianInteractions * 2 && !priorExceptional.has(post.id));
}
export function creatorReport(s: CreatorSnapshot, lastFinding = ''): string {
  const change = s.followerChangeSinceMonitoringStarted;
  const previous = reportedFinding(lastFinding);
  const reportedDelta = previous ? s.followers - previous.followers : 0;
  const comparison = previous && reportedDelta !== 0 ? `\nFollower change since ${previous.asOf ?? 'the last reported snapshot (date unavailable)'}: ${reportedDelta >= 0 ? '+' : ''}${reportedDelta}.` : '';
  return `Whisper performance · ${s.asOf}\n${s.coveredPosts} posts published in the last 30 days, ${s.likes} current likes and ${s.comments} current comments. ${s.followers} followers${s.baseline.asOf !== s.asOf ? ` (${change >= 0 ? '+' : ''}${change} since monitoring began ${s.baseline.asOf.slice(0, 10)})` : ' · first monitoring baseline saved'}.`
    + comparison
    + (s.creatorScoreEstimate === null ? '\nCreator score is not included: Creator Studio requires verified or staff access.' : `\nCreator score monitoring estimate: ${s.creatorScoreEstimate}/100. Uses audience change since monitoring began, not the device’s weekly baseline; it can differ from Creator Studio.`)
    + (s.topPosts.length ? '\nTop posts by current interactions:\n' + s.topPosts.map((p, i) => `${i + 1}. ${p.publishedAt.slice(0, 16).replace('T', ' ')} UTC · ${p.likes} likes, ${p.comments} comments`).join('\n') : '')
    + `\nCoverage: newest 100 authored posts${s.coverageLimited ? '; additional posts in the 30-day window are not covered' : ''}. Counts are current totals on those posts, not reach or interactions occurring only in the last 30 days.`;
}
