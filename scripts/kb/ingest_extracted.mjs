// Bulk-ingest an extracted document (book-to-skill full_text.txt) into public.kb_chunks at page scale.
//
// The agent-expertise corpus target: ~10,000 pages/agent lives in kb_chunks (semantic + fts), NOT in
// hand-crafted ops_knowledge entries. This loader turns one extracted source into many retrievable
// chunks, tagged by category, idempotent per source_id. Embeddings (embedding_gte) are backfilled
// separately by the free in-region kb_embed path; fts is generated on write and is immediately usable.
//
// Usage:
//   node scripts/kb/ingest_extracted.mjs <full_text.txt> --category <cat> --source-id <id> \
//        --source-kind <kind> --citation "<cite>" [--title-prefix "<p>"] [--dry]
//
// Zero cost: writes only kb_chunks rows on the one project. No paid inference, no business effect.

import { supabaseAccessToken } from '../lib/supabase_token.mjs';
import { readFileSync } from 'node:fs';

const args = process.argv.slice(2);
const pos = args.filter(a => !a.startsWith('--'));
const flag = (n, d = null) => { const i = args.indexOf('--' + n); return i >= 0 ? args[i + 1] : d; };
const has = (n) => args.includes('--' + n);

const file = pos[0];
const category = flag('category');
const sourceId = flag('source-id');
const sourceKind = flag('source-kind', 'reference');
const citation = flag('citation', '');
const titlePrefix = flag('title-prefix', '');
const DRY = has('dry');
const TARGET = parseInt(flag('chunk-chars', '1200'), 10);

if (!file || !category || !sourceId) {
  console.error('usage: node scripts/kb/ingest_extracted.mjs <file> --category <cat> --source-id <id> [--source-kind k] [--citation c] [--dry]');
  process.exit(1);
}

const PROD_REF = 'htdblwldjkcgjvmqkbeh';
const token = supabaseAccessToken();

async function dbPost(q, attempt = 0) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD_REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: q }),
  });
  const b = await r.text();
  if ((r.status === 429 || r.status >= 500) && attempt < 7) {
    const wait = Math.min(2000 * 2 ** attempt, 60000);
    console.log(`  ${r.status}; retrying in ${wait / 1000}s`);
    await new Promise(res => setTimeout(res, wait));
    return dbPost(q, attempt + 1);
  }
  if (!r.ok) throw new Error(`database ${r.status}: ${b.slice(0, 400)}`);
  return JSON.parse(b);
}

const lit = (s) => "'" + String(s).replace(/'/g, "''") + "'";

// ---- chunking: paragraph-aware, target size, drop page-marker / boilerplate noise ----------------
const raw = readFileSync(file, 'utf8');
const NOISE = [
  /^={10,}$/, /^SOURCE:/i, /^\s*Page \d+ of \d+\s*$/i, /^v\d+\.\d+(\.\d+)?\s+Page \d+/i,
  /^\s*Foundation Level\s*$/i, /^\s*Copyright Notice/i, /^\s*International Software Testing/i,
  /copyright\s+.{0,6}\s+\d{4}\s+the authors/i, /All rights reserved/i, /transfer the copyright/i,
];
const isNoise = (ln) => NOISE.some(re => re.test(ln.trim()));
// pdftotext emits Latin-1 mojibake for smart quotes / ® / – etc. Normalise to plain ASCII so the
// stored corpus is clean and fts-friendly. Anything still non-ASCII becomes a space.
const sanitize = (s) => s
  .replace(/�/g, '').replace(/[‘’]/g, "'").replace(/[“”]/g, '"')
  .replace(/[–—]/g, '-').replace(/…/g, '...').replace(/[^\x09\x0A\x0D\x20-\x7E]/g, ' ')
  .replace(/[ \t]{2,}/g, ' ');

// A "section" heading looks like "4.2.1 Title" or "Chapter 3 ..." — used to title chunks.
const headingRe = /^(chapter\s+\d+|\d+(\.\d+){0,3})\.?\s+[A-Z].{2,80}$/i;

const lines = raw.split(/\r?\n/).filter(ln => !isNoise(ln));
const chunks = [];
let buf = '', curTitle = titlePrefix || 'Overview', pageApprox = 0;
const flush = () => {
  const c = sanitize(buf).trim();
  if (c.length >= 200) chunks.push({ title: sanitize(curTitle).slice(0, 300), content: c });
  buf = '';
};
for (const ln of lines) {
  const t = ln.trim();
  if (headingRe.test(t) && t.length < 90) { flush(); curTitle = (titlePrefix ? titlePrefix + ' — ' : '') + t; continue; }
  if (t === '') { if (buf.length >= TARGET) flush(); else buf += '\n'; continue; }
  buf += (buf ? ' ' : '') + t;
  if (buf.length >= TARGET * 1.4) flush();
}
flush();

console.log(`source: ${file}`);
console.log(`category=${category} source_id=${sourceId} kind=${sourceKind}`);
console.log(`chunks: ${chunks.length}  (~${Math.round(chunks.reduce((a, c) => a + c.content.length, 0) / 1000)}k chars, ~${Math.round(chunks.reduce((a,c)=>a+c.content.split(/\s+/).length,0)/500)} pages)`);
if (DRY) { console.log('DRY — first chunk:\n', chunks[0]); process.exit(0); }

// ---- idempotent load: clear this source_id, then batch-insert -----------------------------------
await dbPost(`delete from public.kb_chunks where source_id = ${lit(sourceId)};`);

const BATCH = 200;  // larger batches = fewer management-API round trips = less rate-limiting at scale
let done = 0;
for (let i = 0; i < chunks.length; i += BATCH) {
  const slice = chunks.slice(i, i + BATCH);
  const values = slice.map(c =>
    `(${lit(sourceKind)}, ${lit(sourceId)}, ${lit(category)}, ${lit(c.title.slice(0, 300))}, ${lit(c.content)}, ${lit(citation)}, current_date)`
  ).join(',\n');
  await dbPost(`insert into public.kb_chunks (source_kind, source_id, category, title, content, citation, effective_date) values\n${values};`);
  done += slice.length;
  process.stdout.write(`\r  loaded ${done}/${chunks.length}`);
}
// Self-heal retry-induced duplicate rows. A 5xx/timeout retry in dbPost() can re-commit an
// already-committed batch (the management API offers no idempotency key), duplicating whole rows
// for this source_id — measured at scale during bulk ingestion. Collapse byte-identical
// (title, content) rows within THIS source, keeping the earliest ctid. Distinct chunks always
// differ in content, so this can never remove real content; it is scoped to source_id so it never
// touches other documents. (ponytail: post-load dedup is the lazy safe fix; true idempotency would
// need a per-chunk key the management-API path can't carry.)
await dbPost(`delete from public.kb_chunks where ctid in (select ctid from (select ctid, row_number() over (partition by title, content order by ctid) rn from public.kb_chunks where source_id = ${lit(sourceId)}) t where rn > 1);`);
const cnt = await dbPost(`select count(*)::int n from public.kb_chunks where source_id = ${lit(sourceId)};`);
const n = cnt?.[0]?.n ?? done;
console.log(`\ndone: ${done} chunks loaded; kb_chunks now holds ${n} for source_id=${sourceId}.`);
