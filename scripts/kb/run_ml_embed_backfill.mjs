// The pump for the multilingual backfill (knowledge_vector_ml). Seat: it_engineer. 23 Sep 2026.
//
// The embedding happens in ai_gateway (action 'embed_ml_tick': claim up to 16 rows, embed them with
// multilingual-e5-small in the edge runtime, write them back) — free, in-region, not OpenRouter. This script
// is only the clock: it calls that action back to back for --minutes, two calls in flight, and stops early
// when the queue is empty or fn_ml_embed_claim says the gate is shut or today's cap is reached. The gate
// (app_secrets ml_embed_golive) and the cap (ml_embed_daily_cap) are enforced in the database, not here.
// Every write is one row's chunks; nothing here issues a bulk statement.
//
//   node scripts/kb/run_ml_embed_backfill.mjs [--minutes=30] [--limit=16] [--parallel=2]
import { sql, PROJECT_REF } from '../lib/db.mjs';

const arg = (n, d) => (process.argv.find((a) => a.startsWith(`--${n}=`)) || `--${n}=${d}`).split('=').slice(1).join('=');
const MINUTES = Number(arg('minutes', 30));
const LIMIT = Math.max(1, Math.min(Number(arg('limit', 16)), 16));
const PARALLEL = Math.max(1, Math.min(Number(arg('parallel', 2)), 4));

const secret = (await sql(`select value from public.app_secrets where key = 'cred_fn_ai'`))[0]?.value;
if (!secret) { console.error('no cred_fn_ai in app_secrets'); process.exit(2); }
const state = async () => (await sql(`select (select count(*) from public.knowledge_vector_ml where chunk = 0)::int rows_embedded,
  (select count(*) from public.knowledge_vector_ml)::int vectors, (select priority_complete_at from public.knowledge_ml_status) priority_complete_at,
  public.fn_ml_read_space() read_space`, { readOnly: true }))[0];

const t0 = Date.now(), deadline = t0 + MINUTES * 60_000;
console.log('start:', JSON.stringify(await state()));
let calls = 0, embedded = 0, stale = 0, failed = 0, errors = 0, stop = '';
async function worker() {
  while (!stop && Date.now() < deadline) {
    try {
      const r = await fetch(`https://${PROJECT_REF}.supabase.co/functions/v1/ai_gateway`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ __secret: secret, fn: 'ml_embed_backfill', action: 'embed_ml_tick', limit: LIMIT }),
        signal: AbortSignal.timeout(120_000),
      });
      const j = await r.json().catch(() => ({}));
      calls++; embedded += j.embedded ?? 0; stale += j.stale ?? 0; failed += j.failed ?? 0;
      if (j.reason) stop = String(j.reason);
      else if (j.claimed === 0) stop = 'queue empty';
      else if (!r.ok) { errors++; await new Promise((s) => setTimeout(s, 5000 * Math.min(errors, 6))); }
      if (errors >= 10) stop = `10 failed calls (last HTTP ${r.status}: ${JSON.stringify(j).slice(0, 200)})`;
      if (calls % 20 === 0) {
        const m = (Date.now() - t0) / 60_000;
        console.log(`${calls} calls: embedded ${embedded}, stale ${stale}, failed ${failed} | ${(embedded / m).toFixed(0)} rows/min`);
      }
    } catch (e) { errors++; if (errors >= 10) stop = 'errors: ' + String(e.message).slice(0, 200); }
  }
}
await Promise.all(Array.from({ length: PARALLEL }, worker));
console.log(`stopped: ${stop || 'time'}; ${calls} calls, embedded ${embedded}, stale ${stale}, failed ${failed}`);
console.log('end:', JSON.stringify(await state()));
process.exit(failed > 0 && embedded === 0 ? 1 : 0);
