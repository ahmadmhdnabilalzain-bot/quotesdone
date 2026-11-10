// THE SCREEN THAT EXPLAINS WHY YOU ARE NOT MATCHED MUST KNOW EVERY GATE THAT EXCLUDES YOU.
//
// REVIVED 10 Nov 2026 (customer_support; item 9 of the supplier-journey audit's report, #1901) for the rebuilt panel:
// supplier_portal/overview.ts buildEligibility, which the dashboard's "Get matched" checklist renders. Retired 8 Sep 2026
// with the old supplier_portal it read (it was scripts/checks/retired/supplier_eligibility_covers_match_gates.RETIRED.mjs,
// moved here); its reasoning stands and is kept below.
//
// 13 Aug 2026. The panel's blocking[] list was built from match_suppliers_kw while the path that builds an RFQ shortlist is
// fn_match_capability, whose candidate CTE opened with `where sc.confirmed_at is not null`: a supplier who had not
// confirmed his scope read a green "Eligible for matching" badge while excluded from every RFQ.
// 10 Nov 2026. The same defect, twice more: fn_match_capability also excludes a supplier who said he is busy or paused
// (public.fn_supplier_available on supplier_availability) and, through fn_is_matchable, one at the no-response strike
// limit (chat_strikes < fn_matching_strike_limit()). buildEligibility read neither.
//
// This fails when the matcher's candidate gates (read from the committed schema mirror, which equals production on every
// PR, so it runs offline) name something the panel's BLOCKING half does not: a supplier_capabilities column, a
// fn_is_matchable argument's column, the availability rule, or any other gate routine called in the candidate WHERE.
// Behaviour: supabase/functions/supplier_portal/overview.test.ts ("a supplier who paused new requests is not eligible", ...).
//   node --test scripts/checks/supplier_eligibility_covers_match_gates.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const OVERVIEW = readFileSync('supabase/functions/supplier_portal/overview.ts', 'utf8');
const MIRROR = readSchemaMirror();

// The eligibility builder only, and its BLOCKING half: the region that decides whether a supplier is told he is reachable
// ends where `improving` begins (a column named only in improving[] reads as optional polish, which is worse than silence).
const blockingRegion = (() => {
  const at = OVERVIEW.indexOf('export async function buildEligibility(');
  assert.ok(at > 0, 'supplier_portal/overview.ts no longer has buildEligibility');
  const end = OVERVIEW.indexOf('const improving', at);
  assert.ok(end > at, 'buildEligibility no longer separates blocking from improving');
  return OVERVIEW.slice(at, end);
})();

/** A routine's definition from the mirror (CREATE OR REPLACE FUNCTION public.<name>( ... up to its closing tag). */
function routine(name) {
  const at = MIRROR.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  assert.ok(at >= 0, `the schema mirror has no ${name}`);
  const open = MIRROR.indexOf('AS $function$', at);
  return { head: MIRROR.slice(at, open), body: MIRROR.slice(open, MIRROR.indexOf('$function$', open + 14)) };
}

// Columns fn_match_capability may gate on that a SUPPLIER cannot act on from the portal, or that another blocking item
// already covers. Keep it short and justified: it is the escape hatch that makes the check useless if it grows carelessly.
const NOT_THE_SUPPLIER_S_TO_FIX = new Set([
  'supplier_id',        // the join key
  'trades',             // set by the same confirm step as confirmed_at; capability_agent refuses a confirm with none
  'roles',              // ditto
  'excluded_trades',    // a deliberate negative scope the supplier chose; not a fault to report
  'products_norm', 'brands', 'project_types', 'services', 'services_removed',   // ranking / per-request inputs
  'coverage_emirates', 'min_project_value', 'max_project_value',               // per request, not per supplier
  'authority_approvals',
]);
// Gate routines the candidate WHERE may call, and the words the blocking half must carry for each.
const GATE_ROUTINES = {
  fn_is_matchable: null,   // expanded from its own arguments below
  fn_supplier_available: ['supplier_availability', 'busy_until', "avState === 'available'"],
};

