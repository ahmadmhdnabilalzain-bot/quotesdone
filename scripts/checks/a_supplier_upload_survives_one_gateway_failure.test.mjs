// A SUPPLIER'S UPLOAD SURVIVES A BUSY PLATFORM (2 Nov 2026, sales_engineer; supplier walk 41379033121, mobile).
// MEASURED: on the walk's Submit the profile reached storage in 2 s, then ONE 502 (217 ms, edge gateway, during a burst of
// 502/503/546 while several walks and applies ran) hit the catalogue's upload_url call. uploadDirect had no retry, so
// the form showed "The file could not be uploaded", the profile was never saved and every later step failed.
//   node --test scripts/checks/a_supplier_upload_survives_one_gateway_failure.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { retryTransient, isTransientUploadError } from '../../src/lib/signedUpload.ts';
import { readSupplierPortal } from '../lib/portal_sources.mjs';

test('one 502 is retried and the upload completes', async () => {
  let n = 0;
  const r = await retryTransient(async () => (++n === 1 ? { error: { code: 'load_failed', _http: 502 } } : { path: 'p' }), 3, 1);
  assert.equal(r.path, 'p'); assert.equal(n, 2);
});
test('KNOWN-BAD CONTROL: a refusal (400/401/403) is not retried', async () => {
  let n = 0;
  const r = await retryTransient(async () => { n++; return { error: { code: 'file_too_big', _http: 400 } }; }, 3, 1);
  assert.equal(n, 1); assert.ok(r.error);
});
test('KNOWN-BAD CONTROL: a failure that never clears stops after 3 tries and is reported', async () => {
  let n = 0;
  const r = await retryTransient(async () => { n++; return { error: { status: 546 } }; }, 3, 1);
  assert.equal(n, 3); assert.ok(r.error);
});
test('what counts as transient', () => {
  for (const e of [{ status: 0 }, { status: 503 }, { _http: 546 }, { code: 'timeout' }, { code: 'network' }, { code: 'bad_response', _http: 502 }]) assert.ok(isTransientUploadError(e), JSON.stringify(e));
  for (const e of [null, { status: 413 }, { _http: 401 }, { code: 'bad_response', _http: 404 }]) assert.ok(!isTransientUploadError(e), JSON.stringify(e));
});
test('the portal uploads through retryTransient', () => {
  const s = readSupplierPortal();
  assert.match(s, /const uploadDirect = \(kind, file, token\) => retryTransient\(/);
});
