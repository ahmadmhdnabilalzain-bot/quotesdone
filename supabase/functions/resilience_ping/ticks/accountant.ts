// resilience_ping ticks owned by the accountant seat. Moved out of index.ts unchanged (9 Nov 2026);
// the order they run in is still set in index.ts (STEP_RUN).
import { FN, GATEWAY, admin, sec } from '../shared.ts';

export async function refundLadderTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_refund_ladder_sweep');
    if (error) return { ok: false, error: error.message };
    // deno-lint-ignore no-explicit-any
    const d = data as any;
    return { seen: d?.seen, chased: d?.chased, final_calls: d?.final_calls, support_watch: d?.support_watch, ceo_loop: d?.ceo_loop };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE ACCOUNTANT PAYS WHAT THE CEO APPROVED. The seat acts under its own credential
// (cred_fn_accountant -> fn.accountant), so the run is the accountant's, not this watchdog's.
export async function accountantRefundTick(): Promise<unknown> {
  try {
    const secret = await sec('cred_fn_accountant');
    if (!secret) return { ok: false, error: 'cred_fn_accountant is not in app_secrets' };
    const r = await fetch(FN + '/accountant', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: secret, action: 'execute_refunds' }), signal: AbortSignal.timeout(55000),
    });
    // deno-lint-ignore no-explicit-any
    const j = await r.json().catch(() => null) as any;
    return { status: r.status, paused: j?.paused ?? null, executed: Array.isArray(j?.results) ? j.results.length : null };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE ACCOUNTANT'S DUTIES (14 Sep 2026, founder: "yea add them all" / "yea add them"). Called every
// tick; fn_accountant_duties_due inside the seat makes it hourly. Under the seat's own credential, so
// the run is the accountant's. The result names only counts: this endpoint is public and secretless.
export async function accountantDutiesTick(): Promise<unknown> {
  try {
    const secret = await sec('cred_fn_accountant');
    if (!secret) return { ok: false, error: 'cred_fn_accountant is not in app_secrets' };
    const r = await fetch(FN + '/accountant', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: secret, action: 'duties' }), signal: AbortSignal.timeout(55000),
    });
    // deno-lint-ignore no-explicit-any
    const j = await r.json().catch(() => null) as any;
    return { status: r.status, skipped: j?.skipped ? true : false, ok: j?.ok ?? null,
             errors: Array.isArray(j?.result?.errors) ? j.result.errors.length : null };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

export async function vatThresholdTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_accountant_vat_threshold_check', { p_notify: true });
    if (error) return { ok: false, error: error.message };
    return data;
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE ACCOUNTANT'S WEEKLY FINANCIAL REPORT HANGS HERE FOR THE FOURTH TIME, AND FOR THE SAME REASON.
// The founder, 9 Sep 2026: the accountant must "create weekly report as pdf and share it with me and
// the CEO". A weekly report needs a schedule and pg_cron is not one any more, so the once-per-ISO-week
// decision lives in fn_accountant_weekly_report_tick where Asia/Dubai is a real timezone.
// It differs from the other three in ONE way: Postgres cannot render a PDF. The tick returns the
// pdf_native block list it stored at generation, this function renders it, and
// fn_accountant_weekly_report_attach_pdf takes the result and delivers to both recipients. A render
// failure is handed back as p_error, the report row is RETAINED with the reason, and the next tick
// re-renders from the same stored blocks -- so an unavailable PDF service delays a report and never
// loses one. strict_glyphs is true because this document is a financial statement: a character the
// fonts cannot draw would vanish out of a money figure with nothing saying so, and nobody re-reads
// this against a source. Swallowed like the other three: a report must never take the watchdog down.
export async function accountantWeeklyTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_accountant_weekly_report_tick');
    if (error) return { ok: false, error: error.message };
    // deno-lint-ignore no-explicit-any
    const t = data as any;
    if (!t?.pdf_pending || !t?.pdf_blocks || !t?.id) return t;
    const secret = await sec('cred_fn_resilience_ping');
    let path: string | null = null, url: string | null = null, bytes: number | null = null, err: string | null = null;
    try {
      const r = await fetch(FN + '/pdf_native', {
        method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
        body: JSON.stringify({
          __secret: secret, title: t.subject, blocks: t.pdf_blocks,
          bucket: 'agent-docs', folder: 'accountant/weekly',
          name: String(t.report_key || 'weekly_financial_report').replace(/[^\w.-]+/g, '_'),
          options: { letterhead: true, strict_glyphs: true },
        }), signal: AbortSignal.timeout(55000),
      });
      const j = await r.json().catch(() => null);
      if (r.ok && j?.ok && j?.path) { path = j.path; url = j.url ?? null; bytes = j.bytes ?? null; }
      else err = 'pdf_native ' + r.status + ': ' + JSON.stringify(j ?? {}).slice(0, 400);
    } catch (e) { err = 'pdf_native unreachable: ' + String((e as Error)?.message || e); }
    const { data: att, error: aerr } = await admin.rpc('fn_accountant_weekly_report_attach_pdf', {
      p_id: t.id, p_bucket: 'agent-docs', p_path: path, p_url: url, p_bytes: bytes, p_error: err,
    });
    // A render or attach failure keeps the report for the next tick AND is a failed step until it heals.
    if (aerr) return { ...t, pdf_blocks: undefined, pdf_error: err, ok: false, error: 'attach: ' + aerr.message };
    return { ...t, pdf_blocks: undefined, delivery: att, ...(err ? { ok: false, error: err } : {}) };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE ACCOUNTANT'S DAILY OPENROUTER METER HANGS HERE FOR THE FIFTH TIME, AND FOR THE SAME REASON.
