// @vitest-environment node
import { readFileSync } from "node:fs";
import { PGlite } from "@electric-sql/pglite";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

const owner = "11111111-1111-4111-8111-111111111111";
const peer = "22222222-2222-4222-8222-222222222222";
const quiet = "33333333-3333-4333-8333-333333333333";
const stranger = "44444444-4444-4444-8444-444444444444";
const id = (n: number) => `aaaaaaaa-aaaa-4aaa-8aaa-${String(n).padStart(12, "0")}`;
let db: PGlite;
type Summary = { peer_id: string; conversation_kind: string; unread_count: number; last_message_id: string; last_created_at: string; last_message: { body: string; embed: unknown } };

beforeAll(async () => {
  db = new PGlite();
  await db.exec(`
    create role authenticated; create role anon;
    create schema auth;
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
    -- Emulate a restrictive Meet-access denial alongside participant RLS.
    create policy meet_guard on public.whisper_messages as restrictive for select using
      (id <> '${id(999)}');
    insert into public.whisper_messages(id,thread_id,from_user_id,to_user_id,body,created_at)
      select ('aaaaaaaa-aaaa-4aaa-8aaa-' || lpad(n::text,12,'0'))::uuid,
        '${id(1)}', '${peer}', '${owner}', 'busy ' || n, '2026-11-07T12:00:00.123456Z'
      from generate_series(1,130) n;
    insert into public.whisper_messages(id,thread_id,from_user_id,to_user_id,body,created_at,embed) values
      ('${id(200)}','${id(1)}','${quiet}','${owner}','quiet old chat','2020-01-01', '{"kind":"invite"}'),
      ('${id(201)}','${id(1)}','${peer}','${stranger}','private third party','2026-11-07',null),
      ('${id(999)}','${id(1)}','${peer}','${owner}','restricted invite','2027-01-01',null),
      ('${id(202)}','${id(1)}','${peer}','${owner}','::wg-v1::group::body','2027-01-01',null),
      ('${id(203)}','${id(1)}','${peer}','${owner}','::whisper-call-invite','2027-01-01',null);
    insert into public.whisper_messages(id,thread_id,from_user_id,to_user_id,body,created_at)
      values ('${id(204)}',
        substr(encode(sha256(convert_to('dating-v1:${owner}|dating-v1:${peer}', 'UTF8')), 'hex'),1,32)::uuid,
        '${peer}','${owner}','dating only','2026-11-07T12:00:00.123456Z');
  `);
  await db.exec(readFileSync(new URL('../../supabase/whisper-thread-summaries.sql', import.meta.url), 'utf8'));
  await db.exec(`set role authenticated; select set_config('request.jwt.claim.sub','${owner}',false);`);
}, 60_000);
afterAll(async () => { await db?.close(); });

describe("deployed summary SQL contract (local Postgres)", () => {
  it("finds quiet chats beyond a busy history window, with complete unread totals and separate dating identity", async () => {
    const { rows } = await db.query<Summary>("select * from public.whisper_thread_summaries_v1()");
    expect(rows.map(r => [r.peer_id, r.conversation_kind])).toEqual([[peer, 'dating'], [peer, 'direct'], [quiet, 'direct']]);
    expect(Number(rows[1].unread_count)).toBe(130);
    expect(rows[1].last_message_id).toBe(id(130));
    expect(rows[2].last_message.embed).toEqual({ kind: 'invite' });
  });
  it("paginates timestamp ties using the raw last ID without skipping the sentinel", async () => {
    const first = await db.query<Summary>("select * from public.whisper_thread_summaries_v1(1)");
    expect(first.rows).toHaveLength(2); // one row plus look-ahead
    const second = await db.query<Summary>("select * from public.whisper_thread_summaries_v1(1,'2026-11-07T12:00:00.123456Z',$1)", [id(204)]);
    expect(second.rows.map(r => r.last_message_id)).toEqual([id(130), id(200)]);
  });
  it("subtracts hidden messages before latest selection and unread totals; NULL hidden entries cannot erase a page", async () => {
    const { rows } = await db.query<Summary>("select * from public.whisper_thread_summaries_v1(50,null,null,$1::uuid[])", [[id(130), null]]);
    const direct = rows.find(r => r.peer_id === peer && r.conversation_kind === 'direct')!;
    expect(direct.last_message_id).toBe(id(129));
    expect(Number(direct.unread_count)).toBe(129);
  });
  it("keeps participant and restrictive policies in force for another signed-in account", async () => {
    try {
      await db.exec(`select set_config('request.jwt.claim.sub','${stranger}',false);`);
      const { rows } = await db.query<Summary>("select * from public.whisper_thread_summaries_v1()");
      expect(rows).toHaveLength(1);
      expect(rows[0].last_message_id).toBe(id(201));
    } finally { await db.exec(`select set_config('request.jwt.claim.sub','${owner}',false);`); }
  });
  it("denies anonymous execution and remains security invoker", async () => {
    const flags = await db.query<{ prosecdef: boolean; allowed: boolean }>(`select prosecdef, has_function_privilege('anon',oid,'EXECUTE') as allowed from pg_proc where proname='whisper_thread_summaries_v1'`);
    expect(flags.rows).toEqual([{ prosecdef: false, allowed: false }]);
    await db.exec('set role anon');
    try { await expect(db.query('select * from public.whisper_thread_summaries_v1()')).rejects.toThrow('permission denied'); }
    finally { await db.exec('set role authenticated'); }
  });
});
