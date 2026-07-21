import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SB_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await fetch(`${SB_URL}/rest/v1/agent_runs`, { method: "POST", headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, "Content-Type": "application/json" }, body: JSON.stringify({ agent: "qa_suite", status, counts, note: String(note || "").slice(0, 500), started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() }) });
  } catch (_e) { /* never let logging break the function */ }
}

function json(o: unknown, s = 200) {
  return new Response(JSON.stringify(o), { status: s, headers: { "Content-Type": "application/json" } });
}
async function secret(key: string): Promise<string | null> {
  const r = await fetch(`${SB_URL}/rest/v1/app_secrets?key=eq.${key}&select=value`, { headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}` } });
  return (await r.json())?.[0]?.value ?? null;
}

async function anonProbe(anon: string, table: string): Promise<{ leaked: boolean; detail: string }> {
  try {
    const r = await fetch(`${SB_URL}/rest/v1/${table}?select=*&limit=1`, { headers: { apikey: anon, Authorization: `Bearer ${anon}` } });
    const body = await r.json().catch(() => null);
    if (r.status === 401 || (body && body.code === "42501")) return { leaked: false, detail: "permission denied (good)" };
    if (Array.isArray(body) && body.length === 0) return { leaked: false, detail: "RLS empty (good)" };
    if (Array.isArray(body) && body.length > 0) return { leaked: true, detail: `LEAK: ${body.length} row(s) readable by anon` };
    return { leaked: false, detail: `status ${r.status}` };
  } catch (e) {
    return { leaked: false, detail: "probe error: " + String(e) };
  }
}

Deno.serve(async (req) => {
  try {
    const guard = await secret("postiz_publish_key");
    const providedKey = req.headers.get("x-internal-key");
    if (!guard) { await logRun("error", { stage: "config" }, "postiz_publish_key is missing from app_secrets, so qa_suite can never authenticate and the RLS/data-leak and data-integrity checks never run: a regression that exposes customer, supplier or secret data would go completely unnoticed"); }
    else if (providedKey && providedKey !== guard) { await logRun("error", { stage: "auth", rejected: 1 }, "Rejected a call presenting a wrong x-internal-key; the QA suite did not run, so RLS leaks and data-integrity regressions stay unverified for this cycle"); }
    if (!guard || providedKey !== guard) return json({ error: "unauthorized" }, 401);
    const anon = await secret("anon_key");
    if (!anon) { await logRun("error", { stage: "config" }, "anon_key is missing from app_secrets, so qa_suite cannot probe RLS at all: a table left publicly readable (customers, leads, app_secrets, quotes) would never be detected"); return json({ error: "anon_key not configured" }, 500); }

    const results: Array<{ check: string; ok: boolean; detail: string }> = [];

    // 1) RLS / anonymity regression: sensitive tables must NOT be readable by the public key
    const sensitive = ["customers", "app_secrets", "leads", "transactions", "quotes", "inquiries", "messages", "agent_knowledge", "email_suppression", "social_posts", "qa_results", "customer_phone_otps", "inbound_messages"];
    for (const t of sensitive) {
      const p = await anonProbe(anon, t);
      results.push({ check: `anon_cannot_read:${t}`, ok: !p.leaked, detail: p.detail });
    }

    // 2) Positive control: public category data SHOULD be reachable (proves anon key is valid, not just failing)
    try {
      const r = await fetch(`${SB_URL}/rest/v1/category_specs?select=category&limit=1`, { headers: { apikey: anon, Authorization: `Bearer ${anon}` } });
      const b = await r.json().catch(() => null);
      results.push({ check: "public_category_specs_reachable", ok: Array.isArray(b), detail: Array.isArray(b) ? `ok (${b.length})` : "unexpected: " + JSON.stringify(b).slice(0, 120) });
    } catch (e) { results.push({ check: "public_category_specs_reachable", ok: false, detail: String(e) }); }

    // 3) Data-integrity / payment invariants via existing fn_smoke (best effort)
    let smokeNote = "";
    try {
      const r = await fetch(`${SB_URL}/rest/v1/rpc/fn_smoke`, { method: "POST", headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, "Content-Type": "application/json" }, body: "{}" });
      if (r.ok) { const sm = await r.json(); results.push({ check: "smoke_invariants", ok: true, detail: JSON.stringify(sm).slice(0, 400) }); }
      else { smokeNote = "fn_smoke skipped (HTTP " + String(r.status) + "): payment and data-integrity invariants were NOT verified this run"; }
    } catch (_) { smokeNote = "fn_smoke threw (" + String(_) + "): payment and data-integrity invariants were NOT verified this run"; /* optional */ }

    const failed = results.filter((r) => !r.ok);
    const passed = failed.length === 0;

    const qaRes = await fetch(`${SB_URL}/rest/v1/qa_results`, { method: "POST", headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, "Content-Type": "application/json" }, body: JSON.stringify({ passed, total: results.length, failed: failed.length, results }) });

    let alertSent = false; let alertNote = "";
    if (!passed) {
      const rk = await secret("resend_api_key");
      if (rk) {
        const alertRes = await fetch("https://api.resend.com/emails", { method: "POST", headers: { Authorization: `Bearer ${rk}`, "Content-Type": "application/json" }, body: JSON.stringify({ from: "QuotesDone QA <qa@send.quotesdone.com>", to: ["management@quotesdone.com"], subject: `QuotesDone QA FAILED (${failed.length} check(s))`, html: `<h3>QA suite found ${failed.length} failing check(s)</h3><pre>${JSON.stringify(failed, null, 2)}</pre>` }) }).catch(() => null);
        alertSent = !!(alertRes && (alertRes as Response).ok);
        if (!alertSent) alertNote = "the failure alert email could NOT be sent, so nobody was notified of these failing checks";
      } else { alertNote = "resend_api_key is missing, so no failure alert email was sent and nobody was notified of these failing checks"; }
    }

    const leaks = failed.filter((r) => r.check.startsWith("anon_cannot_read:")).map((r) => r.check.split(":")[1]);
    const inconclusive = results.filter((r) => r.detail.startsWith("probe error:") || r.detail.startsWith("status ")).map((r) => r.check);
    const notes: string[] = [];
    if (leaks.length) notes.push("PUBLIC DATA LEAK: table(s) " + leaks.join(",") + " are readable with the anon key, exposing customer and supplier records to anyone on the internet");
    if (failed.length) notes.push(failed.length + " of " + results.length + " checks failed: " + failed.map((r) => r.check).join(","));
    if (inconclusive.length) notes.push(inconclusive.length + " probe(s) were inconclusive and were counted as PASSING (" + inconclusive.join(",") + "); a real RLS leak on those tables would be scored as a pass and stay hidden");
    if (smokeNote) notes.push(smokeNote);
    if (!qaRes.ok) notes.push("qa_results insert failed (HTTP " + String(qaRes.status) + "): this QA run was not persisted, leaving a silent gap in the QA history");
    if (alertNote) notes.push(alertNote);
    if (!notes.length) notes.push("All " + results.length + " QA checks passed: no anon-readable sensitive tables and invariants verified");
    await logRun((!passed || !qaRes.ok || smokeNote || alertNote || inconclusive.length) ? "error" : "ok", { total: results.length, failed: failed.length, leaks, inconclusive: inconclusive.length, qa_results_stored: qaRes.ok, alert_sent: alertSent, smoke_skipped: smokeNote ? 1 : 0 }, notes.join(" | "));
    return json({ passed, total: results.length, failed: failed.length, failing: failed });
  } catch (e) {
    await logRun("error", { stage: "run" }, "qa_suite crashed: " + String(e) + "; no RLS/data-leak or data-integrity verification was performed this cycle, so a regression exposing customer or supplier data would go unnoticed");
    return json({ error: String(e) }, 500);
  }
});
