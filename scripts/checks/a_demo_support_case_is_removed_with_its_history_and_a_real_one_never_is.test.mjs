// A demo support case is removed with its history, and a real one never is (it_engineer, 12 Nov 2026; final audit H6,
// founder ledger 1642: demo data is exempt from the keep-everything rule, a real person's history stays append-only).
//
// On main the harness teardown deleted a run's support_case rows directly. #1943's support_case_summary_version is
// append-only and references support_case, so the delete met 23503 and the teardown stopped there, leaving the run's
// customers, suppliers, requests and auth users (run d9a04dbc). Fails if:
//   - the teardown deletes support_case itself again instead of through fn_demo_support_case_purge;
//   - the trigger lets a delete through on the flag alone, without the case's own demo test;
//   - the sweep stops finding a run whose only leftover is a Resend-sink signup, or teardown stops removing the
//     re-drawn quotation PDFs under quote-files/quotes/<lead>/ (final audit F12);
//   - REPLAY (with a management token): teardown's own support statements, run on a ZZ DEMO case with a summary version
//     inside one aborted transaction, leave the case or its history behind.
//   node --test scripts/checks/a_demo_support_case_is_removed_with_its_history_and_a_real_one_never_is.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const NAME = 'a_demo_support_case_is_removed_with_its_history_and_a_real_one_never_is';
const FILE = `scripts/sql/${NAME}.sql`;
const SQL = read(FILE);
const code = (s) => s.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');   // comments may quote what they forbid

