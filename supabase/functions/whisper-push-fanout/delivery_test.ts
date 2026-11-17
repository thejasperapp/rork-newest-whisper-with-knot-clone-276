import { strict as assert } from "node:assert";

// All requests, including APNs, are intercepted. No production credentials or network writes.
const owner = "10000000-0000-4000-8000-000000000001";
const actor = "20000000-0000-4000-8000-000000000001";
const id = "30000000-0000-4000-8000-000000000001";
const parentID = "40000000-0000-4000-8000-000000000001";
const third = "50000000-0000-4000-8000-000000000001";
const key = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", key.privateKey));
Deno.env.set("SUPABASE_URL", "https://push.test");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "fixture-runtime-api-key");
Deno.env.set("WHISPER_PUSH_WEBHOOK_KEY", "fixture-server-key");
Deno.env.set("APNS_TEAM_ID", "FIXTURE");
Deno.env.set("APNS_KEY_ID", "FIXTURE");
Deno.env.set("APNS_BUNDLE_ID", "test.whisper");
Deno.env.set("APNS_PRIVATE_KEY", `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----`);
const originalFetch = globalThis.fetch;
let tables: Record<string, Record<string, any>[]>;
let pushes: Record<string, any>[];
let receipts: Set<string>;
let requestCount: number;
let failTable: string;
let apnsStatus: number;
let tokenUpdates: number;
let teamsAllowed: boolean;
let storyTag: { tagged: boolean; allowed?: boolean };
let returnAudience: unknown;

function reset() {
  pushes = []; receipts = new Set(); requestCount = 0; failTable = ""; apnsStatus = 200; tokenUpdates = 0; teamsAllowed = false;
  Deno.env.set("WHISPER_STORY_TAGS_ENABLED", "true"); storyTag = { tagged: false };
  Deno.env.set("WHISPER_RETURN_POSTS_ENABLED", "true"); returnAudience = [];
  tables = {
    whisper_profiles: [{ user_id: owner, username: "owner", is_private: false }, { user_id: actor, username: "sender", is_private: false }],
    whisper_device_tokens: [{ user_id: owner, token: "fixture-token", active: true, sandbox: true, bundle_id: "test.whisper" }],
    whisper_posts: [{ id, user_id: owner, is_ghost: false, community_id: "workouts" }],
    whisper_stories: [{ id, user_id: owner, expires_at: new Date(Date.now() + 3600000).toISOString(), is_ghost: false }],
  };
}

function installFetch() {
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    requestCount++;
    const url = new URL(input instanceof Request ? input.url : String(input));
    if (url.hostname.includes("push.apple.com")) {
      pushes.push(JSON.parse(String(init?.body)));
      return apnsStatus === 200 ? new Response("") : Response.json({ reason: "BadTopic" }, { status: apnsStatus });
    }
    assert.equal(url.hostname, "push.test", "test must never access production");
    if (url.pathname.startsWith("/storage/v1/object/sign/whisper-group-avatars/")) return Response.json({ signedURL: `${url.pathname}?token=fixture-signed` });
    const table = url.pathname.split("/").at(-1)!;
    if (table === failTable) return Response.json({ code: "XX000", message: "fixture failure" }, { status: 500 });
    if (table === "whisper_social_teams_push_allowed") return Response.json(teamsAllowed);
    if (table === "whisper_story_tag_push") return Response.json(storyTag);
    if (table === "whisper_return_post_candidates") return Response.json(returnAudience);
    if (table === "whisper_push_receipts" || table === "whisper_social_teams_push_claims") {
      if (init?.method === "DELETE") { receipts.delete(url.searchParams.get("event_key")!.slice(3)); return new Response(null, { status: 204 }); }
      const receipt = JSON.parse(String(init?.body)).event_key;
      if (receipts.has(receipt)) return Response.json({ code: "23505" }, { status: 409 });
      receipts.add(receipt); return new Response(null, { status: 201 });
    }
    if (table === "whisper_device_tokens" && init?.method === "PATCH") { tokenUpdates++; return new Response(null, { status: 204 }); }
    let rows = tables[table] ?? [];
    rows = rows.filter(row => [...url.searchParams].every(([field, value]) => {
      if (value.startsWith("eq.")) return String(row[field]) === value.slice(3);
      return true;
    }));
    return Response.json(rows);
  }) as typeof fetch;
}

