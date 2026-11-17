# whisper-stories-cron

Server-side sweep that deletes expired Whisper stories (and their media in the
`whisper-media` bucket). Stories are 24-hour ephemeral — the client already
filters by `expires_at > now()`, but rows would otherwise pile up forever.

## Deploy

```bash
supabase functions deploy whisper-stories-cron --no-verify-jwt
```

## Schedule (every 15 min)

In Supabase Dashboard → Database → Cron Jobs, or via SQL:

```sql
select cron.schedule(
  'whisper-stories-cleanup',
  '*/15 * * * *',
  $$ select net.http_post(
       url:='https://<PROJECT_REF>.functions.supabase.co/whisper-stories-cron',
       headers:=jsonb_build_object(
         'Content-Type','application/json',
         'Authorization','Bearer ' || current_setting('app.settings.service_role_key', true)
       )
     ) $$
);
```

## Response

```json
{ "ok": true, "deletedRows": 42, "removedMedia": 42, "ranAt": "..." }
```
