// observe.ts — the eyes. One implementation, not 63 copies.
//
// MEASURED 9 Sep 2026, before this file existed: 31 of 63 edge functions captured NOTHING when
// they failed. `public.error_events` had 0 rows, ever. `customer_api` and `customer_portal` — the
// whole customer registration path — had no failure capture at all, so a broken registration would
// have been noticed first by a customer complaining. That is what this closes.
//
// WHY agent_runs AND NOT error_events. agent_runs is the estate's existing run log: send_outbox,
// login_otp, accountant and sales_engineer already write it, `fn_agents_board`, `fn_watch_failed_runs`,
// `fn_runner_silence_watch`, `v_ai_agent_health` and a dozen other routines already read it, and
// `trg_audit_agent_run` already mirrors every row into os_audit_log. error_events has one index and
// no readers. Writing somewhere new would have created a second, unwatched ledger — the exact
// failure this file exists to fix. Nothing new was needed, so nothing new was built.
//
// THE NAMESPACE. Rows go in under `fn:<slug>` (e.g. `fn:customer_api`), never a bare slug. That
// keeps them out of `fn_agents_board` (which LEFT JOINs org_agents.agent_key, so an unmatched name
// is invisible) and makes them trivially selectable for the detection agent. Functions that already
// logged under a bare name — send_outbox, login_otp, accountant, sales_engineer — keep it.
//
// STATUS IS CLASSIFIED, NOT COPIED. A 401 from someone typing the wrong password is not an outage.
// `fn_watch_failed_runs` pages on status='error' and `trg_health_check_agent_threshold` counts
// anything outside ('ok','success','completed','skipped','warn') as a failure, so:
//     5xx or a thrown exception -> 'error'   (a real fault; the watchers may page)
//     4xx                       -> 'warn'    (the caller's fault; recorded, never paged)
//     2xx/3xx                   -> 'ok'
// Marking a rejected password as an outage is the "guard that fires when the system works" defect;
// it would have buried the real signal within a day of launch.
//
// IT MUST NEVER THROW AND NEVER SLOW ANYTHING DOWN. Instrumentation that can take down the thing it
// watches is worse than none. Every write is wrapped, the insert is handed to EdgeRuntime.waitUntil
// so it happens AFTER the response is returned, and if that is unavailable it is fire-and-forget.
// The handler's own Response object is returned untouched: same status, same headers, same body.
//
// ponytail: OK runs are sampled (one row per okEveryMs per isolate, in-memory — no DB read, so the
// throttle itself costs nothing) while EVERY error, and every OK run slower than slowMs, is always
// written. That bounds a busy endpoint at ~1,440 healthy rows/day/isolate and still keeps the whole
// slow tail, which is the half that answers "is this lagging". If per-call latency is ever needed,
// pass okEveryMs: 0.
import { createClient } from 'jsr:@supabase/supabase-js@2';

// deno-lint-ignore no-explicit-any
type Admin = any;
let _admin: Admin | null = null;
function admin(): Admin | null {
  if (_admin) return _admin;
  try {
    const url = Deno.env.get('SUPABASE_URL'), key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!url || !key) return null;
    _admin = createClient(url, key);
    return _admin;
  } catch (_e) { return null; }
}

/** Run a promise after the response has been sent, without ever surfacing its failure. */
function background(p: Promise<unknown>): void {
  const safe = p.catch(() => {});
  // deno-lint-ignore no-explicit-any
  const g = globalThis as any;
  try {
    if (g?.EdgeRuntime && typeof g.EdgeRuntime.waitUntil === 'function') { g.EdgeRuntime.waitUntil(safe); return; }
  } catch (_e) { /* fall through to fire-and-forget */ }
  void safe;
}

export type ObserveStatus = 'ok' | 'warn' | 'error' | 'skipped';

/**
 * HTTP status -> agent_runs.status. Exported because it is the one decision in this file that
 * changes who gets paged, and observe.test.ts asserts it directly.
 *
 * `fn_watch_failed_runs` pages on 'error' and `trg_health_check_agent_threshold` counts anything
 * outside ('ok','success','completed','skipped','warn') as a failure. So 4xx MUST NOT be 'error':
 * a wrong password, an expired unsubscribe link and an unauthenticated poke are the system working.
 */
export function classify(http: number): ObserveStatus {
  if (http >= 500) return 'error';
  if (http >= 400) return 'warn';
  return 'ok';
}

/**
 * Write one run row. Best-effort: it resolves even when the insert fails, and never throws.
 *
 * @param slug    the function slug WITHOUT the `fn:` prefix — this adds it.
 * @param status  see the classification note at the top of this file.
 * @param counts  merged into agent_runs.counts; always carries `ms` when startedAt is given.
 * @param note    free text, truncated to 500 chars (the column every reader already truncates).
 * @param startedAt  Date.now() at the start of the run; makes started_at/finished_at real.
 */
