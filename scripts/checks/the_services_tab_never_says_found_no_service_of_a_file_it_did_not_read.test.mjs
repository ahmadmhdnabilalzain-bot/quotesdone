// THE SERVICES TAB SAYS "FOUND NO SERVICE" ONLY OF A PROFILE IT READ AS TEXT. Seat: sales_engineer. 2 Nov 2026, ledger 1469.
// Found by scripts/e2e/supplier_profile_read_walk.mjs on the live site: a company profile saved as a PNG was read by the vision model, its two
// services were HELD for the sales engineer (status 'read', trades [], source 'photo_text', vision_held [..]) and the tab told the supplier
// "We read your company profile and found no service we could match", which is false of the file. A refused or unreadable file got "a scan or
// photo", also untrue. And "This page updates by itself when the read finishes" was printed by a tab that loaded once.
// Node strips the types from servicesCopy.ts on import. Each known-bad control is the exact record that produced the false sentence.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const { profileStateOf, VERIFY_COPY } = await import(new URL('../../src/components/portal/supplier/servicesCopy.ts', import.meta.url).href);
const TAB = fs.readFileSync(path.join(ROOT, 'src/components/portal/supplier/ServicesTab.tsx'), 'utf8');

test('known-bad (the live record before ledger 1442): trades held off a picture are NOT "found no service"', () => {
  const rec = { status: 'read', source: 'photo_text', choice: 'on', trades: [], vision_held: [{ code: 'elevators' }, { code: 'flooring' }] };
  assert.equal(profileStateOf([rec]), 'scan');
});
test('a picture or scan the model read and proposed trades from is "hits"; one it read and found nothing in is "found no service"', () => {
  assert.equal(profileStateOf([{ status: 'read', source: 'photo_text', choice: 'on', trades: [{ code: 'elevators' }] }]), 'hits');
  assert.equal(profileStateOf([{ status: 'read', source: 'photo_text', choice: 'on', trades: [] }]), 'none');
});
test('known-bad: a refused file, a CAD file, or a model that could not be reached is "could not read", not "found no service"', () => {
  for (const d of [{ status: 'refused' }, { status: 'needs_cad_conversion' }, { status: 'read', choice: 'unavailable', trades: [] }]) assert.equal(profileStateOf([d]), 'failed', JSON.stringify(d));
});
test('known-bad: a file that does not open (corrupt) says it is damaged, not "scan or photo"', () => {
  assert.equal(profileStateOf([{ status: 'unreadable' }]), 'damaged');
  assert.match(VERIFY_COPY.profile_damaged, /damaged/);
  assert.doesNotMatch(VERIFY_COPY.profile_damaged, /scan or photo/);
});
test('control: a text profile that named nothing is "found no service"', () => assert.equal(profileStateOf([{ status: 'read', source: 'document_text', choice: 'on', trades: [] }]), 'none'));
test('control: a text profile that named nothing because the readings disagreed is still "found no service"', () => assert.equal(profileStateOf([{ status: 'read', source: 'document_text', choice: 'held', trades: [] }]), 'none'));
test('control: trades win, then reading, then scan, then failed, then none, then missing', () => {
  assert.equal(profileStateOf([{ status: 'read', trades: [{ code: 'hvac' }] }, { status: 'unreadable' }]), 'hits');
  assert.equal(profileStateOf([{ status: 'reading' }, { status: 'needs_ocr' }]), 'reading');
  assert.equal(profileStateOf([{ status: 'needs_ocr' }, { status: 'unreadable' }]), 'scan');
  assert.equal(profileStateOf([]), 'missing');
});
test('every state has a sentence', () => { for (const s of ['none', 'reading', 'scan', 'damaged', 'failed', 'missing']) assert.ok(VERIFY_COPY['profile_' + s], s); });
test('the tab asks the one function, and keeps no second copy of the rule', () => {
  assert.match(TAB, /profileStateOf\(profileDocs\)/);
  assert.doesNotMatch(TAB, /x\.status === 'needs_ocr' \|\| x\.status === 'unreadable'/);
});
// ── review of #1796 ──
const R = await import(new URL('../../src/components/portal/supplier/servicesRead.ts', import.meta.url).href);
test('1. a refresh because the profile finished reading keeps the ticks, the removed trades, the roles, the text and the rewrite preview', () => {
  const cur = new Set(['aluminium.windows']), fresh = ['glazing.facade'];
  assert.deepEqual([...R.reloadSet(cur, fresh, true)], ['aluminium.windows']);          // known-bad: the old load() replaced it with the server's
  assert.deepEqual([...R.reloadSet(new Set(['hvac']), [], true)], ['hvac']);             // removed trades
  assert.deepEqual([...R.reloadSet(cur, fresh, false)], ['glazing.facade']);             // any other reload still takes the server's
  assert.deepEqual(R.reloadRoles(['installer'], ['supplier'], true), ['installer']);
  assert.deepEqual(R.reloadRoles([], ['supplier'], true), ['supplier']);                 // nothing chosen yet: the server's
  assert.equal(R.reloadText('We install lifts', 'saved text', true), 'We install lifts');
  assert.equal(R.reloadText('  ', 'saved text', true), 'saved text');
  assert.equal(R.reloadText('typed', 'saved text', false), 'saved text');
  assert.match(TAB, /if \(!keep\) \{ setRw\(null\); setDropped\(new Set\(\)\); \}/);
  assert.match(TAB, /setTicked\(\(cur\) => reloadSet\(cur, d\.selected_services, keep\)\)/);
  assert.match(TAB, /setRemovedTrades\(\(cur\) => reloadSet\(cur, \[\], keep\)\)/);
  assert.doesNotMatch(TAB, /setTicked\(new Set\(d\.selected_services\)\)/);
});
test('2. an Arabic line is shown nowhere: not in the summary, not in the "found in" list', () => {
  assert.deepEqual(R.englishLines(['- Elevator installation', 'أعمال تنسيق الحدائق', '', '  Flooring works ']), ['- Elevator installation', 'Flooring works']);
  assert.equal(R.isEnglishLine('أعمال العزل المائي'), false);
  assert.equal(R.isEnglishLine('Waterproofing 2020 (أعمال)'), false);   // a mixed line is Arabic to read
  assert.match(TAB, /isEnglishLine\(doc\.trades\[0\]\.snippet\)/);
  assert.doesNotMatch(TAB, /doc\.trades\[0\] && doc\.trades\[0\]\.snippet \?/);   // the old unfiltered condition
  assert.match(TAB, /const profileLines = englishLines\(/);
});
test('3. every line of the fallback list is worded from the document\'s real state, in plain English, never a raw code', () => {
  const states = [
    [{ status: 'needs_ocr' }, /no printed text/], [{ status: 'needs_ocr', reason: 'The picture is larger than 10 MB. Upload a smaller photo or a PDF.' }, /larger than 10 MB/],
    [{ status: 'unreadable' }, /damaged/], [{ status: 'refused' }, /file check/], [{ status: 'needs_cad_conversion' }, /converted/], [{ status: 'reading' }, /still being read/],
    [{ status: 'read', choice: 'unavailable' }, /not available/], [{ status: 'read', choice: 'held' }, /could not settle/],
    [{ status: 'read', vision_held: [{ code: 'x' }] }, /waiting for our sales engineer/], [{ status: 'read' }, /no service matched/], [{ status: 'mystery' }, /not read yet/],
  ];
  for (const [d, re] of states) { const line = R.docStateLine(d); assert.match(line, re, JSON.stringify(d)); assert.doesNotMatch(line, /needs_ocr|unreadable|refused|needs_cad|_/, line); }
  // known-bad: the old fallback said "read, no service matched" for a reading service that was down and for held trades
  assert.doesNotMatch(R.docStateLine({ status: 'read', choice: 'unavailable' }), /no service matched/);
  assert.doesNotMatch(R.docStateLine({ status: 'read', vision_held: [{}] }), /no service matched/);
  assert.match(TAB, /docStateLine\(doc\)/);
  assert.doesNotMatch(TAB, /doc\.status === 'read' \? VERIFY_COPY\.doc_read_none : doc\.status/);
});
test('"updates by itself" is true: while a profile is being read the tab asks again and reloads when it finishes', () => {
  assert.match(TAB, /x\.kind === 'profile' && x\.status === 'reading'/);
  assert.match(TAB, /services_state[\s\S]{0,200}going[\s\S]{0,200}load\(\{ keepText: true \}\)/);
  assert.match(TAB, /polls\.current >= 120/);
});
