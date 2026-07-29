import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// social_stage — PUBLISHES founder-APPROVED social posts LIVE (the "approve -> goes online" half of the
// marketing review gate). It only touches content_drafts whose review_status='approved' (set by the founder
// via fn_review_decide), and publishes them for real (postiz type='now'). Three safety gates now apply: the
// founder must have approved the post, the marketing_golive master switch must be 'true', AND the weekly
// publish cap below must not be spent. Un-approved drafts are never sent anywhere — they wait in the OS
// review queue.
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SB_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Channels one approved draft fans out to. The founder's cadence spec counts a fan-out like this as
// ONE post, not four — see WEEKLY PUBLISH CAP below.
const CHANNELS = ["instagram", "linkedin", "x", "facebook"];

// WEEKLY PUBLISH CAP — spec origin ------------------------------------------------------------------
// The founder's written marketing spec says: "Maximum 3 posts per week, distributed across all
// connected platforms." No cap existed anywhere in code or config — cadence was simply whatever the
// cron happened to fire — so this enforces it for real, at publish time.
//   * "distributed across all connected platforms" means one approved draft fanned out to Instagram +
//     LinkedIn + X + Facebook counts as ONE post against the cap, not four.
//   * The window is a rolling trailing 7 days, not a calendar week, so the cap can never be dodged by
//     bunching posts around a Sunday/Monday boundary.
//   * The cap is configurable via the app_secrets key `social_posts_per_week`; it defaults to 3.
//     Setting it to 0 is a valid full stop.
//   * social_posts is the ledger of what actually went out live. postiz_publish does not write it, so
//     social_stage records each successful live publish there itself — otherwise the counter would
//     read zero forever and the cap would be decorative.
//   * It FAILS CLOSED: if the count cannot be read, or the ledger row cannot be written, we stop
//     publishing rather than risk exceeding the founder's cadence.
const DEFAULT_POSTS_PER_WEEK = 3;
const WEEK_MS = 7 * 24 * 60 * 60 * 1000;

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

// How many live posts social_stage has already published in the trailing 7 days.
// Returns null when the count cannot be established — callers must treat null as "do not publish".
async function publishedLastWeek(): Promise<number | null> {
  const since = new Date(Date.now() - WEEK_MS).toISOString();
  try {
    const r = await fetch(
      `${SB_URL}/rest/v1/social_posts?select=id&mode=eq.now&status=eq.sent&created_at=gte.${encodeURIComponent(since)}`,
      { headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, Prefer: "count=exact", Range: "0-0" } },
    );
    if (!r.ok) return null;
    const total = Number.parseInt(String(r.headers.get("content-range") || "").split("/")[1] || "", 10);
    return Number.isFinite(total) && total >= 0 ? total : null;
  } catch (_e) { return null; }
}

