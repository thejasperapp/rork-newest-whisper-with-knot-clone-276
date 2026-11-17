// @vitest-environment node
import { readFileSync } from "node:fs";
import { PGlite } from "@electric-sql/pglite";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

const owner = "11111111-1111-4111-8111-111111111111";
const peer = "22222222-2222-4222-8222-222222222222";
const stranger = "33333333-3333-4333-8333-333333333333";
const group = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const id = (n: number) => `aaaaaaaa-aaaa-4aaa-8aaa-${String(n).padStart(12, "0")}`;
type Envelope = { cursor_at: string; cursor_id: string; messages: { id: string; read_at: string | null; logical_group_message_id: string | null }[] };
let db: PGlite;
beforeAll(async () => {
  db = new PGlite();
  await db.exec(`
    create role authenticated; create role anon; create schema auth;
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    grant usage on schema auth to authenticated, anon;
    grant execute on function auth.uid() to authenticated, anon;
    create table public.whisper_messages (
      id uuid primary key, thread_id uuid not null, from_user_id uuid not null,
      to_user_id uuid, from_username text, to_username text, body text,
      created_at timestamptz not null, read_at timestamptz, media_url text,
      embed jsonb, logical_group_message_id uuid
    );
    alter table public.whisper_messages enable row level security;
    grant select on public.whisper_messages to authenticated, anon;
    create policy participants on public.whisper_messages for select using
      (auth.uid() = from_user_id or auth.uid() = to_user_id);
    create policy meet_guard on public.whisper_messages as restrictive for select using (id <> '${id(9999)}');
    insert into public.whisper_messages(id,thread_id,from_user_id,to_user_id,body,created_at,read_at,logical_group_message_id)
    select ('aaaaaaaa-aaaa-4aaa-8aaa-' || lpad((n*10+r)::text,12,'0'))::uuid, '${id(1)}','${owner}',
      case when r=1 then '${peer}'::uuid else ('cccccccc-cccc-4ccc-8ccc-' || lpad(r::text,12,'0'))::uuid end,
      '::wg-v1::${group.toUpperCase()}::Friends::message ' || n,
      '2026-11-07T12:00:00.123456Z', case when r=1 then '2026-11-07T13:00:00Z'::timestamptz end,
      ('dddddddd-dddd-4ddd-8ddd-' || lpad(n::text,12,'0'))::uuid
    from generate_series(1,160) n cross join generate_series(1,5) r;
    insert into public.whisper_messages(id,thread_id,from_user_id,to_user_id,body,created_at) values
      ('${id(9999)}','${id(1)}','${peer}','${owner}','::wg-v1::${group}::Friends::denied','2027-01-01'),
      ('${id(9998)}','${id(1)}','${peer}','${stranger}','::wg-v1::${group}::Friends::private','2027-01-01'),
      ('${id(9997)}','${id(1)}','${peer}','${owner}','ordinary direct','2027-01-01'),
      ('${id(9996)}','${id(1)}','${peer}','${owner}','::wg-v1::${id(2)}::Other::other group','2027-01-01');
  `);
  await db.exec(readFileSync(new URL('../../supabase/whisper-group-history.sql', import.meta.url), 'utf8'));
  await db.exec(readFileSync(new URL('../../supabase/whisper-group-summaries.sql', import.meta.url), 'utf8'));
  await db.exec(`set role authenticated; select set_config('request.jwt.claim.sub','${owner}',false);`);
}, 60_000);
afterAll(async () => { await db?.close(); });

const page = (limit = 100, cursor?: Envelope) => db.query<Envelope>(
  'select cursor_at::text, cursor_id, messages from public.whisper_group_history_v1($1,$2,$3,$4)',
  [group, limit, cursor?.cursor_at ?? null, cursor?.cursor_id ?? null]);

