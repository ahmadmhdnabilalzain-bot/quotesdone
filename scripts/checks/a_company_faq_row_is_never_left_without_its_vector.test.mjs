// A COMPANY FAQ ROW IS NEVER LEFT WITHOUT ITS VECTOR (customer_support, 3 Nov 2026).
//
//   node --test scripts/checks/a_company_faq_row_is_never_left_without_its_vector.test.mjs
//
// Measured 2 Nov 2026: 34 of 638 company_faq rows had no embedding, because nothing scheduled re-embeds company_faq (cron 580
// embeds kb_chunks only). scripts/sql/a_company_faq_row_is_never_left_without_its_vector.sql adds a 10-minute pg_cron tick; its
// probe proves the behaviour on production in a rolled-back transaction. This reads only the repository: it fails if the job,
// its grants, the stale-text guard or the embedding recipe (shared with scripts/kb/embed_sales_knowledge.mjs) is lost.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const F = 'scripts/sql/a_company_faq_row_is_never_left_without_its_vector.sql';
const sql = read(F);
const code = sql.split('\n').filter((l) => !l.startsWith('--')).join('\n');

test('a pg_cron job every 10 minutes runs the tick, registered and owned by customer_support, and the file is applied', () => {
  assert.match(code, /cron\.schedule\('company_faq_embed', '\*\/10 \* \* \* \*', \$CRON\$select public\.fn_company_faq_embed_tick\(\);\$CRON\$\)/);
  assert.match(code, /insert into public\.cron_registry[\s\S]*'company_faq_embed'/);
  assert.match(code, /\('cron_job', 'company_faq_embed', 'customer_support'/);
  assert.ok(read('scripts/sql/MANIFEST.txt').split('\n').includes(F), 'not in MANIFEST.txt');
});

test('the routine and its table are service_role only', () => {
  assert.match(code, /security definer\s+set search_path to 'public', 'extensions', 'pg_temp'/);
  assert.match(code, /revoke execute on function public\.fn_company_faq_embed_tick\(integer\) from public, anon, authenticated;/);
  assert.match(code, /alter table public\.company_faq_embed_inflight enable row level security;/);
  assert.match(code, /create policy company_faq_embed_inflight_service_role_only[\s\S]*using \(false\) with check \(false\)/);
  assert.match(code, /revoke all on public\.company_faq_embed_inflight from anon, authenticated;/);
});

test('a vector is written only to a row still NULL whose text is what was sent, and only one the gateway returned', () => {
  assert.match(code, /where q\.id = g\.faq_id and q\.embedding_gte is null\s+and md5\(coalesce\(q\.question, ''\) \|\| E'\\n' \|\| coalesce\(q\.answer, ''\)\) = g\.text_md5/);
  assert.match(code, /status_code = 200 and \(d\.content::jsonb\) ->> 'embedding' is not null/);
});

test('the text and the path are the embed script\'s: question + newline + answer through ai_gateway embed (gte-small, not OpenRouter)', () => {
  const script = read('scripts/kb/embed_sales_knowledge.mjs');
  assert.match(script, /company_faq: \{ key: 'id', cols: 'id as record_id, question as title, answer as content' \}/);
  assert.match(script, /text: r\.title \+ '\\n' \+ r\.content/);
  assert.match(code, /coalesce\(q\.question, ''\) \|\| E'\\n' \|\| coalesce\(q\.answer, ''\) as txt/);
  assert.match(code, /'action', 'embed'/);
  assert.match(code, /functions\/v1\/ai_gateway/);
});

test('the probe proves the fill, the stale-text refusal and that no NULL row is left unsent', () => {
  const probe = read(F.replace(/\.sql$/, '_probe.sql'));
  for (const s of ["' 2:not_filled", "' 3:stale_vector_written", "' 3:not_resent", "' 4:null_row_unsent", "raise exception 'CHK<<%>>'"]) {
    assert.ok(probe.includes(s), 'probe lacks ' + s);
  }
});
