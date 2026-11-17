// @vitest-environment node
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';
import { beforeAll,afterAll,it,expect } from 'vitest';
const owner='10000000-0000-4000-8000-000000000001',editor='10000000-0000-4000-8000-000000000002',viewer='10000000-0000-4000-8000-000000000003',stranger='10000000-0000-4000-8000-000000000004';
const doc='20000000-0000-4000-8000-000000000001';
let db:PGlite;
async function asUser(id:string):Promise<void>{await db.exec(`set role postgres;select set_config('request.jwt.claim.sub','${id}',false);set role authenticated;`);}
async function call(action:string,payload:Record<string,unknown>={},id=doc):Promise<any>{const result=await db.query<{value:unknown}>('select public.whisper_notes_action($1::uuid,$2,$3::jsonb) as value',[id,action,JSON.stringify(payload)]);return result.rows[0].value;}
beforeAll(async()=>{
 db=new PGlite();await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;grant usage on schema auth to authenticated;create table public.whisper_profiles(user_id uuid,username text);create table public.whisper_blocks(blocker_id uuid,blocked_user_id uuid);`);
 for(const [id,name] of [[owner,'owner'],[editor,'editor'],[viewer,'viewer'],[stranger,'stranger']]){await db.query('insert into auth.users values($1,$2,now())',[id,name+'@example.invalid']);await db.query('insert into whisper_profiles values($1,$2)',[id,name]);}
 await db.exec(readFileSync('../supabase/notes-collaboration.sql','utf8'));await db.exec(readFileSync('../supabase/notes-suggestions.sql','utf8'));await asUser(owner);
 await call('create',{title:'Private source copied deliberately',content:{type:'doc',content:[{type:'paragraph'}]}});
},30000);
afterAll(async()=>{await db?.close();});
it('authorizes Jasper checks for every active reading role but not pending, revoked or blocked readers',async()=>{
 const id=crypto.randomUUID(),invitation=crypto.randomUUID();
 await asUser(owner);await call('create',{title:'Jasper access',content:{type:'doc',content:[{type:'paragraph'}]}},id);
 expect(await call('versions',{},id)).toEqual([]);
 await call('invite',{id:invitation,username:'viewer',role:'viewer'},id);
 await asUser(viewer);await expect(call('versions',{},id)).rejects.toThrow('document_access_denied');await call('accept',{id:invitation},id);
 for(const role of ['viewer','commenter','editor']){await asUser(owner);await call('permission',{id:invitation,role},id);await asUser(viewer);expect(await call('versions',{},id)).toEqual([]);}
 await db.exec('set role postgres');await db.query('insert into whisper_blocks values($1,$2)',[viewer,owner]);await asUser(viewer);await expect(call('versions',{},id)).rejects.toThrow('document_access_denied');await db.exec('set role postgres;delete from whisper_blocks');
 await asUser(owner);await call('permission',{id:invitation,role:'revoked'},id);await asUser(viewer);await expect(call('versions',{},id)).rejects.toThrow('document_access_denied');
 await asUser(stranger);await expect(call('versions',{},id)).rejects.toThrow('document_access_denied');
});
it('denies direct table access and access from uninvited accounts',async()=>{await asUser(stranger);await expect(call('read')).rejects.toThrow('document_access_denied');await expect(db.query('select * from whisper_shared_documents')).rejects.toThrow('permission denied');});
it('requires invitation acceptance and enforces read-only role',async()=>{
 await asUser(owner);const id=crypto.randomUUID();await call('invite',{id,username:'viewer',role:'viewer'});
 await asUser(viewer);await expect(call('read')).rejects.toThrow('document_access_denied');await call('accept',{id});expect((await call('read')).role).toBe('viewer');
 await expect(call('update',{operation:crypto.randomUUID(),update:'AA=='})).rejects.toThrow('document_access_denied');await expect(call('invite',{id:crypto.randomUUID(),username:'stranger',role:'editor'})).rejects.toThrow('document_access_denied');await expect(call('comment',{id:crypto.randomUUID(),body:'Denied'})).rejects.toThrow('document_access_denied');
});
it('merges independent update operations into an ordered log and retries idempotently',async()=>{
 await asUser(owner);const id=crypto.randomUUID();await call('invite',{id,username:'editor',role:'editor'});await asUser(editor);await call('accept',{id});
 const op=crypto.randomUUID();expect((await call('update',{operation:op,update:'AA=='})).seq).toBe(1);expect((await call('update',{operation:op,update:'AA=='})).seq).toBe(1);
 await asUser(owner);expect((await call('update',{operation:crypto.randomUUID(),update:'AQ=='})).seq).toBe(2);
 await asUser(editor);expect((await call('read')).updates).toHaveLength(2);
});
it('keeps comments permission-bound and rejects cross-document parents',async()=>{
 await asUser(editor);const id=crypto.randomUUID();await call('comment',{id,body:'Review this passage',quote:'A quote'});await call('comment',{id,body:'Retry'});expect((await call('comments'))).toHaveLength(1);
 await expect(call('comment',{id:crypto.randomUUID(),parent:crypto.randomUUID(),body:'Wrong parent'})).rejects.toThrow('invalid_comment');
 await call('resolve',{id,resolved:true});expect((await call('comments'))[0].resolved).toBe(true);
});
it('version checkpoints reject stale heads and retain author attribution',async()=>{
 await asUser(editor);await expect(call('version',{id:crypto.randomUUID(),label:'Stale',expected:0,content:{type:'doc'}})).rejects.toThrow('document_changed');
 const id=crypto.randomUUID();await call('version',{id,label:'Reviewed',expected:2,content:{type:'doc',content:[{type:'paragraph'}]}});expect((await call('versions'))[0].name).toBe('editor');expect((await call('version_read',{id})).label).toBe('Reviewed');
});
it('suggestions cannot be accepted by commenters or viewers and stale acceptance is refused',async()=>{
 const invoke=(action:string,payload:unknown)=>db.query('select whisper_notes_suggestions($1::uuid,$2,$3::jsonb)',[doc,action,JSON.stringify(payload)]);
 await asUser(viewer);await expect(invoke('create',{id:crypto.randomUUID(),quote:'A',replacement:'B',anchor:{from:'x',to:'y'}})).rejects.toThrow('document_access_denied');
 await asUser(editor);const id=crypto.randomUUID();await invoke('create',{id,quote:'A',replacement:'B',anchor:{from:'x',to:'y'}});
 await expect(invoke('accept',{id,operation:crypto.randomUUID(),expected:0,update:'AA=='})).rejects.toThrow('document_changed');
 await asUser(viewer);await expect(invoke('reject',{id})).rejects.toThrow('document_access_denied');
 await asUser(owner);await invoke('reject',{id,operation:crypto.randomUUID()});
});
it('revocation blocks both pending update retries and future reads',async()=>{
 await asUser(owner);const members=await call('members');const invite=members.find((m:any)=>m.user_id===editor);await call('permission',{id:invite.id,role:'revoked'});
 await asUser(editor);await expect(call('read')).rejects.toThrow('document_access_denied');await expect(call('update',{operation:crypto.randomUUID(),update:'AA=='})).rejects.toThrow('document_access_denied');await expect(call('accept',{id:invite.id})).rejects.toThrow('document_access_denied');
});
it('email acceptance is bound to a confirmed email in auth, never supplied claims',async()=>{
 await asUser(owner);const id=crypto.randomUUID();await call('invite',{id,email:'stranger@example.invalid',role:'commenter'});
 await asUser(viewer);await expect(call('accept',{id})).rejects.toThrow('document_access_denied');
 await asUser(stranger);await call('accept',{id});expect((await call('read')).role).toBe('commenter');await expect(call('update',{operation:crypto.randomUUID(),update:'AA=='})).rejects.toThrow('document_access_denied');
});
