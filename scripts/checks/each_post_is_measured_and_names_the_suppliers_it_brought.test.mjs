// EACH POST IS MEASURED AND NAMES THE SUPPLIERS IT BROUGHT (marketing + sales_engineer, 23 Sep 2026;
// founder instruction 865). Fails if any link of the chain comes back broken:
//   * the marketing seat's duty list loses post_results or scorecard, or a duty stops naming its seat;
//   * the calendar loader stops tagging our links with UTM (or the publisher starts rewriting approved text);
//   * create_company or claim stops handing the first touch to fn_marketing_first_touch_record;
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
import { readSupplierPortal } from '../lib/portal_sources.mjs';
import { functionModuleSource, functionSource } from '../lib/function_sources.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => (existsSync(join(ROOT, p)) ? readFileSync(join(ROOT, p), 'utf8') : '');
const SQL_FILE = 'scripts/sql/each_post_is_measured_and_names_the_suppliers_it_brought.sql';
const SQL = R(SQL_FILE);

test('the marketing duty list runs post_results and scorecard, each owned by marketing', () => {
  const duties = functionModuleSource('marketing/duties');
  // other duties (platform_spec_freshness, #873) may follow in the same list; these two must be in it
  const list = (duties.match(/export const DUTIES: Duty\[\] = \[([^\]]*)\]/) || [])[1] || '';
  for (const d of ['POST_RESULTS', 'SCORECARD']) assert.ok(list.split(',').map((s) => s.trim()).includes(d), `DUTIES does not run ${d}`);
  const pr = R('supabase/functions/marketing/post_results.ts');
  for (const n of ['post_results', 'scorecard']) assert.match(pr, new RegExp(`name: '${n}', owner_seat: 'marketing'`), `${n} names no owning seat`);
  assert.match(pr, /rpc\('fn_marketing_post_checkpoints_due'/);
  assert.match(pr, /rpc\('fn_marketing_scorecard_publish'/);
});

test('every link the seat publishes carries UTM naming the post, tagged at LOAD so the approved text includes it', () => {
  assert.match(R('scripts/marketing/load_calendar.mjs'), /const calendar = tagCalendar\(JSON\.parse\(readFileSync\(file, 'utf8'\)\)\);/, 'the calendar loader does not tag links before the load');
  assert.match(R('scripts/marketing/utm.mjs'), /utm_medium=social&utm_campaign=/);
  // send time never rewrites the approved body (#874 sends it byte for byte)
  assert.doesNotMatch(R('supabase/functions/_shared/marketing_channels.ts'), /withUtm\(/, 'the publisher rewrites the approved text');
});

test('a supplier registration records the post that brought it', () => {
  const api = functionSource('supplier_api');
  assert.match(api, /rpc\('fn_marketing_first_touch_record', \{ p_lead_id: leadId, p_touch: touch \}\)/);
  // 28 Oct 2026 (#1712, ledger 1401 audit S7): create_company's body moved to supplier_api/create_company.ts, where a new
  // registration and the claim of an invited listing each record the first touch the door hands in.
  const door = R('supabase/functions/supplier_api/create_company.ts');
  assert.match(api, /createCompany\(admin, email, body, \{[^}]*\brecordFirstTouch, /, 'create_company is not handed the first-touch recorder');
  // 11 Nov 2026: after the write, afterTheWrite records the first touch beside the supplier read the answer carries.
  assert.match(door, /async function afterTheWrite\(id: number, touch: unknown, deps: CreateDeps\)[^]*?deps\.recordFirstTouch\(id, touch\)/, 'afterTheWrite does not record the first touch');
  // 15 Nov 2026: afterTheWrite also reads the registration state (no touch), in the same wave; both paths still hand it body.first_touch.
  assert.match(door, /const \[\{ registration, \.\.\.supplier \}\] = await Promise\.all\(\[afterTheWrite\(Number\(ins!\.id\), body\.first_touch, deps\)/, 'create_company does not record the first touch');
  assert.match(door, /const \{ registration, \.\.\.supplier \} = await afterTheWrite\(id, body\.first_touch, deps\)/, 'create_company does not record the first touch when it claims an invited listing');
  // #979 (28 Sep 2026) issues the two together: Promise.all([setRegistration(id, false), recordFirstTouch(...)]).
  assert.match(api, /setRegistration\(id(, false)?\)(; await |, )recordFirstTouch\(id, body\.first_touch\)/, 'claim does not record the first touch');
  const portal = readSupplierPortal();
  assert.match(portal, /action: 'create_company'[^}]*first_touch: /);
  assert.match(portal, /action: 'claim', t, first_touch: /);
  assert.match(R('src/app/[locale]/layout.tsx'), /<FirstTouch \/>/, 'the site does not keep the first touch');
  const legal = JSON.parse(R('src/content/legal.json'))['cookie-policy'];
  assert.match(legal.en.html, /qd-first-touch/, 'the cookie policy (EN) does not disclose qd-first-touch');
  assert.match(legal.ar.html, /qd-first-touch[^<]*[؀-ۿ]/, 'the cookie policy (AR) does not disclose qd-first-touch');
});

test('the SQL: every routine pinned and revoked, every table with a policy, goals cite a source', () => {
  assert.ok(SQL, SQL_FILE + ' is missing');
  const made = [...SQL.matchAll(/create or replace function public\.(\w+)\(/g)].map((m) => m[1]);
  assert.deepEqual(made.sort(), ['fn_marketing_first_touch_record', 'fn_marketing_post_checkpoints_due', 'fn_marketing_scorecard', 'fn_marketing_scorecard_publish', 'fn_table_export_list']);
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
  // youtube and tiktok are post channels since #870: every platform check admits all six
  assert.equal((SQL.match(/check \(platform in \('facebook', 'instagram', 'linkedin', 'x', 'youtube', 'tiktok'\)\)/g) || []).length, 3, 'a platform check omits youtube or tiktok');
  assert.match(R('supabase/functions/marketing/post_results.ts'), /d\.platform === 'youtube' \|\| d\.platform === 'tiktok'/, 'youtube/tiktok have no direct fallback');
  assert.match(SQL, /benchmark_source text not null check \(length\(btrim\(benchmark_source\)\) >= 20\)/, 'a goal may be seeded without a source');
  // committed, not applied: a pending note and no MANIFEST line (the operator applies and swaps them)
  const pendingNote = R('scripts/sql/pending/each_post_is_measured_and_names_the_suppliers_it_brought.txt').trim();
  const inManifest = R('scripts/sql/MANIFEST.txt').split(/\r?\n/).includes(SQL_FILE);
  assert.ok(pendingNote.length > 0 !== inManifest, 'exactly one of: a pending note, or a MANIFEST line');
});
