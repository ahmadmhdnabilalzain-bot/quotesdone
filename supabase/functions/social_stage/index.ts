import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// social_stage — PUBLISHES founder-APPROVED social posts LIVE (the "approve -> goes online" half of the
// marketing review gate). It only touches content_drafts whose review_status='approved' (set by the founder
// via fn_review_decide), and publishes them for real (postiz type='now'). Two safety gates remain: the
// founder must have approved the post, AND the marketing_golive master switch must be 'true'. Un-approved
// drafts are never sent anywhere — they wait in the OS review queue.
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SB_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await fetch(`${SB_URL}/rest/v1/agent_runs`, { method: "POST", headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, "Content-Type": "application/json" }, body: JSON.stringify({ agent: "social_stage", status, counts, note: String(note || "").slice(0, 500), started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() }) });
  } catch (_e) { /* never let logging break the function */ }
}
async function logThrottled(signal: string, minutes: number, status: string, counts: Record<string, unknown>, note: string) {
  try {
    const since = new Date(Date.now() - minutes * 60000).toISOString();
    const q = `${SB_URL}/rest/v1/agent_runs?select=id&agent=eq.social_stage&started_at=gte.${encodeURIComponent(since)}&counts->>signal=eq.${encodeURIComponent(signal)}&limit=1`;
    const rr = await fetch(q, { headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}` } });
    const data = await rr.json();
    if (Array.isArray(data) && data.length) return;
  } catch (_e) { /* fall through and log */ }
  await logRun(status, { ...counts, signal }, note);
}

function json(o: unknown, s = 200) {
  return new Response(JSON.stringify(o), { status: s, headers: { "Content-Type": "application/json" } });
}
async function secret(key: string): Promise<string | null> {
  const r = await fetch(`${SB_URL}/rest/v1/app_secrets?key=eq.${key}&select=value`, {
    headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}` },
  });
  return (await r.json())?.[0]?.value ?? null;
}

Deno.serve(async (req) => {
  try {
    const guard = await secret("postiz_publish_key");
    const providedKey = req.headers.get("x-internal-key");
    if (!guard) { await logThrottled("config_no_publish_key", 60, "error", { stage: "config" }, "postiz_publish_key is missing from app_secrets, so social_stage can never authenticate: no approved post is ever published and the social pipeline is silently dead"); }
    else if (providedKey && providedKey !== guard) { await logThrottled("auth_bad_key", 60, "error", { stage: "auth", rejected: 1 }, "Rejected a call presenting a wrong x-internal-key; no approved posts were published this cycle"); }
    if (!guard || req.headers.get("x-internal-key") !== guard) return json({ error: "unauthorized" }, 401);

    // GO-LIVE GATE: do nothing until the founder flips marketing_golive to 'true'
    // (intentional pause = idle run that did no work, so it is deliberately NOT logged)
    const golive = (await secret("marketing_golive")) || "false";
    if (golive.toLowerCase() !== "true") {
      return json({ ok: true, paused: true, published: 0, message: "marketing pipeline paused (pre go-live)" });
    }

    const img = await secret("default_post_image");
    // ONLY founder-approved posts publish live. Un-approved drafts wait in the OS review queue.
    const r = await fetch(`${SB_URL}/rest/v1/content_drafts?channel=eq.social&staged_at=is.null&review_status=eq.approved&select=id,title,body,image_url&order=created_at.asc&limit=10`, {
      headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}` },
    });
    const rows: Array<{ id: number; title: string; body: string; image_url?: string }> = await r.json();
    if (!Array.isArray(rows)) { await logThrottled("drafts_query_failed", 60, "error", { stage: "select", http: r.status }, "Could not read approved social posts (HTTP " + String(r.status) + "): " + JSON.stringify(rows).slice(0, 200) + "; this failure looks identical to having none, so approved posts silently never publish"); }
    if (!rows.length) return json({ ok: true, published: 0, message: "no approved social posts to publish" });

    const emptyDrafts: number[] = [];
    const patchFails: number[] = [];
    const results: unknown[] = [];
    for (const row of rows) {
      const content = (row.body && row.body.trim()) ? row.body : (row.title || "");
      if (!content) { emptyDrafts.push(row.id); continue; }
      // postiz_publish authenticates on __secret==inbound_secret and reads {action,text,type,channels,image_url}.
      // type='now' = a real live post (this runs only for founder-approved content, behind marketing_golive).
      const inbound = await secret("inbound_secret");
      const pr = await fetch(`${SB_URL}/functions/v1/postiz_publish`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ __secret: inbound, action: "post", text: content, channels: ["instagram", "linkedin", "x", "facebook"], type: "now", image_url: (row.image_url || img) || undefined, source: "marketing_agent" }),
      });
      const pj = await pr.json();
      const ok = pr.status >= 200 && pr.status < 300 && pj?.ok;
      if (ok) {
        const patchRes = await fetch(`${SB_URL}/rest/v1/content_drafts?id=eq.${row.id}`, {
          method: "PATCH",
          headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, "Content-Type": "application/json" },
          body: JSON.stringify({ staged_at: new Date().toISOString(), status: "published" }),
        });
        if (!patchRes.ok) patchFails.push(row.id);
      }
      results.push({ id: row.id, ok, detail: ok ? undefined : pj });
    }
    const publishedN = results.filter((x: any) => x.ok).length;
    const failedN = results.filter((x: any) => !x.ok).length;
    const notes: string[] = [];
    if (failedN) notes.push(failedN + " of " + results.length + " approved posts failed to reach postiz_publish; they keep staged_at null and will be retried, so approved content silently stops publishing");
    if (patchFails.length) notes.push("staged_at could not be written for post(s) " + patchFails.join(",") + "; they were published to Postiz but still look pending, so they may be published again on the next run (duplicate social posts)");
    if (emptyDrafts.length) notes.push("approved post(s) " + emptyDrafts.join(",") + " have no title and no body and were skipped");
    if (publishedN) notes.push("published " + publishedN + " approved social post(s) live");
    if (notes.length) { await logRun((failedN || patchFails.length || emptyDrafts.length) ? "error" : "ok", { published: publishedN, failed: failedN, patch_failures: patchFails.length, empty_drafts: emptyDrafts.length, considered: rows.length }, notes.join(" | ")); }
    return json({ ok: true, published: publishedN, results });
  } catch (e) {
    await logRun("error", { stage: "run" }, "social_stage crashed: " + String(e) + "; no approved posts were published this cycle");
    return json({ error: String(e) }, 500);
  }
});
