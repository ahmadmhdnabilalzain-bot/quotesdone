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
// The last assertion WAS a ratchet at 56 anon / 60 authenticated, held open because "each needs one
// look at its callers before its grant goes, and a blind sweep over 56 routines is how a security
// tidy-up becomes an outage."
//
// 20 AUG 2026 — scripts/sql/phase_d_e4_the_door_was_never_a_browser.sql took that look, function by
// function, and the ratchet is now a FLOOR of zero. What the per-function review found:
//
//   * `X.rpc(` across supabase/functions, src and scripts resolves to exactly three client
//     identifiers — admin (service_role, 279 sites), asUser (anon key + the caller's Bearer JWT,
//     4 sites) and sb (service_role, 1 site). All four asUser calls are in
//     supabase/functions/customer_documents/index.ts and reach exactly two routines.
//   * public.documents' RLS policy documents_customer_select calls fn_customer_document_refs, and a
//     policy expression is evaluated as the QUERYING role. That is a second, independent reason
//     that one routine keeps `authenticated`.
//   * No SECURITY INVOKER routine reachable by a client role calls any of the other 57, and no view
//     definition in public references one. The single invoker pair — fn_artifact_review_valid ->
//     fn_pick_reviewer — is a trigger function on public.artifact_review, where neither anon nor
//     authenticated holds INSERT, UPDATE or DELETE.
//
// So 57 were revoked from public, anon and authenticated (public FIRST — the grant was held through
// PUBLIC on 55 of them, and revoking from anon alone is a silent no-op), and TWO stay by name.
// Verified as the roles themselves on production: anon and authenticated get insufficient_privilege,
// authenticated still executes fn_customer_document_refs, service_role still executes the rest.
//
// The floor is zero, and the authenticated set is pinned by NAME rather than by count — a count
// alone would let one routine close while a different one opened.
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
// The exact string .github/workflows/project-parity.yml greps for. node:test prints a skip as
// `﹣ name # SKIPPED: reason`, which that grep does not match, so this file skipping inside the one
// CI job that holds the credential would read as a pass. E4 turned this from a ratchet into a gate;
// a gate that can go quiet is not one.
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

// The seven D35 closed. Named individually because these are the ones a probe PROVED reachable.
const REVOKED = [
  'fn_customer_preference_learn', 'fn_os_memory', 'fn_supplier_document_impact',
  'fn_supplier_knowledge_graph', 'fn_supplier_opportunities', 'fn_supplier_quote_recommend',
  'fn_supplier_twin',
];

// Measured on production 20 Aug 2026 immediately after E4, with has_function_privilege.
const ANON_CEILING = 0;
const AUTHENTICATED_CEILING = 2;

// The only two SECURITY DEFINER routines in public that a signed-in client role may execute, and the
// reason each one is here. Pinned by name: a bare count of 2 would stay green if one of these closed
// while some unrelated routine opened.
const AUTHENTICATED_BY_DESIGN = {
  fn_customer_document_refs:
    'called with the customer\'s own JWT at customer_documents/index.ts:148, AND used inside the RLS'
    + ' policy documents.documents_customer_select, which is evaluated as the querying role',
  fn_customer_documents:
    'called with the customer\'s own JWT at customer_documents/index.ts:125, :167 and :197',
};

let rows = [], totals = {}, stillOpen = [];
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
  stillOpen = await sql(`
    select p.proname,
           has_function_privilege('anon',          p.oid, 'EXECUTE') as anon_can,
           has_function_privilege('authenticated', p.oid, 'EXECUTE') as authed_can
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prosecdef
       and (has_function_privilege('anon', p.oid, 'EXECUTE')
         or has_function_privilege('authenticated', p.oid, 'EXECUTE'))
     order by p.proname`);
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

test('no SECURITY DEFINER routine in public is anon-executable', { skip: SKIP }, () => {
  console.log(`      ${totals.anon_exec} anon-executable and ${totals.authed_exec} authenticated-executable`
    + ` of ${totals.total_secdef} SECURITY DEFINER routine(s) in public`);
  const openToAnon = stillOpen.filter((r) => r.anon_can).map((r) => r.proname);
  assert.deepEqual(openToAnon, [],
    'these SECURITY DEFINER routines answer an unauthenticated caller:\n  ' + openToAnon.join('\n  ')
    + '\nSomething granted EXECUTE to PUBLIC or to anon — a plain CREATE does exactly that.'
    + ' The browser calls no RPC directly (grep -rn "\\.rpc(" src/ is 0), so no anon grant here is'
    + ' justified by a product surface. Revoke from public FIRST.');
  assert.equal(Number(totals.anon_exec), ANON_CEILING, `anon-executable count is ${totals.anon_exec}, not ${ANON_CEILING}`);
});

test('exactly the two customer-document routines are authenticated-executable', { skip: SKIP }, () => {
  // A count alone would stay green if one of the two closed while an unrelated routine opened, so
  // this compares the SET. Anything new here needs the same per-function review E4 did: who calls
  // it, with which client, and is it named in an RLS policy the querying role evaluates?
  const expected = Object.keys(AUTHENTICATED_BY_DESIGN).sort();
  const actual = stillOpen.filter((r) => r.authed_can).map((r) => r.proname).sort();
  assert.deepEqual(actual, expected,
    'the authenticated-executable SECURITY DEFINER set has changed.\n'
    + `  expected: ${expected.join(', ')}\n  actual:   ${actual.join(', ') || '(none)'}\n`
    + Object.entries(AUTHENTICATED_BY_DESIGN).map(([k, v]) => `  ${k} — ${v}`).join('\n')
    + '\nA routine that DISAPPEARED from this set breaks the customer portal documents tab, and'
    + ' dropping fn_customer_document_refs makes the documents RLS policy raise instead of filter.');
  assert.equal(Number(totals.authed_exec), AUTHENTICATED_CEILING,
    `${totals.authed_exec} are authenticated-executable; by design it is ${AUTHENTICATED_CEILING}.`);
});
