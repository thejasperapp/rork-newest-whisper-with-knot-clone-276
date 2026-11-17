import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info", "Access-Control-Allow-Methods": "POST, OPTIONS", "Cache-Control": "no-store, private" };
const bucket = "whisper-disappearing";
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const headers = { ...cors, "Content-Type": "application/json" };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  try {
    if (Number(req.headers.get("content-length") || 0) > 18000000) return json({ error: "Media is too large" }, 413);
    const text = await req.text();
    if (text.length > 18000000) return json({ error: "Media is too large" }, 413);
    const body = JSON.parse(text);
    if (body.action === "cleanup") {
      // A private, database-generated capability is used only by the scheduled job.
      const { data: secret, error } = await db.from("whisper_disappearing_job").select("secret").eq("id", 1).single();
      if (error || !secret || typeof body.secret !== "string" || body.secret !== secret.secret) return json({ error: "Unauthorized" }, 401);
      const { data: expired, error: scanError } = await db.from("whisper_disappearing_media").select("id,object_path").eq("purged", false)
        .or(`expires_at.lte.${new Date().toISOString()},opened_at.not.is.null,and(ready.eq.false,created_at.lt.${new Date(Date.now() - 3600000).toISOString()})`).limit(200);
      if (scanError) throw scanError;
      let removed = 0;
      for (const row of expired || []) {
        const { error: removeError } = await db.storage.from(bucket).remove([row.object_path]);
        if (removeError) { console.error("disappearing cleanup storage failure"); continue; }
        // Opened receipts stay until the original expiry; bytes do not.
        const { error: updateError } = await db.from("whisper_disappearing_media").update({ purged: true }).eq("id", row.id);
        if (updateError) throw updateError;
        removed++;
      }
      const { data: queued, error: queueError } = await db.from("whisper_disappearing_purge_queue").select("object_path").order("created_at").limit(200);
      if (queueError) throw queueError;
      for (const row of queued || []) {
        const { error: removeError } = await db.storage.from(bucket).remove([row.object_path]);
        if (!removeError) {
          const { error: dequeueError } = await db.from("whisper_disappearing_purge_queue").delete().eq("object_path", row.object_path);
          if (dequeueError) throw dequeueError;
        }
      }
      const { data: old, error: oldError } = await db.from("whisper_disappearing_media").select("id").eq("purged", true).lt("expires_at", new Date().toISOString()).limit(200);
      if (oldError) throw oldError;
      if (old?.length) {
        const { error: pruneError } = await db.from("whisper_disappearing_media").delete().in("id", old.map((row) => row.id));
        if (pruneError) throw pruneError;
      }
      return json({ removed });
    }
    const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
    if (!token) return json({ error: "Unauthorized" }, 401);
    const { data: auth, error: authError } = await db.auth.getUser(token);
    if (authError || !auth.user) return json({ error: "Unauthorized" }, 401);
    const actor = auth.user.id;
    if (body.action === "list") {
      const { data, error } = await db.rpc("whisper_disappearing_list", { p_actor: actor });
      if (error) throw error;
      return json({ items: data || [] });
    }
    if (body.action === "send") {
      if (!uuid.test(body.recipient || "") || !uuid.test(body.id || "") || !["image/jpeg", "video/mp4", "video/quicktime"].includes(body.mime) || typeof body.media !== "string" || body.media.length > 17000000) return json({ error: "Invalid media" }, 400);
      const raw = atob(body.media);
      if (!raw.length || raw.length > 12000000) return json({ error: "Media is too large" }, 413);
      const bytes = Uint8Array.from(raw, (c) => c.charCodeAt(0));
      const isJPEG = bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255;
      const isMovie = String.fromCharCode(...bytes.subarray(4, 8)) === "ftyp";
      if (body.mime === "image/jpeg" ? !isJPEG : !isMovie) return json({ error: "Invalid media" }, 400);
      const { data: existing, error: existingError } = await db.from("whisper_disappearing_media").select("ready,recipient_id,mime").eq("id", body.id).eq("sender_id", actor).maybeSingle();
      if (existingError) throw existingError;
      if (existing?.ready && existing.recipient_id === body.recipient && existing.mime === body.mime) return json({ ok: true });
      const { data: path, error: reserveError } = await db.rpc("whisper_disappearing_reserve", { p_actor: actor, p_recipient: body.recipient, p_id: body.id, p_mime: body.mime });
      if (reserveError || !path) return json({ error: "This photo or video could not be sent. Check whether you can contact this person." }, 403);
      const { error: uploadError } = await db.storage.from(bucket).upload(path, bytes, { contentType: body.mime, upsert: false, cacheControl: "0" });
      if (uploadError && String(uploadError.statusCode) !== "409") throw uploadError;
      const { error: readyError } = await db.rpc("whisper_disappearing_finish", { p_actor: actor, p_id: body.id });
      if (readyError) {
        await db.storage.from(bucket).remove([path]);
        throw readyError;
      }
      return json({ ok: true });
    }
    if (body.action === "open") {
      if (!uuid.test(body.id || "")) return json({ error: "Invalid item" }, 400);
      const { data: row, error } = await db.from("whisper_disappearing_media").select("object_path,mime,recipient_id")
        .eq("id", body.id).eq("recipient_id", actor).eq("ready", true).is("opened_at", null).gt("expires_at", new Date().toISOString()).maybeSingle();
      if (error) throw error;
      if (!row) return json({ error: "This photo or video is no longer available" }, 410);
      const { data: blob, error: downloadError } = await db.storage.from(bucket).download(row.object_path);
      if (downloadError || !blob) throw downloadError || new Error("Download unavailable");
      const bytes = new Uint8Array(await blob.arrayBuffer());
      // Claim only after bytes are ready. Exactly one racing request can succeed.
      const { data: claimed, error: claimError } = await db.rpc("whisper_disappearing_claim", { p_actor: actor, p_id: body.id });
      if (claimError || claimed !== true) return json({ error: "This photo or video is no longer available" }, 410);
      const { error: removeError } = await db.storage.from(bucket).remove([row.object_path]);
      if (removeError) console.error("disappearing claimed media pending cleanup");
      else await db.from("whisper_disappearing_media").update({ purged: true }).eq("id", body.id);
      let binary = "";
      for (let i = 0; i < bytes.length; i += 8192) binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
      return json({ mime: row.mime, media: btoa(binary) });
    }
    return json({ error: "Unknown action" }, 400);
  } catch (error) {
    console.error("disappearing request failed", error instanceof Error ? error.message : "unknown");
    return json({ error: "Couldn't complete that. Please try again." }, 500);
  }
});
