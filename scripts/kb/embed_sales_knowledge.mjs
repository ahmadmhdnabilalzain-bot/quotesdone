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
// 23 Sep 2026 (it_engineer, decision point knowledge.support_ceo_vectors): support_knowledge and ceo_knowledge join,
// keyed on record_id with title + body as the text (their body column is `body`, not `content`). They are read by
// meaning only from then on (fn_reason_retrieve, fn_support_knowledge_search, fn_ceo_knowledge_search), so a row
// with no vector is invisible: the pack loaders call embedMissing() for their table the moment they have written,
// and a BEFORE UPDATE trigger clears the vector of a row whose title or body changed so it is rebuilt, not stale.
//
//   node scripts/kb/embed_sales_knowledge.mjs [--table=sales_knowledge] [--limit=N]
//   node scripts/kb/embed_sales_knowledge.mjs --table=company_faq
//   node scripts/kb/embed_sales_knowledge.mjs --table=support_knowledge
//   node scripts/kb/embed_sales_knowledge.mjs --table=ceo_knowledge

import { sql, PROJECT_REF } from '../lib/db.mjs';

import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

export const TABLES = ['sales_knowledge', 'accountant_knowledge', 'it_engineer_knowledge', 'company_faq', 'support_knowledge', 'ceo_knowledge'];
// The key and the text each table is embedded from; the alias keeps one code path.
const SHAPE = {
  company_faq: { key: 'id', cols: 'id as record_id, question as title, answer as content' },
  support_knowledge: { key: 'record_id', cols: 'record_id, title, body as content' },
  ceo_knowledge: { key: 'record_id', cols: 'record_id, title, body as content' },
};
const CONC = 6;
const lit = (v) => "'" + String(v).replace(/'/g, "''") + "'";

/** One text through the same free in-region path: a 384-d gte-small vector literal, or null (never a made-up one). */
export async function embedText(text, fnName = 'embed_query') {
  const secret = (await sql(`select value from public.app_secrets where key = 'cred_fn_ai'`))[0]?.value;
  if (!secret) throw new Error('no cred_fn_ai in app_secrets');
  const res = await fetch(`https://${PROJECT_REF}.supabase.co/functions/v1/ai_gateway`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ __secret: secret, fn: fnName, action: 'embed', text: String(text).slice(0, 1200) }),
  });
  const j = res.ok ? await res.json() : null;
  return Array.isArray(j?.embedding) ? '[' + j.embedding.join(',') + ']' : null;
}

/** Embeds every row of TABLE that has no vector yet. Returns the counts; never writes a vector it did not get. */
export async function embedMissing(TABLE, { limit = 100000, log = console.log } = {}) {
  if (!TABLES.includes(TABLE)) throw new Error(`table must be one of: ${TABLES.join(', ')}`);
  const secret = (await sql(`select value from public.app_secrets where key = 'cred_fn_ai'`))[0]?.value;
  if (!secret) throw new Error('no cred_fn_ai in app_secrets');
  const KEY = SHAPE[TABLE]?.key ?? 'record_id';
  const COLS = SHAPE[TABLE]?.cols ?? 'record_id, title, content';
  const rows = await sql(`select ${COLS} from public.${TABLE}
                           where embedding_gte is null order by ${KEY} limit ${Number(limit)}`);
  log(`${TABLE}: ${rows.length} record(s) without an embedding`);
  let ok = 0, failed = 0; const reasons = new Map();
  const note = (r) => reasons.set(r, (reasons.get(r) || 0) + 1);
  async function one(r) {
    try {
      const res = await fetch(`https://${PROJECT_REF}.supabase.co/functions/v1/ai_gateway`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ __secret: secret, fn: 'embed_' + TABLE, action: 'embed', text: r.title + '\n' + r.content }),
      });
      if (!res.ok) { failed++; note('HTTP ' + res.status + ': ' + (await res.text()).slice(0, 120)); return null; }
      const j = await res.json();
      // embed() swallows its own errors and returns null. A null here is a refusal, not a vector.
      if (!j.embedding) { failed++; note('gateway returned no embedding'); return null; }
      ok++;
      return [r.record_id, j.embedding];
    } catch (e) { failed++; note(String(e.message).slice(0, 120)); return null; }
  }
  for (let i = 0; i < rows.length; i += 25) {
    const batch = rows.slice(i, i + 25);
    const got = [];
    for (let j = 0; j < batch.length; j += CONC) got.push(...(await Promise.all(batch.slice(j, j + CONC).map(one))).filter(Boolean));
    if (got.length) {
      const values = got.map(([id, v]) => `(${lit(id)}, ${lit(v)}::vector(384))`).join(',');
      await sql(`update public.${TABLE} k set embedding_gte = v.e
                   from (values ${values}) as v(id, e) where k.${KEY}::text = v.id::text`);
    }
  }
  const c = (await sql(`select count(*) total, count(embedding_gte) embedded from public.${TABLE}`))[0];
  log(`${TABLE}: embedded ${ok}, failed ${failed}`);
  for (const [r, n] of reasons) log(`  ${n} x ${r}`);
  log('IN THE DATABASE: ' + JSON.stringify(c));
  return { ok, failed, total: Number(c.total), embedded: Number(c.embedded) };
}

// Run as a script (not imported by a pack loader).
const same = (a, b) => resolve(a).toLowerCase() === resolve(b).toLowerCase();
if (process.argv[1] && same(fileURLToPath(import.meta.url), process.argv[1])) {
  const arg = (n, d) => (process.argv.find((x) => x.startsWith(`--${n}=`)) || `--${n}=${d}`).split('=').slice(1).join('=');
  const TABLE = arg('table', 'sales_knowledge');
  if (!TABLES.includes(TABLE)) { console.error(`--table must be one of: ${TABLES.join(', ')}`); process.exit(2); }
  const r = await embedMissing(TABLE, { limit: Number(arg('limit', 100000)) });
  process.exit(r.failed && !r.ok ? 1 : 0);
}
