import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { requireInternal } from "../_shared/internal_auth.ts";

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SB_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const admin = createClient(SB_URL, SB_KEY);

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

// SUPPRESSION BYPASS 28 Jul 2026 ----------------------------------------------------------------
// The QA failure alert below built its own Resend call and never consulted email_suppressions, the
// last sender in the codebase to do so (send_outbox queries it; login_otp, kyc and contact_submit
// all check before sending). The recipient is a fixed internal address, so the case for exempting it
// is that an operator should always be told - but that argument does not survive contact: this
// mailbox sits on the same sending domain as every customer and supplier email, one hard bounce
// recorded by resend_webhook is enough to put it on the list, and re-mailing it on every QA failure
// would burn the reputation of the shared domain while STILL not reaching anybody. contact_submit
// made exactly this call for its admin notify address on 27 Jul; qa_suite follows it. Not sending is
// not the same as staying quiet: the run is already persisted in qa_results and the skipped alert is
// written loudly to agent_runs, so the failing checks remain visible where operators look.
// Fails OPEN on a lookup error - an alert that might be deliverable is worth more than a silent run.
async function isSuppressed(email: string): Promise<boolean> {
  try {
    const r = await fetch(`${SB_URL}/rest/v1/email_suppressions?email=eq.${encodeURIComponent(email.toLowerCase())}&select=email&limit=1`, { headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}` } });
    if (!r.ok) return false;
    const b = await r.json().catch(() => null);
    return Array.isArray(b) && b.length > 0;
  } catch (_e) { return false; }
}

// 4 SEP 2026: three answers, not two. A probe that could not verify (404, unexpected status, a thrown
// fetch) used to come back as leaked:true — the same value as a real leak — while the summary below
// looked for strings ("probe error:", "status ") that no branch produced, so its "counted as PASSING"
// note could never fire and the run's notes named a leak that was not measured. Error and empty must
// not share a value with success OR with failure: 'ok' / 'leak' / 'inconclusive', each scored on its own.
type ProbeVerdict = "ok" | "leak" | "inconclusive";
async function anonProbe(anon: string, table: string): Promise<{ verdict: ProbeVerdict; detail: string }> {
  try {
    const r = await fetch(`${SB_URL}/rest/v1/${table}?select=*&limit=1`, { headers: { apikey: anon, Authorization: `Bearer ${anon}` } });
    const body = await r.json().catch(() => null);
    if (r.status === 401 || (body && body.code === "42501")) return { verdict: "ok", detail: "permission denied (good)" };
    if (Array.isArray(body) && body.length === 0) return { verdict: "ok", detail: "RLS empty (good)" };
    if (Array.isArray(body) && body.length > 0) return { verdict: "leak", detail: `LEAK: ${body.length} row(s) readable by anon` };
    if (r.status === 404) return { verdict: "inconclusive", detail: `INCONCLUSIVE: table not found (404) - the probe list names a table that does not exist, so it has never actually been checked` };
    return { verdict: "inconclusive", detail: `INCONCLUSIVE: unexpected status ${r.status} - not verified, and not verified is not safe` };
  } catch (e) {
    return { verdict: "inconclusive", detail: "INCONCLUSIVE: probe error, not verified: " + String(e) };
  }
}

Deno.serve(async (req) => {
  try {
    // AUDIT 9.5 (4 Aug 2026). This compared a raw header, `x-internal-key`, against
    // app_secrets.postiz_publish_key. That was a SECOND shared secret - one string, no scope, no
    // attribution, no rotation path - spanning two unrelated functions (a QA suite and a social
    // publisher) and completely invisible to the internal_credential model, to
    // v_legacy_secret_users and to the shared-secret withdrawal plan. Audit 9.5 measured one shared
    // secret and declared coverage; this is what it was not looking at.
    //
    // The credential now arrives as body.__secret and is checked by the same verifier as everything
    // else, so scope, rotation and attribution live in one place. The header path is removed rather
    // than deprecated: leaving it would preserve exactly the thing being removed.
    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    const __auth = await requireInternal(admin, (body as { __secret?: unknown })?.__secret, "qa_suite");
    if (!__auth.ok) {
      await logRun("error", { stage: "auth", rejected: 1 }, "Rejected a call that presented no accepted internal credential; the QA suite did not run, so RLS leaks and data-integrity regressions stay unverified for this cycle");
      return json({ error: "unauthorized" }, 403);
    }
    const anon = await secret("anon_key");
    if (!anon) { await logRun("error", { stage: "config" }, "anon_key is missing from app_secrets, so qa_suite cannot probe RLS at all: a table left publicly readable (customers, leads, app_secrets, quotes) would never be detected"); return json({ error: "anon_key not configured" }, 500); }

    const results: Array<{ check: string; ok: boolean; detail: string; verdict?: ProbeVerdict }> = [];

    // 1) RLS / anonymity regression: sensitive tables must NOT be readable by the public key
    const sensitive = ["customers", "app_secrets", "leads", "transactions", "quotes", "inquiries", "messages", "agent_knowledge", "email_suppressions", "social_posts", "qa_results", "customer_phone_otps", "inbound_messages"];
    for (const t of sensitive) {
      const p = await anonProbe(anon, t);
      // only a verified refusal passes; a leak fails; an unverified probe fails too, but is reported as unverified
      results.push({ check: `anon_cannot_read:${t}`, ok: p.verdict === "ok", detail: p.detail, verdict: p.verdict });
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
      const alertTo = "management@quotesdone.com";
      if (await isSuppressed(alertTo)) {
        alertNote = "no failure alert email was sent: the alert address (" + alertTo + ") is in email_suppressions, so mail to it bounces and would damage the sending domain shared with customer and supplier email. The failing checks are in qa_results and in this run's counts - read them there, then fix the mailbox and delete its email_suppressions row";
      } else if (rk) {
        const alertRes = await fetch("https://api.resend.com/emails", { method: "POST", headers: { Authorization: `Bearer ${rk}`, "Content-Type": "application/json" }, body: JSON.stringify({ from: (await secret("email_from_info")) || "QuotesDone <info@quotesdone.com>", to: [alertTo], subject: `QuotesDone QA FAILED (${failed.length} check(s))`, html: `<h3>QA suite found ${failed.length} failing check(s)</h3><pre>${JSON.stringify(failed, null, 2)}</pre>` }) }).catch(() => null);
        alertSent = !!(alertRes && (alertRes as Response).ok);
        if (!alertSent) alertNote = "the failure alert email could NOT be sent, so nobody was notified of these failing checks";
      } else { alertNote = "resend_api_key is missing, so no failure alert email was sent and nobody was notified of these failing checks"; }
    }

    const leaks = results.filter((r) => r.verdict === "leak").map((r) => r.check.split(":")[1]);
    const inconclusive = results.filter((r) => r.verdict === "inconclusive").map((r) => r.check.split(":")[1]);
    const notes: string[] = [];
    if (leaks.length) notes.push("PUBLIC DATA LEAK: table(s) " + leaks.join(",") + " are readable with the anon key, exposing customer and supplier records to anyone on the internet");
    if (failed.length) notes.push(failed.length + " of " + results.length + " checks failed: " + failed.map((r) => r.check).join(","));
    if (inconclusive.length) notes.push(inconclusive.length + " probe(s) were INCONCLUSIVE and are counted as failed, not as leaks and not as passing (" + inconclusive.join(",") + "); those tables were NOT verified this run");
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
