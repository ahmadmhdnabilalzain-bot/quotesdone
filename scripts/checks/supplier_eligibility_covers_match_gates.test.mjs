// THE SCREEN THAT EXPLAINS WHY YOU ARE NOT MATCHED MUST KNOW EVERY GATE THAT EXCLUDES YOU.
//
// 13 Aug 2026. supplier_portal's `eligibility` action powers the "Your reach" panel, whose entire
// purpose is to answer a supplier asking "why am I not getting matched?". Its blocking[] list was
// built from the clauses in match_suppliers_kw. The path that actually builds an RFQ shortlist is
// fn_match_capability, and its candidate CTE opens with:
//
//     where sc.confirmed_at is not null    -- GATE: supplier confirmed their own scope
//
// which was in neither list. Measured on production by nulling confirmed_at for the one confirmed
// supplier: eligibility returned {eligible:true, blocking:[]} — a green "Eligible for matching"
// badge and an empty "Stopping requests reaching you" — while fn_match_capability(['hvac'])
// returned 0 rows in the same minute. 15,306 suppliers hold capability data; 1 has confirmed.
//
// This check fails when fn_match_capability grows a gate on supplier_capabilities that the panel
// does not mention, so the next gate cannot ship as silence.
//
//   node --test scripts/checks/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const SRC = readFileSync('supabase/functions/supplier_portal/index.ts', 'utf8');
const PORTAL = readFileSync('src/components/portal/SupplierPortal.tsx', 'utf8');

// The eligibility handler only — assertions about "the panel" must not be satisfied by a mention
// somewhere else in a 567-line file.
const eligibility = (() => {
  const at = SRC.indexOf("if (action === 'eligibility')");
  assert.ok(at > 0, 'supplier_portal no longer has an eligibility action');
  return SRC.slice(at);
})();

// And the BLOCKING half only. Measured while writing this file: the pre-change handler already
// contained the string `confirmed_at` — in the improving[] branch, which reads a pending
// supplier_capability_confirmation row. A check that searched the whole handler for a column name
// would therefore have passed on the exact code it exists to catch. The region that decides whether
// a supplier is told they are reachable ends where `improving` begins.
const blockingRegion = (() => {
  const end = eligibility.indexOf('const improving');
  assert.ok(end > 0, 'the eligibility handler no longer separates blocking from improving');
  return eligibility.slice(0, end);
})();

test('the eligibility panel evaluates the scope-confirmation gate before deciding eligible', () => {
  assert.match(blockingRegion, /supplier_capabilities/,
    'nothing before improving[] reads supplier_capabilities, so eligible:true is decided without '
    + 'knowing whether fn_match_capability can reach this supplier at all');
  assert.match(blockingRegion, /confirmed_at/,
    'the blocking half does not look at confirmed_at — the single clause excluding 15,305 of 15,306 suppliers');
});

test('an unconfirmed scope BLOCKS, it does not merely "improve ranking"', () => {
  // The distinction is the whole point: the panel separates what stops requests reaching you from
  // what only raises your rank. A pre-existing `confirm_scope` entry sits in improving[] and reads
  // as optional polish. Putting the gate there would be worse than silence.
  const push = blockingRegion.match(/blocking\.push\(\{[^}]*scope_unconfirmed[^}]*\}\)/s);
  assert.ok(push, 'scope_unconfirmed is not pushed onto blocking[] — if it is on improving[], a '
    + 'supplier who is invisible to every RFQ is still shown a green "Eligible for matching" badge');
  assert.match(push[0], /fix:\s*'scope'/,
    "the blocking item must route to the scope screen (fix:'scope'), or it names a problem with no way to fix it");
});

test('a failed capability read does not invent a green badge', () => {
  // capConfirmed starts false and is only ever set true by a successful read, so a database error
  // produces "not currently eligible" rather than a badge asserting something we could not check.
  assert.match(blockingRegion, /let capConfirmed = false;/,
    'capConfirmed must default to false so an unreadable row fails closed');
});

