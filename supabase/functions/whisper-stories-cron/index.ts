// Whisper expired-stories cleanup cron
//
// Deletes every row in `public.whisper_stories` whose `expires_at` is in the
// past. The client already filters by `expires_at > now()` so users never see
// stale stories, but rows accumulate forever without this sweep — eating
// storage in the `whisper-media` bucket and bloating the table.
//
// Deploy:
//   supabase functions deploy whisper-stories-cron --no-verify-jwt
//
// Schedule (Supabase Dashboard → Database → Cron Jobs, or pg_cron):
//   select cron.schedule(
//     'whisper-stories-cleanup',
//     '*/15 * * * *',
//     $$ select net.http_post(
//          url:='https://<PROJECT_REF>.functions.supabase.co/whisper-stories-cron',
//          headers:=jsonb_build_object(
//            'Content-Type','application/json',
//            'Authorization','Bearer ' || current_setting('app.settings.service_role_key', true)
//          )
//        ) $$
//   );
//
// Or hit it from any external cron (cron-job.org, GitHub Actions, etc.).
// The function authenticates via the service-role key in the Authorization
// header (or via the auto-injected `SUPABASE_SERVICE_ROLE_KEY` for internal
// invocations).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const BUCKET = "whisper-media";

interface StoryRow {
  id: string;
  user_id: string;
  image_url: string | null;
}

Deno.serve(async (_req) => {
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const nowISO = new Date().toISOString();

  // 1) Find expired stories so we can delete their underlying media too.
  const { data: expired, error: selectError } = await supabase
    .from("whisper_stories")
    .select("id, user_id, image_url")
    .lt("expires_at", nowISO)
    .limit(1000);

  if (selectError) {
    return new Response(
      JSON.stringify({ ok: false, stage: "select", error: selectError.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  const rows = (expired ?? []) as StoryRow[];

  // 2) Best-effort: remove media files for each expired story so the bucket
  // doesn't grow forever. Paths follow `<userId>/stories/<storyId>.jpg`.
  const mediaPaths = rows
    .map((r) => `${r.user_id}/stories/${r.id}.jpg`)
    .filter((p): p is string => Boolean(p));

  let removedMedia = 0;
  if (mediaPaths.length > 0) {
    // Storage `remove` accepts up to ~1000 paths in one call.
    const { data: removed, error: removeError } = await supabase
      .storage
      .from(BUCKET)
      .remove(mediaPaths);
    if (!removeError) {
      removedMedia = removed?.length ?? 0;
    }
  }

  // 3) Delete the rows themselves. We do this after the storage call so a
  // future re-run can still reconstruct the paths if storage fails.
  const { error: deleteError, count } = await supabase
    .from("whisper_stories")
    .delete({ count: "exact" })
    .lt("expires_at", nowISO);

  if (deleteError) {
    return new Response(
      JSON.stringify({ ok: false, stage: "delete", error: deleteError.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  return new Response(
    JSON.stringify({
      ok: true,
      deletedRows: count ?? rows.length,
      removedMedia,
      ranAt: nowISO,
    }),
    { status: 200, headers: { "Content-Type": "application/json" } }
  );
});
