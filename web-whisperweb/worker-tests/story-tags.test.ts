// @vitest-environment node
import { beforeAll, beforeEach, afterAll, it, expect } from "vitest";
import { PGlite } from "@electric-sql/pglite";
import { readFile } from "node:fs/promises";
const a="11111111-1111-4111-8111-111111111111",b="22222222-2222-4222-8222-222222222222",id="33333333-3333-4333-8333-333333333333";
let db:PGlite;
beforeAll(async()=>{
 db=new PGlite();
 await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;
 create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create function auth.role() returns text language sql as $$select current_setting('request.jwt.claim.role',true)$$;
 create table auth.users(id uuid primary key,deleted_at timestamptz,is_anonymous boolean default false,banned_until timestamptz);
 create table public.whisper_profiles(user_id uuid primary key,username text,ghost_enabled boolean default false,is_private boolean default false);
 create table public.whisper_blocks(blocker_id uuid,blocked_user_id uuid);create table public.whisper_dm_blocks(blocked_sender_id uuid,protected_user_id uuid);
 create table public.whisper_follows(follower_id uuid,followee_id uuid);create table public.whisper_notification_prefs(user_id uuid primary key,master_enabled boolean,quiet_mode boolean,dms boolean);
 create table public.whisper_messages(id uuid primary key,thread_id uuid not null,from_user_id uuid,to_user_id uuid,from_username text,to_username text,body text,created_at timestamptz default now(),read_at timestamptz,embed jsonb,media_url text);
 create table public.whisper_stories(id uuid primary key,user_id uuid,username text,image_url text,is_ghost boolean default false,caption text,metadata text,video_url text,music_url text,music_title text,music_artist text,music_artwork text,created_at timestamptz default now(),expires_at timestamptz default now()+interval '1 day');`);
 for(const name of ['20261001010000_social_teams_invitations.sql','20261001020000_story_tag_delivery.sql']) await db.exec(await readFile(new URL(`../../supabase/migrations/${name}`,import.meta.url),'utf8'));
},30000);
afterAll(async()=>{await db?.close();});
beforeEach(async()=>{await db.exec(`truncate whisper_story_social_private.tags,public.whisper_stories,public.whisper_messages,public.whisper_profiles,public.whisper_blocks,public.whisper_dm_blocks,public.whisper_follows,whisper_social_teams_private.privacy;
 insert into auth.users(id) values('${a}'),('${b}') on conflict do nothing;
 insert into public.whisper_profiles(user_id,username) values('${a}','alice'),('${b}','bob');
 update whisper_story_social_private.activation set enabled=true;
 select set_config('request.jwt.claim.role','authenticated',false),set_config('request.jwt.claim.sub','${a}',false);`);});
const metadata=JSON.stringify({stickers:[{kind:'mention',label:'@Bob'},{kind:'mention',label:'bob'},{kind:'mention',label:'alice'}]});
async function post(){await db.query('insert into public.whisper_stories(id,user_id,username,image_url,metadata) values($1,$2,$3,$4,$5) on conflict do nothing',[id,a,'alice','https://fixture.test/story.jpg',metadata]);}
async function count(){return (await db.query<{n:number}>('select count(*)::int as n from public.whisper_messages')).rows[0].n;}
it('deduplicates repeated stickers and retried publications into one ID-only DM',async()=>{await post();await post();expect(await count()).toBe(1);expect((await db.query<{body:string}>('select body from public.whisper_messages')).rows[0].body).toBe(`::whisper-storytag-v1::${id}`);});
it('does not notify or deliver when blocked in either direction',async()=>{for(const [x,y] of [[a,b],[b,a]]){await db.query('insert into whisper_blocks values($1,$2)',[x,y]);await post();expect(await count()).toBe(0);await db.exec('delete from whisper_stories;delete from whisper_blocks;');}});
it('private stories require an actual approved follow, not merely the tag',async()=>{await db.exec(`update whisper_profiles set is_private=true where user_id='${a}'`);await post();expect(await count()).toBe(0);});
it('server-owned receipt cannot be rebound, and deletion does not resurrect it',async()=>{await post();await expect(db.exec("update whisper_messages set body='modified'")).rejects.toThrow();await db.exec('delete from whisper_messages;delete from whisper_stories;');await post();expect(await count()).toBe(0);});
it('resolver fails closed on expiry and unauthenticated reads',async()=>{await post();await db.exec("select set_config('request.jwt.claim.sub','',false)");await expect(db.query('select whisper_story_card($1)',[id])).rejects.toThrow();await db.exec(`select set_config('request.jwt.claim.sub','${b}',false);update whisper_stories set expires_at=now()-interval '1 minute';`);await expect(db.query('select whisper_story_card($1)',[id])).rejects.toThrow();});
it('forged insert and conversion of ordinary messages into tags are refused',async()=>{const body=`::whisper-storytag-v1::${id}`;await expect(db.query('insert into whisper_messages(id,thread_id,from_user_id,to_user_id,body) values($1,$1,$2,$3,$4)',[id,a,b,body])).rejects.toThrow();await db.query('insert into whisper_messages(id,thread_id,from_user_id,to_user_id,body) values($1,$1,$2,$3,$4)',[id,a,b,'hello']);await expect(db.query('update whisper_messages set body=$1 where id=$2',[body,id])).rejects.toThrow();});
it('limits one author-recipient pair to five Story deliveries per day',async()=>{for(let i=0;i<7;i++)await db.query('insert into whisper_stories(id,user_id,username,image_url,metadata) values(gen_random_uuid(),$1,$2,$3,$4)',[a,'alice','https://fixture.test/story.jpg',metadata]);expect(await count()).toBe(5);});
it('ghost Stories do not deliver tags',async()=>{await db.query('insert into whisper_stories(id,user_id,username,is_ghost,metadata) values($1,$2,$3,true,$4)',[id,a,'alice',metadata]);expect(await count()).toBe(0);});
it('inactive rollout creates no deliveries',async()=>{await db.exec('update whisper_story_social_private.activation set enabled=false');await post();expect(await count()).toBe(0);});
