// Teardown removes every supplier-door malware scan of the run's own leads, not only the catalogue ingest's.
// Run 390dafcc (27 Oct 2026, it_engineer): the registration walk's licence was scanned under 'supplier_portal.license',
// teardown deleted only source = 'supplier_catalog_ingest', and verify-clean found 1 file_scan row.
//   node --test scripts/e2e/teardown_file_scan.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const SRC = readFileSync(new URL('../lib/demo_factory.mjs', import.meta.url), 'utf8');

test("file_scan teardown covers every 'supplier%' source, scoped to the run's own leads", () => {
  assert.match(SRC, /\['file_scan', `delete from public\.file_scan where source like 'supplier%' and subject in \$\{LEAD_T\}`\]/);
  assert.doesNotMatch(SRC, /file_scan where source = 'supplier_catalog_ingest'/);
});
