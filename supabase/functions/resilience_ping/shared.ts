// Shared by the ticks of resilience_ping: the service-role client, the function base URL, the JSON
// responder, the app_secrets reader and the gateway headers. Module-level, defined once here and imported.
import { createClient } from 'jsr:@supabase/supabase-js@2';
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
// Now the tick only KICKS them: one authenticated POST to this same function with {detached: <name>} (since 19 Nov 2026 made by
// the database through pg_net, see kickDetached), which
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
// THE KICK GOES THROUGH THE DATABASE, NOT FROM THIS FUNCTION TO ITSELF (it_engineer, 19 Nov 2026).
// MEASURED (production, 18-19 Nov 2026, function_edge_logs and agent_runs): the edge runtime rate-limits the function-to-function
// fetches of one request chain ("Rate limit exceeded for trace <the tick's request id>. Retry after 20-50 s", i.e. a one-minute
// window from the tick's start), and a self-POST to resilience_ping keeps the kicked run inside the tick's chain. On the :15 and
// :45 ticks two runs are kicked (supportVoice, caseCatchup); on :00 and :30 also marketing and itlater, and itlater's own run
// kicks heldReplay and routineJudgements, so 3-6 self-calls two deep. Over 96 ticks: 48 with at most 2 kicks drained the
// outbox 47 times; 48 with 3 or more drained it 9 times, and every step after the limit failed (duty:heartbeat:outbox, seen 380
// times; whatsapp, supportVoice, specoffer the same tick). Call volume did not decide it: a tick of 162 calls with 2 kicks drained.
// fn_resilience_detached_kick posts the run through pg_net, a request that ENTERS the platform like the Vercel cron does, so each
// detached run is a chain of its own and the tick's chain holds no recursion. A kick that cannot be made answers ok:false here
// (this step's finding); a kicked run that answered non-2xx, or was never answered, is reported by the NEXT kick of the same name,
// so a child that never starts is a finding too, one beat late. The run itself still settles duty:detached_<name>.
// prevented by: resilience_ping/detached_kick_is_not_a_self_call.test.ts,
// scripts/sql/the_heartbeat_kicks_its_detached_runs_through_the_database_so_every_tick_drains_the_outbox.sql (its probe)
export async function kickDetached(name: string): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_resilience_detached_kick', { p_name: name });
    if (error) return { ok: false, error: 'fn_resilience_detached_kick ' + name + ': ' + error.message };
    const j = data as { ok?: boolean; started?: boolean; error?: string } | null;
    return j?.ok === true && j.started === true ? { ok: true, started: true, request: (j as Record<string, unknown>).request }
      : { ok: false, error: String(j?.error || 'fn_resilience_detached_kick ' + name + ' did not start it') };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}
