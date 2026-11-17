"""Read-only catalog audit of the existing Whisper message backend.

Uses the Supabase Management API's read-only query endpoint. Never prints
credentials or message content; no production data/schema writes.
"""
import json
import os
import re
import urllib.request

PROJECT_REF = "uryyyegnbtlmyhqlgndy"
QUERIES = {
    "indexes": """select schemaname, tablename, indexname, indexdef from pg_catalog.pg_indexes
        where schemaname = 'public' and tablename in
        ('whisper_messages','whisper_group_threads','whisper_group_message_identity') order by tablename, indexname""",
    "rls": """select c.relname, c.relrowsecurity, c.relforcerowsecurity, c.relreplident
        from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace
        where n.nspname='public' and c.relname in
        ('whisper_messages','whisper_group_threads','whisper_group_message_identity')""",
    "policies": """select tablename, policyname, permissive, roles, cmd, qual, with_check
        from pg_catalog.pg_policies where schemaname='public' and tablename in
        ('whisper_messages','whisper_group_threads','whisper_group_message_identity') order by tablename, policyname""",
    "grants": """select c.relname as table_name, r.rolname as grantee,
        pg_catalog.has_table_privilege(r.rolname,c.oid,'SELECT') as can_select,
        pg_catalog.has_table_privilege(r.rolname,c.oid,'INSERT') as can_insert,
        pg_catalog.has_table_privilege(r.rolname,c.oid,'UPDATE') as can_update,
        pg_catalog.has_table_privilege(r.rolname,c.oid,'DELETE') as can_delete
        from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace
        cross join pg_catalog.pg_roles r where n.nspname='public' and c.relname in
        ('whisper_messages','whisper_group_threads','whisper_group_message_identity')
        and r.rolname in ('anon','authenticated') order by c.relname,r.rolname""",
    "functions": """select p.proname, p.prosecdef,
        pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute,
        pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE') as anon_execute,
        pg_catalog.pg_get_function_identity_arguments(p.oid) as args,
        pg_catalog.pg_get_functiondef(p.oid) as definition from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid=p.pronamespace
        where n.nspname='public' and (p.proname like '%message%access%' or
        p.proname like 'whisper%group%message%' or p.proname like 'whisper_thread_summaries%') order by p.proname""",
    "triggers": """select c.relname, t.tgname, p.proname as function_name, pn.nspname as function_schema
        from pg_catalog.pg_trigger t join pg_catalog.pg_class c on c.oid=t.tgrelid
        join pg_catalog.pg_namespace n on n.oid=c.relnamespace
        join pg_catalog.pg_proc p on p.oid=t.tgfoid
        join pg_catalog.pg_namespace pn on pn.oid=p.pronamespace
        where n.nspname='public' and c.relname in ('whisper_messages','whisper_group_threads')
        and not t.tgisinternal order by c.relname,t.tgname""",
}

def main():
    token = os.environ["SUPABASE_ACCESS_TOKEN"]
    for name, query in QUERIES.items():
        request = urllib.request.Request(
            f"https://api.supabase.com/v1/projects/{PROJECT_REF}/database/query/read-only",
            data=json.dumps({"query": query}).encode(),
            headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=45) as response:
            result = json.load(response)
        # Catalog definitions can contain old webhook credentials. Never emit
        # JWTs even if a future audit query accidentally includes arguments.
        output = json.dumps({"section": name, "result": result}, indent=2)
        print(re.sub(r"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+", "[redacted JWT]", output))

if __name__ == "__main__":
    main()
