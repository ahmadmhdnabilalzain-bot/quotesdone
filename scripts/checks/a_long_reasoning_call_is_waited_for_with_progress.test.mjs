// A LONG REASONING CALL IS WAITED FOR, WITH PROGRESS (it_engineer, 12 Nov 2026; founder ledger 1642: "thinking that needs longer
// ... its wait is lengthened where the person is shown progress"; final audit 2026-11-12 section 3, E3 and E4).
//
// Measured on the 11-12 Nov journey runs, after effort was raised to high on 11 Nov (f78d2e916):
//   - the customer's comparison (quote_compare, quote_comparison at high): a fresh one took 42-74 s (ai_cost_log p50 53.3 s,
//     max 70.6 s); Comparison.tsx waited the portal's default 30 s and showed "We could not prepare the comparison report"
//     2 of 2 times;
//   - the supplier's "check before sending" (supplier_api dry run): 6 of 8 outlasted the supplier portal's 20 s default, up
//     to 66.6 s, and the supplier read "could not submit" for a check that was still working.
// Each now waits the long timeout its portal already has for such a call (the comparison PDF's, the reasoning actions'), and
// says it is still working after STILL_WORKING_MS (src/lib/stillWorking.ts, the pattern of the chat and the request screen).
// Offline, reading the sources and the real constants.
//   node --test scripts/checks/a_long_reasoning_call_is_waited_for_with_progress.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const read = (p) => readFileSync(root + p, 'utf8');
const num = (src, name) => Number((src.match(new RegExp(`const ${name} = (\\d+)`)) || [])[1]);
const COMPARISON = read('src/components/me/requests/Comparison.tsx');
const QUOTE_FORM = read('src/components/portal/supplier/core/QuoteForm.tsx');
const ME_API = read('src/components/me/api.ts');
const SUP_API = read('src/components/portal/supplier/api.ts');
const STILL = num(read('src/lib/stillWorking.ts').replace('export const STILL_WORKING_MS = 8_000', 'const STILL_WORKING_MS = 8000'), 'STILL_WORKING_MS');
const MEASURED_COMPARISON_MS = 74_000, MEASURED_CHECK_MS = 66_600, EDGE_WALL_MS = 150_000;

test('the comparison waits longer than it was measured to take, and says it is still working', () => {
  const wait = num(ME_API, 'COMPARE_PDF_TIMEOUT_MS');
  assert.ok(wait > MEASURED_COMPARISON_MS && wait <= EDGE_WALL_MS, `COMPARE_PDF_TIMEOUT_MS ${wait}`);
  assert.match(COMPARISON, /call\('quote_compare', \{ inquiry_id: inqId, lang \}, token, COMPARE_PDF_TIMEOUT_MS\)/, 'the comparison call waits only the 30 s default');
  assert.match(COMPARISON, /setTimeout\(\(\) => \{ if \(on\) setSlow\(true\); \}, STILL_WORKING_MS\)/);
  assert.match(COMPARISON, /\{slow \? <div[^>]*>\{t\(lang, 'cmp_still'\)\}<\/div> : null\}/, 'the busy panel never says it is still working');
  const pt = read('src/components/me/portalText.ts');
  assert.equal((pt.match(/cmp_still: '/g) || []).length, 2, 'cmp_still in English and Arabic');
  // what it says is what was measured (42-74 s): "a minute or two", never "up to a minute" (review of 12 Nov 2026)
  assert.match(pt, /cmp_still: 'Still working: a full comparison of every quote can take a minute or two\./);
  assert.ok(!/cmp_still: '[^']*up to a minute/.test(pt));
  assert.ok(STILL > 0 && STILL < 30_000);
  // WHICH CLOCK BINDS (review of 12 Nov 2026). quote_compare bounds its model call at min(what is left of its own
  // COMPARE_WALL_MS, 100 s), so the gateway's wall (97 s) binds first, and a cut model is answered by the deterministic
  // ranking, labelled degraded; quote_compare answers inside its 140 s, 10 s before the edge wall. The portal waits 150 s,
  // longer than that, so the customer reads quote_compare's answer (or its error card), never a silent kill.
  const qc = read('supabase/functions/quote_compare/index.ts');
  const wall = num(qc, 'COMPARE_WALL_MS');
  assert.match(qc, /client_timeout_ms: Math\.min\(leftMs, 100000\)/);
  assert.ok(wall <= EDGE_WALL_MS - 10_000 && wait > wall, `quote_compare ${wall} ms inside the edge wall, the portal's ${wait} ms past it`);
});

test("the supplier's check before sending waits the reasoning timeout, and says it is still checking", () => {
  const wait = num(SUP_API, 'REASONING_TIMEOUT_MS');
  assert.ok(wait > MEASURED_CHECK_MS && wait <= EDGE_WALL_MS, `REASONING_TIMEOUT_MS ${wait}`);
  // 15 Nov 2026: the payload also carries the currency the supplier typed (a non-AED total is refused, ruling 1008)
  assert.match(QUOTE_FORM, /call\('supplier_api', \{ \.\.\.buildPayload\(\),(?: currency,)? dry_run: true \}, token, \{ timeoutMs: REASONING_TIMEOUT_MS \}\)/, 'the dry run waits only the 20 s default');
  assert.match(QUOTE_FORM, /setTimeout\(\(\) => setMsg\(t\(lang, 'check_still'\)\), STILL_WORKING_MS\)/);
  assert.match(read('src/components/portal/supplier/core/copy.ts'), /check_still:'Still checking your quote\./);
});

// THE DRY RUN RESTORES OR DELETES THE QUOTE ROW WHEN IT ENDS (supplier_api/actions/quotes.ts), so a quote submitted while the
// check runs (now up to 90 s) would be undone by it (review of 12 Nov 2026). Submit is closed while checking, in the button
// and in the handler (a keyboard or a stale render cannot reach it either).
test('a quote cannot be submitted while its check is running', () => {
  assert.match(QUOTE_FORM, /<Button size="sm" disabled=\{checking \|\| busy \|\| reading\} onClick=\{submit\}>/, 'Submit is enabled during the check');
  assert.match(QUOTE_FORM, /const submit = async \(\) => \{\n    if \(inFlight\.current \|\| checking\) return;/, 'the submit handler runs during the check');
  assert.match(QUOTE_FORM, /disabled=\{checking \|\| busy \|\| reading\} onClick=\{check\}/, 'the check runs during a submit');
});