// supabase-js captures fetch when its client is constructed, so install the boundary before import.
installFetch();
const { handleRequest } = await import("./index.ts");

async function dispatch(table: string, record: Record<string, any>, authorization = "Bearer fixture-server-key") {
  tables[table] = [...(tables[table] ?? []), record];
  const response = await handleRequest(new Request("https://sender.test", { method: "POST", headers: { authorization },
    body: JSON.stringify({ type: "INSERT", schema: "public", table, record }) }));
  if (!failTable && apnsStatus === 200 && authorization === "Bearer fixture-server-key") assert.equal(response.status, 200);
  return response;
}
const fresh = () => ({ id, created_at: new Date().toISOString() });

Deno.test("real push handler with isolated database and APNs boundaries", async t => {
  installFetch();
  try {
    await t.step("anon requests stop before database access", async () => {
      reset(); const response = await dispatch("whisper_messages", fresh(), "Bearer fixture-anon");
      assert.equal(response.status, 401); assert.equal(requestCount, 0);
    });
    await t.step("follow uses deployed columns, recipient identity, and per-device dedupe", async () => {
      reset(); const row = { follower_id: actor, followee_id: owner, created_at: new Date().toISOString() };
      assert.equal((await dispatch("whisper_follows", row)).status, 200);
      assert.equal(pushes.length, 1); assert.equal(pushes[0].data.recipient_user_id, owner);
      // Do not insert a second fixture row; replay the same database webhook.
      const response = await handleRequest(new Request("https://sender.test", { method: "POST", headers: { authorization: "Bearer fixture-server-key" }, body: JSON.stringify({ type: "INSERT", schema: "public", table: "whisper_follows", record: row }) }));
      assert.equal(response.status, 200); assert.equal(pushes.length, 1);
    });
    await t.step("likes in built-in communities work without a nonexistent username column", async () => {
      reset(); await dispatch("whisper_post_likes", { post_id: id, user_id: actor, created_at: new Date().toISOString() });
      assert.equal(pushes.length, 1); assert.equal(pushes[0].data.post_id, id);
    });
    await t.step("private community membership is enforced even for a catalog slug", async () => {
      reset(); tables.whisper_communities = [{ slug: "workouts", visibility: "private", creator_id: third }];
      await dispatch("whisper_post_likes", { post_id: id, user_id: actor, created_at: new Date().toISOString() });
      assert.equal(pushes.length, 0);
    });
    await t.step("block and preference errors fail closed", async () => {
      for (const table of ["whisper_blocks", "whisper_notification_prefs"]) {
        reset(); failTable = table;
        const response = await dispatch("whisper_follows", { follower_id: actor, followee_id: owner, created_at: new Date().toISOString() });
        assert.equal(response.status, 503); assert.equal(pushes.length, 0);
      }
    });
    await t.step("quiet mode prevents background delivery", async () => {
      reset(); tables.whisper_notification_prefs = [{ user_id: owner, quiet_mode: true }];
      await dispatch("whisper_follows", { follower_id: actor, followee_id: owner, created_at: new Date().toISOString() });
      assert.equal(pushes.length, 0);
    });
    await t.step("comment replies reach both distinct owners with highlight identity", async () => {
      reset(); tables.whisper_post_comments = [{ id: parentID, user_id: third, post_id: id }];
      tables.whisper_device_tokens.push({ user_id: third, token: "fixture-third", active: true });
      await dispatch("whisper_post_comments", { ...fresh(), post_id: id, user_id: actor, body: "reply", parent_comment_id: parentID });
      assert.equal(pushes.length, 2); assert.deepEqual(new Set(pushes.map(p => p.data.recipient_user_id)), new Set([owner, third]));
      assert(pushes.every(p => p.data.comment_id === id));
    });
    await t.step("Story likes are correctly labeled while reaction Activity records are silent", async () => {
      reset(); await dispatch("whisper_story_responses", { ...fresh(), story_id: id, story_owner_id: owner, responder_id: actor, kind: "like", response: "liked" });
      assert.equal(pushes.length, 1); assert.match(pushes[0].aps.alert.title, /liked your story/); assert.equal(pushes[0].data.response_id, id);
      reset(); await dispatch("whisper_story_responses", { ...fresh(), story_id: id, story_owner_id: owner, responder_id: actor, kind: "reaction", response: "reaction" });
      assert.equal(pushes.length, 0);
    });
    await t.step("read messages, removed group members and stale events do not alert", async () => {
      reset(); await dispatch("whisper_messages", { ...fresh(), from_user_id: actor, to_user_id: owner, body: "hello", read_at: new Date().toISOString() });
      assert.equal(pushes.length, 0);
      reset(); await dispatch("whisper_messages", { ...fresh(), from_user_id: actor, to_user_id: owner, body: `::wg-v1::${parentID}::Spoofed name::hello` });
      assert.equal(pushes.length, 0);
      reset(); await dispatch("whisper_follows", { follower_id: actor, followee_id: owner, created_at: "2020-01-01T00:00:00Z" });
      assert.equal(pushes.length, 0);
    });
    await t.step("group artwork comes from the current authorized registry, never the message body", async () => {
      reset(); tables.whisper_group_threads = [{ id: parentID, owner_id: actor, member_ids: [owner], name: "Real group", avatar_path: `${parentID}/${id}.jpg` }];
      await dispatch("whisper_messages", { ...fresh(), from_user_id: actor, to_user_id: owner, body: `::wg-v1::${parentID}::Spoofed name::hello` });
      assert.equal(pushes.length, 1); assert.equal(pushes[0].aps.alert.title, "Real group");
      assert.equal(pushes[0].data.group_name, "Real group");
      assert.match(pushes[0].data.group_avatar_url, /whisper-group-avatars/);
      reset(); tables.whisper_group_threads = [{ id: parentID, owner_id: actor, member_ids: [owner], name: "Real group", avatar_path: `${third}/${id}.jpg` }];
      await dispatch("whisper_messages", { ...fresh(), from_user_id: actor, to_user_id: owner, body: `::wg-v1::${parentID}::Spoofed name::hello` });
      assert.equal(pushes[0].data.group_avatar_url, undefined);
    });
    await t.step("Story tags alert only after server admission and both mention/DM preferences", async () => {
      const row = { ...fresh(), from_user_id: actor, to_user_id: owner, thread_id: parentID, body: `::whisper-storytag-v1::${parentID}` };
      reset(); storyTag = { tagged:true, allowed:true }; await dispatch("whisper_messages", row);
      assert.equal(pushes.length,1); assert.match(pushes[0].aps.alert.body,/Tagged you in a story/); assert.equal(pushes[0].data.message_id,id);
      for(const prefs of [{mentions:false},{dms:false},{quiet_mode:true}]) {
        reset(); storyTag={tagged:true,allowed:true}; tables.whisper_notification_prefs=[{user_id:owner,...prefs}];
        await dispatch("whisper_messages",row);assert.equal(pushes.length,0);
      }
      for(const admission of [{tagged:false},{tagged:true,allowed:false}]) {
        reset();storyTag=admission;await dispatch("whisper_messages",row);assert.equal(pushes.length,0);
      }
      reset();storyTag={tagged:true,allowed:true};failTable="whisper_story_tag_push";
      assert.equal((await dispatch("whisper_messages",row)).status,503);assert.equal(pushes.length,0);
    });
    await t.step("return-post delivery is gated, preference-controlled, recipient-bound and deduplicated", async () => {
      const row = {...fresh(),user_id:actor,is_ghost:false,community_id:null};
      const setup=()=>{reset();tables.whisper_posts=[];returnAudience=[owner];tables.whisper_notification_prefs=[{user_id:owner,new_posts:true,new_posts_synced:true}];tables.whisper_follows=[{follower_id:owner,followee_id:actor}];};
      setup();await dispatch("whisper_posts",row);assert.equal(pushes.length,1);assert.equal(pushes[0].data.postID,id);assert.equal(pushes[0].data.recipient_user_id,owner);
      const replay=()=>handleRequest(new Request("https://sender.test",{method:"POST",headers:{authorization:"Bearer fixture-server-key"},body:JSON.stringify({type:"INSERT",schema:"public",table:"whisper_posts",record:row})}));
      await replay();assert.equal(pushes.length,1);
      for(const patch of [{new_posts:false},{new_posts_synced:false},{quiet_mode:true},{master_enabled:false}]){setup();Object.assign(tables.whisper_notification_prefs[0],patch);await dispatch("whisper_posts",row);assert.equal(pushes.length,0);}
      setup();tables.whisper_follows=[];await dispatch("whisper_posts",row);assert.equal(pushes.length,0);
      setup();Deno.env.set("WHISPER_RETURN_POSTS_ENABLED","false");await dispatch("whisper_posts",row);assert.equal(pushes.length,0);
      setup();failTable="whisper_return_post_candidates";assert.equal((await dispatch("whisper_posts",row)).status,503);assert.equal(pushes.length,0);
      setup();apnsStatus=400;assert.equal((await dispatch("whisper_posts",row)).status,503);apnsStatus=200;await replay();assert.equal(pushes.length,1);
    });
    await t.step("Teams uses an authorized generic alert and ordinary recipient-bound DM routing", async () => {
      reset(); teamsAllowed = true;
      const row = { ...fresh(), thread_id: parentID, from_user_id: actor, to_user_id: owner, body: `::whisper-teams-v1::${id}` };
      await dispatch("whisper_messages", row);
      assert.equal(pushes.length, 1); assert.equal(pushes[0].aps.alert.title, "Whisper");
      assert.equal(pushes[0].aps.alert.body, "You have a team invitation. Open Whisper to review it.");
      assert.deepEqual(pushes[0].data, {kind:"dm",social_teams:"v1",recipient_user_id:owner,message_id:id,thread_id:parentID,from_user_id:actor});
      const replay = new Request("https://sender.test", {method:"POST",headers:{authorization:"Bearer fixture-server-key"},body:JSON.stringify({type:"INSERT",schema:"public",table:"whisper_messages",record:row})});
      assert.equal((await handleRequest(replay)).status,200); assert.equal(pushes.length,1);
    });
    await t.step("Teams authority denial, lookup failure, forged binding and DM opt-out are silent", async () => {
      const row = { ...fresh(), thread_id:parentID,from_user_id:actor,to_user_id:owner,body:`::whisper-teams-v1::${id}` };
      reset(); await dispatch("whisper_messages",row); assert.equal(pushes.length,0);
      reset(); failTable="whisper_social_teams_push_allowed"; assert.equal((await dispatch("whisper_messages",row)).status,503); assert.equal(pushes.length,0);
      reset(); teamsAllowed=true; await dispatch("whisper_messages",{...row,body:`::whisper-teams-v1::${third}`}); assert.equal(pushes.length,0);
      reset(); teamsAllowed=true; tables.whisper_notification_prefs=[{user_id:owner,dms:false}]; await dispatch("whisper_messages",row); assert.equal(pushes.length,0);
    });
    await t.step("Teams ambiguous APNs attempts retain their claim instead of duplicating alerts", async () => {
      reset(); teamsAllowed=true; apnsStatus=400;
      const row={...fresh(),thread_id:parentID,from_user_id:actor,to_user_id:owner,body:`::whisper-teams-v1::${id}`};
      assert.equal((await dispatch("whisper_messages",row)).status,503); assert.equal(receipts.size,1);
      apnsStatus=200;
      const replay=new Request("https://sender.test",{method:"POST",headers:{authorization:"Bearer fixture-server-key"},body:JSON.stringify({type:"INSERT",schema:"public",table:"whisper_messages",record:row})});
      await handleRequest(replay); assert.equal(pushes.length,1); assert.equal(tokenUpdates,0);
    });
    await t.step("APNs configuration failures preserve tokens and release failed-device receipt", async () => {
      reset(); apnsStatus = 400;
      const response = await dispatch("whisper_follows", { follower_id: actor, followee_id: owner, created_at: new Date().toISOString() });
      assert.equal(response.status, 503); assert.equal(tokenUpdates, 0); assert.equal(receipts.size, 0);
    });
  } finally { globalThis.fetch = originalFetch; }
});
