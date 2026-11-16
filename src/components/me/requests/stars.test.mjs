// The comparison card's stars (stars.ts): five symbols, rounded to the nearest half, so 4.0 and 4.6 never look the same.
//   node --test src/components/me/requests/stars.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { starsOf } from './stars.ts';

const draw = (s) => '★'.repeat(s.full) + (s.half ? '⯪' : '') + '☆'.repeat(s.empty);

test('every score draws exactly five symbols (3.9 drew four)', () => {
  for (const v of [1, 1.2, 2.5, 3.3, 3.9, 4, 4.24, 4.25, 4.6, 4.75, 5]) {
    const s = starsOf(v);
    assert.equal(s.full + (s.half ? 1 : 0) + s.empty, 5, `score ${v}`);
  }
});

test('4.0 (fails what he asked) and 4.6 do not look equal', () => {
  assert.equal(draw(starsOf(4.0)), '★★★★☆');
  assert.equal(draw(starsOf(4.6)), '★★★★⯪');
  assert.notEqual(draw(starsOf(4.0)), draw(starsOf(4.6)));
  assert.equal(draw(starsOf(3.9)), '★★★★☆');
  assert.equal(draw(starsOf(3.3)), '★★★⯪☆');
});

test('no score, or a score out of range, never draws a wrong row', () => {
  assert.equal(starsOf(null), null);
  assert.equal(starsOf(undefined), null);
  assert.equal(starsOf('x'), null);
  assert.equal(draw(starsOf(7)), '★★★★★');
  assert.equal(draw(starsOf(-1)), '☆☆☆☆☆');
});