test('the portal can act on fix:\'scope\'', () => {
  // A blocking item whose fix code the client does not handle renders with no link at all: the
  // supplier is told what is wrong and given no way to it. 'profile' and 'documents' were the only
  // two handled for months.
  assert.match(PORTAL, /fix === 'scope'\) goScope\(\)/,
    "EligibilityPanel's go() does not handle fix:'scope'");
  assert.match(PORTAL, /goScope=\{\(\) => setTab\('scope'\)\}/,
    'EligibilityPanel is not given a goScope, so the scope link cannot navigate');
  assert.match(PORTAL, /it\.fix === 'scope'/,
    "the Row link is not rendered for fix:'scope', so the item appears with no call to action");
});

// ── AND THE LIVE HALF: every supplier_capabilities gate in fn_match_capability is accounted for ──
const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const mgmtToken = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();

// Columns fn_match_capability may gate on that a SUPPLIER cannot act on from the portal, or that
// are already covered by another blocking item. Anything not listed here must be explained by the
// panel. Keep this list short and justified — it is the escape hatch that makes the check useless
// if it grows carelessly.
const NOT_THE_SUPPLIER_S_TO_FIX = new Set([
  'supplier_id',        // the join key
  'trades',             // set by the same confirm step as confirmed_at; cannot be confirmed empty
  'roles',              // ditto — capability_agent refuses a confirm with no trade or no role
  'excluded_trades',    // a deliberate negative scope the supplier chose; not a fault to report
  'products_norm', 'brands', 'project_types',  // ranking inputs, already in improving[]
  'coverage_emirates', 'min_project_value', 'max_project_value',  // per-request, not per-supplier
  'authority_approvals',  // per-trade authority; surfaced by the trade licence items
]);

test('fn_match_capability has not grown a supplier_capabilities gate the panel cannot explain', async (t) => {
  if (!mgmtToken) {
    t.skip('no SUPABASE_ACCESS_TOKEN and no local access token, so the live routine cannot be read. '
      + 'The source assertions above still ran.');
    return;
  }
  const r = await fetch('https://api.supabase.com/v1/projects/htdblwldjkcgjvmqkbeh/database/query', {
    method: 'POST', headers: { Authorization: 'Bearer ' + mgmtToken, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: "select pg_get_functiondef(p.oid) as def from pg_proc p "
      + "join pg_namespace n on n.oid = p.pronamespace "
      + "where n.nspname = 'public' and p.proname = 'fn_match_capability'" }),
  });
  assert.ok(r.ok, `could not read fn_match_capability: ${r.status}`);
  const rows = await r.json();
  assert.equal(rows.length, 1, 'fn_match_capability is missing or overloaded');
  const def = String(rows[0].def);

  // The candidate CTE is the gate. Everything after `scored as (` is ranking.
  const from = def.indexOf('cand as (');
  const to = def.indexOf('scored as (');
  assert.ok(from > 0 && to > from, 'fn_match_capability no longer has the cand/scored shape this check parses');
  const gates = def.slice(from, to);

  const referenced = new Set([...gates.matchAll(/\bsc\.([a-z_]+)/g)].map((m) => m[1]));
  const unexplained = [...referenced]
    .filter((c) => !NOT_THE_SUPPLIER_S_TO_FIX.has(c))
    .filter((c) => !blockingRegion.includes(c))
    .sort();

  assert.deepEqual(unexplained, [],
    `fn_match_capability gates on supplier_capabilities.${unexplained.join(', ')} but supplier_portal's `
    + 'eligibility panel never mentions it. A supplier excluded by that clause is shown "Eligible for '
    + 'matching" and an empty blocking list. Add a blocking item, or add the column to '
    + 'NOT_THE_SUPPLIER_S_TO_FIX with the reason it is not theirs to fix.');

  console.log(`fn_match_capability gates on supplier_capabilities.{${[...referenced].sort().join(', ')}}; `
    + `${unexplained.length} unexplained by the eligibility panel.`);
});
