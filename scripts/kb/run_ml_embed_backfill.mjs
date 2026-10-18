// THE MULTILINGUAL BACKFILL, embedded on the runner. Seat: it_engineer. 23-24 Sep 2026.
//
// The backlog (~165,000 rows, 150,103 of them kb_chunks) is embedded HERE, in Node on the GitHub runner
// (.github/workflows/ml-embed-backfill.yml), with the SAME model files the edge path loads: the trimmed
// multilingual-e5-small from the public Storage bucket (_shared/ml_embed_recipe.ts). An edge worker embeds 4 rows
// a call at most (8 rows took 1.3 s of its CPU, 16 were refused, measured 24 Sep 2026), so the edge keeps only the
// trickle (resilience_ping -> embed_ml 'tick') and live questions. Free (runner minutes), not OpenRouter.
//
// The queue is the database's: fn_ml_embed_claim (the gate app_secrets ml_embed_golive, the daily cap
// ml_embed_daily_cap) hands out rows, fn_ml_embed_write stores a vector only if the row's text still has the hash
// that was embedded. support_knowledge and ceo_knowledge rows also need their gte-small vector: that one comes
// from embed_ml's 'gte' action, i.e. Supabase.ai gte-small itself, so the gte space never mixes in a second copy
// of the model. Writes are one statement per batch of at most 16 fn_ml_embed_write calls, one row each.
//
//   npm i --no-save @huggingface/transformers@3.8.1
//   node scripts/kb/run_ml_embed_backfill.mjs [--minutes=40] [--claim=64]
import { sql, lit, PROJECT_REF } from '../lib/db.mjs';
import { ML_MODEL, modelHost, mlRowText, rowText } from './ml_embed_recipe.mjs';

const arg = (n, d) => (process.argv.find((a) => a.startsWith(`--${n}=`)) || `--${n}=${d}`).split('=').slice(1).join('=');
const MINUTES = Number(arg('minutes', 40));
const CLAIM = Math.max(1, Math.min(Number(arg('claim', 64)), 64));
const GTE_ALSO = new Set(['support_knowledge', 'ceo_knowledge']);   // _shared/ml_embed.ts GTE_ALSO
const URL = `https://${PROJECT_REF}.supabase.co`;

const { pipeline, env } = await import('@huggingface/transformers');
env.allowLocalModels = false;
Object.assign(env, modelHost(ML_MODEL, URL));
const embed = await pipeline('feature-extraction', ML_MODEL, { dtype: 'q8' });

const secret = (await sql(`select value from public.app_secrets where key = 'cred_fn_ai'`, { readOnly: true }))[0]?.value;
async function gte(text) {
  const r = await fetch(`${URL}/functions/v1/embed_ml`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ __secret: secret, fn: 'ml_embed_backfill', action: 'gte', text }), signal: AbortSignal.timeout(30_000) });
  const j = await r.json().catch(() => ({}));
  return r.ok && typeof j.embedding === 'string' ? j.embedding : null;
}
const state = async () => (await sql(`select (select count(*) from public.knowledge_vector_ml)::int vectors,
  (select priority_complete_at from public.knowledge_ml_status) priority_complete_at, public.fn_ml_read_space() read_space`))[0];   // not the read-only role: it cannot EXECUTE the service-role-only fn_ml_read_space (42501, 24 Sep 2026)

const t0 = Date.now(), deadline = t0 + MINUTES * 60_000;
console.log('start:', JSON.stringify(await state()));
let embedded = 0, stale = 0, failed = 0, stop = '';
while (!stop && Date.now() < deadline) {
  const c = (await sql(`select public.fn_ml_embed_claim(${CLAIM}) c`))[0].c;
  const rows = Array.isArray(c?.rows) ? c.rows : [];
  if (c?.reason) { stop = c.reason; break; }
  if (!rows.length) { stop = 'queue empty'; break; }
  for (let i = 0; i < rows.length; i += 16) {
    const part = rows.slice(i, i + 16);
    const texts = part.map((r) => mlRowText(r.src, r.title, r.body));
    const v = (await embed(texts, { pooling: 'mean', normalize: true })).tolist();
    const calls = [];
    for (const [k, r] of part.entries()) {
      if (v[k]?.length !== 384) { failed++; continue; }
      const g = GTE_ALSO.has(r.src) ? await gte(rowText(r.title, r.body)) : null;
      if (GTE_ALSO.has(r.src) && !g) { failed++; continue; }
      calls.push(`public.fn_ml_embed_write(${lit(r.src)}, ${lit(r.row_id)}, ${lit(r.hash)}, ${lit('[' + v[k].join(',') + ']')}::vector(384), ${g ? lit(g) + '::vector(384)' : 'null'})`);
    }
    if (!calls.length) continue;
    const res = await sql(`select ${calls.map((x, n) => `${x} w${n}`).join(', ')}`);
    for (const val of Object.values(res[0] ?? {})) { if (val === true) embedded++; else stale++; }
  }
  const m = (Date.now() - t0) / 60_000;
  console.log(`embedded ${embedded}, stale ${stale}, failed ${failed} | ${(embedded / m).toFixed(0)} rows/min`);
  if (failed > 50 && embedded === 0) stop = `${failed} rows failed and none embedded`;
}
console.log(`stopped: ${stop || 'time'}; embedded ${embedded}, stale ${stale}, failed ${failed}`);
console.log('end:', JSON.stringify(await state()));
process.exit(failed > 0 && embedded === 0 ? 1 : 0);
