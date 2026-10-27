// 1,496 OF PRODUCTION'S 4,956 KNOWLEDGE CHUNKS HAVE NO EMBEDDING, AND STAGING HAS THEM ALL.
//
// Found while chasing a false red in verify_prod_parity: the two corpora hold identical content and
// identical row counts, and every check in the repo agreed — but semantic retrieval runs on
// kb_chunks.embedding_gte, and a NULL vector is invisible to it. The LIVE system was searching 70%
// of its own knowledge base. Staging is at 100%.
//
// The vectors already exist and were already paid for, so this is a copy, not a re-embed: zero
// model spend. Rows are matched on (category, content) because the two projects assigned their
// surrogate ids independently — 1,858 ids exist on only one side — so matching on id would find
// almost nothing.
//
//   node scripts/backfill_production_embeddings.mjs [--dry-run]
import { supabaseAccessToken } from '../lib/supabase_token.mjs';
import { readFileSync } from 'node:fs';
import { mgmtRead, PROD_REF } from '../lib/qd_guard.mjs';
import { REF as STAGE } from '../lib/demo_factory.mjs';

const DRY = process.argv.includes('--dry-run');
const one = (r) => (r && r[0]) ? Object.values(r[0])[0] : null;

const token = supabaseAccessToken();
async function prodPost(sql) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD_REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  const b = await r.text();
  if (!r.ok) throw new Error(`production ${r.status}: ${b.slice(0, 300)}`);
  return JSON.parse(b);
}

const before = Number(one(await mgmtRead(PROD_REF,
  `select count(*) from public.kb_chunks where embedding_gte is null`)));
console.log(`production chunks with no embedding: ${before}`);

// The join key. md5 of content keeps the payload small; category disambiguates the same text filed
// under two categories.
const KEY = `md5(coalesce(category,'')||'|'||coalesce(content,''))`;

const need = (await mgmtRead(PROD_REF,
  `select ${KEY} k from public.kb_chunks where embedding_gte is null`)).map(r => r.k);
console.log(`distinct keys needing a vector: ${new Set(need).size}`);

let filled = 0, unmatched = 0;
const keys = [...new Set(need)];
for (let i = 0; i < keys.length; i += 100) {
  const batch = keys.slice(i, i + 100);
  const inList = batch.map(k => `'${k}'`).join(',');
  // Pull staging's vectors for exactly these keys. ::text so the vector travels as its literal
  // form and is never parsed into a JavaScript number array and re-serialised.
  const rows = await mgmtRead(STAGE,
    `select ${KEY} k, embedding_gte::text v from public.kb_chunks
      where embedding_gte is not null and ${KEY} in (${inList})`);
  const seen = new Map();
  for (const r of rows) if (!seen.has(r.k)) seen.set(r.k, r.v);
  unmatched += batch.filter(k => !seen.has(k)).length;
  if (!seen.size) continue;
  if (DRY) { filled += seen.size; continue; }

  const values = [...seen.entries()]
    .map(([k, v]) => `('${k}','${v.replace(/'/g, "''")}'::vector(384))`).join(',');
  const res = await prodPost(
    `with src(k, v) as (values ${values})
     update public.kb_chunks t set embedding_gte = src.v
       from src where src.k = ${KEY} and t.embedding_gte is null
     returning 1`);
  filled += Array.isArray(res) ? res.length : 0;
  process.stdout.write(`  ${Math.min(i + 100, keys.length)}/${keys.length} keys · ${filled} rows filled\r`);
}

const after = Number(one(await mgmtRead(PROD_REF,
  `select count(*) from public.kb_chunks where embedding_gte is null`)));
const total = Number(one(await mgmtRead(PROD_REF, `select count(*) from public.kb_chunks`)));
console.log(`\n${DRY ? 'DRY RUN — ' : ''}rows filled: ${filled} · keys with no staging vector: ${unmatched}`);
console.log(`production embeddings: ${total - before}/${total} -> ${total - after}/${total} (${Math.round(100 * (total - after) / total)}%)`);
