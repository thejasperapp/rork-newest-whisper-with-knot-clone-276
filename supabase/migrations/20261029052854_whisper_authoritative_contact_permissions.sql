begin;
create table if not exists public.whisper_contact_permissions(recipient_id uuid not null references auth.users(id),sender_id uuid not null references auth.users(id),allowed boolean not null default false,updated_at timestamptz not null default now(),primary key(recipient_id,sender_id),check(recipient_id<>sender_id));
alter table public.whisper_contact_permissions enable row level security;
create policy whisper_contact_own_read on public.whisper_contact_permissions for select to authenticated using(recipient_id=auth.uid());
create policy whisper_contact_own_write on public.whisper_contact_permissions for insert to authenticated with check(recipient_id=auth.uid());
create policy whisper_contact_own_update on public.whisper_contact_permissions for update to authenticated using(recipient_id=auth.uid()) with check(recipient_id=auth.uid());
grant select,insert,update on public.whisper_contact_permissions to authenticated;
create table if not exists public.whisper_contact_restrictions(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),reason text not null,review_at timestamptz not null,expires_at timestamptz not null,revoked_at timestamptz,reviewed_by uuid not null references auth.users(id),created_at timestamptz not null default now(),check(length(trim(reason))>0),check(expires_at>created_at));
alter table public.whisper_contact_restrictions enable row level security;
create policy whisper_restriction_read on public.whisper_contact_restrictions for select to authenticated using(user_id=auth.uid() or public.whisper_is_reviewer());
grant select on public.whisper_contact_restrictions to authenticated;
create or replace function public.whisper_can_contact(p_sender uuid,p_recipient uuid) returns boolean language sql stable security definer set search_path='' as $$
 select p_sender is not null and p_recipient is not null and (auth.uid() in (p_sender,p_recipient) or auth.role()='service_role')
 and not exists(select 1 from public.whisper_blocks b where (b.blocker_id=p_sender and b.blocked_user_id=p_recipient) or (b.blocker_id=p_recipient and b.blocked_user_id=p_sender))
 and not exists(select 1 from public.whisper_contact_restrictions r where r.user_id=p_sender and r.revoked_at is null and r.expires_at>now())
 and (
  exists(select 1 from public.whisper_contact_permissions c where c.recipient_id=p_recipient and c.sender_id=p_sender and c.allowed)
  or (
   coalesce((select age_band from public.profiles where id=p_sender),'unknown') in ('adult','teen')
   and coalesce((select age_band from public.profiles where id=p_recipient),'unknown') in ('adult','teen')
   and not ((select age_band from public.profiles where id=p_recipient)='teen' and (select age_band from public.profiles where id=p_sender)='adult')
  )
 ); $$;
revoke all on function public.whisper_can_contact(uuid,uuid) from public;
grant execute on function public.whisper_can_contact(uuid,uuid) to authenticated,service_role;
create policy whisper_contact_send_guard_v2 on public.whisper_messages as restrictive for insert to public with check(auth.uid()=from_user_id and public.whisper_can_contact(from_user_id,to_user_id));
create or replace function public.whisper_message_immutable_contact() returns trigger language plpgsql security definer set search_path='' as $$ begin
 if auth.role()='service_role' then return new; end if;
 if new.from_user_id is distinct from old.from_user_id or new.to_user_id is distinct from old.to_user_id or new.body is distinct from old.body or new.media_url is distinct from old.media_url or new.embed is distinct from old.embed or new.thread_id is distinct from old.thread_id or new.id is distinct from old.id then raise exception 'Message content and participants are immutable'; end if;
 return new; end $$;
create trigger whisper_message_immutable_contact_v2 before update on public.whisper_messages for each row execute function public.whisper_message_immutable_contact();
commit;
