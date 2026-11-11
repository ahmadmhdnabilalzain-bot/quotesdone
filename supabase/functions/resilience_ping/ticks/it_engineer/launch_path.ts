// resilience_ping ticks owned by the it_engineer seat: the hourly launch-path probe and the portal warm-up. Moved out of ticks/it_engineer.ts unchanged (9 Nov 2026);
// the order the steps run in is still set in resilience_ping/index.ts (STEP_RUN).
import { launchPathAction, launchPathItem, probeLaunchPath } from '../../../_shared/launch_path.ts';
import { FN, admin, sec } from '../../shared.ts';

// THE LAUNCH PATH, HOURLY (21 Sep 2026, it_engineer): the invitation link on both hosts in EN/AR, the
// customer's request page, the portal API, the sign-in code request and the portal functions' health —
// all read-only, none able to reach a person; _shared/launch_path.ts says what each probe asserts.
// Hourly by public.resilience_step (scripts/sql/the_launch_path_is_tested_every_hour.sql), not by
// GitHub Actions: an hourly job is 720 billed minutes a month on the allowance the 15-minute ping was
// moved off for (.github/workflows/resilience-ping.yml).
// A broken path is ONE finding, duty:launch_path:down, held open two clean hours before it closes so a
// blip cannot reopen it and re-email the founder as a recurrence. It reaches him only through
// fn_it_engineer_alert_tick and founder_mail_policy, never from here. This step reports ok:false only
// when it could not settle; a failing probe is the finding, not a failing step.
export async function launchPathTick(): Promise<unknown> {
  try {
    const r = await probeLaunchPath(Deno.env.get('SUPABASE_ANON_KEY')!, fetch, undefined, (await sec('cred_fn_resilience_ping')) || undefined);
    const { data: open } = await admin.from('it_engineer_finding').select('last_seen_at')
      .eq('issue_key', 'duty:launch_path:down').is('closed_at', null).maybeSingle();
    const act = launchPathAction(r.ok, (open?.last_seen_at as string) ?? null);
    if (act !== 'hold') {
      const { error } = await admin.rpc('fn_it_duty_settle', { p_duty: 'launch_path', p_items: act === 'raise' ? [launchPathItem(r)] : [] });
      if (error) return { ok: false, error: 'fn_it_duty_settle: ' + error.message };
    }
    // Counts and probe names only: this endpoint is public.
    return { probes: r.results.length, failed: r.failed.map((x) => x.id), action: act, ms: r.ms };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// KEEP THE PORTAL'S FIVE COLD ISOLATES WARM (14 Sep 2026 e2e finding; reviewed and corrected same
// day). The customer Overview warms kyc, customer_api, customer_portal, project_api and messages_api
// together on every sign-in (CustomerPortal.tsx warmDashboard) — five separate Deno isolates, any
// one of which, cold, adds full V8-boot-plus-module-import latency on top of its query. This closes
// isolate eviction BETWEEN sign-ins; the portal's own warmDashboard already covers a single sign-in.
//
// THE FIRST VERSION OF THIS RELIED ON A 401. That is only confirmed harmless for kyc and
// customer_api; for customer_portal, project_api and messages_api an unauthenticated call could run
// real code before failing, and every one of the five would write a 'warn' row to agent_runs every
// ~15 minutes forever. Each of the five functions now checks `x-qd-warm: 1` as the very first thing
// in its handler — before auth, before any DB read — and returns 204 with no side effect at all.
// verify_jwt:true (customer_api, project_api, messages_api) still requires a signed JWT to pass the
// PLATFORM GATEWAY before the handler ever runs, so the service key travels alongside the warm
// header for those three; kyc and customer_portal (verify_jwt:false) do not need it and are sent it
// anyway for one code path instead of two. A 204 classifies 'ok' in observe.ts (see classify()), so
// none of this can be counted as a failure by any alerting the estate already runs.
//
// Piggybacks on this file's existing ~15min external trigger (.github/workflows/resilience-ping.yml)
// so no new schedule or SQL is needed. Every call is best-effort and swallowed; a warm-ping failure
// must never affect the watchdog's own health verdict.
export async function warmPortal(): Promise<{ fn: string; ms: number; ok: boolean; region?: string | null }[]> {
  // The SUPPLIER journey's four joined 28 Sep 2026 (it_engineer): measured on the 24 Sep walk, each first
  // call to supplier_api, supplier_portal, supplier_pay and claim_lookup paid a 2.5-4.5 s isolate boot —
  // the landing-to-claim step and the Billing tab were almost entirely boot. Each answers x-qd-warm with
  // a 204 before auth or the database, exactly like the five above. login_otp joined 11 Nov 2026 (it_engineer): the
  // certification's slowest code check (2,272 ms in the handler, 11:38:31Z) was on an isolate that booted for it, and
  // login_otp is the door to both portals.
  const targets = ['kyc', 'customer_api', 'customer_portal', 'project_api', 'messages_api',
    'supplier_api', 'supplier_portal', 'supplier_pay', 'claim_lookup', 'login_otp'];
  return Promise.all(targets.map(async (fn) => {
    const t0 = Date.now();
    try {
      // PINNED TO THE PORTAL'S REGION (28 Sep 2026, it_engineer). Unpinned, Supabase runs a function in
      // the region nearest the CALLER, and this caller is wherever the external cron entered, while
      // both portals pin ?forceFunctionRegion=ap-southeast-1 (src/lib/supaEnv.ts FN_REGION). Measured
      // from Dubai: the same x-qd-warm GET unpinned answered from ap-south-1, pinned from
      // ap-southeast-1 - separate isolates. So this ping kept isolates warm that no customer uses.
      const r = await fetch(FN + '/' + fn + '?forceFunctionRegion=ap-southeast-1', { method: 'GET',
        headers: { 'x-qd-warm': '1', Authorization: 'Bearer ' + Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')! },
        signal: AbortSignal.timeout(8000) });
      await r.body?.cancel().catch(() => {}); // release the connection; a 204 has nothing to read
      return { fn, ms: Date.now() - t0, ok: r.status === 204, region: r.headers.get('x-sb-edge-region') };
    } catch (e) { return { fn, ms: Date.now() - t0, ok: false }; }
  }));
}
