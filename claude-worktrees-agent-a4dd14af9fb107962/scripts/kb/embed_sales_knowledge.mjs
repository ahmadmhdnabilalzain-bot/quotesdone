// Embed a knowledge body -- public.sales_knowledge by default, --table for any other -- through the
// FREE in-region path.
//
// ai_gateway {action:'embed'} runs `new Supabase.ai.Session('gte-small')` inside the edge runtime
// (supabase/functions/ai_gateway/index.ts:54-64) and returns a 384-dimension vector. It short-
// circuits BEFORE routing, budget and every model call, so it is not OpenRouter and the founder's
// OpenRouter hold does not reach it. Verified by reading that file, not assumed from the name.
//
// If the gateway refuses, the column stays NULL and this says so. A fabricated vector would make
// the HNSW index return confident nonsense; the lexical GIN index works either way.
//
// GENERALISED 9 Sep 2026 by --table. Every knowledge body in this estate embeds through the same
// free in-region path against the same three columns (record_id, title, content) and the same
// embedding_gte vector(384), so a second copy of this file per table would be the same 45 lines
// with one identifier changed. The table name is validated against an explicit allowlist rather
// than interpolated: it lands inside a SQL statement, and a knowledge-table name is not user input
// today but there is no reason to leave that as the only thing standing between here and an
// injection.
//
// 22 Sep 2026 (customer_support, instruction 763): company_faq joins, keyed on id with question +
// answer as the text -- the recipe its existing vectors were built from (measured: re-embedding FAQ 90
// as question + "\n" + answer reproduces the stored vector at cosine 1.0000). 20 English and all 23
// Arabic approved FAQ rows had none, the fee answers among them, so WhatsApp and the site could not
// reach them by meaning.
//
//   node scripts/kb/embed_sales_knowledge.mjs [--table=sales_knowledge] [--limit=N]
//   node scripts/kb/embed_sales_knowledge.mjs --table=company_faq

import { sql, PROJECT_REF } from '../lib/db.mjs';

const arg = (n, d) => (process.argv.find((a) => a.startsWith(`--${n}=`)) || `--${n}=${d}`).split('=').slice(1).join('=');
const LIMIT = Number(arg('limit', 100000));
const TABLES = ['sales_knowledge', 'accountant_knowledge', 'it_engineer_knowledge', 'company_faq'];
const TABLE = arg('table', 'sales_knowledge');
if (!TABLES.includes(TABLE)) { console.error(`--table must be one of: ${TABLES.join(', ')}`); process.exit(2); }
const CONC = 6;

const secret = (await sql(`select value from public.app_secrets where key = 'cred_fn_ai'`))[0]?.value;
if (!secret) { console.error('no cred_fn_ai in app_secrets'); process.exit(2); }

// company_faq names its columns differently; the alias keeps one code path.
const KEY = TABLE === 'company_faq' ? 'id' : 'record_id';
const COLS = TABLE === 'company_faq' ? 'id as record_id, question as title, answer as content' : 'record_id, title, content';
const rows = await sql(`select ${COLS} from public.${TABLE}
                         where embedding_gte is null order by ${KEY} limit ${LIMIT}`);
console.log(`${rows.length} record(s) without an embedding`);
if (!rows.length) process.exit(0);

let ok = 0, failed = 0; const reasons = new Map();
const note = (r) => reasons.set(r, (reasons.get(r) || 0) + 1);

async function one(r) {
  try {
    const res = await fetch(`https://${PROJECT_REF}.supabase.co/functions/v1/ai_gateway`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ __secret: secret, fn: 'embed_' + TABLE,
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
    await sql(`update public.${TABLE} k set embedding_gte = v.e
                 from (values ${values}) as v(id, e) where k.${KEY}::text = v.id::text`);
  }
  process.stdout.write(`${i + batch.length} `);
}

console.log(`\nembedded ${ok}, failed ${failed}`);
for (const [r, n] of reasons) console.log(`  ${n} x ${r}`);
const c = await sql(`select count(*) total, count(embedding_gte) embedded from public.${TABLE}`);
console.log('IN THE DATABASE: ' + JSON.stringify(c[0]));
process.exit(failed && !ok ? 1 : 0);