test('the file is either applied (MANIFEST) or pending (its note), and its probe is kept and never applied', () => {
  const manifest = read('scripts/sql/MANIFEST.txt').split('\n').map((l) => l.trim());
  assert.ok(manifest.includes(FILE) !== existsSync(join(REPO, `scripts/sql/pending/${NAME}.txt`)), 'exactly one of: a MANIFEST line, a pending note');
  assert.ok(existsSync(join(REPO, `scripts/sql/pending/${NAME}_probe.txt`)), 'the probe carries its never-applied note');
  assert.match(read(`scripts/sql/${NAME}_probe.sql`), /raise exception 'PROBE OK/, 'the probe always raises');
});

test('the trigger lets a delete through only on the flag AND the case\'s own demo test; the routine is closed', () => {
  const s = code(SQL);
  assert.match(s, /if tg_op = 'DELETE' and coalesce\(current_setting\('qd\.demo_case_purge', true\), ''\) = 'on'\s+and public\.fn_support_case_is_demo\(old\.case_id\) then\s+return old;/);
  assert.match(s, /raise exception 'support_case_summary_version is append-only \(ruling 1634\)/, 'everything else is still refused');
  for (const sig of ['fn_support_case_is_demo(bigint)', 'fn_demo_support_case_purge(bigint[])', 'fn_support_case_summary_version_is_append_only()']) {
    assert.ok(s.includes(`revoke execute on function public.${sig} from public, anon, authenticated;`), `${sig} is revoked`);
  }
  assert.match(s, /fn_party_is_demo\(c\.party_kind, c\.party_id\)[\s\S]{0,200}fn_is_demo_email\(p\.email\)[\s\S]{0,200}fn_customer_is_demo\(p\.customer_id\)[\s\S]{0,200}fn_supplier_is_demo\(p\.lead_id\)/,
    'the demo test is the promise ledger\'s, not a new definition');
});

test('teardown removes a run\'s support cases through the routine, and stops on any it refuses', async () => {
  const { supportCaseSteps, SUPPORT_CASE_PURGE } = await import('../lib/demo_factory.mjs');
  const steps = supportCaseSteps('zztag001', '(select null::uuid)', '(select null::bigint)');
  const labels = steps.map(([l]) => l);
  assert.ok(labels.indexOf(SUPPORT_CASE_PURGE) >= 0 && labels.indexOf(SUPPORT_CASE_PURGE) < labels.indexOf('support_customer_profile'), 'cases go before their profiles');
  assert.ok(!steps.some(([, s]) => /^\s*delete from public\.support_case\b/.test(s)), 'no step deletes support_case directly');
  assert.match(steps.find(([l]) => l === SUPPORT_CASE_PURGE)[1], /public\.fn_demo_support_case_purge\(array\(/);
  const DF = read('scripts/lib/demo_factory.mjs');
  assert.match(DF, /if \(refused\.length\) \{\s+throw new Error/, 'a refused case stops the teardown and is named');
  assert.match(DF, /\.\.\.supportCaseSteps\(tag, CUST, LEAD\),/, 'teardown() runs these steps');
});

test('the sweep finds a Resend-sink signup run, and teardown takes the re-drawn quotation PDFs', () => {
  const FIX = read('scripts/e2e/fixtures.mjs');
  const fn = FIX.slice(FIX.indexOf('export async function staleRunTags'), FIX.indexOf('export async function sweepStaleRuns'));
  assert.match(fn, /from public\.customers where email like 'delivered\+qd-%@resend\.dev'/);
  assert.match(fn, /from auth\.users where email like 'delivered\+qd-%@resend\.dev'/);
  assert.match(read('scripts/lib/demo_factory.mjs'), /o\.bucket_id = 'quote-files'\s+and exists \(select 1 from public\.leads l where \$\{s\.lead\} and o\.name like 'quotes\/' \|\| l\.id::text \|\| '\/%'\)/);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('REPLAY: teardown\'s own support statements remove a ZZ DEMO case with its summary history', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const { replaySql } = await import('../lib/safe_replay.mjs');
  const { supportCaseSteps, SUPPORT_CASE_PURGE, countedDelete } = await import('../lib/demo_factory.mjs');
  const live = (await sql(`select count(*)::int n from pg_proc where proname = 'fn_demo_support_case_purge'`))[0].n;
  // Before merge the file rides in the same aborted transaction; after, it is live.
  const prefix = "select set_config('lock_timeout', '3s', true), set_config('statement_timeout', '60s', true);\n" + (live ? '' : SQL + '\n');
  const steps = supportCaseSteps('zzpurge1', '(select id from public.customers where email like \'qd-zzpurge1-%\')', '(select null::bigint)');
  const run = steps.map(([label, s], i) => label === SUPPORT_CASE_PURGE
    ? `  execute $s${i}$${s}$s${i}$ into v_n, v_ref; v_out := v_out || jsonb_build_object('purged', v_n, 'refused', v_ref);`
    : `  execute $s${i}$${countedDelete(s)}$s${i}$ into v_n; v_out := v_out || jsonb_build_object(${`'${label.replace(/'/g, "''")}'`}, v_n);`).join('\n');
  const block = `do $replay$
declare v_out jsonb := '{}'; v_n int; v_ref jsonb; v_open jsonb; v_prof bigint; v_case jsonb; v_id bigint;
begin
  v_open := public.fn_support_open_cases('unknown', null, 'qd-zzpurge1-c1@example.invalid', null);
  v_prof := (v_open ->> 'profile')::bigint;
  v_case := public.fn_support_case_route(v_prof, 'new', null, 'widget', 'ZZ DEMO teardown replay', 'en');
  v_id := (select case_id from public.support_case where case_ref = v_case ->> 'case_ref');
  perform public.fn_support_case_summary_write(v_case ->> 'case_ref', 0,
    '{"asked":"a quote","said_or_did":"asked for sizes","promised":[],"open":["sizes"]}', 'ASKED: a quote', 'ZZ DEMO replay', 'customer_support', 'replay');
${run}
  raise exception 'CHK<<%>>CHK', jsonb_build_object('removed', v_out,
    'versions_before_teardown_were', 1,
    'case_left', (select count(*) from public.support_case where case_id = v_id),
    'versions_left', (select count(*) from public.support_case_summary_version where case_id = v_id),
    'profile_left', (select count(*) from public.support_customer_profile where id = v_prof));
end $replay$;`;
  let msg = '';
  try { await replaySql(prefix + block, { label: 'demo support case teardown replay', retry: false }); } catch (e) { msg = String(e?.body ?? e?.message ?? e); }
  const m = msg.match(/CHK<<(.*)>>CHK/s);
  assert.ok(m, `the replay did not reach its verdict: ${msg.slice(0, 800)}`);
  const r = JSON.parse(m[1].replace(/\\"/g, '"'));
  assert.equal(r.removed.purged, 1, `one case purged: ${m[1]}`);
  assert.deepEqual(r.removed.refused, []);
  assert.equal(r.case_left, 0); assert.equal(r.versions_left, 0); assert.equal(r.profile_left, 0);
});
