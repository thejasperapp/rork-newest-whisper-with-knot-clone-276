create or replace function public.whisper_can_contact(p_sender uuid,p_recipient uuid) returns boolean language sql stable security definer set search_path='' as $$
select p_sender is not null and p_recipient is not null and (auth.uid() in (p_sender,p_recipient) or auth.role()='service_role')
and not exists(select 1 from public.whisper_blocks b where (b.blocker_id=p_sender and b.blocked_user_id=p_recipient) or (b.blocker_id=p_recipient and b.blocked_user_id=p_sender))
and not exists(select 1 from public.whisper_dm_blocks b where (b.protected_user_id=p_sender and b.blocked_sender_id=p_recipient) or (b.protected_user_id=p_recipient and b.blocked_sender_id=p_sender))
and not exists(select 1 from public.whisper_contact_restrictions r where r.user_id=p_sender and r.revoked_at is null and r.expires_at>now())
and (exists(select 1 from public.whisper_contact_permissions c where c.recipient_id=p_recipient and c.sender_id=p_sender and c.allowed) or (coalesce((select age_band from public.profiles where id=p_sender),'unknown') in ('adult','teen') and coalesce((select age_band from public.profiles where id=p_recipient),'unknown') in ('adult','teen') and not ((select age_band from public.profiles where id=p_recipient)='teen' and (select age_band from public.profiles where id=p_sender)='adult'))); $$;
create or replace function public.whisper_guard_identity_flags() returns trigger language plpgsql security definer set search_path='' as $$
declare key text; prior jsonb; incoming jsonb:=to_jsonb(new);
begin
if auth.role()='service_role' or auth.uid() is null then return new; end if;
if tg_op='UPDATE' then prior:=to_jsonb(old); else prior:='{}'::jsonb; end if;
-- Preserve the established native fitness subscription sync (is_pro_user).
-- It does not authorize Whisper moderation, identity, or professional roles.
foreach key in array array['is_owner','is_admin','is_moderator','is_verified','is_coach','is_athlete','is_recruiter','is_director','is_blogger','is_one','is_plus','is_trusted_member','helpful_report_count','is_liar','liar_reason'] loop
if incoming ? key and (incoming->key) is distinct from (prior->key) then
if tg_op='INSERT' and (incoming->key='false'::jsonb or incoming->key='null'::jsonb or incoming->key='0'::jsonb) then continue; end if;
raise exception 'Identity and entitlement fields are managed by Whisper';
end if;
end loop;
return new;
end $$;
