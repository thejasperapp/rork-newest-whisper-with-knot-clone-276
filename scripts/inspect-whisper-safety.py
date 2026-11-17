"""Read-only, targeted production catalog inspection; never prints credentials or member rows."""
import json
import os
import urllib.request

QUERY = """
select json_build_object(
 'columns', (select json_agg(row_to_json(c)) from (select table_name,column_name,data_type from information_schema.columns where table_schema='public' and table_name in ('whisper_admins','whisper_reports','whisper_messages','whisper_blocks','whisper_liar_badges','whisper_liar_strikes','profiles','whisper_profiles','whisper_posts','whisper_safety_strikes') order by table_name,ordinal_position) c),
 'policies', (select json_agg(row_to_json(p)) from (select tablename,policyname,permissive,roles,cmd,qual,with_check from pg_policies where schemaname='public' and tablename in ('whisper_admins','whisper_reports','whisper_messages','whisper_blocks','whisper_liar_badges','whisper_liar_strikes','profiles','whisper_profiles','whisper_posts','whisper_safety_strikes')) p),
 'triggers', (select json_agg(row_to_json(t)) from (select event_object_table,trigger_name,action_statement from information_schema.triggers where event_object_schema='public' and event_object_table in ('whisper_messages','whisper_liar_badges','whisper_liar_strikes','profiles','whisper_profiles','whisper_safety_strikes')) t),
 'functions', (select json_agg(row_to_json(f)) from (select proname,pg_get_functiondef(p.oid) definition from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and (proname in ('whisper_submit_report','whisper_is_admin') or proname ilike '%liar%' or proname ilike '%safety%strike%' or proname ilike '%message%guard%' or proname ilike '%block%')) f)
) as catalog;
"""
import sys
if len(sys.argv) > 1 and sys.argv[1] == 'details':
    QUERY = """select json_build_object('constraints',(select json_agg(row_to_json(x)) from (select conrelid::regclass::text tab,pg_get_constraintdef(oid) def from pg_constraint where conrelid in ('public.whisper_reports'::regclass,'public.whisper_messages'::regclass)) x),'functions',(select json_agg(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and proname in ('whisper_chat_meet_legacy_message','whisper_chat_meet_message_access','is_coach_of')),'columns',(select json_agg(row_to_json(x)) from (select table_name,column_name,column_default from information_schema.columns where table_schema='public' and (table_name in ('whisper_follows','whisper_follow_requests','whisper_safety_flags','whisper_liar_appeals') or (table_name='profiles' and column_name='age_band'))) x)) as catalog"""
if len(sys.argv) > 1 and sys.argv[1] == 'rollout':
    QUERY = """select json_build_object('functions',(select json_agg(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and proname in ('whisper_can_contact','whisper_guard_identity_flags','whisper_review_correction','whisper_review_correction_appeal','whisper_is_reviewer')),'constraints',(select json_agg(pg_get_constraintdef(oid)) from pg_constraint where conrelid='public.whisper_admins'::regclass),'columns',(select json_agg(row_to_json(x)) from (select table_name,column_name,data_type from information_schema.columns where table_schema='public' and table_name in ('whisper_contact_restrictions','whisper_correction_history','whisper_dm_blocks')) x)) as catalog"""
if len(sys.argv) > 1 and sys.argv[1] == 'audit':
    QUERY = """select json_build_object('policies',(select json_agg(row_to_json(x)) from (select tablename,policyname,permissive,cmd,qual,with_check from pg_policies where schemaname='public' and tablename in ('whisper_admins','whisper_corrections','whisper_correction_appeals','whisper_correction_history','whisper_liar_appeals','whisper_contact_permissions','whisper_contact_restrictions')) x),'reviewer_roles',(select json_agg(role) from (select distinct role from public.whisper_admins) x),'migration_columns',(select json_agg(column_name) from information_schema.columns where table_schema='supabase_migrations' and table_name='schema_migrations')) as catalog"""
if len(sys.argv) > 1 and sys.argv[1] == 'contacts':
    QUERY = """select json_build_object('helpers',(select json_agg(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='whisper_social_teams_private' and p.proname in ('pair_allowed','notify_allowed')) or (n.nspname='public' and p.proname in ('whisper_story_tag_push','whisper_story_tag_deliver','whisper_teams_deliver_dm_v1','whisper_notes_message','whisper_event_action_v1'))),'message_writers',(select json_agg(row_to_json(x)) from (select n.nspname schema,p.proname,p.prosecdef security_definer,pg_get_function_identity_arguments(p.oid) args from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','whisper_social_teams_private') and p.prosrc ~* 'insert[[:space:]]+into[[:space:]]+(public\\.\\\"?whisper_messages|whisper_messages)' order by 1,2) x),'message_triggers',(select json_agg(json_build_object('name',t.tgname,'function',t.tgfoid::regproc::text)) from pg_trigger t where t.tgrelid='public.whisper_messages'::regclass and not t.tgisinternal)) as catalog"""
if len(sys.argv) > 1 and sys.argv[1] == 'export':
    QUERY = """select json_agg(json_build_object('version',version,'name',name,'statements',statements) order by version) as catalog from supabase_migrations.schema_migrations where replace(name,'_','-') in ('whisper-review-authority-and-report-receipts','whisper-report-receipt-variable-scope','whisper-authoritative-contact-permissions','whisper-reviewed-post-corrections','whisper-retire-public-legacy-labels','whisper-support-report-compatibility','whisper-private-profile-and-post-boundaries','whisper-contact-block-and-billing-compatibility','whisper-report-snapshot-and-legacy-appeal-privacy','whisper-legacy-appeal-owner-binding','whisper-correction-version-review-consistency','whisper-service-message-contact-boundary')"""
request = urllib.request.Request(
    'https://api.supabase.com/v1/projects/uryyyegnbtlmyhqlgndy/database/query',
    data=json.dumps({'query': QUERY, 'read_only': True}).encode(),
    headers={'Authorization': 'Bearer ' + os.environ['SUPABASE_ACCESS_TOKEN'], 'Content-Type': 'application/json'},
    method='POST',
)
with urllib.request.urlopen(request, timeout=60) as response:
    result = json.load(response)[0]['catalog']
    if len(sys.argv) > 1 and sys.argv[1] == 'export':
        import pathlib
        import re
        for migration in result or []:
            version = migration['version']
            name = migration['name'].replace('-', '_')
            if not re.fullmatch(r'[0-9]+', version) or not re.fullmatch(r'[a-z0-9_]+', name):
                raise ValueError('Unexpected migration identifier')
            path = pathlib.Path('supabase/migrations') / f'{version}_{name}.sql'
            content = '\n\n'.join(migration['statements']) + '\n'
            if path.exists() and path.read_text() != content:
                raise ValueError(f'Refusing to overwrite different migration: {path}')
            path.write_text(content)
            print(str(path))
        print(f'Exported {len(result or [])} production migration sources; no database writes.')
        sys.exit(0)
    if len(sys.argv) > 1:
        print(json.dumps(result, indent=2))
        sys.exit(0)
    print('POLICIES')
    for row in result['policies'] or []:
        if row['tablename'] != 'profiles':
            print(json.dumps(row))
    print('TRIGGERS', json.dumps(result['triggers']))
    print('FUNCTIONS')
    for row in result['functions'] or []:
        print(row['definition'])
