// node --test src/components/portal/supplier/licenceReceived.test.mjs
// Free supplier registration certification, 11 Nov 2026, run 2, J5 desktop (customer_support): process_docs had the licence in
// storage 1.7 s in, the browser was cut off at ~30 s (net::ERR_FAILED), and the form said "We could not store your licence file";
// Submit then refused "Still needed to register: Trade licence". This fails if a lost answer is said as a failed store without
// the row being read again, or if Submit lists the licence as missing without asking the row.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { answerWasLost, licenceStoredSince, recheckLicenceStored, LICENCE_RECEIVED_NOTE } from './licenceReceived.ts';

const noWait = () => Promise.resolve();

test('an answer our function never gave is lost, not a refusal; our own refusal is a refusal', () => {
  for (const code of ['timeout', 'network', 'server_error', 'bad_response', 'worker_limit']) assert.equal(answerWasLost({ ok: false, code }), true, code);
  assert.equal(answerWasLost(null), true);
  for (const code of ['upload_failed', 'malware_detected', 'file_too_large', 'document_not_found', 'unsupported_type']) assert.equal(answerWasLost({ ok: false, code }), false, code);
  assert.equal(answerWasLost({ ok: true }), false);
});

test('a licence counts as received only when the row names a file other than the one before this upload', () => {
  assert.equal(licenceStoredSince('', { license_doc_path: 'licenses/157513/1794408330957_L5_rakez_scan.pdf' }), true);
  assert.equal(licenceStoredSince('licenses/1/a.pdf', { license_doc_path: 'licenses/1/a.pdf' }), false, 'the old licence is not the new one');
  assert.equal(licenceStoredSince('licenses/1/a.pdf', { license_doc_path: 'licenses/1/b.pdf' }), true);
  assert.equal(licenceStoredSince('', { license_doc_path: null }), false);
  assert.equal(licenceStoredSince('', null), false);
});

test('J5 replayed: the answer is lost at ~30 s, the row already names the file, and the recheck finds it', async () => {
  const row = { license_doc_path: 'licenses/157513/1794408330957_L5_rakez_scan.pdf', trade_license_no: null };
  let reads = 0;
  const found = await recheckLicenceStored(async () => { reads++; return row; }, '', { sleep: noWait });
  assert.deepEqual(found, row);
  assert.equal(reads, 1);
});

test('a row that names the file only on a later read is still found; one that never does is not', async () => {
  let n = 0;
  const late = await recheckLicenceStored(async () => (++n < 3 ? { license_doc_path: null } : { license_doc_path: 'licenses/9/x.png' }), null, { sleep: noWait });
  assert.equal(late && late.license_doc_path, 'licenses/9/x.png');
  let m = 0;
  const never = await recheckLicenceStored(async () => { m++; throw new Error('offline'); }, null, { tries: 3, sleep: noWait });
  assert.equal(never, null);
  assert.equal(m, 3, 'each try is made even when a read throws');
});

test('the received note says our reader has not finished, and never asks the supplier for anything', () => {
  assert.match(LICENCE_RECEIVED_NOTE, /received your trade licence/);
  assert.match(LICENCE_RECEIVED_NOTE, /not finished reading/);
  assert.doesNotMatch(LICENCE_RECEIVED_NOTE, /could not|try again|upload/i);
});

test('the registration form rechecks a lost licence answer, and Submit asks the row before listing the licence as missing', () => {
  const src = readFileSync(new URL('./core/ProfileForm.tsx', import.meta.url), 'utf8');
  const up = src.slice(src.indexOf('const upLicense'), src.indexOf('const save = async'));
  assert.match(up, /answerWasLost\(j\)\s*\?\s*await recheckLicenceStored\(readRow, before\)/, 'upLicense must recheck the row when the answer was lost');
  assert.ok(up.indexOf('recheckLicenceStored') < up.indexOf("t(lang, 'lic_upload_failed')"), 'the recheck must come before the failure is said');
  const save = src.slice(src.indexOf('const save = async'), src.indexOf("missing.push('reg_profile')"));
  assert.match(save, /if \(!onFile\) \{ const row = await readRow\(\)/, 'Submit must read the row before it says the licence is missing');
  assert.match(save, /if \(!onFile\) missing\.push\('reg_licence'\)/);
});
