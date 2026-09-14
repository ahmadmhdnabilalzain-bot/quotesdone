// The spec-offer question is answered with one tap, so its words are checked, not only rendered:
// the supplier count takes the right Arabic number form and no Arabic string carries English.
//
//   node --test src/components/me/specOffer.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { T, tf, supplierCount } from './portalText.ts';

test('English supplier count', () => {
  assert.equal(supplierCount('en', 1), '1 supplier');
  assert.equal(supplierCount('en', 2), '2 suppliers');
  assert.equal(supplierCount('en', 12), '12 suppliers');
});

test('Arabic supplier count takes singular, dual, plural and 11+ forms', () => {
  assert.equal(supplierCount('ar', 1), 'مورّد واحد');
  assert.equal(supplierCount('ar', 2), 'مورّدان');
  assert.equal(supplierCount('ar', 3), '3 مورّدين');
  assert.equal(supplierCount('ar', 10), '10 مورّدين');
  assert.equal(supplierCount('ar', 11), '11 مورّدًا');
  for (const n of [1, 2, 3, 7, 10, 11, 25]) assert.doesNotMatch(supplierCount('ar', n), /[A-Za-z]/);
});

test('every Arabic spec-offer string exists and is Latin-free', () => {
  const keys = Object.keys(T.en).filter((k) => k.startsWith('so_'));
  assert.ok(keys.length >= 10);
  for (const k of keys) {
    assert.ok(T.ar[k], 'missing Arabic ' + k);
    assert.doesNotMatch(T.ar[k].replace(/\{\w+\}/g, ''), /[A-Za-z]/, k);
  }
  assert.equal(tf('ar', 'so_yes', { v: '600x600' }), 'نعم، تابِع بـ 600x600');
});
