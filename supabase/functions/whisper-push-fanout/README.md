# whisper-push-fanout

Supabase Edge Function that listens for inserts on the social tables and pushes
a notification to the recipient's iOS devices via APNs.

## 1. Deploy

```bash
supabase functions deploy whisper-push-fanout --project-ref uryyyegnbtlmyhqlgndy
```

Keep gateway JWT verification enabled when using the CLI. The handler also requires
an exact server service-role bearer credential; anon keys and user sessions are rejected
before any database access. Merely using a service-role client internally does not
provide request authentication. Never put this credential in an app or URL.
`WHISPER_PUSH_WEBHOOK_KEY` pins the existing database's service-role JWT separately
from `SUPABASE_SERVICE_ROLE_KEY`, whose runtime-injected value may differ. Rotate
the pinned secret and database webhook headers together. The gateway remains JWT-verified.

Inspect the deployed sender before replacing it. Apply the additive September 23
preference/receipt migrations before deployment, and the social-webhook migration
afterward. Do not replay historical events: only new inserts should alert.

## 2. Secrets

Grab your APNs auth key from https://developer.apple.com/account/resources/authkeys/list
(create one with the **Apple Push Notifications service (APNs)** capability if
you don't have one — note that auth keys are account-wide, you only need one).

```bash
supabase secrets set \
  APNS_TEAM_ID=ABCDE12345 \
  APNS_KEY_ID=ABC1234DEF \
  APNS_BUNDLE_ID=com.yourcompany.whisper \
  APNS_USE_SANDBOX=true \
  APNS_PRIVATE_KEY="$(cat AuthKey_ABC1234DEF.p8)"
```

Set `APNS_USE_SANDBOX=false` only once you're shipping a production (App Store)
build. TestFlight builds use the **production** APNs server too — but
`whisper_device_tokens.sandbox` is recorded per-device when the app registers,
so the function picks the right host automatically when that column is set.

## 3. Hook up Database Webhooks

In Supabase Dashboard → Database → Webhooks, create one webhook per table:

| Table                    | Events | URL                                                                 |
| ------------------------ | ------ | ------------------------------------------------------------------- |
| `whisper_messages`       | Insert | `https://<project-ref>.functions.supabase.co/whisper-push-fanout`   |
| `whisper_follows`        | Insert | (same URL)                                                          |
| `whisper_post_likes`     | Insert | (same URL)                                                          |
| `whisper_post_comments`  | Insert | (same URL)                                                          |

Method: `POST`, trusted server `Authorization: Bearer <service-role key>` required.
The September 23 webhook migration adds comments, mentions and Story responses and
upgrades the existing thought-reply trigger without duplicating the DM/follow/like hooks.

## 4. Required tables / columns

Inspect the live schema first; do not blindly run the older `migrations.sql`. The sender uses:

- `whisper_device_tokens` (token, user_id, sandbox, bundle_id, active, …)
- An `active` column retired only for APNs Unregistered responses, never general 400 errors.
- `whisper_notification_prefs`, owner-scoped group mutes and private per-device delivery receipts.
- Current block, group membership, profile/privacy and source-row checks.

Delivery receipts suppress concurrent/repeated sends per device; failed attempts release
the receipt. A crash between claim and acknowledgement can still lose an alert, and a
network-ambiguous APNs retry can repeat one. There is no durable retry worker yet.
Story reaction rows are Activity-only because both native and web also send a DM.

## 5. Test

Run isolated tests (no production writes or APNs sends):

```bash
bun test ./supabase/functions/whisper-push-fanout/preview.test.ts ./supabase/functions/whisper-push-fanout/call-preview.test.ts ./supabase/functions/whisper-push-fanout/policy.test.ts
deno test --allow-env supabase/functions/whisper-push-fanout/delivery_test.ts
```

Real delivery requires two consenting test accounts and an APNs-capable installation.
Use ordinary in-app actions, not synthetic inserts in production. Inspect filtered logs
with `rork-agent logs supabase`. A successful deployment is not proof of device delivery.
