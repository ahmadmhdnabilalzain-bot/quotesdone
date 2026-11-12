// node --test src/components/portal/supplier/fileCheck.test.mjs
// Browser perfection walk, 12 Nov 2026 (customer_support), B1, M1, M2, L4: a .docx licence was answered "Could not load this
// section", a HEIC after 25.5 s with the same sentence, an empty PDF was announced "Licence uploaded", a 15.33 MB file was called
// "14.6 MB", and a 4032x3024 phone photo went to the server whole. Each is decided in the browser now, in a true sentence.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fileKind, licenceFileProblem, paperFileProblem, shrinkSize, jpegName, mbText, PHOTO_MAX_EDGE, HEIC_SENTENCE } from './fileCheck.ts';

const f = (name, type, size) => ({ name, type, size });

test('the licence takes a PDF or a photo, and says at once and plainly what it cannot take', () => {
  assert.equal(licenceFileProblem(f('licence.pdf', 'application/pdf', 23_779)), null);
  assert.equal(licenceFileProblem(f('IMG_4032.jpg', 'image/jpeg', 4_321_364)), null, 'a photo is shrunk before its size is judged');
  assert.equal(licenceFileProblem(f('scan.png', 'image/png', 900_000)), null);
  assert.match(licenceFileProblem(f('licence.docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 1004)), /cannot read a \.docx file as a trade licence\. Please choose a PDF or a photo/);
  assert.equal(licenceFileProblem(f('IMG_0001.HEIC', 'image/heic', 1_600_024)), HEIC_SENTENCE);
  assert.equal(licenceFileProblem(f('IMG_0001.heic', '', 1_600_024)), HEIC_SENTENCE, 'a browser that names no type is read by the name');
  assert.match(licenceFileProblem(f('empty.pdf', 'application/pdf', 0)), /empty \(0 bytes\)/);
  assert.doesNotMatch(licenceFileProblem(f('licence.docx', '', 1004)), /Could not load this section/);
});

test('a licence over the read ceiling is refused with its true size; a photo only after it is shrunk', () => {
  assert.match(licenceFileProblem(f('big_15mb.pdf', 'application/pdf', 15_332_512)), /That file is 15\.3 MB\. We can read a licence of up to 10 MB/);
  assert.equal(licenceFileProblem(f('big.jpg', 'image/jpeg', 15_332_512)), null);
  assert.match(licenceFileProblem(f('big.jpg', 'image/jpeg', 15_332_512), { afterShrink: true }), /15\.3 MB/);
  assert.equal(mbText(15_332_512), '15.3 MB', 'counted as a phone counts it (L4: the walk read "14.6 MB")');
});

test('a profile or catalogue takes the six types the server takes, up to 100 MB', () => {
  for (const [n, t] of [['p.pdf', 'application/pdf'], ['p.docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'], ['p.pptx', 'application/vnd.openxmlformats-officedocument.presentationml.presentation'], ['p.jpg', 'image/jpeg'], ['p.png', 'image/png'], ['p.webp', 'image/webp']]) assert.equal(paperFileProblem(f(n, t, 1000)), null, n);
  assert.match(paperFileProblem(f('p.xlsx', 'application/vnd.ms-excel', 1000)), /cannot accept a \.xlsx file as your company profile/);
  assert.match(paperFileProblem(f('p.pdf', 'application/pdf', 0)), /empty/);
  assert.match(paperFileProblem(f('p.pdf', 'application/pdf', 101 * 1024 * 1024)), /up to 100 MB/);
});

test('a phone photo is drawn with its long edge at 2,000 px and its shape kept; a small one is left alone', () => {
  assert.deepEqual(shrinkSize(4032, 3024), { w: 2000, h: 1500 });
  assert.deepEqual(shrinkSize(3024, 4032), { w: 1500, h: 2000 });
  assert.equal(shrinkSize(1600, 1200), null);
  assert.equal(shrinkSize(PHOTO_MAX_EDGE, 900), null);
  assert.equal(jpegName('IMG_0001.HEIC'), 'IMG_0001.jpg');
  assert.equal(jpegName('licence.png'), 'licence.jpg');
  assert.equal(fileKind(f('a.PDF', '', 1)), 'pdf');
});