const cand = (() => {
  const { body } = routine('fn_match_capability');
  // The candidate CTE is the gate; it ends at its own closing `),` (what follows, eff / svc / scored, is ranking).
  const from = body.indexOf('cand as (');
  const to = body.indexOf('\n),', from);
  assert.ok(from > 0 && to > from && body.indexOf('scored as (') > to, 'fn_match_capability no longer has the cand ... scored shape this check parses');
  const c = body.slice(from, to).replace(/--[^\n]*/g, '');
  return c.slice(c.search(/\bwhere\b/));
})();

test('the panel evaluates the scope-confirmation gate before deciding eligible, and it BLOCKS', () => {
  assert.match(blockingRegion, /supplier_capabilities/);
  assert.match(blockingRegion, /confirmed_at/);
  const push = blockingRegion.match(/blocking\.push\(\{ code: 'scope_unconfirmed'[\s\S]*?fix: 'scope' \}\)/);
  assert.ok(push, "scope_unconfirmed must be pushed onto blocking[] with fix:'scope'");
});

test('every supplier_capabilities gate of fn_match_capability is explained by the panel', () => {
  const referenced = new Set([...cand.matchAll(/\bsc\.([a-z_]+)/g)].map((m) => m[1]));
  const unexplained = [...referenced].filter((c) => !NOT_THE_SUPPLIER_S_TO_FIX.has(c) && !blockingRegion.includes(c)).sort();
  assert.deepEqual(unexplained, [], `fn_match_capability gates on supplier_capabilities.${unexplained.join(', ')} and the panel never says so`);
});

test('every gate routine in the candidate WHERE is known, and the panel carries what it decides on', () => {
  const called = [...new Set([...cand.matchAll(/public\.(fn_[a-z_]+)\(/g)].map((m) => m[1]))].sort();
  const unknown = called.filter((f) => !(f in GATE_ROUTINES));
  assert.deepEqual(unknown, [], `fn_match_capability's candidates are gated by ${unknown.join(', ')}, which this check (and so the panel) does not know`);
  for (const [fn, words] of Object.entries(GATE_ROUTINES)) {
    if (!words || !called.includes(fn)) continue;
    for (const w of words) assert.ok(blockingRegion.includes(w), `${fn} gates matching but the panel's blocking half never mentions ${w}`);
  }
});

test("every argument of fn_is_matchable is a column the panel reads and decides on; the strike limit is the database's", () => {
  const call = cand.match(/fn_is_matchable\(([^)]*)\)/);
  assert.ok(call, 'the candidates are no longer gated by fn_is_matchable');
  const cols = call[1].split(',').map((x) => x.trim().replace(/^[a-z]+\./, ''));
  const { head, body } = routine('fn_is_matchable');
  assert.equal(cols.length, (head.match(/\bp_[a-z_]+\b/g) || []).length, 'fn_is_matchable takes an argument the matcher does not pass');
  const select = (blockingRegion.match(/\.select\('([^']+)'\)/) || [])[1] || '';
  const decides = blockingRegion.slice(blockingRegion.indexOf('const r = '));
  for (const c of cols) {
    assert.ok(select.split(',').includes(c), `buildEligibility does not read leads.${c}, which fn_is_matchable decides on`);
    assert.match(decides, new RegExp(`\\br\\.${c}\\b`), `the panel reads ${c} but never decides on it`);
  }
  if (/fn_matching_strike_limit\(\)/.test(body)) assert.match(blockingRegion, /rpc\('fn_matching_strike_limit'\)/, 'the strike limit must be read from fn_matching_strike_limit, never retyped');
});

test('the portal can act on every fix the blocking half names', () => {
  const fixes = [...new Set([...blockingRegion.matchAll(/fix: '([a-z_]+)'/g)].map((m) => m[1]))];
  const tabs = readFileSync('src/components/portal/supplier/core/tabs.ts', 'utf8');
  const getMatched = readFileSync('src/components/portal/supplier/GetMatched.tsx', 'utf8');
  for (const f of fixes) {
    if (f === 'contact') continue;   // no link by design
    assert.ok(new RegExp(`'${f}'|\\b${f}:`).test(tabs), `fix:'${f}' names no portal tab or alias, so the link goes nowhere`);
    if (f !== 'profile') assert.match(getMatched, new RegExp(`fix === '${f}' \\?`), `GetMatched labels fix:'${f}' as "Go to Profile"`);
  }
});
