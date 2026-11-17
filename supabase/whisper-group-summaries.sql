-- Independent group list authority; does not depend on downloaded history.
-- Registry-backed empty groups are merged by clients. This function discovers
-- only history the caller is already allowed to SELECT, including legacy groups.
create or replace function public.whisper_group_summaries_v1(
  p_limit integer default 50, p_before_at timestamptz default null,
  p_before_id uuid default null, p_hidden_ids uuid[] default '{}'
) returns table(group_id uuid, last_created_at timestamptz, last_message_id uuid,
  unread_count bigint, last_message jsonb, participants jsonb)
language sql stable security invoker set search_path = pg_catalog, public as $$
  with authorized as materialized (
    select m.*, lower(split_part(m.body,'::',3))::uuid as group_uuid
    from public.whisper_messages m
    where auth.uid() is not null and (m.from_user_id=auth.uid() or m.to_user_id=auth.uid())
      and m.body ~* '^::wg-v1::[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}::'
      and strpos(substring(m.body from 48),'::') > 0
      and not exists (select 1 from unnest(coalesce(p_hidden_ids,'{}')) h where h=m.id)
  ), latest as (
    select distinct on (a.group_uuid) a.* from authorized a
    order by a.group_uuid,a.created_at desc,a.id desc
  ), page as (
    select l.* from latest l
    where p_before_at is null or p_before_id is null or (l.created_at,l.id)<(p_before_at,p_before_id)
    order by l.created_at desc,l.id desc
    limit greatest(1,least(coalesce(p_limit,50),100))+1
  )
  select p.group_uuid,p.created_at,p.id,
    (select count(*) from authorized a where a.group_uuid=p.group_uuid and a.to_user_id=auth.uid() and a.from_user_id<>auth.uid() and a.read_at is null),
    to_jsonb(p)-'group_uuid',
    (select coalesce(jsonb_agg(jsonb_build_object('user_id', people.user_id,'username',people.username) order by people.user_id),'[]'::jsonb)
     from (
       select distinct on (v.user_id) v.user_id,v.username
       from authorized a cross join lateral (values(a.from_user_id,a.from_username),(a.to_user_id,a.to_username)) v(user_id,username)
       where a.group_uuid=p.group_uuid and v.user_id is not null and v.user_id<>auth.uid()
       order by v.user_id,a.created_at desc,a.id desc
     ) people)
  from page p order by p.created_at desc,p.id desc;
$$;
revoke all on function public.whisper_group_summaries_v1(integer,timestamptz,uuid,uuid[]) from public,anon;
grant execute on function public.whisper_group_summaries_v1(integer,timestamptz,uuid,uuid[]) to authenticated;
notify pgrst,'reload schema';
