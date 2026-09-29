// Run the kb_chunks embedding backfill, demand-first, entirely through the database.
//
// WHY THIS EXISTS. The old path was: pg_cron -> fn_kernel_cron_exec -> net.http_post -> the kb_embed
// edge function -> fn_kb_embed_claim. Three of those four are gone (pg_cron emptied 7 Sep 17:51 UTC
// on the founder's instruction; fn_kernel_cron_exec and phase_c_system_execution_wrapper dropped
// with it; supabase/functions/kb_embed deleted 8 Sep by commit 182308b). Only the picker survived.
//
// The replacement needs no edge deployment and no pg_cron: fn_kb_embed_dispatch queues one
// net.http_post per chunk to ai_gateway {action:'embed'} -- deployed, ACTIVE, and carrying the same
// FREE in-region gte-small session -- and fn_kb_embed_harvest writes the vectors back. This script
// is just the pump; the same two routines are what a scheduler calls via fn_kb_embed_tick.
//
// MEASURED 9 Sep 2026 on production: 500 dispatched, 0 failed. pg_net resolves ~200 requests per
// drain cycle, so the loop dispatches, waits, harvests, and repeats. The old cron cadence achieved
// 33.7 rows/min (mean of 26 full hours, 6-7 Sep); this path is limited by pg_net's drain rate
// rather than by a 7-second edge budget.
//
// COST: the model is free and in-region. The only spend is one Supabase edge invocation per chunk.
//
//   node scripts/kb/run_embed_backfill.mjs [--batch=400] [--max-tier=4] [--minutes=30]
import { readFileSync } from 'node:fs';

const PROD = 'htdblwldjkcgjvmqkbeh';
const arg = (n, d) => (process.argv.find(a => a.startsWith(`--${n}=`)) || `--${n}=${d}`).split('=').slice(1).join('=');
const BATCH = Math.max(1, Math.min(Number(arg('batch', 400)), 1000));
const MAX_TIER = Math.max(1, Math.min(Number(arg('max-tier', 4)), 4));
const MINUTES = Number(arg('minutes', 30));
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();

const sleep = (ms) => new Promise(r => setTimeout(r, ms));
// A 429 from the Management API throttler means the statement never ran, so it is the one answer that
// is safe to retry for a write like fn_kb_embed_dispatch. Run 36544186787 (29 Sep) died on the first
// query with "ThrottlerException: Too Many Requests". Any other status still fails at once.
const q = async (sql) => {
  for (let i = 0; ; i++) {
    const r = await fetch(`https://api.supabase.com/v1/projects/${PROD}/database/query`, {
      method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: sql }),
    });
    if (r.status === 429 && i < 5) { console.error(`429 throttled (attempt ${i + 1}/6), waiting`); await sleep(5000 * 2 ** i); continue; }
    if (!r.ok) throw new Error(`${r.status}: ${(await r.text()).slice(0, 300)}`);
    return r.json();
  }
};
const embedded = async () => Number((await q('select count(*) n from public.kb_chunks where embedding_gte is not null'))[0].n);

const t0 = Date.now();
const deadline = t0 + MINUTES * 60_000;
const start = await embedded();
console.log(`start: ${start} embedded; batch=${BATCH} max_tier=${MAX_TIER} for ${MINUTES} min`);

let cycles = 0, written = 0, failed = 0, loopErrors = 0, refused = '', drained = false;
while (Date.now() < deadline) {
  try {
    const d = (await q(`select public.fn_kb_embed_dispatch(${BATCH}, ${MAX_TIER}) r`))[0].r;
    if (!d.ok) { refused = JSON.stringify(d).slice(0, 200); console.log('dispatch refused:', d); break; }
    if (d.queued === 0) { drained = true; console.log('nothing left to claim at this tier'); break; }
    // pg_net resolves roughly 200 requests per drain cycle; give the queue time before harvesting.
    await sleep(Math.max(4000, Math.ceil(d.queued / 200) * 6000));
    const h = (await q('select public.fn_kb_embed_harvest() r'))[0].r;
    written += h.embedded; failed += h.failed; cycles++;
    const mins = (Date.now() - t0) / 60_000;
    console.log(`cycle ${cycles}: queued ${d.queued}, embedded ${h.embedded}, failed ${h.failed}, `
      + `inflight ${h.still_inflight} | total ${written} in ${mins.toFixed(1)} min = ${(written / mins).toFixed(1)}/min`);
  } catch (e) {
    loopErrors++;
    console.log('cycle error, backing off 15s:', String(e).slice(0, 200));
    await sleep(15000);
  }
}

// Anything still in flight when the clock runs out is harvested rather than abandoned.
const last = (await q('select public.fn_kb_embed_harvest() r'))[0].r;
written += last.embedded;
const end = await embedded();
const mins = (Date.now() - t0) / 60_000;
console.log(`done: ${end - start} newly embedded in ${mins.toFixed(1)} min = ${((end - start) / mins).toFixed(1)}/min `
  + `(${failed} failed). Total embedded now ${end}.`);

// THE RUN LEAVES A ROW, SO ITS ABSENCE IS A FINDING (17 Sep 2026, it_engineer).
// This backfill wrote nothing to agent_runs, so nothing could tell a night it ran from a night it did
// not: kb-embed-backfill.yml failed six consecutive scheduled runs, 10-15 Sep, and the estate never
// said a word — the script was merged to a branch and the workflow to main, so every scheduled run
// died on MODULE_NOT_FOUND. fn_it_duty_ran is the row fn_it_workflow_heartbeats reads (the same key
// shape as duty:dependency, duty:platform and duty:smoke), so a run that does not happen is now a
// finding within 36 hours. It is written LAST on purpose: a run that fell over did not beat.
// A RUN THAT DID NOTHING BECAUSE IT WAS BROKEN MUST NOT BEAT (found in review, 18 Sep 2026).
// fn_it_duty_ran writes status='ok' unconditionally and the heartbeat reads only max(started_at), so
// the row's existence IS the claim that this workflow ran. Doing no work is only honest in one case:
// the queue was empty. A refused dispatch, or a run where every cycle threw, is a failure and leaves
// NO row — so the heartbeat raises it within 36 h — and exits non-zero so the Action goes red too.
const brokeWithoutWorking = cycles === 0 && !drained;
const result = JSON.stringify({
  newly_embedded: end - start, embedded_total: end, minutes: Number(mins.toFixed(1)),
  cycles, failed, loop_errors: loopErrors, drained, refused: refused || null,
}).replace(/'/g, "''");   // the only metacharacter a single-quoted SQL literal has
if (brokeWithoutWorking) {
  console.error(`no cycle completed: ${refused ? 'dispatch refused ' + refused : loopErrors + ' cycle error(s)'}. `
    + 'Not writing a kb_embed heartbeat over a run that embedded nothing.');
  process.exit(1);
}
await q(`select public.fn_it_duty_ran('kb_embed', '${result}'::jsonb)`);
