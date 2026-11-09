// Shared by the ticks of resilience_ping: the service-role client, the function base URL, the JSON
// responder, the app_secrets reader and the gateway headers. Module-level, defined once here and imported.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { httpHopError } from './steps.ts';
import { timedFetch } from '../_shared/timed_fetch.ts';
export const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
export const FN = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
export const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
export async function sec(k: string): Promise<string> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
// A SEAT DEPLOYED WITH verify_jwt ON IS REFUSED AT THE PLATFORM GATEWAY BEFORE ITS OWN CODE RUNS, unless a
// signed JWT travels with the call. Measured 15 Sep 2026: accountant is verify_jwt=true, and in 24 hours the
// gateway answered 151 calls to it with HTTP 401 — the refund and duties ticks, which sent no Authorization.
// So no accountant duty run had ever been recorded. The service key only opens the gateway; inside, the
// seat still decides the caller from __secret (whoami in accountant/index.ts), as sales_engineer does.
export const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
export const GATEWAY = { Authorization: `Bearer ${SERVICE_KEY}`, apikey: SERVICE_KEY };

// THE TWO SLOW STEPS RUN DETACHED, IN THEIR OWN INVOCATION (12 Oct 2026, it_engineer).
// Measured on production that morning: `marketing` (ewma 54.5 s) timed out at its 55 s fetch on every run
// from 03:46 UTC - the marketing seat's twelve duties had grown from ~46 s to past 55 s, so the tick
// aborted the wait and recorded "Signal timed out." - and `itlater` cost 52-75 s inline. The plan admits
// its stalest step whatever it costs, so whichever of the two was stalest took most of the 70 s budget and
// `seatDuties` (6 s) was deferred tick after tick: the sales engineer's 15- and 30-minute duties did not
// start from 09:15 to 10:35 UTC.
// Now the tick only KICKS them: one authenticated POST to this same function with {detached: <name>}, which
// answers 202 at once and does the work under EdgeRuntime.waitUntil, with its own wall clock and its own
// timeout (DETACHED_MS, 120 s, raced over the whole run) instead of the tick's. resilience_step's last_ok_at and
// ewma for these two now record only the KICK; whether the work passed is the duty:detached_<name> findings. The tick's cost for each is the kick (~1 s), so neither can
// starve another step again, and whatever the marketing seat adds to its duties (lead sourcing, #1304)
// never runs inside the tick. The detached run settles its own failures as IT findings under duty
// detached_<name>, one per failing sub-step, closed when it passes. A detached call never writes the
// fn:resilience_ping observe row, so it can never make a dead scheduler look alive.
// 120 s for the run itself, raced in runDetached so a hung RPC is cut off with time left inside the ~150 s
// wall clock for fn_it_duty_settle to record it; the marketing fetch waits the same 120 s.
export const DETACHED_MS = 120_000;
export async function kickDetached(name: string): Promise<unknown> {
  try {
    const r = await timedFetch(FN + '/resilience_ping', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY }, body: JSON.stringify({ detached: name }),
    }, 15_000);
    const j = await r.json().catch(() => null) as { started?: boolean } | null;
    return r.ok && j?.started === true ? { ok: true, started: true }
      : { ok: false, error: httpHopError('resilience_ping detached ' + name, r.status, j) };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}
