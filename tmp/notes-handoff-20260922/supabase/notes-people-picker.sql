-- Additive, account-bound identity lookup for the Notes invitation picker.
-- Only already-public display fields are returned; no account email or contact data.
create or replace function public.whisper_notes_people(p_query text default '', p_ids uuid[] default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); term text:=lower(ltrim(btrim(coalesce(p_query,'')),'@'));
begin
 if uid is null then raise exception 'sign_in_required' using errcode='42501'; end if;
 if length(term)>80 or coalesce(cardinality(p_ids),0)>200 then raise exception 'invalid_query'; end if;
 return coalesce((select jsonb_agg(x) from (
  select p.user_id, p.username, coalesce(nullif(p.display_name,''),p.username) as name, p.profile_image_url as photo
  from public.whisper_profiles p
  where p.user_id<>uid and p.username ~ '^[A-Za-z0-9_.]{1,40}$'
    and not exists(select 1 from public.whisper_blocks b where (b.blocker_id=uid and b.blocked_user_id=p.user_id) or (b.blocker_id=p.user_id and b.blocked_user_id=uid))
    and ((term='' and p.user_id=any(coalesce(p_ids,'{}'::uuid[]))) or (length(term)>=2 and (strpos(lower(p.username),term)>0 or strpos(lower(coalesce(p.display_name,'')),term)>0)))
  order by (lower(p.username)=term) desc,lower(coalesce(nullif(p.display_name,''),p.username)),p.user_id
  limit case when term='' then 200 else 30 end
 ) x),'[]'::jsonb);
end $$;
revoke all on function public.whisper_notes_people(text,uuid[]) from public,anon;
grant execute on function public.whisper_notes_people(text,uuid[]) to authenticated;

-- Stable account identity is authoritative even if a username changes after selection.
-- Existing owner, role, block and invitation limits remain authoritative in notes_action.
create or replace function public.whisper_notes_invite_person(p_doc uuid,p_invitation uuid,p_user uuid,p_role text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); handle text; existing public.whisper_document_members; result jsonb;
begin
 if uid is null then raise exception 'sign_in_required' using errcode='42501'; end if;
 perform 1 from public.whisper_shared_documents where id=p_doc and owner_id=uid and not deleted for update;
 if not found then raise exception 'document_access_denied' using errcode='42501'; end if;
 if p_user is null or p_user=uid or p_invitation is null or p_role is null or p_role not in ('viewer','commenter','editor') then raise exception 'person_unavailable'; end if;
 if exists(select 1 from public.whisper_blocks where (blocker_id=uid and blocked_user_id=p_user) or (blocker_id=p_user and blocked_user_id=uid)) then raise exception 'person_unavailable'; end if;
 select * into existing from public.whisper_document_members where id=p_invitation;
 if found then
  if existing.document_id<>p_doc or existing.user_id is distinct from p_user or existing.role<>p_role or existing.status<>'pending' then raise exception 'invitation_unavailable'; end if;
  return jsonb_build_object('id',existing.id,'status',existing.status);
 end if;
 select username into handle from public.whisper_profiles where user_id=p_user for share;
 if handle is null then raise exception 'person_unavailable'; end if;
 result:=public.whisper_notes_action(p_doc,'invite',jsonb_build_object('id',p_invitation,'username',handle,'role',p_role));
 if not exists(select 1 from public.whisper_document_members where id=p_invitation and document_id=p_doc and user_id=p_user) then raise exception 'person_unavailable'; end if;
 return result;
end $$;
revoke all on function public.whisper_notes_invite_person(uuid,uuid,uuid,text) from public,anon;
grant execute on function public.whisper_notes_invite_person(uuid,uuid,uuid,text) to authenticated;
