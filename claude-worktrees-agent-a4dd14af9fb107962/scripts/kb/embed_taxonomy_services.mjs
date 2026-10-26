// Embed every active taxonomy_trade_service row through the FREE in-region path, for the meaning layer
// (supabase/functions/_shared/service_meaning.ts). Seat: sales_engineer. 21 Sep 2026.
//
// Same route as scripts/kb/embed_sales_knowledge.mjs: ai_gateway {action:'embed'} runs
// Supabase.ai.Session('gte-small') inside the edge runtime and returns a 384-dimension vector BEFORE
// routing, budget or any model call — not OpenRouter. The text embedded is serviceEmbedText(), the one
// function the tests use too, so a stored vector and a test vector mean the same words.
//
// A refusal leaves the column NULL and is counted, never replaced by a made-up vector: the meaning layer
// skips a service with no vector and says the layer is not ready, which is the honest state.
//
//   node scripts/kb/embed_taxonomy_services.mjs            # count what has no vector; writes nothing
//   node scripts/kb/embed_taxonomy_services.mjs --write    # embed those rows and store the vectors
//   node scripts/kb/embed_taxonomy_services.mjs --write --all   # re-embed every row (names changed)
import { sql, PROJECT_REF } from '../lib/db.mjs';
import { serviceEmbedText } from '../../supabase/functions/_shared/service_meaning.ts';

const WRITE = process.argv.includes('--write');
const ALL = process.argv.includes('--all');
const rows = await sql(`select s.trade_code, s.code, s.label_en, s.label_ar, t.label, t.label_ar as trade_label_ar
                          from public.taxonomy_trade_service s join public.taxonomy_trade t on t.code = s.trade_code
                         where s.active ${ALL ? '' : 'and s.embedding_gte is null'} order by 1, 2`);
console.log(`${rows.length} service row(s) ${ALL ? 'to re-embed' : 'without a vector'}`);
if (!WRITE || !rows.length) process.exit(0);

const secret = (await sql(`select value from public.app_secrets where key = 'cred_fn_ai'`))[0]?.value;
if (!secret) { console.error('no cred_fn_ai in app_secrets'); process.exit(2); }
// A gte-small failure is a 503 embed_failed (22 Sep 2026, instruction 645; it used to be ok:true with a
// null vector). A 503 is retried, three attempts in all; anything else fails the row at once, as before.
async function embedText(text) {
  for (let attempt = 1; ; attempt++) {
    const res = await fetch(`https://${PROJECT_REF}.supabase.co/functions/v1/ai_gateway`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ __secret: secret, fn: 'embed_taxonomy_services', action: 'embed', text }),
    });
    if (res.status === 503 && attempt < 3) { await new Promise((s) => setTimeout(s, 1000 * attempt)); continue; }
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const j = await res.json();
    if (!j.embedding) throw new Error('gateway returned no embedding');
    return j.embedding;
  }
}
const lit = (v) => "'" + String(v).replace(/'/g, "''") + "'";
let ok = 0; const failed = [];
for (const r of rows) {
  try {
    const v = await embedText(serviceEmbedText(r, { label: r.label, label_ar: r.trade_label_ar }));
    await sql(`update public.taxonomy_trade_service set embedding_gte = ${lit(v)}::vector
                where trade_code = ${lit(r.trade_code)} and code = ${lit(r.code)}`);
    ok++;
  } catch (e) { failed.push(`${r.trade_code}.${r.code}: ${String(e.message).slice(0, 100)}`); }
}
console.log(`embedded ${ok}, failed ${failed.length}`);
for (const f of failed) console.log('  ' + f);
process.exit(failed.length ? 1 : 0);
