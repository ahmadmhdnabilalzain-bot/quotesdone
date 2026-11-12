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
  // 12 Nov 2026 (customer_support, browser walk B1): the upload to storage now comes first and has its own failure line; this
  // holds the order for process_docs' answer, which is the one a lost answer can hide.
  assert.ok(up.indexOf('recheckLicenceStored') < up.indexOf("srvMsg(lang, j, t(lang, 'lic_upload_failed'))"), 'the recheck must come before the failure is said');
  const save = src.slice(src.indexOf('const save = async'), src.indexOf("missing.push('reg_profile')"));
  assert.match(save, /if \(!onFile\) \{ const row = await readRow\(\)/, 'Submit must read the row before it says the licence is missing');
  assert.match(save, /if \(!onFile\) missing\.push\('reg_licence'\)/);
});

// Final audit 12 Nov 2026, R2 (paid round of 11 Nov, run 1 J4, a phone photo): process_docs answered at 22:38:20.049 before the
// model's reading, the row was written 22:38:20.593, and the form said "has not finished" with the fields empty until Submit. This
// fails if the form does not look at the row again after such an answer, or keeps looking once the supplier has moved on.
import { awaitLateLicenceRead, LATE_READ_WAITS_MS, LICENCE_READING_NOTE, waitsForLateRead } from './licenceReceived.ts';
import { expiredLicenceNote, licenceHasExpired } from './licenceExpiry.ts';

test('a reading that lands after the answer is found on the row and handed back with its fields', async () => {
  const path = 'licenses/7/1_L4.jpg';
  const rows = [{ license_doc_path: path, licence_read_state: 'ours_failed' }, { license_doc_path: path, licence_read_state: 'ours_failed' },
    { license_doc_path: path, licence_read_state: 'read', trade_license_no: 'ZZ-4401', license_authority: 'Ajman DED', license_expiry: '2027-03-01' }];
  let reads = 0; const slept = [];
  const row = await awaitLateLicenceRead(async () => rows[Math.min(reads++, rows.length - 1)], path, { sleep: async (ms) => { slept.push(ms); } });
  assert.equal(row.trade_license_no, 'ZZ-4401');
  assert.equal(reads, 3, 'stops reading as soon as the reading landed');
  assert.deepEqual(slept, LATE_READ_WAITS_MS.slice(0, 3));
});

test('it gives up after about a minute, and stops at once when the supplier leaves or uploads another licence', async () => {
  const total = LATE_READ_WAITS_MS.reduce((a, b) => a + b, 0);
  assert.ok(total >= 55_000 && total <= 65_000, `the second look lasts ${total} ms, about 60 s (model reads up to 37.3 s measured)`);
  const path = 'licenses/7/1_L4.jpg';
  let reads = 0;
  assert.equal(await awaitLateLicenceRead(async () => { reads++; return { license_doc_path: path, licence_read_state: 'ours_failed' }; }, path, { sleep: noWait }), null);
  assert.equal(reads, LATE_READ_WAITS_MS.length, 'never read, the row is asked for each wait and the answer is null (the form keeps "not finished")');
  let left = false; reads = 0;
  const gone = awaitLateLicenceRead(async () => { reads++; left = true; return { license_doc_path: path, licence_read_state: 'ours_failed' }; }, path, { sleep: noWait, stop: () => left });
  assert.equal(await gone, null); assert.equal(reads, 1, 'leaving the form stops the second look');
  assert.equal(await awaitLateLicenceRead(async () => ({ license_doc_path: 'licenses/7/2_other.pdf', licence_read_state: 'read' }), path, { sleep: noWait }), null,
    'a row that names another licence is not this reading');
  assert.equal(await awaitLateLicenceRead(async () => { throw new Error('network'); }, path, { sleep: noWait, waits: [1, 1] }), null, 'a lost read is not a crash');
});

