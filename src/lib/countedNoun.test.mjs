// countedNoun.test.mjs — a counted noun agrees with its number (CP-I18N-05, 22 Sep 2026).
// node --test src/lib/countedNoun.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { arCount, countPhrase, AR_NOUN } from './countedNoun.ts';

test('Arabic takes its own form at 1, 2, 3-10 and 11+', () => {
  assert.equal(arCount(1, AR_NOUN.line), 'بند واحد');
  assert.equal(arCount(2, AR_NOUN.line), 'بندان');
  assert.equal(arCount(2, AR_NOUN.line, { oblique: true }), 'بندين');
  assert.equal(arCount(3, AR_NOUN.line), '3 بنود');
  assert.equal(arCount(10, AR_NOUN.line), '10 بنود');
  assert.equal(arCount(11, AR_NOUN.line), '11 بندًا');
  assert.equal(arCount(0, AR_NOUN.line), '0 بندًا');
});

test('the oblique option changes the dual and nothing else', () => {
  for (const forms of Object.values(AR_NOUN)) {
    for (const n of [0, 1, 3, 10, 11, 100]) assert.equal(arCount(n, forms, { oblique: true }), arCount(n, forms), String(n));
  }
});

test('every noun has all five forms and the dual is not the plural', () => {
  for (const [k, f] of Object.entries(AR_NOUN)) {
    for (const key of ['one', 'two', 'twoOblique', 'few', 'many']) assert.ok(f[key], `${k}.${key}`);
    assert.notEqual(arCount(2, f), arCount(3, f), k);
  }
});

test('English agrees too, and never prints "page(s)"', () => {
  assert.equal(countPhrase('en', 1, 'page'), '1 page');
  assert.equal(countPhrase('en', 2, 'page'), '2 pages');
  assert.equal(countPhrase('en', 0, 'category'), '0 categories');
  assert.equal(countPhrase('ar', 2, 'page'), 'صفحتان');
});
