// Embed every active taxonomy_trade_service row, in BOTH spaces, for the meaning layer
// (supabase/functions/_shared/service_meaning.ts). Seat: sales_engineer. 21 Sep 2026; 29 Sep 2026.
//
// Two vectors per service, both through embed_ml (the free in-region embedder; never OpenRouter):
//   embedding_gte  <- 'gte'   (Supabase.ai gte-small) of serviceEmbedText: names + English aliases + trade names
//   embedding_ml   <- 'query' (multilingual-e5-small) of serviceMlText:   both names + every alias + trade names
// each written with the SHA-256 of its text (embedding_gte_sha / embedding_ml_sha), so a row is re-embedded only
// when its text changed (a renamed service, a new alias) and a reader can tell a current vector from a stale one.
// The texts are the functions every test and scripts/lib/service_vectors.mjs use, so a stored vector and a test
// vector mean the same words. A refusal leaves the row as it was and is counted, never replaced by a made-up vector.
//
// Needs scripts/sql/every_service_is_embedded_from_its_names_and_aliases_in_both_languages.sql applied first.
//   node scripts/kb/embed_taxonomy_services.mjs            # count what is stale; writes nothing
//   node scripts/kb/embed_taxonomy_services.mjs --write    # embed the stale rows and store vectors + shas
import { sql, lit, PROJECT_REF } from '../lib/db.mjs';
import { embedMl, pool } from '../lib/service_vectors.mjs';
import { serviceEmbedText, serviceMlText, textSha } from '../../supabase/functions/_shared/service_meaning.ts';

const WRITE = process.argv.includes('--write');
const rows = await sql(`select s.trade_code, s.code, s.label_en, s.label_ar, s.aliases, t.label, t.label_ar as trade_label_ar,
    s.embedding_gte_sha, s.embedding_ml_sha, s.embedding_gte is null as no_gte, s.embedding_ml is null as no_ml
  from public.taxonomy_trade_service s join public.taxonomy_trade t on t.code = s.trade_code where s.active order by 1, 2`);
const jobs = [];
for (const r of rows) {
  const trade = { label: r.label, label_ar: r.trade_label_ar };
  const g = serviceEmbedText(r, trade), m = serviceMlText(r, trade);
  const [gs, ms] = [await textSha(g), await textSha(m)];
  if (r.no_gte || r.embedding_gte_sha !== gs) jobs.push({ r, col: 'embedding_gte', shaCol: 'embedding_gte_sha', space: 'gte', text: g, sha: gs });
  if (r.no_ml || r.embedding_ml_sha !== ms) jobs.push({ r, col: 'embedding_ml', shaCol: 'embedding_ml_sha', space: 'ml', text: m, sha: ms });
}
console.log(`${rows.length} service row(s); ${jobs.length} stale vector(s) (${jobs.filter((j) => j.space === 'gte').length} gte, ${jobs.filter((j) => j.space === 'ml').length} ml)`);
if (!WRITE || !jobs.length) process.exit(0);

const secret = (await sql(`select value from public.app_secrets where key = 'cred_fn_ai'`))[0]?.value;
if (!secret) { console.error('no cred_fn_ai in app_secrets'); process.exit(2); }
const embed = embedMl(PROJECT_REF, secret, 'embed_taxonomy_services');
let ok = 0; const failed = [];
await pool(jobs, 8, async (j) => {
  const v = await embed(j.text, j.space);
  if (!v || v.length !== 384) { failed.push(`${j.r.trade_code}.${j.r.code} ${j.space}`); return; }
  await sql(`update public.taxonomy_trade_service set ${j.col} = ${lit('[' + v.join(',') + ']')}::vector, ${j.shaCol} = ${lit(j.sha)}
              where trade_code = ${lit(j.r.trade_code)} and code = ${lit(j.r.code)}`);
  ok++;
});
console.log(`embedded ${ok}, failed ${failed.length}`);
for (const f of failed) console.log('  ' + f);
process.exit(failed.length ? 1 : 0);
