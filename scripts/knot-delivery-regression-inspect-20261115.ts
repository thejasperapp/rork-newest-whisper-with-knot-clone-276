// Owner-authorized diagnosis: admin link generation and verification CREATE
// auth sessions whose credentials stay in memory; this is not wholly read-only.
// Subsequent managed calls only read account-owned conversations and Events.
// No historical execution/capture, refresh, password changes, email sending,
// data migration, persisted credentials, or credential output.
const base = 'https://uryyyegnbtlmyhqlgndy.supabase.co';
const backend = 'https://newest-whisper-with-knot-clone-t6ui3ur-backend.rork.app';
const key = process.env.KNOT_ACCEPTANCE_SUPABASE_SERVICE_ROLE_KEY;
if (!key) throw new Error('authorized_admin_credential_unavailable');
async function auth(path: string, body?: unknown) {
 const r = await fetch(base + path, {method: body ? 'POST':'GET', headers:{apikey:key!,Authorization:'Bearer '+key,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});
 if (!r.ok) throw new Error('auth_http_'+r.status); return r.json();
}
for (const id of ['d49f632a-2c64-4d1e-a672-287b147e8aec','71b598c5-b235-46e4-90ba-9ae0e4ee9280']) {
 const user = await auth('/auth/v1/admin/users/'+id);
 console.log(JSON.stringify({accountID:id,exists:user.id===id,synthetic:user.user_metadata?.dedicated_knot_acceptance===true,createdAt:user.created_at,hasEmail:!!user.email}));
 if (user.id!==id || !user.email) continue;
 const link = await auth('/auth/v1/admin/generate_link',{type:'magiclink',email:user.email});
 const session = await auth('/auth/v1/verify',{type:'email',token_hash:link.hashed_token});
 if(session.user?.id!==id) throw new Error('account_identity_mismatch');
 async function api(path:string,body?:unknown) {
  const r=await fetch(backend+path,{method:body?'POST':'GET',headers:{'X-Whisper-Authorization':'Bearer '+session.access_token,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});
  if(!r.ok) throw new Error('managed_http_'+r.status); return r.json();
 }
 const chats=await api('/knot/conversations');
 console.log(JSON.stringify({accountID:id,chats:chats.conversations?.map((c:any)=>({id:c.id,bot:c.botID,updatedAt:c.updatedAt,deleted:c.deleted}))}));
 for(const chat of (chats.conversations??[]).filter((c:any)=>!c.deleted&&c.botID==='main').sort((a:any,b:any)=>b.updatedAt-a.updatedAt).slice(0,3)) {
  const ev=await api('/knot/shell/events',{bot:'main',conversationID:chat.id});
  for (const r of (ev.records??[]).filter((r:any)=>r.state==='uncertain')) {
   const detail=await api('/knot/shell/events',{bot:'main',conversationID:chat.id,proposalID:r.spec.id});
   console.log(JSON.stringify({accountID:id,proposalID:r.spec.id,uncertainEvents:(detail.events??[]).map((e:any)=>({kind:e.kind,recordedAt:e.recordedAt,sessionID:e.sessionID,attached:e.attached,reason:e.reason}))}));
  }
  console.log(JSON.stringify({accountID:id,conversationID:chat.id,records:(ev.records??[]).filter((r:any)=>r.state!=='finished').slice(0,8),events:(ev.events??[]).slice(0,8),failures:(ev.activities??[]).filter((a:any)=>/unavailable|rejected|degraded|expired|cancelled/.test(a.kind)).slice(0,12).map((a:any)=>({taskID:a.taskID,kind:a.kind,detail:a.detail})),documents:(ev.documents??[]).map((d:any)=>({id:d.id,format:d.format,createdAt:d.createdAt,sourceMessageID:d.sourceMessageID}))}));
 }
}
