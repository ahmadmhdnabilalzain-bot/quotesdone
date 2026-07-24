import "jsr:@supabase/functions-js/edge-runtime.d.ts";

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
    if (!guard) { await logThrottled("config_no_publish_key", 60, "error", { stage: "config" }, "postiz_publish_key is missing from app_secrets, so social_stage can never authenticate: no marketing content is ever staged and the social pipeline is silently dead"); }
    else if (providedKey && providedKey !== guard) { await logThrottled("auth_bad_key", 60, "error", { stage: "auth", rejected: 1 }, "Rejected a call presenting a wrong x-internal-key; no social drafts were staged this cycle"); }
    if (!guard || req.headers.get("x-internal-key") !== guard) return json({ error: "unauthorized" }, 401);

    // GO-LIVE GATE: do nothing until the founder flips marketing_golive to 'true'
    // (intentional pause = idle run that did no work, so it is deliberately NOT logged)
    const golive = (await secret("marketing_golive")) || "false";
    if (golive.toLowerCase() !== "true") {
      return json({ ok: true, paused: true, staged: 0, message: "marketing pipeline paused (pre go-live)" });
    }

    const img = await secret("default_post_image");
    const r = await fetch(`${SB_URL}/rest/v1/content_drafts?channel=eq.social&staged_at=is.null&select=id,title,body,image_url&order=created_at.asc&limit=10`, {
      headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}` },
    });
    const rows: Array<{ id: number; title: string; body: string; image_url?: string }> = await r.json();
    if (!Array.isArray(rows)) { await logThrottled("drafts_query_failed", 60, "error", { stage: "select", http: r.status }, "Could not read pending social drafts (HTTP " + String(r.status) + "): " + JSON.stringify(rows).slice(0, 200) + "; this failure looks identical to having no drafts, so the marketing pipeline silently stages nothing indefinitely"); }
    if (!rows.length) return json({ ok: true, staged: 0, message: "no pending social drafts" });

    const emptyDrafts: number[] = [];
    const patchFails: number[] = [];
    const results: unknown[] = [];
    for (const row of rows) {
      const content = (row.body && row.body.trim()) ? row.body : (row.title || "");
      if (!content) { emptyDrafts.push(row.id); continue; }
      // H13 (OS audit): postiz_publish authenticates on __secret==inbound_secret and reads {action,text,type,image[]}.
      // social_stage previously sent x-internal-key + {content,mode,image_url}, so every call 403'd (and past that,
      // text was empty) — the whole social pipeline was silently dead. Aligned to postiz_publish's real contract.
      const inbound = await secret("inbound_secret");
      const pr = await fetch(`${SB_URL}/functions/v1/postiz_publish`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ __secret: inbound, action: "post", text: content, channels: ["instagram", "linkedin", "x", "facebook"], type: "draft", image_url: (row.image_url || img) || undefined, source: "marketing_agent" }),
      });
      const pj = await pr.json();
      const ok = pr.status >= 200 && pr.status < 300 && pj?.ok;
      if (ok) {
        const patchRes = await fetch(`${SB_URL}/rest/v1/content_drafts?id=eq.${row.id}`, {
          method: "PATCH",
          headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, "Content-Type": "application/json" },
          body: JSON.stringify({ staged_at: new Date().toISOString(), status: "staged" }),
        });
        if (!patchRes.ok) patchFails.push(row.id);
      }
      results.push({ id: row.id, ok, detail: ok ? undefined : pj });
    }
    const stagedN = results.filter((x: any) => x.ok).length;
    const failedN = results.filter((x: any) => !x.ok).length;
    const notes: string[] = [];
    if (failedN) notes.push(failedN + " of " + results.length + " drafts failed to reach postiz_publish; they keep staged_at null and will be retried every hour, so the marketing queue silently stops moving");
    if (patchFails.length) notes.push("staged_at could not be written for draft(s) " + patchFails.join(",") + "; they were published to Postiz but still look pending, so they will be published again on every subsequent hourly run (duplicate social posts)");
    if (emptyDrafts.length) notes.push("draft(s) " + emptyDrafts.join(",") + " have no title and no body and were skipped; they stay pending forever and permanently block nothing but never publish");
    if (stagedN) notes.push("staged " + stagedN + " social draft(s)");
    if (notes.length) { await logRun((failedN || patchFails.length || emptyDrafts.length) ? "error" : "ok", { staged: stagedN, failed: failedN, patch_failures: patchFails.length, empty_drafts: emptyDrafts.length, considered: rows.length }, notes.join(" | ")); }
    return json({ ok: true, staged: results.filter((x: any) => x.ok).length, results });
  } catch (e) {
    await logRun("error", { stage: "run" }, "social_stage crashed: " + String(e) + "; no social drafts were staged this cycle and the pending queue stops moving");
    return json({ error: String(e) }, 500);
  }
});