// The founder, 9 Sep 2026: "the accountant need to be tracking open router daily expense with a
// breakdown of where it was used. which agent used it and for what, like a proper log."
//
// WHY A METER AND NOT A DAILY ENDPOINT. Probed with the real key on 9 Sep 2026:
//   GET /api/v1/credits  -> 200  {"data":{"total_credits":210,"total_usage":195.92587941}}
//   GET /api/v1/key      -> 200  usage_daily 0, usage_monthly 0, limit_remaining 4.07412059
//   GET /api/v1/activity -> 403  "Only management keys can fetch activity for an account"
// The endpoint that would hand us a day's spend directly is refused to the key we hold, and this
// function does not ask the founder to mint a management key. So the day is read the way a utility
// bill is read: /api/v1/credits returns a MONOTONIC lifetime total_usage, and two readings either
// side of a day differ by exactly what that day cost. Every ~15 minutes is the sampling rate that
// makes "the last reading of the day" a tight bound on midnight.
//
// A FAILED READING IS STILL RECORDED, with ok:false and the error. That is deliberate and it is
// the whole reason the reconciliation can be honest: a gap in the meter is what turns a day's
// basis from 'measured' to 'unknown', and a dropped failure would let a gap look like a quiet day.
// Swallowed like the other four: bookkeeping must never take the watchdog down.
export async function openrouterMeterTick(): Promise<unknown> {
  const reading: Record<string, unknown> = { ok: false };
  try {
    const key = await sec('openrouter_api_key');
    if (!key) {
      reading.err = 'app_secrets.openrouter_api_key is missing or empty, so the meter cannot be read';
    } else {
      const H = { Authorization: 'Bearer ' + key };
      const [cr, kr] = await Promise.all([
        fetch('https://openrouter.ai/api/v1/credits', { headers: H, signal: AbortSignal.timeout(15000) })
          .then(r => r.json()).catch((e) => ({ __err: String((e as Error)?.message || e) })),
        fetch('https://openrouter.ai/api/v1/key', { headers: H, signal: AbortSignal.timeout(15000) })
          .then(r => r.json()).catch((e) => ({ __err: String((e as Error)?.message || e) })),
      ]);
      // deno-lint-ignore no-explicit-any
      const c = (cr as any)?.data, k = (kr as any)?.data;
      // total_usage from /credits is THE meter. Everything else is corroborating. If it is absent
      // the reading is not ok, even when /key answered — half a reading cannot close a day.
      if (c && typeof c.total_usage === 'number') {
        reading.ok = true;
        reading.cumulative_usd = c.total_usage;
        reading.credits_total_usd = c.total_credits ?? null;
      } else {
        reading.err = 'credits: ' + JSON.stringify(cr ?? {}).slice(0, 300);
      }
      if (k) {
        reading.usage_daily_usd = k.usage_daily ?? null;
        reading.usage_monthly_usd = k.usage_monthly ?? null;
        reading.limit_remaining_usd = k.limit_remaining ?? null;
        reading.key_label = k.label ?? null;
        // The key endpoint carries its own lifetime `usage`; when /credits failed it is the only
        // meter we have, so it is used rather than losing the reading entirely.
        if (!reading.ok && typeof k.usage === 'number') {
          reading.ok = true; reading.cumulative_usd = k.usage;
          reading.err = String(reading.err ?? '') + ' [fell back to /api/v1/key usage]';
        }
      } else {
        reading.err = String(reading.err ?? '') + ' key: ' + JSON.stringify(kr ?? {}).slice(0, 200);
      }
    }
  } catch (e) { reading.err = String((e as Error)?.message || e).slice(0, 400); }
  try {
    const { data, error } = await admin.rpc('fn_accountant_openrouter_tick', { p_reading: reading });
    if (error) return { ok: false, error: error.message, reading };
    return data;
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e), reading }; }
}