export async function record(
  slug: string,
  status: ObserveStatus,
  counts: Record<string, unknown> = {},
  note = '',
  startedAt?: number,
): Promise<void> {
  try {
    const db = admin();
    if (!db) return;
    const t0 = typeof startedAt === 'number' ? startedAt : Date.now();
    await db.from('agent_runs').insert({
      agent: 'fn:' + slug,
      status,
      counts: { ms: Date.now() - t0, ...counts },
      note: String(note || '').slice(0, 500),
      started_at: new Date(t0).toISOString(),
      finished_at: new Date().toISOString(),
    });
  } catch (_e) { /* instrumentation never breaks the thing it watches */ }
}

export type ObserveOpts = {
  /** Minimum gap between logged healthy runs, per isolate. 0 logs every run. Default 60000. */
  okEveryMs?: number;
  /** A healthy run at or over this many ms is ALWAYS logged, whatever the sampling says. Default 4000. */
  slowMs?: number;
};

/** The path is free to read (no body consumed) and is what separates one route from another. */
function pathOf(req: Request): string {
  try { return new URL(req.url).pathname.slice(0, 120); } catch (_e) { return ''; }
}

/**
 * Which Supabase edge region served this run. The platform routes a call to the region nearest the
 * CALLER, while the database is in ap-southeast-1, so the same request costs ~1s from ap-south-1 and
 * ~3.3s from us-east-1/2 (supplier_portal POST, 21 Sep 2026: p50 967ms ap-south-1, 3,556ms us-east-1,
 * 3,336ms us-east-2 — function_edge_logs). The US calls were the post-deploy E2E smoke on GitHub's
 * runners. Without the region in the row, a smoke run reads as the function getting slower; with it,
 * a latency baseline can compare a region with its own history. SB_REGION is set by the platform;
 * a missing env permission (deno test) or an unset variable gives null.
 */
export function edgeRegion(): string | null {
  try { return Deno.env.get('SB_REGION') || null; } catch (_e) { return null; }
}

/** The counts every observed run carries. `region` is passed in by tests; production reads it. */
export function baseCounts(req: Request, http: number, region: string | null = edgeRegion()) {
  return { http, method: req.method, path: pathOf(req), region };
}

/** Read a failed response's body WITHOUT disturbing the one being returned. */
async function bodyOf(res: Response): Promise<string> {
  try {
    const ct = res.headers.get('content-type') || '';
    // Only text-shaped bodies, and only ones already buffered in memory: cloning a large binary or
    // streaming body to read an error message would cost more than the message is worth.
    if (!/json|text|xml|html|plain/i.test(ct)) return '';
    return (await res.clone().text()).slice(0, 300);
  } catch (_e) { return ''; }
}

/**
 * Wrap a Deno.serve handler so every run records that it ran, how long it took, and how it failed.
 *
 * BEHAVIOUR IS UNCHANGED. The handler's own Response is returned as-is, and an exception it throws
 * is re-thrown after being recorded — same inputs, same outputs, same status codes.
 *
 *     Deno.serve(observe('project_api', async (req) => { ... }));
 */
export function observe(
  slug: string,
  handler: (req: Request) => Response | Promise<Response>,
  opts: ObserveOpts = {},
): (req: Request) => Promise<Response> {
  const okEveryMs = opts.okEveryMs ?? 60_000;
  const slowMs = opts.slowMs ?? 4_000;
  let lastOkAt = 0;
  return async (req: Request): Promise<Response> => {
    const t0 = Date.now();
    let res: Response;
    try {
      res = await handler(req);
    } catch (e) {
      const msg = String((e as Error)?.message || e);
      background(record(slug, 'error', { ...baseCounts(req, 500), threw: true },
        'threw before any response: ' + msg, t0));
      throw e;                       // the caller sees exactly what it saw before
    }
    const ms = Date.now() - t0;
    const http = res.status;
    const base = baseCounts(req, http);
    if (http >= 400) {
      const status = classify(http);
      const cloned = bodyOf(res);    // clone NOW, read in the background
      background((async () => {
        await record(slug, status, base, 'HTTP ' + http + ' — ' + (await cloned), t0);
      })());
    } else if (okEveryMs === 0 || ms >= slowMs || Date.now() - lastOkAt >= okEveryMs) {
      lastOkAt = Date.now();
      background(record(slug, 'ok', base, ms >= slowMs ? 'slow run: ' + ms + 'ms' : '', t0));
    }
    return res;
  };
}
