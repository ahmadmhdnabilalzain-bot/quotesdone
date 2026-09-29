// THE SERVICE VECTORS AS THE MEANING LAYER WILL READ THEM (29 Sep 2026, sales_engineer; decision point 93 (b)).
//
// taxonomy_trade_service carries a gte-small vector (embedding_gte) and, since
// scripts/sql/every_service_is_embedded_from_its_names_and_aliases_in_both_languages.sql, a multilingual one
// (embedding_ml), each with the SHA-256 of the text it was made from (embedding_gte_sha, embedding_ml_sha). The text
// is service_meaning.ts serviceEmbedText / serviceMlText. A stored vector whose sha is the current text's is used as
// it is; any other (older recipe, not embedded yet, or the columns not applied yet) is embedded HERE, in memory,
// through embed_ml exactly as scripts/kb/embed_taxonomy_services.mjs will store it at release — so a live check
// measures what production reads once the backfill has run, and says how many vectors it had to compute.
// Read-only against the database. Vectors computed are cached in the OS temp dir by sha (never in the repository).
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';

const SHARED = fileURLToPath(new URL('../../supabase/functions/_shared/', import.meta.url));
const CACHE = join(tmpdir(), 'qd_service_vectors_cache.json');

/** embed_ml over HTTP: 'gte' (Supabase.ai gte-small) or 'query' (multilingual e5), with a 503 retried. */
export function embedMl(PROJECT_REF, secret, caller) {
  return async (text, space) => {
    for (let attempt = 1; attempt <= 4; attempt++) {
      try {
        const r = await fetch(`https://${PROJECT_REF}.supabase.co/functions/v1/embed_ml`, {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ __secret: secret, fn: caller, action: space === 'ml' ? 'query' : 'gte', text }),
          signal: AbortSignal.timeout(30_000),
        });
        const j = await r.json().catch(() => ({}));
        if (r.ok && typeof j.embedding === 'string') return JSON.parse(j.embedding);
      } catch { /* retried */ }
      await new Promise((s) => setTimeout(s, 700 * attempt));
    }
    return null;
  };
}

/** Run fn over items, `n` at a time. */
export async function pool(items, n, fn) {
  let i = 0;
  await Promise.all(Array.from({ length: Math.min(n, items.length) }, async () => { while (i < items.length) { const k = i++; await fn(items[k], k); } }));
}

export async function liveServices({ sql, PROJECT_REF, caller = 'service_vectors' }) {
  const M = await import(pathToFileURL(join(SHARED, 'service_meaning.ts')).href);
  const cols = (await sql(`select column_name from information_schema.columns where table_schema = 'public' and table_name = 'taxonomy_trade_service'`)).map((r) => r.column_name);
  const hasMl = cols.includes('embedding_ml');
  const rows = await sql(`select s.trade_code, s.code, s.label_en, s.label_ar, s.aliases, t.label, t.label_ar as trade_label_ar,
      s.embedding_gte::text as gte${hasMl ? ', s.embedding_ml::text as ml, s.embedding_gte_sha as gte_sha, s.embedding_ml_sha as ml_sha' : ''}
    from public.taxonomy_trade_service s join public.taxonomy_trade t on t.code = s.trade_code where s.active order by 1, 2`);
  const secret = (await sql(`select value from public.app_secrets where key = 'cred_fn_ai'`))[0]?.value;
  if (!secret) throw new Error('no cred_fn_ai in app_secrets');
  const embed = embedMl(PROJECT_REF, secret, caller);
  const cache = existsSync(CACHE) ? JSON.parse(readFileSync(CACHE, 'utf8')) : {};
  const todo = [];
  const services = await Promise.all(rows.map(async (r) => {
    const trade = { label: r.label, label_ar: r.trade_label_ar };
    const s = { trade_code: r.trade_code, code: r.code, label_en: r.label_en, label_ar: r.label_ar, aliases: r.aliases || [] };
    const gText = M.serviceEmbedText(s, trade), mText = M.serviceMlText(s, trade);
    const [gSha, mSha] = [await M.textSha(gText), await M.textSha(mText)];
    const out = { ...s, vec: r.gte_sha === gSha ? M.parseVec(r.gte) : null, vec_ml: hasMl && r.ml_sha === mSha ? M.parseVec(r.ml) : null };
    if (!out.vec) todo.push([out, 'vec', 'gte', gText, 'gte:' + gSha]);
    if (!out.vec_ml) todo.push([out, 'vec_ml', 'ml', mText, 'ml:' + mSha]);
    return out;
  }));
  let computed = 0, failed = 0;
  await pool(todo, 8, async ([o, field, space, text, key]) => {
    const v = cache[key] ?? await embed(text, space);
    if (v) { o[field] = v; cache[key] = v; computed++; } else failed++;
  });
  if (todo.length) writeFileSync(CACHE, JSON.stringify(cache));
  return { services, embed, stats: { rows: rows.length, ml_column: hasMl, computed_in_memory: computed, failed } };
}