describe('group history SQL contract (local Postgres)', () => {
  it('summarizes complete unread state and authorized participants independently of history windows', async () => {
    type Summary = { group_id: string; unread_count: number; participants: { user_id: string }[]; last_message_id: string };
    const sent = (await db.query<Summary>('select * from public.whisper_group_summaries_v1()')).rows.find(r => r.group_id === group)!;
    expect(Number(sent.unread_count)).toBe(0);
    expect(sent.participants).toHaveLength(5);
    expect(sent.last_message_id).toBe(id(1605));
    try {
      await db.exec(`select set_config('request.jwt.claim.sub','${peer}',false);`);
      const received = (await db.query<Summary>('select * from public.whisper_group_summaries_v1()')).rows.find(r => r.group_id === group)!;
      expect(Number(received.unread_count)).toBe(0); // every peer copy has a confirmed read_at
      expect(received.participants).toEqual([{ user_id: owner, username: null }, { user_id: stranger, username: null }]);
      await db.exec("select set_config('request.jwt.claim.sub','cccccccc-cccc-4ccc-8ccc-000000000002',false);");
      const unread = (await db.query<Summary>('select * from public.whisper_group_summaries_v1()')).rows.find(r => r.group_id === group)!;
      expect(Number(unread.unread_count)).toBe(160);
      expect(unread.participants).toEqual([{ user_id: owner, username: null }]);
    } finally { await db.exec(`select set_config('request.jwt.claim.sub','${owner}',false);`); }
  });
  it('paginates quiet groups past the shared history window, honoring hidden IDs and timestamp ties', async () => {
    await db.exec('reset role');
    try {
      await db.exec(`insert into public.whisper_messages(id,thread_id,from_user_id,to_user_id,body,created_at)
        select ('eeeeeeee-eeee-4eee-8eee-'||lpad(n::text,12,'0'))::uuid,'${id(1)}','${peer}','${owner}',
          '::wg-v1::ffffffff-ffff-4fff-8fff-'||lpad(n::text,12,'0')||'::Quiet::hello','2020-01-01T00:00:00.123456Z'
        from generate_series(1,55) n; set role authenticated;`);
      type Summary = { last_created_at: string; last_message_id: string; unread_count: number };
      const first = (await db.query<Summary>('select last_created_at::text,last_message_id,unread_count from public.whisper_group_summaries_v1()')).rows;
      expect(first).toHaveLength(51);
      const last = first[49];
      const rest = (await db.query<Summary>('select * from public.whisper_group_summaries_v1(50,$1,$2)', [last.last_created_at,last.last_message_id])).rows;
      expect(rest[0].last_message_id).toBe(first[50].last_message_id);
      expect(first.slice(0,50).concat(rest).filter(r => r.last_message_id.startsWith('eeeeeeee'))).toHaveLength(55);
      expect(Number(rest[0].unread_count)).toBe(1);
      const hidden = (await db.query<Summary>('select * from public.whisper_group_summaries_v1(50,null,null,$1::uuid[])', [[first[0].last_message_id,null]])).rows;
      expect(hidden.some(r => r.last_message_id === first[0].last_message_id)).toBe(false);
    } finally { await db.exec("reset role; delete from public.whisper_messages where id::text like 'eeeeeeee-%'; set role authenticated;"); }
  });
  it('pages 100 logical messages plus look-ahead without splitting five-recipient fanout', async () => {
    const { rows } = await page();
    expect(rows).toHaveLength(101);
    expect(rows[0].cursor_id).toBe(id(1601));
    expect(rows[99].cursor_id).toBe(id(611));
    expect(rows.every(row => row.messages.length === 5)).toBe(true);
    expect(rows[0].messages[0].read_at).not.toBeNull();
    expect(new Set(rows.flatMap(row => row.messages.map(m => m.id))).size).toBe(505);
  });
  it('continues timestamp ties and microseconds in 50-message older pages without skipping the sentinel', async () => {
    const first = (await page()).rows;
    const second = (await page(50, first[99])).rows;
    expect(second).toHaveLength(51);
    expect(second[0].cursor_id).toBe(first[100].cursor_id);
    expect(second[49].cursor_id).toBe(id(111));
    const third = (await page(50, second[49])).rows;
    expect(third).toHaveLength(10);
    const ids = [...first.slice(0,100), ...second.slice(0,50), ...third].map(r => r.cursor_id);
    expect(new Set(ids).size).toBe(160);
  });
  it('returns only each recipient’s own authorized copies, including restrictive policy enforcement', async () => {
    try {
      await db.exec(`select set_config('request.jwt.claim.sub','${peer}',false);`);
      const { rows } = await page();
      expect(rows.every(row => row.messages.length === 1)).toBe(true);
      expect(rows.some(row => row.messages.some(m => m.id === id(9999)))).toBe(false);
      await db.exec(`select set_config('request.jwt.claim.sub','${stranger}',false);`);
      const thirdParty = (await page()).rows;
      expect(thirdParty).toHaveLength(1);
      expect(thirdParty[0].messages.map(m => m.id)).toEqual([id(9998)]);
    } finally { await db.exec(`select set_config('request.jwt.claim.sub','${owner}',false);`); }
  });
  it('keeps legacy Meet identity, malformed JSON and UTC ten-second compatibility without merging senders', async () => {
    const identity = async (sender: string, body: string, at: string) => (await db.query<{ k: string }>(
      'select public.whisper_group_history_identity_v1($1,null,$2,$3) as k', [sender, body, at])).rows[0].k;
    const meet = `::whisper-calendar-v1::{"kind":"chat-meet","eventID":"${id(7)}","recipient":"one"}`;
    const a = await identity(owner, meet, '2026-11-07T12:00:01Z');
    expect(await identity(owner, meet.replace('one','two'), '2026-11-08T12:00:01Z')).toBe(a);
    expect(await identity(peer, meet, '2026-11-07T12:00:01Z')).not.toBe(a);
    const malformed = '::whisper-calendar-v1::{broken';
    expect(await identity(owner, malformed, '2026-11-07T12:00:01Z')).toContain('|legacy:');
    expect(await identity(owner, 'same', '2026-11-07T12:00:09.999999Z')).toBe(await identity(owner, 'same', '2026-11-07T14:00:01+02:00'));
    expect(await identity(owner, 'same', '2026-11-07T12:00:10Z')).not.toBe(await identity(owner, 'same', '2026-11-07T12:00:09Z'));
  });
  it('uses the earliest fanout representative even when a late copy arrives, retaining all copies', async () => {
    await db.exec('reset role');
    try {
      await db.exec(`insert into public.whisper_messages(id,thread_id,from_user_id,to_user_id,body,created_at,logical_group_message_id) values
        ('${id(9000)}','${id(1)}','${owner}','${peer}','::wg-v1::${group}::Friends::message 1','2028-01-01','dddddddd-dddd-4ddd-8ddd-000000000001');`);
      await db.exec('set role authenticated');
      const first = (await page()).rows;
      expect(first[0].cursor_id).toBe(id(1601));
      const last = (await page(100, first[99])).rows.at(-1)!;
      expect(last.cursor_id).toBe(id(11));
      expect(last.messages).toHaveLength(6);
    } finally {
      await db.exec(`reset role; delete from public.whisper_messages where id='${id(9000)}'; set role authenticated;`);
    }
  });
  it('preserves colons in group names and delimiters in legacy message bodies', async () => {
    await db.exec('reset role');
    try {
      await db.exec(`insert into public.whisper_messages(id,thread_id,from_user_id,to_user_id,body,created_at) values
        ('${id(8001)}','${id(1)}','${owner}','${peer}','::wg-v1::${id(3)}::Friends: work::Hello::world','2026-11-07T12:00:01Z'),
        ('${id(8002)}','${id(1)}','${owner}','${peer}','::wg-v1::${id(3)}::Friends: work::Hello::world','2026-11-07T12:00:09Z');
        set role authenticated;`);
      const result = await db.query<Envelope>('select * from public.whisper_group_history_v1($1)', [id(3)]);
      expect(result.rows).toHaveLength(1);
      expect(result.rows[0].messages.map(m => m.id)).toEqual([id(8001), id(8002)]);
    } finally { await db.exec(`reset role; delete from public.whisper_messages where id in ('${id(8001)}','${id(8002)}'); set role authenticated;`); }
  });
  it('bounds limits, denies anonymous execution and never elevates privileges', async () => {
    expect((await page(500)).rows).toHaveLength(101);
    expect((await page(0)).rows).toHaveLength(2);
    const flags = await db.query<{ prosecdef: boolean; allowed: boolean }>(`select prosecdef, has_function_privilege('anon',oid,'EXECUTE') as allowed from pg_proc where proname in ('whisper_group_history_v1','whisper_group_history_identity_v1')`);
    expect(flags.rows).toEqual([{ prosecdef: false, allowed: false }, { prosecdef: false, allowed: false }]);
    await db.exec('set role anon');
    try { await expect(page()).rejects.toThrow('permission denied'); }
    finally { await db.exec('set role authenticated'); }
  });
});
