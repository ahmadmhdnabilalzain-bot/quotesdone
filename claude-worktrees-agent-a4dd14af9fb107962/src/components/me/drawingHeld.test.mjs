// The composer's words for a HELD drawing (customer audit 21 Sep 2026, finding 9): the customer is
// told the drawing will not be sent, in both languages, and is no longer sent to an editor that does
// not open ("mark what to hide below" was the audit's screenshot).
//
//   node --test src/components/me/drawingHeld.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { T, tf } from './portalText.ts';

const KEYS = ['nr_not_prepared', 'nr_partial_none', 'nr_drawing_held', 'nr_drawing_held_boq'];

test('every held-drawing string exists in English and Arabic', () => {
  for (const k of KEYS) { assert.ok(T.en[k], k + ' en'); assert.ok(T.ar[k], k + ' ar'); }
  assert.equal(T.en.nr_partial_some, undefined, 'a partial run shares nothing now, so "only X of Y pages" is gone');
  assert.equal(T.ar.nr_partial_some, undefined);
});

test('English says held and not sent, and no longer asks the customer to mark boxes below', () => {
  for (const k of KEYS) {
    const s = T.en[k];
    assert.match(s, /held/i, k);
    assert.match(s, /not (be sent|go) to suppliers/i, k);
    assert.doesNotMatch(s, /\bmark\b.*\bbelow\b/i, k + ' points at an editor that does not open');
  }
});

test('Arabic says held (محجوز) and carries no English', () => {
  for (const k of KEYS) {
    const s = T.ar[k];
    assert.match(s, /محجوز/, k);
    assert.doesNotMatch(s.replace(/\{name\}/g, ''), /[A-Za-z]/, k + ' leaks English');
  }
});

test('the card line names the file', () => {
  assert.match(tf('en', 'nr_drawing_held', { name: 'zz_demo_drawing.pdf' }), /zz_demo_drawing\.pdf/);
  assert.match(tf('ar', 'nr_drawing_held', { name: 'zz_demo_drawing.pdf' }), /zz_demo_drawing\.pdf/);
});