// Record a live publish in social_posts. This row IS the cap's memory, so a failure here is fatal to
// the rest of the run (see caller).
async function recordPublished(draftId: number, text: string, imageUrl: string | undefined, postizId: unknown): Promise<boolean> {
  try {
    const r = await fetch(`${SB_URL}/rest/v1/social_posts`, {
      method: "POST",
      headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, "Content-Type": "application/json", Prefer: "return=minimal" },
      body: JSON.stringify({
        source: "social_stage",
        content: { text, draft_id: draftId },
        image_url: imageUrl || null,
        channels: CHANNELS,
        schedule_at: new Date().toISOString(),
        mode: "now",
        status: "sent",
        postiz_ids: postizId ? [postizId] : null,
      }),
    });
    return r.ok;
  } catch (_e) { return false; }
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

    // WEEKLY PUBLISH CAP GATE (spec: "Maximum 3 posts per week, distributed across all connected
    // platforms"). Evaluated after the go-live gate and BEFORE any call to postiz_publish.
    const capRaw = String((await secret("social_posts_per_week")) ?? "").trim();
    const capParsed = Number.parseInt(capRaw, 10);
    const cap = Number.isFinite(capParsed) && capParsed >= 0 ? capParsed : DEFAULT_POSTS_PER_WEEK;
    const usedThisWeek = await publishedLastWeek();
    if (usedThisWeek === null) {
      // Fail closed: without a trustworthy count we cannot prove we are inside the founder's cap.
      await logThrottled("cap_count_unreadable", 60, "error", { stage: "weekly_cap", cap }, "Could not count social_posts published in the trailing 7 days, so the 3-posts-per-week cap could not be proven; refusing to publish this cycle rather than risk exceeding the founder's cadence");
      return json({ ok: false, published: 0, capped: true, cap, error: "weekly_cap_uncountable" });
    }
    let remaining = cap - usedThisWeek;
    if (remaining <= 0) {
      await logThrottled("weekly_cap_reached", 360, "ok", { stage: "weekly_cap", cap, used_this_week: usedThisWeek, published: 0 }, "Weekly publish cap reached: " + usedThisWeek + " of " + cap + " posts already went live in the trailing 7 days (spec: max " + cap + " posts/week across all platforms), so no approved post was published this cycle. Approved drafts keep staged_at null and publish once the rolling window frees a slot.");
      return json({ ok: true, published: 0, capped: true, cap, used_this_week: usedThisWeek, message: "weekly publish cap reached (" + usedThisWeek + "/" + cap + " in trailing 7 days)" });
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
    const ledgerFails: number[] = [];
    const cappedDrafts: number[] = [];
    const results: unknown[] = [];
    for (const row of rows) {
      // Per-post cap check: the budget is spent down as we go, so a single run can never publish more
      // than the remaining weekly allowance no matter how many approved drafts are queued.
      if (remaining <= 0) { cappedDrafts.push(row.id); continue; }
      const content = (row.body && row.body.trim()) ? row.body : (row.title || "");
      if (!content) { emptyDrafts.push(row.id); continue; }
      // postiz_publish authenticates on __secret==inbound_secret and reads {action,text,type,channels,image_url}.
      // type='now' = a real live post (this runs only for founder-approved content, behind marketing_golive
      // and behind the weekly cap).
      const inbound = await secret("inbound_secret");
      const imageUrl = (row.image_url || img) || undefined;
      const pr = await fetch(`${SB_URL}/functions/v1/postiz_publish`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ __secret: inbound, action: "post", text: content, channels: CHANNELS, type: "now", image_url: imageUrl, source: "marketing_agent" }),
      });
      const pj = await pr.json();
      const ok = pr.status >= 200 && pr.status < 300 && pj?.ok;
      if (ok) {
        // Spend the budget first, then record it. social_posts is the cap's only memory across runs,
        // so if the ledger write fails we stop publishing for the rest of this run.
        remaining--;
        const logged = await recordPublished(row.id, content, imageUrl, pj?.post_id);
        if (!logged) { ledgerFails.push(row.id); remaining = 0; }
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
    if (ledgerFails.length) notes.push("post(s) " + ledgerFails.join(",") + " went live but could NOT be recorded in social_posts; the weekly cap counter is now under-counting, so publishing was halted for the rest of this run to stay inside the max " + cap + " posts/week spec");
    if (cappedDrafts.length) notes.push("weekly publish cap of " + cap + " post(s)/week reached mid-run (" + usedThisWeek + " already live in the trailing 7 days); approved draft(s) " + cappedDrafts.join(",") + " were deliberately NOT published and stay queued for a later slot");
    if (emptyDrafts.length) notes.push("approved post(s) " + emptyDrafts.join(",") + " have no title and no body and were skipped");
    if (publishedN) notes.push("published " + publishedN + " approved social post(s) live (" + (usedThisWeek + publishedN) + "/" + cap + " used in the trailing 7 days)");
    if (notes.length) { await logRun((failedN || patchFails.length || ledgerFails.length || emptyDrafts.length) ? "error" : "ok", { published: publishedN, failed: failedN, patch_failures: patchFails.length, ledger_failures: ledgerFails.length, capped: cappedDrafts.length, cap, used_this_week: usedThisWeek, empty_drafts: emptyDrafts.length, considered: rows.length }, notes.join(" | ")); }
    return json({ ok: true, published: publishedN, cap, used_this_week: usedThisWeek, capped: cappedDrafts.length, results });
  } catch (e) {
    await logRun("error", { stage: "run" }, "social_stage crashed: " + String(e) + "; no approved posts were published this cycle");
    return json({ error: String(e) }, 500);
  }
});
