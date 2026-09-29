// specGuide.test.mjs - a published guide renders, a draft or missing one renders nothing.
// node --test src/lib/specGuide.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { specGuideText } from './specGuide.ts';

test('published row renders in the reader language', () => {
  const row = { trade: 'hvac', body_en: 'EN body', body_ar: 'AR body', status: 'published' };
  assert.equal(specGuideText(row, 'en'), 'EN body');
  assert.equal(specGuideText(row, 'ar'), 'AR body');
});

test('draft row renders nothing (prevented by: status check in specGuideText and RLS policy)', () => {
  assert.equal(specGuideText({ trade: 'hvac', body_en: 'EN', body_ar: 'AR', status: 'draft' }, 'en'), null);
});

test('no row or empty body renders nothing', () => {
  assert.equal(specGuideText(null, 'en'), null);
  assert.equal(specGuideText({ body_en: '  ', status: 'published' }, 'en'), null);
});
