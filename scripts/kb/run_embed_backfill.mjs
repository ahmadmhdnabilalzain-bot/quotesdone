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

const q = async (sql) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  if (!r.ok) throw new Error(`${r.status}: ${(await r.text()).slice(0, 300)}`);
  return r.json();
};
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const embedded = async () => Number((await q('select count(*) n from public.kb_chunks where embedding_gte is not null'))[0].n);

const t0 = Date.now();
const deadline = t0 + MINUTES * 60_000;
const start = await embedded();
console.log(`start: ${start} embedded; batch=${BATCH} max_tier=${MAX_TIER} for ${MINUTES} min`);

let cycles = 0, written = 0, failed = 0;
while (Date.now() < deadline) {
  try {
    const d = (await q(`select public.fn_kb_embed_dispatch(${BATCH}, ${MAX_TIER}) r`))[0].r;
    if (!d.ok) { console.log('dispatch refused:', d); break; }
    if (d.queued === 0) { console.log('nothing left to claim at this tier'); break; }
    // pg_net resolves roughly 200 requests per drain cycle; give the queue time before harvesting.
    await sleep(Math.max(4000, Math.ceil(d.queued / 200) * 6000));
    const h = (await q('select public.fn_kb_embed_harvest() r'))[0].r;
    written += h.embedded; failed += h.failed; cycles++;
    const mins = (Date.now() - t0) / 60_000;
    console.log(`cycle ${cycles}: queued ${d.queued}, embedded ${h.embedded}, failed ${h.failed}, `
      + `inflight ${h.still_inflight} | total ${written} in ${mins.toFixed(1)} min = ${(written / mins).toFixed(1)}/min`);
  } catch (e) {
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
