// A DOCUMENT UPLOAD THAT READS IS NOT CUT OFF BY THE PORTAL (28 Oct 2026, sales_engineer; production document walk).
//
// Measured on production with a ZZ DEMO invited supplier (scripts/e2e/supplier_document_walk.mjs, run e8d1e4b5, 1366 px):
// a phone photo of a trade licence uploaded on the Documents tab answered HTTP 200 after 18,019 ms, because
// supplier_portal save_documents reads the licence (license_extract, the vision model: 9.4 s at the gateway) before it
// answers. The portal's call() aborts at 20 s, so a read a few seconds slower told the supplier "We could not save that
// file" for a licence that was on record. The registration form's licence box (supplier_api process_docs) reads the same
// way with up to two attempts. Both calls now wait REASONING_TIMEOUT_MS, as the Services tab's reasoning calls do
// (scripts/checks/a_services_save_that_reasons_is_not_cut_off_by_the_portal.test.mjs); every other call keeps 20 s.
// 28 Oct 2026 (review of #1709): the quotation upload (supplier_api extract_quote) reads synchronously too: quote_extract's
// model read measured p50 15.5 s, p90 20.7 s, max 24.7 s over 30 days (ai_cost_log, n=29), so more than half of all
// quotation uploads were cut off at 20 s. It is held to the same wait.
//   node --test scripts/checks/a_document_upload_that_reads_is_not_cut_off_by_the_portal.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { readSupplierPortal } from '../lib/portal_sources.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const PORTAL = readSupplierPortal();
const API = readFileSync(root + 'src/components/portal/supplier/api.ts', 'utf8');
const MEASURED_MS = 18019;

const callOf = (action) => {
  const at = PORTAL.indexOf(`action: '${action}'`);
  assert.ok(at > 0, `${action} call not found in SupplierPortal.tsx`);
  const start = PORTAL.lastIndexOf('await call(', at);
  const end = PORTAL.indexOf(');', at);
  return PORTAL.slice(start, end + 2);
};

test('the Documents tab save, the registration licence upload and the quotation upload wait the reasoning timeout', () => {
  for (const action of ['save_documents', 'process_docs', 'extract_quote']) {
    const c = callOf(action);
    assert.match(c, /token, \{ timeoutMs: REASONING_TIMEOUT_MS \}\);$/, `${action} must pass { timeoutMs: REASONING_TIMEOUT_MS }: ${c.slice(0, 120)}`);
  }
  // './supplier/api' from the entry, '../api' from supplier/core/ (the portal was split there, 9 Nov 2026): the same module.
  assert.match(PORTAL, /import \{ call, REASONING_TIMEOUT_MS[^}]*\} from '(\.\/supplier|\.\.)\/api';/);
});

test('the reasoning timeout stays well over the measured read, and the default stays 20 s', () => {
  const m = API.match(/export const REASONING_TIMEOUT_MS = (\d+);/);
  assert.ok(m, 'REASONING_TIMEOUT_MS not found in api.ts');
  assert.ok(Number(m[1]) >= 4 * MEASURED_MS, `REASONING_TIMEOUT_MS ${m[1]} must stay well over the measured ${MEASURED_MS} ms`);
  assert.match(API, /const TIMEOUT_MS = 20000;/);
});
