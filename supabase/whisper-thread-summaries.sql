-- Read-only direct/dating inbox pages. Native group transport remains separate.
-- SECURITY INVOKER retains participant RLS and the restrictive Meet guard.
-- Hidden IDs only subtract the caller's rows; they cannot widen access.
-- No history, read receipts, contact permissions or existing policies are changed.
create or replace function public.whisper_thread_summaries_v1(
    p_limit integer default 50,
    p_before_at timestamptz default null,
    p_before_id uuid default null,
    p_hidden_ids uuid[] default '{}'::uuid[]
) returns table (
    peer_id uuid,
    conversation_kind text,
    last_message_id uuid,
    last_body text,
    last_created_at timestamptz,
    last_from_me boolean,
    peer_username text,
    unread_count bigint,
    last_message jsonb
)
language sql stable security invoker
set search_path = pg_catalog, public
as $function$
    with owned as (
        select m.id, m.from_user_id, m.to_user_id, m.from_username,
               m.to_username, m.thread_id, m.body, m.created_at, m.read_at,
               m.media_url, m.embed, m.logical_group_message_id,
               case when m.from_user_id = auth.uid()
                    then m.to_user_id else m.from_user_id end as peer
        from public.whisper_messages m
        where auth.uid() is not null
          and (m.from_user_id = auth.uid() or m.to_user_id = auth.uid())
          and m.from_user_id <> m.to_user_id
          and not exists (select 1 from unnest(coalesce(p_hidden_ids, '{}'::uuid[])) h(id) where h.id = m.id)
          and (m.body is null or
               (m.body not like '::wg-v1::%' and m.body not like '::whisper-call-%'))
    ), scoped as (
        select o.*,
            case when replace(o.thread_id::text, '-', '') =
                substr(encode(sha256(convert_to(
                    'dating-v1:' || least(o.from_user_id::text, o.to_user_id::text) ||
                    '|dating-v1:' || greatest(o.from_user_id::text, o.to_user_id::text),
                    'UTF8')), 'hex'), 1, 32)
            then 'dating' else 'direct' end as kind
        from owned o
    ), latest as (
        select distinct on (s.peer, s.kind)
               s.peer, s.kind, s.id, s.body, s.created_at,
               s.from_user_id = auth.uid() as from_me,
               case when s.from_user_id = auth.uid()
                    then s.to_username else s.from_username end as username,
               jsonb_build_object(
                   'id', s.id, 'thread_id', s.thread_id,
                   'from_user_id', s.from_user_id, 'to_user_id', s.to_user_id,
                   'from_username', s.from_username, 'to_username', s.to_username,
                   'body', s.body, 'created_at', s.created_at, 'read_at', s.read_at,
                   'media_url', s.media_url, 'embed', s.embed,
                   'logical_group_message_id', s.logical_group_message_id
               ) as message
        from scoped s
        order by s.peer, s.kind, s.created_at desc nulls last, s.id desc
    ), unread as (
        select s.peer, s.kind, count(*) as n
        from scoped s
        where s.to_user_id = auth.uid() and s.read_at is null
        group by s.peer, s.kind
    )
    select l.peer, l.kind, l.id, coalesce(l.body, ''), l.created_at,
           l.from_me, l.username, coalesce(u.n, 0), l.message
    from latest l
    left join unread u on u.peer = l.peer and u.kind = l.kind
    where (p_before_id is null or
           (p_before_at is null and l.created_at is null and l.id < p_before_id) or
           (p_before_at is not null and
            (l.created_at < p_before_at or l.created_at is null or
             (l.created_at = p_before_at and l.id < p_before_id))))
    order by l.created_at desc nulls last, l.id desc
    limit greatest(1, least(coalesce(p_limit, 50), 100)) + 1;
$function$;
revoke all on function public.whisper_thread_summaries_v1(integer, timestamptz, uuid, uuid[]) from public, anon;
grant execute on function public.whisper_thread_summaries_v1(integer, timestamptz, uuid, uuid[]) to authenticated;
