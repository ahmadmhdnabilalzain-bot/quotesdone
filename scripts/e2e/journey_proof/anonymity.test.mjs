// The dossier's anonymity check finds an identity however a real document writes it, and does not cry wolf.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { scan, needles, normText, leakSentence } from './anonymity.mjs';

const ITEMS = [
  { label: "the old supplier's name", value: 'Falcon Trading', kind: 'name' },
  { label: "the customer's mobile", value: '+971 55 000 0499', kind: 'phone' },
  { label: "the old supplier's mobile", value: '050-000-0413', kind: 'phone' },
  { label: "the customer's e-mail", value: 'omar.haddad@zz-mail.example.invalid', kind: 'email' },
  { label: 'the villa number', value: 'Villa 15', kind: 'text' },
  { label: 'the area', value: 'Al Barsha 2', kind: 'text' },
  { label: "the old supplier's TRN", value: '100000000000412', kind: 'number' },
  { label: 'the surname', value: 'Haddad', kind: 'name' },
];

test('finds a phone written with spaces, dashes or Arabic-Indic digits', () => {
  for (const t of ['call 0550000499 now', 'Mob: 055 000 0499', '(+971) 55-000-0499', 'هاتف: ٠٥٥ ٠٠٠ ٠٤٩٩']) {
    const r = scan(ITEMS, [{ where: 'w', kind: 'pdf_text', text: t }]);
    assert.equal(r.rows.find((x) => x.label === "the customer's mobile").leak, true, t);
  }
  const r = scan(ITEMS, [{ where: 'w', kind: 'pdf_text', text: 'Mob: 050-000-0413 | Tel 04 000 0412' }]);
  assert.equal(r.rows.find((x) => x.label === "the old supplier's mobile").leak, true);
});

test('names and places match whole words, any case or punctuation', () => {
  const r = scan(ITEMS, [{ where: 'the inquiry PDF (text)', kind: 'pdf_text', text: 'Site: VILLA-15, al barsha 2 (near the mall). From FALCON  TRADING LLC.' }]);
  assert.equal(r.rows.find((x) => x.label === 'the villa number').leak, true);
  assert.equal(r.rows.find((x) => x.label === 'the area').leak, true);
  assert.equal(r.rows.find((x) => x.label === "the old supplier's name").leak, true);
  assert.equal(r.rows.find((x) => x.label === 'the surname').leak, false, 'not in the text');
  const r2 = scan(ITEMS, [{ where: 's', kind: 'screen', text: 'Haddadi Street; Villa 150; Al Barsha 21' }]);
  for (const l of ['the surname', 'the villa number', 'the area']) assert.equal(r2.rows.find((x) => x.label === l).leak, false, `${l} must be a whole-word match`);
});

test('an e-mail, a TRN inside other digits, PDF properties and file names are all surfaces', () => {
  const r = scan(ITEMS, [
    { where: 'the PDF properties', kind: 'pdf_props', text: 'Author: Omar.Haddad@ZZ-Mail.example.invalid' },
    { where: 'file name', kind: 'file_name', text: 'quote TRN-100 000 000 000 412.pdf' },
  ]);
  assert.equal(r.rows.find((x) => x.label === "the customer's e-mail").leak, true);
  assert.equal(r.rows.find((x) => x.label === "the old supplier's TRN").leak, true);
});

test('a picture-only surface is listed as not checked, never as clean', () => {
  const r = scan(ITEMS, [{ where: 'drawing page 1', kind: 'pdf_text', unreadable: true, why: 'the page is a picture', text: 'Villa 15' }]);
  assert.equal(r.leaks, 0);
  assert.deepEqual(r.not_checked, ['drawing page 1: the page is a picture']);
});

test('a value too short to look for is reported, not silently dropped', () => {
  const r = scan([{ label: 'villa digits', value: '15', kind: 'number' }], [{ where: 'x', kind: 'pdf_text', text: '15 m2' }]);
  assert.equal(r.rows.length, 0);
  assert.deepEqual(r.too_short_to_check, ['villa digits']);
});

test('the sentence the dossier prints says LEAK in plain words', () => {
  const r = scan(ITEMS, [{ where: 'the e-mail to the supplier', kind: 'message', text: 'New request from Villa 15' }]);
  const row = r.rows.find((x) => x.label === 'the villa number');
  assert.match(leakSentence(row, 'supplier'), /^LEAK: the villa number \("Villa 15"\) reached the supplier in the e-mail to the supplier\./);
  assert.match(leakSentence(r.rows.find((x) => x.label === 'the area'), 'supplier'), /not found in anything the supplier received/);
  assert.equal(normText('Al-Barsha  2'), ' al barsha 2 ');
  assert.equal(needles([{ label: 'p', value: '+971500000012', kind: 'phone' }])[0].probe, '500000012');
});