test('the form looks again after a late answer and fills what the row holds; the waiting note asks nothing of the supplier', () => {
  const form = readFileSync(new URL('./core/ProfileForm.tsx', import.meta.url), 'utf8');
  assert.match(form, /waitsForLateRead\(j\.extracted\) && licPath\.current\)[\s\S]{0,300}awaitLateLicenceRead\(readRow, path, \{ stop: \(\) => licUpload\.current !== upload \}\)/);
  assert.match(form, /useEffect\(\(\) => \(\) => \{ licUpload\.current\+\+; \}, \[\]\)/, 'leaving the form stops it');
  assert.match(form, /showLicenceRead\(row\.trade_license_no, row\.license_authority, row\.license_expiry\)/);
  assert.match(LICENCE_READING_NOTE, /being read/, 'the certification\'s licence step waits on "being read"');
  assert.doesNotMatch(LICENCE_READING_NOTE, /[؀-ۿ]|clearer|upload (it )?again|please send/i);
  const me = readFileSync(new URL('../../../../supabase/functions/supplier_api/lib/me_row.ts', import.meta.url), 'utf8');
  assert.match(me, /ME_COLUMNS = '[^']*\blicence_read_state\b/, 'me serves the read state the form waits on');
});

// Review of the fix (12 Nov 2026), blocking 1. J8, L8_rak_ded_expired.pdf: a TEXT licence code reads at once (state 'read', expiry
// 2026-08-31), while the model's read outlasts the 10 s budget (32-38% of reads). The form must keep saying the licence has
// expired, never replace it with "being read now". This fails if the late-read look starts for a licence code already read.
test('an expired text licence whose model read is late keeps its expired alert: no second look starts', () => {
  const extracted = { licence_read_after_answer: true, license_read_state: 'read', license: { license_number: 'ZZ-261150', expiry: '2026-08-31' } };
  assert.equal(waitsForLateRead(extracted), false, 'code read it: nothing is polled, nothing is replaced');
  assert.equal(licenceHasExpired(extracted.license.expiry, Date.parse('2026-11-12T08:00:00Z')), true);
  assert.match(expiredLicenceNote(extracted.license.expiry, 'ZZ-261150'), /expired on 31 Aug 2026/);
  assert.equal(waitsForLateRead({ licence_read_after_answer: true, license_read_state: 'ours_failed' }), true, 'a photo our reader has not read is looked at again');
  assert.equal(waitsForLateRead({ license_read_state: 'ours_failed' }), false, 'a read that did not outlast the answer is not');
  assert.equal(waitsForLateRead(null), false);
  // the form decides with this, so the expired branch above it is never overwritten by LICENCE_READING_NOTE
  const form = readFileSync(new URL('./core/ProfileForm.tsx', import.meta.url), 'utf8');
  assert.doesNotMatch(form, /licence_read_after_answer && licPath\.current/);
});

// Review of #1978, F7 (12 Nov 2026): while a newly attached licence was read, the panel's "Expiry" line kept the OLD licence's date
// (`ex.expiry || o.license_expiry`): for the founder, the 30 Oct 2026 that had refused him. The panel now holds only the new reading.
test("a new licence's panel holds only what was read off it: no old number, authority or expiry while it is read", async () => {
  const { licencePanelOf, LICENCE_PANEL_WHILE_READING } = await import('./licenceReceived.ts');
  assert.deepEqual(LICENCE_PANEL_WHILE_READING, { trade_license_no: '', license_authority: '', license_expiry: '' });
  // the answer read the number and the authority, the expiry not yet: no expiry line, never the old one
  assert.deepEqual(licencePanelOf({ license_number: 'ZZ-9990001', authority: 'ZZ Authority', expiry: null }),
    { trade_license_no: 'ZZ-9990001', license_authority: 'ZZ Authority', license_expiry: '' });
  // a row read again (the lost answer, the late read)
  assert.deepEqual(licencePanelOf({ trade_license_no: 'ZZ-9990001', license_authority: null, license_expiry: '2027-10-29' }),
    { trade_license_no: 'ZZ-9990001', license_authority: '', license_expiry: '2027-10-29' });
  assert.deepEqual(licencePanelOf(null), LICENCE_PANEL_WHILE_READING);
  const form = readFileSync(new URL('./core/ProfileForm.tsx', import.meta.url), 'utf8');
  assert.ok(!/license_expiry: (?:ex\.expiry|kept\.license_expiry|expiry) \|\| o\.license_expiry/.test(form), 'the form still falls back to the old expiry');
  assert.match(form, /setLicStage\('reading'\);[^\n]*\n[^\n]*\n\s*setF\(\(o\) => \(\{ \.\.\.o, \.\.\.LICENCE_PANEL_WHILE_READING \}\)\);/, 'the panel is not emptied while the new licence is read');
});

