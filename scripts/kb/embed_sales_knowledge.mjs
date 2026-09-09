// Embed public.sales_knowledge through the FREE in-region path.
//
// ai_gateway {action:'embed'} runs `new Supabase.ai.Session('gte-small')` inside the edge runtime
// (supabase/functions/ai_gateway/index.ts:54-64) and returns a 384-dimension vector. It short-
// circuits BEFORE routing, budget and every model call, so it is not OpenRouter and the founder's
// OpenRouter hold does not reach it. Verified by reading that file, not assumed from the name.
//
// If the gateway refuses, the column stays NULL and this says so. A fabricated vector would make
// the HNSW index return confident nonsense; the lexical GIN index works either way.
//
//   node scripts/kb/embed_sales_knowledge.mjs [--limit=N]

import { sql, PROJECT_REF } from '../lib/db.mjs';

const arg = (n, d) => (process.argv.find((a) => a.startsWith(`--${n}=`)) || `--${n}=${d}`).split('=').slice(1).join('=');
const LIMIT = Number(arg('limit', 100000));
const CONC = 6;

const secret = (await sql(`select value from public.app_secrets where key = 'cred_fn_ai'`))[0]?.value;
if (!secret) { console.error('no cred_fn_ai in app_secrets'); process.exit(2); }

const rows = await sql(`select record_id, title, content from public.sales_knowledge
                         where embedding_gte is null order by record_id limit ${LIMIT}`);
console.log(`${rows.length} record(s) without an embedding`);
if (!rows.length) process.exit(0);

let ok = 0, failed = 0; const reasons = new Map();
const note = (r) => reasons.set(r, (reasons.get(r) || 0) + 1);

async function one(r) {
  try {
    const res = await fetch(`https://${PROJECT_REF}.supabase.co/functions/v1/ai_gateway`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ __secret: secret, fn: 'embed_sales_knowledge',
        action: 'embed', text: r.title + '\n' + r.content }),
    });
    if (!res.ok) { failed++; note('HTTP ' + res.status + ': ' + (await res.text()).slice(0, 120)); return null; }
    const j = await res.json();
    // embed() swallows its own errors and returns null. A null here is a refusal, not a vector.
    if (!j.embedding) { failed++; note('gateway returned no embedding'); return null; }
    ok++;
    return [r.record_id, j.embedding];
  } catch (e) { failed++; note(String(e.message).slice(0, 120)); return null; }
}

const lit = (v) => "'" + String(v).replace(/'/g, "''") + "'";
for (let i = 0; i < rows.length; i += 25) {
  const batch = rows.slice(i, i + 25);
  const got = [];
  for (let j = 0; j < batch.length; j += CONC) {
    got.push(...(await Promise.all(batch.slice(j, j + CONC).map(one))).filter(Boolean));
  }
  if (got.length) {
    const values = got.map(([id, v]) => `(${lit(id)}, ${lit(v)}::vector(384))`).join(',');
    await sql(`update public.sales_knowledge k set embedding_gte = v.e
                 from (values ${values}) as v(id, e) where k.record_id = v.id`);
  }
  process.stdout.write(`${i + batch.length} `);
}

console.log(`\nembedded ${ok}, failed ${failed}`);
for (const [r, n] of reasons) console.log(`  ${n} x ${r}`);
const c = await sql(`select count(*) total, count(embedding_gte) embedded from public.sales_knowledge`);
console.log('IN THE DATABASE: ' + JSON.stringify(c[0]));
process.exit(failed && !ok ? 1 : 0);
