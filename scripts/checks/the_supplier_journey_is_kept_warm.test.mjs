// THE SUPPLIER JOURNEY IS KEPT WARM, AND ITS FUNCTIONS DO NOT COMPILE SHEETJS AT BOOT (28 Sep 2026).
// Seat: it_engineer, with sales_engineer for the portal.
//
// Measured on 24 Sep: claim 9-10 s, Messages 5.8 s, Billing 5.7 s, Settings 7.8 s. Re-measured 28 Sep
// with a ZZ DEMO supplier: SQL on every one of those paths is under 25 ms (pg_stat_statements); the time
// was isolate boot (2.5-4.5 s on each function's first call) plus serial round trips. The boot had two
// causes this file guards: four of the journey's functions were not in resilience_ping's keep-warm list,
// and _shared/doc_read imported the ~1 MB SheetJS module statically, so supplier_api and supplier_portal
// compiled it on every cold start.
//
// Fails if a function the supplier's portal reads stops answering x-qd-warm, drops out of the keep-warm
// list, or if doc_read goes back to a static SheetJS import.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { warmable } from '../lib/warm_functions.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const read = (p) => readFileSync(root + p, 'utf8');
const source = (s) => read(`supabase/functions/${s}/index.ts`);

// The journey: claim_lookup (the invitation), supplier_api (claim, me, projects, settings), supplier_portal
// (dashboard), and every function the tab prefetch names.
function journeyFunctions() {
  const pre = read('src/components/portal/supplier/tabPrefetch.ts');
  const fromPrefetch = [...pre.matchAll(/call\('([a-z_]+)'/g)].map((m) => m[1]);
  assert.ok(fromPrefetch.length >= 3, `tabPrefetch.ts names ${fromPrefetch.length} functions; expected at least 3`);
  return [...new Set(['claim_lookup', 'supplier_api', 'supplier_portal', 'kyc', ...fromPrefetch])].sort();
}

test('every function on the supplier journey answers the keep-warm header', () => {
  const fns = journeyFunctions();
  assert.deepEqual(warmable(fns, source).sort(), fns, 'a supplier-journey function no longer answers x-qd-warm');
});

test('resilience_ping keeps every supplier-journey function warm', () => {
  const src = source('resilience_ping');
  const m = src.match(/const targets = \[([^\]]+)\]/);
  assert.ok(m, 'resilience_ping has no keep-warm targets list');
  const targets = [...m[1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1]);
  const missing = journeyFunctions().filter((f) => !targets.includes(f));
  assert.deepEqual(missing, [], `resilience_ping does not keep these warm: ${missing.join(', ')}`);
});

test('doc_read loads SheetJS on first use, never at boot', () => {
  for (const f of ['office.ts', 'ole.ts']) {
    const code = read(`supabase/functions/_shared/doc_read/${f}`).replace(/\/\/.*$/gm, '');
    assert.doesNotMatch(code, /^\s*import\s+(?!type\b)[^;]*sheetjs[^;]*xlsx\.mjs/m, `${f} imports SheetJS statically again`);
  }
});
