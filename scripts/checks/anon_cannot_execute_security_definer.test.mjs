// 19 AUG 2026. The Phase D §8 probe that calls RPCs directly as `anon` found
// public.fn_supplier_opportunities — SECURITY DEFINER, ranks open inquiries — answering an
// unauthenticated caller with HTTP 200. It returned `count: 0`, because the estate holds zero
// inquiries; a zero cannot tell a dead guard from an idle system, and the first live RFQ would have
// changed the payload rather than the permission.
//
// Six siblings were open the same way. The cause was a measurement defect, not an oversight:
// revoke_execute_on_trigger_only_secdef_fns.sql kept seven grants because the names appear in src/,
// and `grep -rn "\.rpc(" src/` returns ZERO occurrences in the entire frontend. The browser calls no
// database routine directly. The hit that produced the classification was a COMMENT.
//
// This is the check left behind so the fix cannot silently come undone. It matters because a plain
// CREATE re-grants EXECUTE to PUBLIC — only CREATE OR REPLACE preserves the ACL — so the regression
// is one careless DROP-and-recreate away, and nothing else in the suite would notice.
//
// The last assertion is a RATCHET rather than a demand for zero. 56 SECURITY DEFINER routines are
// still anon-executable, and they are NOT swept here on purpose: the original triage was right that
// each needs one look at its callers before its grant goes, and a blind sweep over 56 routines is
// how a security tidy-up becomes an outage. What the ratchet forbids is the number GROWING while
// nobody is watching. Lower it when routines are genuinely closed; raising it needs a reason.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

// THE SKIP IS node:test's OWN, not a top-level process.exit(0). Exiting before any test registers
// makes `node --test` report a file with ZERO tests, and a runner that reads that as success is how
// a check goes quiet without anyone noticing — the defect every_test_file_is_run.test.mjs exists
// for. A skipped test is visible in the summary; a file that vanished is not.
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

// The seven D35 closed. Named individually because these are the ones a probe PROVED reachable.
const REVOKED = [
  'fn_customer_preference_learn', 'fn_os_memory', 'fn_supplier_document_impact',
  'fn_supplier_knowledge_graph', 'fn_supplier_opportunities', 'fn_supplier_quote_recommend',
  'fn_supplier_twin',
];

// Measured on production 19 Aug 2026 immediately after D35, with has_function_privilege.
const ANON_CEILING = 56;
const AUTHENTICATED_CEILING = 60;

let rows = [], totals = {};
if (hasToken) {
  const { sql } = await import('../phase_c/lib/db.mjs');
  rows = await sql(`
    select p.proname,
           has_function_privilege('anon',          p.oid, 'EXECUTE') as anon_can,
           has_function_privilege('authenticated', p.oid, 'EXECUTE') as authed_can,
           has_function_privilege('service_role',  p.oid, 'EXECUTE') as service_can
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname in (${REVOKED.map((f) => `'${f}'`).join(',')})
     order by p.proname`);
  totals = (await sql(`
    select count(*) filter (where has_function_privilege('anon', p.oid,'EXECUTE'))          as anon_exec,
           count(*) filter (where has_function_privilege('authenticated', p.oid,'EXECUTE')) as authed_exec,
           count(*)                                                                          as total_secdef
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prosecdef`))[0];
}

test('the seven routines D35 closed are still closed to anon and authenticated', { skip: SKIP }, () => {
  assert.equal(rows.length, REVOKED.length,
    `expected ${REVOKED.length} routine(s), the database has ${rows.length}. A rename or a drop is itself the regression.`);
  const open = rows.filter((r) => r.anon_can || r.authed_can)
    .map((r) => `${r.proname}(${r.anon_can ? 'anon ' : ''}${r.authed_can ? 'authenticated' : ''})`);
  assert.deepEqual(open, [],
    'these SECURITY DEFINER routines are executable without a service role again:\n  ' + open.join('\n  ')
    + '\nA plain CREATE re-grants EXECUTE to PUBLIC. Re-apply scripts/sql/phase_d_d35_a_mention_is_not_a_call.sql,'
    + ' and revoke from PUBLIC first — revoke ... from anon against a PUBLIC grant is a silent no-op.');
});

test('the revoke did not take the grant the real callers depend on', { skip: SKIP }, () => {
  // Every real caller is an edge function using admin.rpc(...), i.e. the service role. If this goes
  // false the supplier portal stops working, and that failure must not look like a security win.
  const broken = rows.filter((r) => !r.service_can).map((r) => r.proname);
  assert.deepEqual(broken, [],
    'service_role lost EXECUTE on: ' + broken.join(', ')
    + ' — these are called from supplier_portal / customer_api / os_api and will now fail.');
});

test('the anon-executable SECURITY DEFINER surface has not grown', { skip: SKIP }, () => {
  console.log(`      ${totals.anon_exec} anon-executable and ${totals.authed_exec} authenticated-executable`
    + ` of ${totals.total_secdef} SECURITY DEFINER routine(s) in public`);
  assert.ok(Number(totals.anon_exec) <= ANON_CEILING,
    `${totals.anon_exec} SECURITY DEFINER routines are anon-executable; the disclosed ceiling is ${ANON_CEILING}.`
    + ' Something granted EXECUTE to PUBLIC or anon. Find it before lowering the bar —'
    + ' the browser calls no RPC directly, so no anon grant here is justified by a product surface.');
  assert.ok(Number(totals.authed_exec) <= AUTHENTICATED_CEILING,
    `${totals.authed_exec} are authenticated-executable; the disclosed ceiling is ${AUTHENTICATED_CEILING}.`);
});
