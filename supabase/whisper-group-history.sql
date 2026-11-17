-- Additive, read-only group history. Caller RLS remains authoritative.
-- Identity is sender + logical ID, legacy Meet event, or body + UTC ten-second bucket.
create or replace function public.whisper_group_history_identity_v1(
  p_sender uuid, p_logical uuid, p_body text, p_created timestamptz
) returns text language plpgsql immutable security invoker
set search_path = pg_catalog, public as $$
declare
  payload jsonb;
  event_id text;
  calendar_prefix constant text := '::whisper-calendar-v1::';
begin
  if p_logical is not null then return p_sender::text || '|message:' || p_logical::text; end if;
  if left(p_body, length(calendar_prefix)) = calendar_prefix and length(p_body) <= 32768 then
    begin
      payload := substring(p_body from length(calendar_prefix) + 1)::jsonb;
      event_id := payload ->> 'eventID';
      if payload ->> 'kind' = 'chat-meet' and event_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
        return p_sender::text || '|meet:' || lower(event_id);
      end if;
    exception when invalid_text_representation then
      null; -- A malformed legacy card is ordinary text, not a failed history page.
    end;
  end if;
  return p_sender::text || '|legacy:' || coalesce(p_body, '') || '|' ||
    to_char(p_created at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:') ||
    floor(extract(second from p_created at time zone 'UTC') / 10)::text;
end;
$$;
revoke all on function public.whisper_group_history_identity_v1(uuid,uuid,text,timestamptz) from public, anon;
grant execute on function public.whisper_group_history_identity_v1(uuid,uuid,text,timestamptz) to authenticated;

create or replace function public.whisper_group_history_v1(
  p_group_id uuid, p_limit integer default 100,
  p_before_at timestamptz default null, p_before_id uuid default null
) returns table(cursor_at timestamptz, cursor_id uuid, messages jsonb)
language sql stable security invoker set search_path = pg_catalog, public as $$
  with authorized as materialized (
    select m.*, substring(m.body from 50 + length(split_part(m.body, '::', 4))) as content
    from public.whisper_messages m
    where auth.uid() is not null
      and (m.from_user_id = auth.uid() or m.to_user_id = auth.uid())
      and lower(left(m.body, length('::wg-v1::') + 36 + 2)) = '::wg-v1::' || p_group_id::text || '::'
      and strpos(substring(m.body from 48), '::') > 0
  ), keyed as materialized (
    select a.*, public.whisper_group_history_identity_v1(a.from_user_id, a.logical_group_message_id, a.content, a.created_at) as identity
    from authorized a
  ), representatives as (
    select distinct on (k.identity) k.identity, k.created_at, k.id
    from keyed k order by k.identity, k.created_at, k.id
  ), page as (
    select r.* from representatives r
    where p_before_at is null or p_before_id is null or (r.created_at,r.id) < (p_before_at,p_before_id)
    order by r.created_at desc, r.id desc
    limit greatest(1,least(coalesce(p_limit,100),100)) + 1
  )
  select p.created_at, p.id,
    jsonb_agg(to_jsonb(k) - 'content' - 'identity' order by k.created_at,k.id)
  from page p join keyed k on k.identity = p.identity
  group by p.created_at,p.id
  order by p.created_at desc,p.id desc;
$$;
revoke all on function public.whisper_group_history_v1(uuid,integer,timestamptz,uuid) from public, anon;
grant execute on function public.whisper_group_history_v1(uuid,integer,timestamptz,uuid) to authenticated;
notify pgrst, 'reload schema';
