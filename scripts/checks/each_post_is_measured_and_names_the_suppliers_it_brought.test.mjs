// EACH POST IS MEASURED AND NAMES THE SUPPLIERS IT BROUGHT (marketing + sales_engineer, 23 Sep 2026;
// founder instruction 865). Fails if any link of the chain comes back broken:
//   * the marketing seat's duty list loses post_results or scorecard, or a duty stops naming its seat;
//   * the publish path stops tagging our links with UTM;
//   * supplier registration stops handing the first touch to fn_marketing_first_touch_record;
//   * the site stops keeping the first touch, or the cookie policy stops disclosing it (EN and AR);
//   * a routine in the SQL loses its pinned search_path or its revoke, a table its policy, or a month-1 goal
//     loses its cited source.
// Measured on the pre-fix source (origin/main fa53b1e): every test fails (DUTIES = [], no UTM, no file).
//   node --test scripts/checks/each_post_is_measured_and_names_the_suppliers_it_brought.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => (existsSync(join(ROOT, p)) ? readFileSync(join(ROOT, p), 'utf8') : '');
const SQL_FILE = 'scripts/sql/each_post_is_measured_and_names_the_suppliers_it_brought.sql';
const SQL = R(SQL_FILE);

test('the marketing duty list runs post_results and scorecard, each owned by marketing', () => {
  const duties = R('supabase/functions/marketing/duties.ts');
  assert.match(duties, /export const DUTIES: Duty\[\] = \[POST_RESULTS, SCORECARD\]/, 'DUTIES does not run post_results and scorecard');
  const pr = R('supabase/functions/marketing/post_results.ts');
  for (const n of ['post_results', 'scorecard']) assert.match(pr, new RegExp(`name: '${n}', owner_seat: 'marketing'`), `${n} names no owning seat`);
  assert.match(pr, /rpc\('fn_marketing_post_checkpoints_due'/);
  assert.match(pr, /rpc\('fn_marketing_scorecard_publish'/);
});

test('every link the seat publishes carries UTM naming platform, month and post', () => {
  const ch = R('supabase/functions/_shared/marketing_channels.ts');
  assert.match(ch, /withUtm\(postBody\(post\), ch, campaignOf\(post\.scheduled_at\), post\.ingest_key\)/, 'buildPostizPayload does not tag links');
  assert.match(R('supabase/functions/marketing_channels/index.ts'), /select\('id,ingest_key,/, 'publishDue does not read ingest_key');
  assert.match(R('supabase/functions/_shared/marketing_post_results.ts'), /utm_medium=social&utm_campaign=/);
});

test('a supplier registration records the post that brought it', () => {
  assert.match(R('supabase/functions/supplier_api/index.ts'), /rpc\('fn_marketing_first_touch_record', \{ p_lead_id: ins!\.id, p_touch: body\.first_touch \}\)/);
  assert.match(R('src/components/portal/SupplierPortal.tsx'), /action: 'create_company'[^}]*first_touch: /);
  assert.match(R('src/app/[locale]/layout.tsx'), /<FirstTouch \/>/, 'the site does not keep the first touch');
  const legal = JSON.parse(R('src/content/legal.json'))['cookie-policy'];
  assert.match(legal.en.html, /qd-first-touch/, 'the cookie policy (EN) does not disclose qd-first-touch');
  assert.match(legal.ar.html, /qd-first-touch[^<]*[؀-ۿ]/, 'the cookie policy (AR) does not disclose qd-first-touch');
});

test('the SQL: every routine pinned and revoked, every table with a policy, goals cite a source', () => {
  assert.ok(SQL, SQL_FILE + ' is missing');
  const made = [...SQL.matchAll(/create or replace function public\.(\w+)\(/g)].map((m) => m[1]);
  assert.deepEqual(made.sort(), ['fn_marketing_first_touch_record', 'fn_marketing_post_checkpoints_due', 'fn_marketing_scorecard', 'fn_marketing_scorecard_publish']);
  for (const fn of made) {
    const body = SQL.slice(SQL.indexOf(`create or replace function public.${fn}(`)).split('$fn$')[0];
    assert.match(body, /set search_path to 'public', 'pg_temp'/, `${fn} has no pinned search_path`);
    assert.match(SQL, new RegExp(`revoke execute on function public\\.${fn}\\([^)]*\\) from public, anon, authenticated`), `${fn} is not revoked`);
  }
  const tables = [...SQL.matchAll(/create table if not exists public\.(\w+)/g)].map((m) => m[1]);
  assert.equal(tables.length, 5);
  for (const t of tables) {
    assert.match(SQL, new RegExp(`alter table public\\.${t} enable row level security`), `${t}: RLS off`);
    assert.match(SQL, new RegExp(`create policy ${t}_service_role_only on public\\.${t}`), `${t}: no policy`);
    assert.match(SQL, new RegExp(`revoke all on public\\.${t} from anon, authenticated`), `${t}: not revoked`);
  }
  assert.match(SQL, /benchmark_source text not null check \(length\(btrim\(benchmark_source\)\) >= 20\)/, 'a goal may be seeded without a source');
  // committed, not applied: a pending note and no MANIFEST line (the operator applies and swaps them)
  const pendingNote = R('scripts/sql/pending/each_post_is_measured_and_names_the_suppliers_it_brought.txt').trim();
  const inManifest = R('scripts/sql/MANIFEST.txt').split(/\r?\n/).includes(SQL_FILE);
  assert.ok(pendingNote.length > 0 !== inManifest, 'exactly one of: a pending note, or a MANIFEST line');
});
