// drawingGlance.test.mjs — a drawing is understood at once (19 Nov 2026, sales_engineer; founder ruling 1533).
// node --test src/components/me/drawingGlance.test.mjs
// ./drawingGlance.ts has the measurement: the customer's first answer came p50 109.5 s / p90 129.5 s after the server call.
// Proved here: the glance names the sheets, trades and kinds of sheet from fixed lists; it never echoes a word of the
// drawing (a title block's name, villa, plot or e-mail cannot reach it); a scan is said to be one; and the portal says it
// beside the server's read, never before it or instead of it. Fixtures are ZZ DEMO text.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { glanceOf, glanceText, TRADE_MIN_HITS } from './drawingGlance.ts';

const TITLE = 'ZZ DEMO CLIENT LLC  VILLA 15 AL BARSHA 2  PLOT 345-1234  zz.owner@example.invalid  +971 50 000 0012  DRAWN BY ZZ DEMO CONSULTANTS';
const hvacSet = [
  `GROUND FLOOR HVAC DUCT LAYOUT  FCU-1 FCU-2 SUPPLY DIFFUSER 600x600  ${TITLE}`,
  `FIRST FLOOR DUCT LAYOUT  AHU-01 RETURN GRILLE  DAMPER  ${TITLE}`,
  `ROOF PLAN  CHILLER CH-1  EXHAUST FAN EF-1  ${TITLE}`,
  `EQUIPMENT SCHEDULE  FCU AHU CHILLER  ${TITLE}`,
  `DRAINAGE LAYOUT  FLOOR DRAIN  SOIL PIPE 110 UPVC  ${TITLE}`,
  `SECTIONS AND DETAILS  DUCT SUPPORT DETAIL  ${TITLE}`,
  `SPRINKLER LAYOUT  ${TITLE}`,
  `LIGHTING LAYOUT  DB-1 ${TITLE}`,
];

test('an 8-sheet set is named by its sheets, its trades (most mentioned first) and its kinds of sheet', () => {
  const g = glanceOf(hvacSet, 8);
  assert.equal(g.sheets, 8);
  assert.equal(g.scanned, false);
  assert.equal(g.trades[0], 'hvac');
  assert.ok(g.trades.includes('plumbing'));
  assert.ok(g.trades.length <= 3);
  for (const k of ['layout', 'schedule', 'section', 'detail']) assert.ok(g.kinds.includes(k), k);
  const en = glanceText(g, 'en', '8 pages');
  assert.match(en, /^I have your drawing: 8 pages of HVAC/);
  assert.match(en, /checking every sheet before any supplier sees it/);
});

test('a trade mentioned once is not a trade', () => {
  assert.ok(TRADE_MIN_HITS >= 2);
  const g = glanceOf(['GROUND FLOOR HVAC DUCT LAYOUT  DUCT 300x200', 'ONE SPRINKLER NOTE'], 2);
  assert.deepEqual(g.trades, ['hvac']);
});

test('no word of the drawing is ever echoed: the title block cannot reach the glance', () => {
  const g = glanceOf(hvacSet, 8);
  for (const lang of ['en', 'ar']) {
    const s = glanceText(g, lang, lang === 'ar' ? '8 صفحات' : '8 pages');
    for (const leak of ['ZZ', 'DEMO', 'VILLA', 'Villa', 'BARSHA', 'Barsha', '345', '1234', '@', 'example', '971', 'CONSULTANTS', 'FCU-1', 'CH-1'])
      assert.ok(!s.includes(leak), `${lang} glance echoes ${leak}: ${s}`);
  }
});

test('a scan or a picture with no text layer is said to be one, with no trade guessed', () => {
  const g = glanceOf(['', ' ', ''], 3);
  assert.equal(g.scanned, true);
  assert.match(glanceText(g, 'en', '3 pages'), /3 pages, scanned with no text layer/);
  assert.match(glanceText(g, 'ar', '3 صفحات'), /ممسوحة ضوئيًا/);
});

test('Arabic names the trades in Arabic', () => {
  const ar = glanceText(glanceOf(hvacSet, 8), 'ar', '8 صفحات');
  assert.match(ar, /^استلمتُ مخططكم: 8 صفحات من أعمال التكييف والتهوية/);
  assert.ok(!/[A-Za-z]/.test(ar), ar);
});

test('nothing read is no glance', () => {
  assert.equal(glanceOf([], 0), null);
});

test('wired: the portal says the glance beside the read, never awaiting it, and reads text without rendering a page', () => {
  const nr = readFileSync(new URL('./NewRequest.tsx', import.meta.url), 'utf8');
  const onFile = nr.slice(nr.indexOf('const onFile = async'));
  const at = onFile.indexOf("glance(file).then(");
  assert.ok(at > 0, 'onFile starts the glance');
  assert.ok(at < onFile.indexOf('await fileToImages(file)'), 'the glance starts before the pages are rasterised');
  assert.ok(!/await glance\(/.test(nr), 'the read never waits on the glance');
  assert.match(nr, /if \(source === 'drawing'\) glance\(file\)/, 'only a drawing gets a drawing glance');
  const pr = readFileSync(new URL('./pdfRaster.ts', import.meta.url), 'utf8');
  const body = pr.slice(pr.indexOf('export async function pdfPageTexts'), pr.indexOf('export async function rasterisePdf'));
  assert.ok(body.includes('getTextContent'), 'pdfPageTexts reads the text layer');
  assert.ok(!/render\(|fetch\(|toDataURL/.test(body), 'pdfPageTexts renders nothing and sends nothing');
});