// Founder ruling 1668 (12 Nov 2026): a company profile attached as the licence was only ever "being read". The form now shows the
// server's sentence for a file that is not a licence: at the upload, on the late-read poll (a `me` row) and when it opens, and Submit
// stops on it.
test('a file that is not a licence is said in the server\'s words wherever the form learns it, and stops Submit', async () => {
  const { wrongDocumentNote } = await import('./licenceReceived.ts');
  const msg = 'This looks like a company profile, not a trade licence. Please attach your trade licence here. Your company profile goes in the Company profile box below.';
  assert.equal(wrongDocumentNote({ licence_wrong_document: { kind: 'company_profile', message: msg } }), msg);
  assert.equal(wrongDocumentNote({ licence_wrong_document: null }), '');
  assert.equal(wrongDocumentNote({}), '');
  assert.equal(wrongDocumentNote(null), '');
  const form = readFileSync(new URL('./core/ProfileForm.tsx', import.meta.url), 'utf8');
  assert.match(form, /if \(wrongDocumentNote\(j\.extracted\)\) \{/, 'the answer is not read for it');
  assert.match(form, /if \(wrongDocumentNote\(row\)\) \{ setLicWrong/, 'the late-read poll does not show it');
  assert.match(form, /useState\(wrongDocumentNote\(me\)\)/, 'the form does not open with it');
  assert.match(form, /if \(licWrong && licWrongBlocks\) \{ setMsg\(licWrong\); return; \}/, 'Submit does not stop on it');
  assert.match(form, /const licDone = licOnFile && !licExpired && !\(licWrong && licWrongBlocks\);/);
});

// Second review of #1978, A (12 Nov 2026): an approved supplier's accepted reading stays on the row while his new licence is read;
// the form opened meanwhile must not present those values as the new file's reading.
test('the form opens with no licence values while our reader has not finished the file on record', async () => {
  const { licencePanelOnLoad } = await import('./licenceReceived.ts');
  const me = { license_doc_path: 'licenses/1/new.pdf', trade_license_no: 'ZZ-OLD-0001', license_authority: 'ZZ Authority', license_expiry: '2026-10-30' };
  assert.deepEqual(licencePanelOnLoad({ ...me, licence_read_state: 'ours_failed' }), { trade_license_no: '', license_authority: '', license_expiry: '' });
  assert.deepEqual(licencePanelOnLoad({ ...me, licence_read_state: 'read' }), { trade_license_no: 'ZZ-OLD-0001', license_authority: 'ZZ Authority', license_expiry: '2026-10-30' });
  const form = readFileSync(new URL('./core/ProfileForm.tsx', import.meta.url), 'utf8');
  assert.match(form, /\.\.\.licencePanelOnLoad\(me\)/, 'the form does not open its panel through licencePanelOnLoad');
});

// Review of #1985 (D3): a file the model is sure is not a licence is never his licence file; the row is put back to the licence before it.
// The late-read poll must still land on it: `me` names the wrong file, and the poll shows its sentence instead of "being read".
test('the late-read poll lands on a wrong file the row was put back from', async () => {
  const { awaitLateLicenceRead, wrongDocumentNote } = await import('./licenceReceived.ts');
  const path = 'licenses/1/ZZ_DEMO_profile.pdf';
  const row = { license_doc_path: 'licenses/1/old_licence.pdf', licence_read_state: 'read', licence_wrong_document: { kind: 'company_profile', message: 'This looks like a company profile, not a trade licence.', path } };
  const got = await awaitLateLicenceRead(async () => row, path, { waits: [0], sleep: () => Promise.resolve() });
  assert.equal(wrongDocumentNote(got), 'This looks like a company profile, not a trade licence.');
  // another licence on the row and no finding for this file: the poll stops as before
  assert.equal(await awaitLateLicenceRead(async () => ({ license_doc_path: 'licenses/1/other.pdf', licence_read_state: 'read' }), path, { waits: [0], sleep: () => Promise.resolve() }), null);
});

// Second review of #1985, W3: Submit stops on a wrong file only when no licence was put back; a file a person is checking never stops it.
test('Submit stops on a wrong file only when nothing was put back, never on a file a person is checking', async () => {
  const { wrongDocumentBlocks } = await import('./licenceReceived.ts');
  assert.equal(wrongDocumentBlocks({ licence_wrong_document: { message: 'x', blocks_submit: true } }), true);
  assert.equal(wrongDocumentBlocks({ licence_wrong_document: { message: 'x', blocks_submit: false } }), false);
  assert.equal(wrongDocumentBlocks({ licence_wrong_document: { message: 'x', held: true, blocks_submit: false } }), false);
  assert.equal(wrongDocumentBlocks({}), false);
});
